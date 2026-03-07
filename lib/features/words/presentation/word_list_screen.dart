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
