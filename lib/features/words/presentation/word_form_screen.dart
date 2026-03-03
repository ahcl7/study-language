import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:image_picker/image_picker.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class WordFormScreen extends ConsumerStatefulWidget {
  final int? wordId;
  final int? groupId;

  const WordFormScreen({super.key, this.wordId, this.groupId});

  @override
  ConsumerState<WordFormScreen> createState() => _WordFormScreenState();
}

class _WordFormScreenState extends ConsumerState<WordFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _meaningCtrl = TextEditingController();
  final _exampleCtrl = TextEditingController();
  String? _imagePath;
  bool _loading = true;
  Word? _existing;

  List<WordType> _allTypes = [];
  Set<int> _selectedTypeIds = {};
  List<Group> _allGroups = [];
  Set<int> _selectedGroupIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final db = ref.read(databaseProvider);
    _allTypes = await db.getAllWordTypes();
    _allGroups = await db.getAllGroups();

    if (widget.wordId != null) {
      final allWords = await db.getAllWords();
      _existing = allWords.where((w) => w.id == widget.wordId).firstOrNull;
      if (_existing != null) {
        _nameCtrl.text = _existing!.name;
        _meaningCtrl.text = _existing!.meaning;
        _exampleCtrl.text = _existing!.example;
        _imagePath = _existing!.imagePath;
        _selectedTypeIds =
            (await db.getTypeIdsForWord(_existing!.id)).toSet();
        _selectedGroupIds =
            (await db.getGroupIdsForWord(_existing!.id)).toSet();
      }
    } else if (widget.groupId != null) {
      _selectedGroupIds = {widget.groupId!};
    }

    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _meaningCtrl.dispose();
    _exampleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery);
    if (xfile != null) {
      setState(() => _imagePath = xfile.path);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final db = ref.read(databaseProvider);

    int wordId;
    if (_existing != null) {
      await db.updateWord(Word(
        id: _existing!.id,
        name: _nameCtrl.text.trim(),
        meaning: _meaningCtrl.text.trim(),
        example: _exampleCtrl.text.trim(),
        imagePath: _imagePath,
        createdAt: _existing!.createdAt,
      ));
      wordId = _existing!.id;

      // Clear old links
      await db.deleteWordGroupLinksByWord(wordId);
      await db.deleteWordTypeLinksByWord(wordId);
    } else {
      wordId = await db.insertWord(WordsCompanion.insert(
        name: _nameCtrl.text.trim(),
        meaning: _meaningCtrl.text.trim(),
        example: Value(_exampleCtrl.text.trim()),
        imagePath: Value(_imagePath),
      ));
    }

    // Re-create links
    for (final gId in _selectedGroupIds) {
      await db.linkWordToGroup(wordId, gId);
    }
    for (final tId in _selectedTypeIds) {
      await db.linkWordToType(wordId, tId);
    }

    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.wordId != null;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit Word' : 'New Word'),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Word',
                            hintText: 'Enter the vocabulary word'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _meaningCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Meaning',
                            hintText: 'Enter the meaning / translation'),
                        maxLines: 3,
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _exampleCtrl,
                        decoration: const InputDecoration(
                            labelText: 'Example',
                            hintText: 'Example sentence (optional)'),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 20),
                      // Word types
                      Text('Word Types',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _allTypes.map((type) {
                          final selected =
                              _selectedTypeIds.contains(type.id);
                          return FilterChip(
                            label: Text(type.name),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedTypeIds.add(type.id);
                                } else {
                                  _selectedTypeIds.remove(type.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // Groups
                      Text('Groups',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _allGroups.map((group) {
                          final selected =
                              _selectedGroupIds.contains(group.id);
                          return FilterChip(
                            label: Text(group.name),
                            selected: selected,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _selectedGroupIds.add(group.id);
                                } else {
                                  _selectedGroupIds.remove(group.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 20),
                      // Image
                      Text('Image',
                          style: theme.textTheme.titleSmall),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickImage,
                            icon: const Icon(Icons.image),
                            label: const Text('Pick Image'),
                          ),
                          if (_imagePath != null) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(_imagePath!,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => _imagePath = null),
                            ),
                          ],
                        ],
                      ),
                      if (_imagePath != null &&
                          File(_imagePath!).existsSync()) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(_imagePath!),
                            height: 150,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
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
