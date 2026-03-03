import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class Mode1Screen extends ConsumerStatefulWidget {
  const Mode1Screen({super.key});

  @override
  ConsumerState<Mode1Screen> createState() => _Mode1ScreenState();
}

class _Mode1ScreenState extends ConsumerState<Mode1Screen>
    with TickerProviderStateMixin {
  String _filterType = 'class';
  int? _selectedId;
  bool _started = false;

  List<ClassesData> _classes = [];
  List<Group> _groups = [];
  List<WordType> _wordTypes = [];

  final List<_FloatingWord> _floatingWords = [];
  final _inputCtrl = TextEditingController();
  late FocusNode _inputFocus;
  late AnimationController _tickController;
  int _score = 0;
  int _totalWords = 0;

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode();
    _loadFilters();
    _tickController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..addListener(_onTick);
  }

  @override
  void dispose() {
    _tickController.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    for (final fw in _floatingWords) {
      fw.controller.dispose();
    }
    super.dispose();
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  Future<void> _loadFilters() async {
    final db = ref.read(databaseProvider);
    _classes = await db.getAllClasses();
    _groups = await db.getAllGroups();
    _wordTypes = await db.getAllWordTypes();
    setState(() {});
  }

  Future<void> _startGame() async {
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

    final seen = <int>{};
    words = words.where((w) => seen.add(w.id)).toList();
    words.shuffle(Random());

    if (words.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No words found')),
        );
      }
      return;
    }

    // Clean up old floating words
    for (final fw in _floatingWords) {
      fw.controller.dispose();
    }
    _floatingWords.clear();

    final rng = Random();
    _totalWords = words.length;
    _score = 0;

    for (int i = 0; i < words.length; i++) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(seconds: 8 + rng.nextInt(8)),
      );

      final fw = _FloatingWord(
        word: words[i],
        yPosition: 50.0 + rng.nextDouble() * 300,
        controller: ctrl,
      );
      _floatingWords.add(fw);

      // Stagger starts
      Future.delayed(Duration(milliseconds: i * 1500 + rng.nextInt(1000)), () {
        if (mounted && !fw.dismissed) {
          ctrl.repeat();
        }
      });
    }

    setState(() => _started = true);
    _tickController.repeat();
  }

  void _onSubmit(String text) {
    final typed = text.trim().replaceAll(' ', '').toLowerCase();
    if (typed.isEmpty) return;

    for (final fw in _floatingWords) {
      if (!fw.dismissed &&
          fw.word.name.replaceAll(' ', '').toLowerCase() == typed) {
        setState(() {
          fw.dismissed = true;
          fw.controller.stop();
          _score++;
        });
        break;
      }
    }

    _inputCtrl.clear();
    _inputFocus.requestFocus();

    // Check if all done
    if (_floatingWords.every((fw) => fw.dismissed)) {
      _tickController.stop();
      _showResults();
    }
  }

  void _showResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Completed!'),
        content: Text('You typed $_score / $_totalWords words correctly!'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _started = false);
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Type to Learn - Floating Words'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: !_started ? _buildConfig(theme) : _buildGame(theme),
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
            .map((t) => DropdownMenuItem<int>(value: t.id, child: Text(t.name)))
            .toList();
        break;
      default:
        items = [];
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Floating Words', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('Words float across the screen. Type them to dismiss!',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center),
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
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selectedId == null ? null : _startGame,
                  child: const Text('Start'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGame(ThemeData theme) {
    return Column(
      children: [
        // Score bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Score: $_score / $_totalWords',
                  style: theme.textTheme.titleMedium),
              TextButton(
                onPressed: () {
                  _tickController.stop();
                  setState(() => _started = false);
                },
                child: const Text('Stop'),
              ),
            ],
          ),
        ),
        // Floating area
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return Stack(
                children: _floatingWords.where((fw) => !fw.dismissed).map((fw) {
                  final progress = fw.controller.value;
                  final x = constraints.maxWidth * (1.0 - progress) -
                      20; // right to left
                  final y = fw.yPosition;
                  return Positioned(
                    left: x,
                    top: y.clamp(0, constraints.maxHeight - 40),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color:
                                theme.colorScheme.shadow.withValues(alpha: 0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        fw.word.name,
                        style: TextStyle(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ),
        // Input
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            decoration: const InputDecoration(
              hintText: 'Type the word and press Enter...',
              prefixIcon: Icon(Icons.keyboard),
            ),
            onSubmitted: _onSubmit,
            autofocus: true,
          ),
        ),
      ],
    );
  }
}

class _FloatingWord {
  final Word word;
  final double yPosition;
  final AnimationController controller;
  bool dismissed;

  _FloatingWord({
    required this.word,
    required this.yPosition,
    required this.controller,
  }) : dismissed = false;
}
