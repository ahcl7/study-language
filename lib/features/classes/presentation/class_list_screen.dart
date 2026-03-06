import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class ClassListScreen extends ConsumerStatefulWidget {
  const ClassListScreen({super.key});

  @override
  ConsumerState<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends ConsumerState<ClassListScreen> {
  Future<void> _reorder(
      List<ClassesData> classes, int index, int direction) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= classes.length) return;
    final db = ref.read(databaseProvider);
    await db.swapClassSortOrders(classes[index].id, classes[newIndex].id);
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Classes'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.push('/home'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/classes/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Class'),
      ),
      body: StreamBuilder<List<ClassesData>>(
        stream: db.watchAllClasses(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final classes = snapshot.data ?? [];
          if (classes.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.class_,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No classes yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Create a class to organize your vocabulary'),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: classes.length,
            itemBuilder: (context, index) {
              final cls = classes[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      cls.language.toUpperCase(),
                      style: TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(cls.name),
                  subtitle: Text(
                      'Language: ${cls.language == 'en' ? 'English' : cls.language == 'ja' ? 'Japanese' : cls.language}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: index == 0
                            ? null
                            : () => _reorder(classes, index, -1),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        onPressed: index == classes.length - 1
                            ? null
                            : () => _reorder(classes, index, 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () =>
                            context.push('/classes/edit/${cls.id}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _confirmDelete(context, db, cls),
                      ),
                    ],
                  ),
                  onTap: () => context.push('/classes/${cls.id}/groups'),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, AppDatabase db, ClassesData cls) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Class'),
        content: Text(
            'Delete "${cls.name}"? This will not delete words, but will remove groups in this class.'),
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
      await db.deleteClass(cls);
    }
  }
}
