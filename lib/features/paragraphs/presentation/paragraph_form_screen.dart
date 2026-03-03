import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class ParagraphFormScreen extends ConsumerStatefulWidget {
  final int? paragraphId;
  final int? classId;

  const ParagraphFormScreen({super.key, this.paragraphId, this.classId});

  @override
  ConsumerState<ParagraphFormScreen> createState() =>
      _ParagraphFormScreenState();
}

class _ParagraphFormScreenState extends ConsumerState<ParagraphFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  int? _selectedClassId;
  bool _loading = true;
  Paragraph? _existing;
  List<ClassesData> _classes = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = ref.read(databaseProvider);
    _classes = await db.getAllClasses();
    _selectedClassId = widget.classId;

    if (widget.paragraphId != null) {
      final all = await db.getAllParagraphs();
      _existing =
          all.where((p) => p.id == widget.paragraphId).firstOrNull;
      if (_existing != null) {
        _titleCtrl.text = _existing!.title;
        _contentCtrl.text = _existing!.content;
        _selectedClassId = _existing!.classId;
      }
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClassId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a class')),
      );
      return;
    }

    final db = ref.read(databaseProvider);

    if (_existing != null) {
      await db.updateParagraph(Paragraph(
        id: _existing!.id,
        classId: _selectedClassId!,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
        createdAt: _existing!.createdAt,
      ));
    } else {
      await db.insertParagraph(ParagraphsCompanion.insert(
        classId: _selectedClassId!,
        title: _titleCtrl.text.trim(),
        content: _contentCtrl.text.trim(),
      ));
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.paragraphId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Paragraph' : 'New Paragraph'),
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
                    children: [
                      DropdownButtonFormField<int>(
                        value: _selectedClassId,
                        decoration:
                            const InputDecoration(labelText: 'Class'),
                        items: _classes
                            .map((c) => DropdownMenuItem<int>(
                                value: c.id, child: Text(c.name)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _selectedClassId = v),
                        validator: (v) =>
                            v == null ? 'Select a class' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Title'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _contentCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Content',
                          hintText: 'Enter the paragraph text...',
                          alignLabelWithHint: true,
                        ),
                        maxLines: 10,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
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
