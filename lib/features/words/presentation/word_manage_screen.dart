import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class WordManageScreen extends ConsumerStatefulWidget {
  const WordManageScreen({super.key});

  @override
  ConsumerState<WordManageScreen> createState() => _WordManageScreenState();
}

class _WordManageScreenState extends ConsumerState<WordManageScreen> {
  List<Word> _allWords = [];
  List<Word> _filtered = [];
  List<Group> _allGroups = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    final words = await db.getAllWords();
    final groups = await db.getAllGroups();
    words.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _allWords = words;
      _filtered = words;
      _allGroups = groups;
      _loading = false;
    });
  }

  void _onSearch() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _allWords;
      } else {
        _filtered = _allWords
            .where((w) =>
                w.name.toLowerCase().contains(q) ||
                w.meaning.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  Future<void> _toggleActive(Word word) async {
    final db = ref.read(databaseProvider);
    await db.setWordActive(word.id, isActive: !word.isActive);
    await _load();
  }

  Future<void> _showMoveDialog(Word word) async {
    final db = ref.read(databaseProvider);
    final currentGroupIds = await db.getGroupIdsForWord(word.id);

    if (!mounted) return;

    final currentGroups = _allGroups
        .where((g) => currentGroupIds.contains(g.id))
        .toList();

    Group? selectedTarget;
    bool moveMode = true; // true = move (replace), false = add (link)

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);

          return AlertDialog(
            title: Text('Manage: ${word.name}'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Current groups:', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 4),
                  if (currentGroups.isEmpty)
                    Text('(none)', style: theme.textTheme.bodySmall)
                  else
                    Wrap(
                      spacing: 6,
                      children: currentGroups
                          .map((g) => Chip(
                                label: Text(g.name),
                                deleteIcon: const Icon(Icons.close, size: 16),
                                onDeleted: () async {
                                  await db.unlinkWordFromGroup(word.id, g.id);
                                  currentGroupIds.remove(g.id);
                                  currentGroups
                                      .removeWhere((x) => x.id == g.id);
                                  setDialogState(() {});
                                },
                              ))
                          .toList(),
                    ),
                  const Divider(height: 24),
                  Text('Move or add to group:',
                      style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<Group>(
                    value: selectedTarget,
                    decoration:
                        const InputDecoration(labelText: 'Target group'),
                    items: _allGroups
                        .map((g) => DropdownMenuItem<Group>(
                              value: g,
                              child: Text(g.name),
                            ))
                        .toList(),
                    onChanged: (v) => setDialogState(() => selectedTarget = v),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                          value: true,
                          label: Text('Move'),
                          icon: Icon(Icons.drive_file_move_outline)),
                      ButtonSegment(
                          value: false,
                          label: Text('Add'),
                          icon: Icon(Icons.playlist_add)),
                    ],
                    selected: {moveMode},
                    onSelectionChanged: (v) =>
                        setDialogState(() => moveMode = v.first),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    moveMode
                        ? 'Removes from all current groups, then adds to target.'
                        : 'Keeps current groups and links to target as well.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: selectedTarget == null
                    ? null
                    : () async {
                        if (moveMode) {
                          await db.deleteWordGroupLinksByWord(word.id);
                        }
                        await db.linkWordToGroup(
                            word.id, selectedTarget!.id);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(moveMode
                                  ? '"${word.name}" moved to "${selectedTarget!.name}"'
                                  : '"${word.name}" added to "${selectedTarget!.name}"'),
                            ),
                          );
                        }
                      },
                child: Text(moveMode ? 'Move' : 'Add'),
              ),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Words'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by word or meaning...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          if (!_loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_filtered.length} word${_filtered.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.search_off,
                                size: 48,
                                color: theme.colorScheme.outline),
                            const SizedBox(height: 12),
                            Text('No words found',
                                style: theme.textTheme.titleMedium),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final word = _filtered[index];
                          return ListTile(
                            leading: Tooltip(
                              message: word.isActive ? 'Active' : 'Deactivated',
                              child: Switch(
                                value: word.isActive,
                                onChanged: (_) => _toggleActive(word),
                              ),
                            ),
                            title: Text(
                              word.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: word.isActive
                                    ? null
                                    : theme.colorScheme.outline,
                                decoration: word.isActive
                                    ? null
                                    : TextDecoration.lineThrough,
                              ),
                            ),
                            subtitle: Text(
                              word.meaning,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: word.isActive
                                    ? null
                                    : theme.colorScheme.outline,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Move / add to group',
                              icon: const Icon(Icons.drive_file_move_outline),
                              onPressed: () => _showMoveDialog(word),
                            ),
                            onTap: () => _showMoveDialog(word),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
