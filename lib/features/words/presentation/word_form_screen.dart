import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:image_picker/image_picker.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class WordFormScreen extends ConsumerStatefulWidget {
  final int? wordId;
  final int? groupId;

  const WordFormScreen({super.key, this.wordId, this.groupId});

  @override
  ConsumerState<WordFormScreen> createState() => _WordFormScreenState();
}

class _WordFormScreenState extends ConsumerState<WordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _meaningCtrl = TextEditingController();
  final _exampleCtrl = TextEditingController();
  String? _imagePath;
  bool _loading = true;
  Word? _existing;

  // Live-match state (new-word mode only)
  List<_WordMatchInfo> _nameMatches = [];
  List<_WordMatchInfo> _duplicateInGroup = [];
  Set<int> _currentGroupWordIds = {};
  Timer? _searchDebounce;

  List<WordType> _allTypes = [];
  Set<int> _selectedTypeIds = {};
  List<Group> _allGroups = [];
  Set<int> _selectedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = ref.read(databaseProvider);
    _allTypes = await db.getAllWordTypes();
    _allGroups = await db.getAllGroups();

    if (widget.wordId != null) {
      final allWords = await db.getAllWords();
      _existing = allWords.where((w) => w.id == widget.wordId).firstOrNull;
      if (_existing != null) {
        _nameCtrl.text = _existing!.name;
        _meaningCtrl.text = _existing!.meaning;
        _exampleCtrl.text = _existing!.example;
        _imagePath = _existing!.imagePath;
        _selectedTypeIds = (await db.getTypeIdsForWord(_existing!.id)).toSet();
        _selectedGroupIds =
            (await db.getGroupIdsForWord(_existing!.id)).toSet();
      }
    } else if (widget.groupId != null) {
      _selectedGroupIds = {widget.groupId!};
      // Load existing word ids in this group so we can exclude them from matches
      final groupWords = await db.getWordsByGroup(widget.groupId!);
      _currentGroupWordIds = groupWords.map((w) => w.id).toSet();
    }

    setState(() => _loading = false);

    // Attach name listener only in new-word mode
    if (widget.wordId == null) {
      _nameCtrl.addListener(_onNameChanged);
    }
  }

  void _onNameChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final query = _nameCtrl.text.trim();
      if (query.isEmpty) {
        if (mounted)
          setState(() {
            _nameMatches = [];
            _duplicateInGroup = [];
          });
        return;
      }
      final db = ref.read(databaseProvider);
      final results = await db.searchWordsByName(query);
      // Split: already in group (warning) vs not in group (suggestion)
      final inGroup =
          results.where((w) => _currentGroupWordIds.contains(w.id)).toList();
      final filtered =
          results.where((w) => !_currentGroupWordIds.contains(w.id)).toList();
      // Load group membership for each
      final dupInfos = await Future.wait(
        inGroup.map((w) async {
          final grps = await db.getGroupsForWord(w.id);
          return _WordMatchInfo(word: w, groups: grps);
        }),
      );
      final infos = await Future.wait(
        filtered.map((w) async {
          final grps = await db.getGroupsForWord(w.id);
          return _WordMatchInfo(word: w, groups: grps);
        }),
      );
      if (mounted)
        setState(() {
          _nameMatches = infos;
          _duplicateInGroup = dupInfos;
        });
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    if (widget.wordId == null) _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _meaningCtrl.dispose();
    _exampleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile != null) {
      setState(() => _imagePath = xfile.path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(databaseProvider);

    int wordId;
    if (_existing != null) {
      await db.updateWord(Word(
        id: _existing!.id,
        name: _nameCtrl.text.trim(),
        meaning: _meaningCtrl.text.trim(),
        example: _exampleCtrl.text.trim(),
        imagePath: _imagePath,
        isActive: _existing!.isActive,
        createdAt: _existing!.createdAt,
      ));
      wordId = _existing!.id;

      // Clear old links
      await db.deleteWordGroupLinksByWord(wordId);
      await db.deleteWordTypeLinksByWord(wordId);
    } else {
      wordId = await db.insertWord(WordsCompanion.insert(
        name: _nameCtrl.text.trim(),
        meaning: _meaningCtrl.text.trim(),
        example: Value(_exampleCtrl.text.trim()),
        imagePath: Value(_imagePath),
      ));
    }

    // Re-create links
    for (final gId in _selectedGroupIds) {
      await db.linkWordToGroup(wordId, gId);
    }
    for (final tId in _selectedTypeIds) {
      await db.linkWordToType(wordId, tId);
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.wordId != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Word' : 'New Word'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Word',
                            hintText: 'Enter the vocabulary word'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      // Duplicate-in-group warning banner
                      if (!isEdit && _duplicateInGroup.isNotEmpty)
                        ..._duplicateInGroup
                            .map((info) => _DuplicateWarningCard(info: info))
                            .toList(),
                      // Existing-word suggestion banner
                      if (!isEdit && _nameMatches.isNotEmpty)
                        ..._nameMatches
                            .map((info) => _MatchSuggestionCard(
                                  info: info,
                                  groupId: widget.groupId,
                                  onClone: () async {
                                    final db = ref.read(databaseProvider);
                                    final typeIds = await db
                                        .getTypeIdsForWord(info.word.id);
                                    setState(() {
                                      _meaningCtrl.text = info.word.meaning;
                                      _exampleCtrl.text = info.word.example;
                                      _imagePath = info.word.imagePath;
                                      _selectedTypeIds = typeIds.toSet();
                                      _nameMatches = [];
                                    });
                                  },
                                  onAddToGroup: widget.groupId == null
                                      ? null
                                      : () async {
                                          final db = ref.read(databaseProvider);
                                          await db.linkWordToGroup(
                                              info.word.id, widget.groupId!);
                                          if (mounted) context.pop();
                                        },
                                  onMoveToGroup: widget.groupId == null
                                      ? null
                                      : () async {
                                          final db = ref.read(databaseProvider);
                                          await db.deleteWordGroupLinksByWord(
                                              info.word.id);
                                          await db.linkWordToGroup(
                                              info.word.id, widget.groupId!);
                                          if (mounted) context.pop();
                                        },
                                ))
                            .toList(),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _meaningCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Meaning',
                            hintText:
                                'Enter the meaning / translation (optional)'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _exampleCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Example',
                            hintText: 'Example sentence (optional)'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 20),
                      // Word types
                      Text('Word Types', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _allTypes.map((type) {
                          final selected = _selectedTypeIds.contains(type.id);
                          return FilterChip(
                            label: Text(type.name),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedTypeIds.add(type.id);
                                } else {
                                  _selectedTypeIds.remove(type.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // Groups
                      Text('Groups', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _allGroups.map((group) {
                          final selected = _selectedGroupIds.contains(group.id);
                          return FilterChip(
                            label: Text(group.name),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedGroupIds.add(group.id);
                                } else {
                                  _selectedGroupIds.remove(group.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // Image
                      Text('Image', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image),
                            label: const Text('Pick Image'),
                          ),
                          if (_imagePath != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_imagePath!,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _imagePath = null),
                            ),
                          ],
                        ],
                      ),
                      if (_imagePath != null &&
                          File(_imagePath!).existsSync()) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_imagePath!),
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _save,
                          child: Text(isEdit ? 'Update' : 'Create'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
// ─── Data class for a matched word + its current group memberships ────────────

class _WordMatchInfo {
  final Word word;
  final List<Group> groups;
  const _WordMatchInfo({required this.word, required this.groups});
}

// ─── Suggestion card shown when a matching word already exists ───────────────

class _MatchSuggestionCard extends StatelessWidget {
  final _WordMatchInfo info;
  final int? groupId;
  final VoidCallback onClone;
  final VoidCallback? onAddToGroup;
  final VoidCallback? onMoveToGroup;

  const _MatchSuggestionCard({
    required this.info,
    required this.groupId,
    required this.onClone,
    required this.onAddToGroup,
    required this.onMoveToGroup,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = info.word;
    final isActive = word.isActive;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row: icon + name + active badge
            Row(
              children: [
                Icon(Icons.info_outline,
                    size: 15, color: theme.colorScheme.secondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Existing: ${word.name}',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                // Active / Inactive badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: isActive
                        ? Colors.green.shade100
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? Icons.check_circle : Icons.cancel,
                        size: 11,
                        color: isActive
                            ? Colors.green.shade700
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: isActive
                              ? Colors.green.shade700
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Meaning
            if (word.meaning.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                word.meaning,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
            // Groups membership
            if (info.groups.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.folder_open,
                      size: 13, color: theme.colorScheme.outline),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      info.groups.map((g) => g.name).join(', '),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            // Action buttons
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Clone'),
                  onPressed: onClone,
                ),
                if (onAddToGroup != null)
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.playlist_add, size: 16),
                    label: const Text('Add to group'),
                    onPressed: onAddToGroup,
                  ),
                if (onMoveToGroup != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    icon: const Icon(Icons.drive_file_move, size: 16),
                    label: const Text('Move here'),
                    onPressed: onMoveToGroup,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
// ─── Warning card for words that already exist in the current group ───────────

class _DuplicateWarningCard extends StatelessWidget {
  final _WordMatchInfo info;

  const _DuplicateWarningCard({required this.info});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final word = info.word;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 15, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '"${word.name}" already exists in this group',
                    style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: word.isActive
                        ? Colors.green.shade100
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        word.isActive ? Icons.check_circle : Icons.cancel,
                        size: 11,
                        color: word.isActive
                            ? Colors.green.shade700
                            : theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        word.isActive ? 'Active' : 'Inactive',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: word.isActive
                              ? Colors.green.shade700
                              : theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (word.meaning.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(word.meaning,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
