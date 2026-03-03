import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class FlashcardScreen extends ConsumerStatefulWidget {
  const FlashcardScreen({super.key});

  @override
  ConsumerState<FlashcardScreen> createState() => _FlashcardScreenState();
}

class _FlashcardScreenState extends ConsumerState<FlashcardScreen> {
  String _filterType = 'class';
  int? _selectedId;
  List<Word> _words = [];
  int _currentIndex = 0;
  bool _showBack = false;
  bool _started = false;

  List<ClassesData> _classes = [];
  List<Group> _groups = [];
  List<WordType> _wordTypes = [];

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    final db = ref.read(databaseProvider);
    _classes = await db.getAllClasses();
    _groups = await db.getAllGroups();
    _wordTypes = await db.getAllWordTypes();
    setState(() {});
  }

  Future<void> _loadWords() async {
    if (_selectedId == null) return;
    final db = ref.read(databaseProvider);

    List<Word> words;
    switch (_filterType) {
      case 'class':
        words = await db.getWordsByClass(_selectedId!);
        break;
      case 'group':
        words = await db.getWordsByGroup(_selectedId!);
        break;
      case 'type':
        words = await db.getWordsByType(_selectedId!);
        break;
      default:
        words = [];
    }

    // Remove duplicates
    final seen = <int>{};
    words = words.where((w) => seen.add(w.id)).toList();

    setState(() {
      _words = words;
      _currentIndex = 0;
      _showBack = false;
      _started = true;
    });
  }

  void _shuffle() {
    setState(() {
      _words.shuffle(Random());
      _currentIndex = 0;
      _showBack = false;
    });
  }

  void _next() {
    if (_currentIndex < _words.length - 1) {
      setState(() {
        _currentIndex++;
        _showBack = false;
      });
    }
  }

  void _prev() {
    if (_currentIndex > 0) {
      setState(() {
        _currentIndex--;
        _showBack = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Flashcards'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: !_started ? _buildConfig(theme) : _buildFlashcard(theme),
      ),
    );
  }

  Widget _buildConfig(ThemeData theme) {
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
            .map((t) => DropdownMenuItem(value: t.id, child: Text(t.name)))
            .toList();
        break;
      default:
        items = [];
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.style, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Flashcard Study', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 32),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'class', label: Text('Class')),
                ButtonSegment(value: 'group', label: Text('Group')),
                ButtonSegment(value: 'type', label: Text('Type')),
              ],
              selected: {_filterType},
              onSelectionChanged: (v) =>
                  setState(() {
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
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedId == null ? null : _loadWords,
                child: const Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFlashcard(ThemeData theme) {
    if (_words.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('No words found', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => setState(() => _started = false),
              child: const Text('Back to config'),
            ),
          ],
        ),
      );
    }

    final word = _words[_currentIndex];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  onPressed: () => setState(() => _started = false),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                Text('${_currentIndex + 1} / ${_words.length}',
                    style: theme.textTheme.titleMedium),
                IconButton(
                  onPressed: _shuffle,
                  icon: const Icon(Icons.shuffle),
                  tooltip: 'Shuffle',
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Card
            GestureDetector(
              onTap: () => setState(() => _showBack = !_showBack),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Card(
                  key: ValueKey('${word.id}_$_showBack'),
                  elevation: 4,
                  child: Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 250),
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (!_showBack) ...[
                          Text(word.name,
                              style: theme.textTheme.displaySmall,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Text('Tap to flip',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(
                                      color:
                                          theme.colorScheme.outline)),
                        ] else ...[
                          Text(word.meaning,
                              style: theme.textTheme.headlineMedium,
                              textAlign: TextAlign.center),
                          if (word.example.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Text(word.example,
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(
                                        fontStyle: FontStyle.italic),
                                textAlign: TextAlign.center),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  onPressed: _currentIndex > 0 ? _prev : null,
                  icon: const Icon(Icons.arrow_back),
                  iconSize: 32,
                ),
                const SizedBox(width: 32),
                IconButton.filled(
                  onPressed:
                      _currentIndex < _words.length - 1 ? _next : null,
                  icon: const Icon(Icons.arrow_forward),
                  iconSize: 32,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
