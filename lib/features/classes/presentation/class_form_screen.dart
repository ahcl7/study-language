import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class ClassFormScreen extends ConsumerStatefulWidget {
  final int? classId;

  const ClassFormScreen({super.key, this.classId});

  @override
  ConsumerState<ClassFormScreen> createState() => _ClassFormScreenState();
}

class _ClassFormScreenState extends ConsumerState<ClassFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String _language = 'en';
  bool _loading = true;
  ClassesData? _existing;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (widget.classId != null) {
      final db = ref.read(databaseProvider);
      final all = await db.getAllClasses();
      _existing = all.where((c) => c.id == widget.classId).firstOrNull;
      if (_existing != null) {
        _nameCtrl.text = _existing!.name;
        _language = _existing!.language;
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
      await db.updateClass(ClassesData(
        id: _existing!.id,
        name: _nameCtrl.text.trim(),
        language: _language,
        createdAt: _existing!.createdAt,
      ));
    } else {
      await db.insertClass(ClassesCompanion.insert(
        name: _nameCtrl.text.trim(),
        language: Value(_language),
      ));
    }

    if (mounted) context.push('/classes');
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.classId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Class' : 'New Class'),
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
                            const InputDecoration(labelText: 'Class Name'),
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: _language,
                        decoration:
                            const InputDecoration(labelText: 'Language'),
                        items: const [
                          DropdownMenuItem(value: 'en', child: Text('English')),
                          DropdownMenuItem(
                              value: 'ja', child: Text('Japanese')),
                        ],
                        onChanged: (v) => setState(() => _language = v ?? 'en'),
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
