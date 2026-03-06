import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class GroupFormScreen extends ConsumerStatefulWidget {
  final int classId;
  final int? groupId;

  const GroupFormScreen({super.key, required this.classId, this.groupId});

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _loading = true;
  Group? _existing;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.groupId != null) {
      final db = ref.read(databaseProvider);
      final groups = await db.getGroupsByClass(widget.classId);
      _existing = groups.where((g) => g.id == widget.groupId).firstOrNull;
      if (_existing != null) {
        _nameCtrl.text = _existing!.name;
      }
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(databaseProvider);

    if (_existing != null) {
      await db.updateGroup(Group(
        id: _existing!.id,
        classId: widget.classId,
        name: _nameCtrl.text.trim(),
        createdAt: _existing!.createdAt,
        sortOrder: _existing!.sortOrder,
      ));
    } else {
      await db.insertGroup(GroupsCompanion.insert(
        classId: widget.classId,
        name: _nameCtrl.text.trim(),
      ));
    }

    if (mounted) context.push('/classes/${widget.classId}/groups');
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.groupId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Group' : 'New Group'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Group Name'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
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
