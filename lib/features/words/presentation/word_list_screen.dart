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
    setState(() {
      _words = words;
      _loading = false;
    });
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
          await context
              .push('/words/new?groupId=${widget.groupId}');
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
                      Icon(Icons.abc, size: 64,
                          color: theme.colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('No words yet',
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      const Text('Add vocabulary words to this group'),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _words.length,
                  itemBuilder: (context, index) {
                    final word = _words[index];
                    return Card(
                      child: ListTile(
                        title: Text(word.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        subtitle: Text(word.meaning,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
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
                Text(word.imagePath!,
                    style: theme.textTheme.bodySmall),
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
