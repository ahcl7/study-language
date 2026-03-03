import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class ParagraphListScreen extends ConsumerStatefulWidget {
  const ParagraphListScreen({super.key});

  @override
  ConsumerState<ParagraphListScreen> createState() =>
      _ParagraphListScreenState();
}

class _ParagraphListScreenState extends ConsumerState<ParagraphListScreen> {
  int? _selectedClassId;
  List<ClassesData> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final db = ref.read(databaseProvider);
    _classes = await db.getAllClasses();
    if (_classes.isNotEmpty) {
      _selectedClassId = _classes.first.id;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Paragraphs'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.push('/home'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _selectedClassId == null
            ? null
            : () async {
                await context.push('/paragraphs/new?classId=$_selectedClassId');
                setState(() {}); // refresh
              },
        icon: const Icon(Icons.add),
        label: const Text('New Paragraph'),
      ),
      body: Column(
        children: [
          // Class filter
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              value: _selectedClassId,
              decoration: const InputDecoration(labelText: 'Filter by Class'),
              items: _classes
                  .map((c) =>
                      DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedClassId = v),
            ),
          ),
          // List
          if (_selectedClassId != null)
            Expanded(
              child: StreamBuilder<List<Paragraph>>(
                stream: db.watchParagraphsByClass(_selectedClassId!),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final paragraphs = snapshot.data ?? [];
                  if (paragraphs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.article,
                              size: 64, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          Text('No paragraphs yet',
                              style: theme.textTheme.titleMedium),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: paragraphs.length,
                    itemBuilder: (context, index) {
                      final para = paragraphs[index];
                      return Card(
                        child: ListTile(
                          title: Text(para.title),
                          subtitle: Text(
                            para.content,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit),
                                onPressed: () async {
                                  await context
                                      .push('/paragraphs/edit/${para.id}');
                                  setState(() {});
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () =>
                                    _confirmDelete(context, db, para),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppDatabase db, Paragraph para) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Paragraph'),
        content: Text('Delete "${para.title}"?'),
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
      await db.deleteParagraph(para);
    }
  }
}
