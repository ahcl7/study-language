import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class WordListScreen extends ConsumerStatefulWidget {
  final int groupId;

  const WordListScreen({super.key, required this.groupId});

  @override
  ConsumerState<WordListScreen> createState() => _WordListScreenState();
}

class _WordListScreenState extends ConsumerState<WordListScreen> {
  List<Word> _words = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadWords();
  }

  Future<void> _loadWords() async {
    final db = ref.read(databaseProvider);
    final words = await db.getWordsByGroup(widget.groupId);
    // Active words first (preserving sort order), inactive after
    final active = words.where((w) => w.isActive).toList();
    final inactive = words.where((w) => !w.isActive).toList();
    setState(() {
      _words = [...active, ...inactive];
      _loading = false;
    });
  }

  Future<void> _toggleActive(Word word) async {
    final db = ref.read(databaseProvider);
    await db.setWordActive(word.id, isActive: !word.isActive);
    _loadWords();
  }

  Future<void> _exportGroup() async {
    // Show filter config dialog
    final config = await showDialog<_ExportConfig>(
      context: context,
      builder: (ctx) => _ExportConfigDialog(words: _words),
    );
    if (config == null) return; // cancelled

    final filtered = _words.where((w) {
      if (config.onlyActive && !w.isActive) return false;
      if (config.onlyInactive && w.isActive) return false;
      // Completeness filters: OR logic — include if missing meaning OR missing example
      if (config.missingMeaning || config.missingExample) {
        final lacksMeaning = config.missingMeaning && w.meaning.trim().isEmpty;
        final lacksExample = config.missingExample && w.example.trim().isEmpty;
        if (!lacksMeaning && !lacksExample) return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No words match the selected filters')),
        );
      }
      return;
    }

    try {
      final db = ref.read(databaseProvider);
      final group = await db.getGroupById(widget.groupId);
      final exportData = {
        'group_id': group.id,
        'group_name': group.name,
        'exported_at': DateTime.now().toIso8601String(),
        'filter': config.describe(),
        'word_count': filtered.length,
        'words': filtered
            .map((w) => {
                  'name': w.name,
                  'meaning': w.meaning,
                  'example': w.example,
                  'isActive': w.isActive,
                })
            .toList(),
      };
      final json = const JsonEncoder.withIndent('  ').convert(exportData);
      final groupName = group.name
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .trim()
          .replaceAll(' ', '_');
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Group Words',
        fileName: 'group_${groupName}_${config.fileTag()}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null) {
        await File(result).writeAsString(json);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Exported ${filtered.length} words to: $result')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }

  Future<void> _importGroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import Words'),
        content: const Text(
          'Words in the JSON will be matched by name.\n'
          '• Existing word → update meaning & example\n'
          '• New word → inserted and linked to this group\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Import Group Words',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final raw = jsonDecode(await file.readAsString());
      final wordsData = raw is Map ? raw['words'] as List? : raw as List?;
      if (wordsData == null) throw 'Invalid format: missing "words" array';

      final db = ref.read(databaseProvider);
      await db.importGroupWords(widget.groupId, wordsData);
      await _loadWords();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${wordsData.length} words')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    }
  }

  Future<void> _reorder(int index, int direction) async {
    // direction: -1 = move up, +1 = move down
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= _words.length) return;
    final db = ref.read(databaseProvider);
    await db.swapWordSortOrders(
        _words[index].id, _words[newIndex].id, widget.groupId);
    await _loadWords();
  }

  /// Opens a bottom sheet to move [word] to any position within its
  /// active/inactive segment. Uses midpoint strategy — usually 1 DB update.
  Future<void> _openMoveSheet(Word word) async {
    // Only show peers in the same active/inactive group
    final peers = _words.where((w) => w.isActive == word.isActive).toList();
    if (peers.length < 2) return;
    final currentIdx = peers.indexWhere((w) => w.id == word.id);

    final db = ref.read(databaseProvider);
    // Each entry represents "insert after peers[i]" (or null = move to top)
    // We show N+1 slots (before first, after each word) minus current position
    await showModalBottomSheet(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        // Slots: null = before first, peers[i].id = after i-th peer
        final slots = <int?>[
          null,
          ...peers.map((p) => p.id as int?),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Move "${word.name}" to...',
                  style: theme.textTheme.titleMedium),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: slots.length,
                itemBuilder: (ctx, i) {
                  final afterId = slots[i];
                  // Skip slots that would leave word in same position
                  final afterIdx = afterId == null
                      ? -1
                      : peers.indexWhere((p) => p.id == afterId);
                  // Same position: afterIdx == currentIdx - 1  OR  afterIdx == currentIdx
                  final isSamePos =
                      afterIdx == currentIdx - 1 || afterIdx == currentIdx;
                  final label = afterId == null
                      ? 'Move to top'
                      : 'After: ${peers.firstWhere((p) => p.id == afterId).name}';
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      afterId == null
                          ? Icons.vertical_align_top
                          : Icons.arrow_downward,
                      size: 18,
                      color: isSamePos
                          ? theme.colorScheme.outline
                          : theme.colorScheme.primary,
                    ),
                    title: Text(label,
                        style: TextStyle(
                          color: isSamePos ? theme.colorScheme.outline : null,
                        )),
                    trailing: isSamePos
                        ? Text('current',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.colorScheme.outline))
                        : null,
                    onTap: isSamePos
                        ? null
                        : () async {
                            Navigator.pop(ctx);
                            await db.moveWordToPositionInGroup(
                              word.id,
                              widget.groupId,
                              afterWordId: afterId,
                            );
                            await _loadWords();
                          },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Words'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            tooltip: 'Export group',
            icon: const Icon(Icons.upload_file),
            onPressed: _exportGroup,
          ),
          IconButton(
            tooltip: 'Import words from JSON',
            icon: const Icon(Icons.download_for_offline),
            onPressed: _importGroup,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/words/new?groupId=${widget.groupId}');
          _loadWords();
        },
        icon: const Icon(Icons.add),
        label: const Text('New Word'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _words.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.abc,
                          size: 64, color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('No words yet', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text('Add vocabulary words to this group'),
                    ],
                  ),
                )
              : Column(
                  children: [
                    // Summary bar
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle,
                              size: 16, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${_words.where((w) => w.isActive).length} active',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.cancel,
                              size: 16, color: theme.colorScheme.outline),
                          const SizedBox(width: 4),
                          Text(
                            '${_words.where((w) => !w.isActive).length} inactive',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                                fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          Text(
                            'Total: ${_words.length}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _words.length,
                        itemBuilder: (context, index) {
                          final word = _words[index];
                          return Card(
                            child: ListTile(
                              leading: Tooltip(
                                message:
                                    word.isActive ? 'Active' : 'Deactivated',
                                child: Switch(
                                  value: word.isActive,
                                  onChanged: (_) => _toggleActive(word),
                                ),
                              ),
                              title: Text(
                                '${index + 1}. ${word.name}',
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
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: word.isActive
                                      ? null
                                      : theme.colorScheme.outline,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Move up',
                                    icon: const Icon(Icons.arrow_upward,
                                        size: 20),
                                    onPressed: index == 0 ||
                                            _words[index - 1].isActive !=
                                                word.isActive
                                        ? null
                                        : () => _reorder(index, -1),
                                  ),
                                  IconButton(
                                    tooltip: 'Move down',
                                    icon: const Icon(Icons.arrow_downward,
                                        size: 20),
                                    onPressed: index == _words.length - 1 ||
                                            _words[index + 1].isActive !=
                                                word.isActive
                                        ? null
                                        : () => _reorder(index, 1),
                                  ),
                                  IconButton(
                                    tooltip: 'Move to position',
                                    icon: const Icon(Icons.swap_vert, size: 20),
                                    onPressed: () => _openMoveSheet(word),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.edit),
                                    onPressed: () async {
                                      await context
                                          .push('/words/edit/${word.id}');
                                      _loadWords();
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    onPressed: () =>
                                        _confirmDelete(context, db, word),
                                  ),
                                ],
                              ),
                              onTap: () => _showWordDetail(context, word),
                            ),
                          );
                        },
                      ),
                    ), // Expanded
                  ],
                ), // Column
    );
  }

  void _showWordDetail(BuildContext context, Word word) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(word.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Meaning:', style: theme.textTheme.labelLarge),
              Text(word.meaning),
              if (word.example.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Example:', style: theme.textTheme.labelLarge),
                Text(word.example),
              ],
              if (word.imagePath != null) ...[
                const SizedBox(height: 12),
                Text('Image:', style: theme.textTheme.labelLarge),
                const SizedBox(height: 4),
                Text(word.imagePath!, style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppDatabase db, Word word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Word'),
        content: Text('Delete "${word.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      await db.deleteWordGroupLinksByWord(word.id);
      await db.deleteWordTypeLinksByWord(word.id);
      await db.deleteWord(word);
      _loadWords();
    }
  }
}

// ─── Export config ───

class _ExportConfig {
  final bool onlyActive;
  final bool onlyInactive;
  final bool missingMeaning;
  final bool missingExample;

  const _ExportConfig({
    required this.onlyActive,
    required this.onlyInactive,
    required this.missingMeaning,
    required this.missingExample,
  });

  String describe() {
    final parts = <String>[];
    if (onlyActive) parts.add('active only');
    if (onlyInactive) parts.add('inactive only');
    if (missingMeaning) parts.add('missing meaning');
    if (missingExample) parts.add('missing example');
    return parts.isEmpty ? 'all words' : parts.join(', ');
  }

  String fileTag() {
    final parts = <String>[];
    if (onlyActive) parts.add('active');
    if (onlyInactive) parts.add('inactive');
    if (missingMeaning) parts.add('no_meaning');
    if (missingExample) parts.add('no_example');
    return parts.isEmpty ? 'all' : parts.join('_');
  }
}

class _ExportConfigDialog extends StatefulWidget {
  final List<Word> words;
  const _ExportConfigDialog({required this.words});

  @override
  State<_ExportConfigDialog> createState() => _ExportConfigDialogState();
}

class _ExportConfigDialogState extends State<_ExportConfigDialog> {
  bool _onlyActive = false;
  bool _onlyInactive = false;
  bool _missingMeaning = false;
  bool _missingExample = false;

  int get _matchCount {
    return widget.words.where((w) {
      if (_onlyActive && !w.isActive) return false;
      if (_onlyInactive && w.isActive) return false;
      // Completeness filters: OR logic
      if (_missingMeaning || _missingExample) {
        final lacksMeaning = _missingMeaning && w.meaning.trim().isEmpty;
        final lacksExample = _missingExample && w.example.trim().isEmpty;
        if (!lacksMeaning && !lacksExample) return false;
      }
      return true;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Export Config'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter by status', style: theme.textTheme.labelLarge),
            CheckboxListTile(
              dense: true,
              title: const Text('Active words only'),
              value: _onlyActive,
              onChanged: (v) => setState(() {
                _onlyActive = v!;
                if (v) _onlyInactive = false;
              }),
            ),
            CheckboxListTile(
              dense: true,
              title: const Text('Inactive words only'),
              value: _onlyInactive,
              onChanged: (v) => setState(() {
                _onlyInactive = v!;
                if (v) _onlyActive = false;
              }),
            ),
            const Divider(),
            Text('Filter by completeness', style: theme.textTheme.labelLarge),
            CheckboxListTile(
              dense: true,
              title: const Text('Missing meaning'),
              subtitle: const Text('meaning is empty'),
              value: _missingMeaning,
              onChanged: (v) => setState(() => _missingMeaning = v!),
            ),
            CheckboxListTile(
              dense: true,
              title: const Text('Missing example'),
              subtitle: const Text('example sentence is empty'),
              value: _missingExample,
              onChanged: (v) => setState(() => _missingExample = v!),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'Words to export: $_matchCount / ${widget.words.length}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _matchCount == 0
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _matchCount == 0
              ? null
              : () => Navigator.pop(
                    context,
                    _ExportConfig(
                      onlyActive: _onlyActive,
                      onlyInactive: _onlyInactive,
                      missingMeaning: _missingMeaning,
                      missingExample: _missingExample,
                    ),
                  ),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
