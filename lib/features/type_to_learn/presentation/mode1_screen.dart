import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
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
  Set<int> _selectedIds = {};
  bool _started = false;

  List<ClassesData> _classes = [];
  List<Group> _groups = [];
  List<WordType> _wordTypes = [];

  final List<_FloatingWord> _floatingWords = [];
  // All words not yet completed (includes words currently floating)
  final List<Word> _pendingWords = [];
  final _inputCtrl = TextEditingController();
  late FocusNode _inputFocus;
  late AnimationController _tickController;
  int _score = 0;
  int _totalWords = 0;
  int _elapsedSeconds = 0;
  Timer? _timer;

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
    _timer?.cancel();
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
    if (_selectedIds.isEmpty) return;
    final db = ref.read(databaseProvider);

    List<Word> words = [];
    for (final id in _selectedIds) {
      List<Word> chunk;
      switch (_filterType) {
        case 'class':
          chunk = await db.getActiveWordsByClass(id);
          break;
        case 'group':
          chunk = await db.getActiveWordsByGroup(id);
          break;
        case 'type':
          chunk = await db.getActiveWordsByType(id);
          break;
        default:
          chunk = [];
      }
      words.addAll(chunk);
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
    _pendingWords.clear();
    _timer?.cancel();
    _elapsedSeconds = 0;

    final rng = Random();
    _totalWords = words.length;
    _score = 0;

    // pendingWords holds ALL incomplete words (including those currently floating)
    _pendingWords.addAll(words);
    _pendingWords.shuffle(rng);

    // Spawn initial floating words (max 5) without removing from pendingWords
    final maxInitialWords = min(5, _pendingWords.length);
    for (int i = 0; i < maxInitialWords; i++) {
      _createFloatingWord(_pendingWords[i], i, rng);
    }

    setState(() => _started = true);
    _tickController.repeat();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  void _createFloatingWord(Word word, int index, Random rng) {
    final ctrl = AnimationController(
      vsync: this,
      duration: Duration(seconds: 8 + rng.nextInt(8)),
    );

    final fw = _FloatingWord(
      word: word,
      showMeaning: rng.nextBool(),
      yPosition: rng.nextDouble() * 600,
      verticalOffset: 30.0 + rng.nextDouble() * 40,
      verticalSpeed: 0.5 + rng.nextDouble() * 1.0,
      controller: ctrl,
    );
    _floatingWords.add(fw);

    // When animation completes the word has crossed the left edge — dismiss it
    ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed &&
          !fw.dismissed &&
          !fw._offScreenDismissed) {
        fw._offScreenDismissed = true;
        fw.dismissed = true;
        if (mounted) {
          _floatingWords.remove(fw);
          _addWordFromPendingNotFloating();
          setState(() {});
        }
      }
    });

    // Stagger starts then run once (forward, not repeat)
    Future.delayed(Duration(milliseconds: index * 1500 + rng.nextInt(1000)),
        () {
      if (mounted && !fw.dismissed) {
        ctrl.forward();
      }
    });
  }

  /// Picks a random word from pendingWords that is NOT currently floating
  /// and spawns it as a new floating word immediately (no stagger delay).
  void _addWordFromPendingNotFloating() {
    final floatingIds = _floatingWords
        .where((fw) => !fw.dismissed)
        .map((fw) => fw.word.id)
        .toSet();

    final candidates =
        _pendingWords.where((w) => !floatingIds.contains(w.id)).toList();

    if (candidates.isEmpty) return;

    final rng = Random();
    final word = candidates[rng.nextInt(candidates.length)];
    // Use index=0 so replacement appears immediately without stagger delay
    _createFloatingWord(word, 0, rng);
  }

  void _onSubmit(String text) {
    final typed = text.trim().replaceAll(' ', '').toLowerCase();
    if (typed.isEmpty) return;

    // Always match against word name (vocabulary), regardless of what the cloud shows.
    Word? matchedPending;
    for (final w in _pendingWords) {
      if (w.name.replaceAll(' ', '').toLowerCase() == typed) {
        matchedPending = w;
        break;
      }
    }

    if (matchedPending != null) {
      _pendingWords.removeWhere((w) => w.id == matchedPending!.id);
      setState(() => _score++);

      // Also check if it's currently floating — if so, dismiss and replace
      _FloatingWord? matchedFloating;
      for (final fw in _floatingWords) {
        if (!fw.dismissed && fw.word.id == matchedPending!.id) {
          matchedFloating = fw;
          break;
        }
      }

      if (matchedFloating != null) {
        setState(() {
          matchedFloating!.dismissed = true;
          matchedFloating.controller.stop();
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _floatingWords.removeWhere((w) => w.dismissed);
            _addWordFromPendingNotFloating();
            setState(() {});
            _checkAllDone();
          }
        });
      } else {
        _checkAllDone();
      }
    }

    _inputCtrl.clear();
    _inputFocus.requestFocus();
  }

  void _checkAllDone() {
    if (_pendingWords.isEmpty &&
        _floatingWords.where((w) => !w.dismissed).isEmpty) {
      _tickController.stop();
      _timer?.cancel();
      _showResults();
    }
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  void _showResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Completed!'),
        content: Text('You typed $_score / $_totalWords words correctly!\n'
            'Time: ${_formatTime(_elapsedSeconds)}'),
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Icon(Icons.cloud, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('Floating Words',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center),
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
                  _selectedIds = {};
                }),
              ),
              const SizedBox(height: 16),
              _buildMultiSelect(theme),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: _selectedIds.isEmpty ? null : _startGame,
                child: const Text('Start'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMultiSelect(ThemeData theme) {
    List<({int id, String label})> options;
    switch (_filterType) {
      case 'class':
        options = _classes.map((c) => (id: c.id, label: c.name)).toList();
        break;
      case 'group':
        options = _groups.map((g) => (id: g.id, label: g.name)).toList();
        break;
      case 'type':
        options = _wordTypes.map((t) => (id: t.id, label: t.name)).toList();
        break;
      default:
        options = [];
    }

    if (options.isEmpty) {
      return Text('No options available',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              _selectedIds.isEmpty
                  ? 'Select (tap to toggle)'
                  : '${_selectedIds.length} selected',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.secondary),
            ),
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(
                  () => _selectedIds = options.map((o) => o.id).toSet()),
              child: const Text('All'),
            ),
            if (_selectedIds.isNotEmpty)
              TextButton(
                style:
                    TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => setState(() => _selectedIds = {}),
                child: const Text('Clear'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: options.map((opt) {
            final selected = _selectedIds.contains(opt.id);
            return FilterChip(
              label: Text(opt.label),
              selected: selected,
              onSelected: (v) => setState(() {
                if (v) {
                  _selectedIds = {..._selectedIds, opt.id};
                } else {
                  _selectedIds = _selectedIds.difference({opt.id});
                }
              }),
            );
          }).toList(),
        ),
      ],
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score: $_score / $_totalWords',
                      style: theme.textTheme.titleMedium),
                  Text(
                    'Time: ${_formatTime(_elapsedSeconds)}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              TextButton(
                onPressed: () {
                  _tickController.stop();
                  _timer?.cancel();
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
                  final x = constraints.maxWidth * (1.0 - progress) - 20;

                  // Vertical bobbing motion using sine wave
                  final verticalBob =
                      sin(progress * 2 * pi * fw.verticalSpeed) *
                          fw.verticalOffset;
                  final y = (fw.yPosition + verticalBob)
                      .clamp(0.0, constraints.maxHeight - 60);

                  // Calculate cloud size based on displayed text length
                  final displayText =
                      fw.showMeaning ? fw.word.meaning : fw.word.name;
                  final cloudWidth = (200 + displayText.length * 10)
                      .toDouble()
                      .clamp(220.0, 420.0);
                  final cloudHeight =
                      cloudWidth / 2.0; // Maintain 2:1 aspect ratio

                  return Positioned(
                      left: x,
                      top: y,
                      child: SizedBox(
                        width: cloudWidth,
                        height: cloudHeight,
                        child: Stack(
                          children: [
                            // ☁️ Cloud fill hết container
                            Positioned.fill(
                              child: SvgPicture.asset(
                                'assets/cloud.svg',
                                fit: BoxFit.fitHeight, // hoặc BoxFit.cover
                              ),
                            ),

                            // 📝 Text nằm dưới + center ngang
                            Positioned(
                              bottom: cloudHeight * 0.25, // chỉnh % tuỳ bạn
                              left: 8,
                              right: 8,
                              child: Text(
                                fw.showMeaning ? fw.word.meaning : fw.word.name,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: fw.showMeaning ? 16 : 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ));
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
              hintText: 'Type the vocabulary and press Enter...',
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
  final bool showMeaning;
  final double yPosition;
  final double verticalOffset;
  final double verticalSpeed;
  final AnimationController controller;
  bool dismissed;
  bool _offScreenDismissed = false;

  _FloatingWord({
    required this.word,
    required this.showMeaning,
    required this.yPosition,
    required this.verticalOffset,
    required this.verticalSpeed,
    required this.controller,
  }) : dismissed = false;
}
