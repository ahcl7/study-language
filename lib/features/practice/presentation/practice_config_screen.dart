import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class PracticeConfigScreen extends ConsumerStatefulWidget {
  const PracticeConfigScreen({super.key});

  @override
  ConsumerState<PracticeConfigScreen> createState() =>
      _PracticeConfigScreenState();
}

class _PracticeConfigScreenState extends ConsumerState<PracticeConfigScreen> {
  String _filterType = 'class';
  int? _selectedId;
  String _mode = 'mcq';

  List<ClassesData> _classes = [];
  List<Group> _groups = [];
  List<WordType> _wordTypes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(databaseProvider);
    _classes = await db.getAllClasses();
    _groups = await db.getAllGroups();
    _wordTypes = await db.getAllWordTypes();
    setState(() {});
  }

  Future<void> _start() async {
    if (_selectedId == null) return;
    final db = ref.read(databaseProvider);

    List<Word> words;
    String title;
    switch (_filterType) {
      case 'class':
        words = await db.getWordsByClass(_selectedId!);
        title = _classes.firstWhere((c) => c.id == _selectedId!).name;
        break;
      case 'group':
        words = await db.getWordsByGroup(_selectedId!);
        title = _groups.firstWhere((g) => g.id == _selectedId!).name;
        break;
      case 'type':
        words = await db.getWordsByType(_selectedId!);
        title = _wordTypes.firstWhere((t) => t.id == _selectedId!).name;
        break;
      default:
        return;
    }

    // Remove duplicates
    final seen = <int>{};
    words = words.where((w) => seen.add(w.id)).toList();

    if (words.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Need at least 2 words to practice')),
        );
      }
      return;
    }

    words.shuffle();

    final route = _mode == 'mcq' ? '/practice/mcq' : '/practice/fill-blank';
    if (mounted) {
      context.push(route, extra: {'words': words, 'title': title});
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    List<DropdownMenuItem<int>> items;
    switch (_filterType) {
      case 'class':
        items = _classes
            .map((c) => DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
            .toList();
        break;
      case 'group':
        items = _groups
            .map((g) => DropdownMenuItem<int>(value: g.id, child: Text(g.name)))
            .toList();
        break;
      case 'type':
        items = _wordTypes
            .map((t) => DropdownMenuItem<int>(value: t.id, child: Text(t.name)))
            .toList();
        break;
      default:
        items = [];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.push('/home'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.quiz, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Practice Configuration',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 32),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'class', label: Text('Class')),
                    ButtonSegment(value: 'group', label: Text('Group')),
                    ButtonSegment(value: 'type', label: Text('Type')),
                  ],
                  selected: {_filterType},
                  onSelectionChanged: (v) => setState(() {
                    _filterType = v.first;
                    _selectedId = null;
                  }),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: _selectedId,
                  decoration: const InputDecoration(labelText: 'Select'),
                  items: items,
                  onChanged: (v) => setState(() => _selectedId = v),
                ),
                const SizedBox(height: 24),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'mcq', label: Text('Multiple Choice')),
                    ButtonSegment(value: 'fill', label: Text('Fill Blank')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (v) => setState(() => _mode = v.first),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _selectedId == null ? null : _start,
                    child: const Text('Start Practice'),
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
