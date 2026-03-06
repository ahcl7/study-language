import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class GroupListScreen extends ConsumerStatefulWidget {
  final int classId;

  const GroupListScreen({super.key, required this.classId});

  @override
  ConsumerState<GroupListScreen> createState() => _GroupListScreenState();
}

class _GroupListScreenState extends ConsumerState<GroupListScreen> {
  Future<void> _reorder(List<Group> groups, int index, int direction) async {
    final newIndex = index + direction;
    if (newIndex < 0 || newIndex >= groups.length) return;
    final db = ref.read(databaseProvider);
    await db.swapGroupSortOrders(groups[index].id, groups[newIndex].id);
  }

  Future<void> _confirmDelete(
      BuildContext context, AppDatabase db, Group group) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Group'),
        content: Text('Delete "${group.name}"?'),
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
      await db.deleteGroup(group);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = ref.watch(databaseProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.push('/classes'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/classes/${widget.classId}/groups/new'),
        icon: const Icon(Icons.add),
        label: const Text('New Group'),
      ),
      body: StreamBuilder<List<Group>>(
        stream: db.watchGroupsByClass(widget.classId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final groups = snapshot.data ?? [];
          if (groups.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder,
                      size: 64, color: theme.colorScheme.outline),
                  const SizedBox(height: 16),
                  Text('No groups yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('Create a group to organize vocabulary'),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    child: Icon(Icons.folder,
                        color: theme.colorScheme.onSecondaryContainer),
                  ),
                  title: Text(group.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Move up',
                        icon: const Icon(Icons.arrow_upward, size: 20),
                        onPressed: index == 0
                            ? null
                            : () => _reorder(groups, index, -1),
                      ),
                      IconButton(
                        tooltip: 'Move down',
                        icon: const Icon(Icons.arrow_downward, size: 20),
                        onPressed: index == groups.length - 1
                            ? null
                            : () => _reorder(groups, index, 1),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => context.push(
                            '/classes/${widget.classId}/groups/edit/${group.id}'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () => _confirmDelete(context, db, group),
                      ),
                    ],
                  ),
                  onTap: () => context.push('/groups/${group.id}/words'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
