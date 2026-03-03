import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/database/database_provider.dart';

class Mode2Screen extends ConsumerStatefulWidget {
  const Mode2Screen({super.key});

  @override
  ConsumerState<Mode2Screen> createState() => _Mode2ScreenState();
}

class _Mode2ScreenState extends ConsumerState<Mode2Screen> {
  int? _selectedClassId;
  int? _selectedParagraphId;
  bool _started = false;

  List<ClassesData> _classes = [];
  List<Paragraph> _paragraphs = [];

  List<String> _paragraphWords = [];
  int _currentWordIndex = 0;
  final _inputCtrl = TextEditingController();
  late FocusNode _inputFocus;
  final List<_WordStatus> _wordStatuses = [];
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode();
    _loadData();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final db = ref.read(databaseProvider);
    _classes = await db.getAllClasses();
    setState(() {});
  }

  Future<void> _loadParagraphs() async {
    if (_selectedClassId == null) return;
    final db = ref.read(databaseProvider);
    _paragraphs = await db.getParagraphsByClass(_selectedClassId!);
    _selectedParagraphId = null;
    setState(() {});
  }

  void _startPractice() {
    if (_selectedParagraphId == null) return;
    final para = _paragraphs.firstWhere((p) => p.id == _selectedParagraphId);
    _paragraphWords =
        para.content.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    _wordStatuses.clear();
    for (final w in _paragraphWords) {
      _wordStatuses.add(_WordStatus(word: w));
    }
    _currentWordIndex = 0;
    setState(() => _started = true);
  }

  void _onSubmit(String text) {
    final typed = text.trim();
    if (typed.isEmpty || _currentWordIndex >= _paragraphWords.length) return;

    final expected = _paragraphWords[_currentWordIndex];
    // Strip punctuation and spaces for comparison
    String clean(String s) =>
        s.replaceAll(RegExp(r'[^\w]'), '').replaceAll(' ', '').toLowerCase();

    if (clean(typed) == clean(expected)) {
      setState(() {
        _wordStatuses[_currentWordIndex].status = _Status.correct;
        _currentWordIndex++;
      });
    } else {
      setState(() {
        _wordStatuses[_currentWordIndex].status = _Status.wrong;
        _wordStatuses[_currentWordIndex].attempts++;
      });
    }

    _inputCtrl.clear();
    _inputFocus.requestFocus();

    // Check if done
    if (_currentWordIndex >= _paragraphWords.length) {
      _showResults();
    }
  }

  void _showResults() {
    final totalAttempts = _wordStatuses.fold<int>(0, (a, s) => a + s.attempts);
    final wrongWords = _wordStatuses.where((w) => w.attempts > 1).length;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Completed!'),
        content: Text('All ${_paragraphWords.length} words typed correctly!\n'
            'Mistakes: $wrongWords words needed extra attempts\n'
            'Total attempts: $totalAttempts'),
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
        title: const Text('Type to Learn - Paragraph'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: !_started ? _buildConfig(theme) : _buildPractice(theme),
      ),
    );
  }

  Widget _buildConfig(ThemeData theme) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.keyboard, size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('Paragraph Typing', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text('Type each word in order to complete the paragraph',
                style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            DropdownButtonFormField<int>(
              value: _selectedClassId,
              decoration: const InputDecoration(labelText: 'Select Class'),
              items: _classes
                  .map((c) =>
                      DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: (v) {
                setState(() => _selectedClassId = v);
                _loadParagraphs();
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              value: _selectedParagraphId,
              decoration: const InputDecoration(labelText: 'Select Paragraph'),
              items: _paragraphs
                  .map((p) =>
                      DropdownMenuItem<int>(value: p.id, child: Text(p.title)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedParagraphId = v),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _selectedParagraphId == null ? null : _startPractice,
                child: const Text('Start'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPractice(ThemeData theme) {
    return Column(
      children: [
        // Progress
        LinearProgressIndicator(
          value: _currentWordIndex / _paragraphWords.length,
        ),
        const SizedBox(height: 8),
        Text('$_currentWordIndex / ${_paragraphWords.length} words',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 16),
        // Paragraph display
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: Wrap(
              spacing: 6,
              runSpacing: 8,
              children: List.generate(_paragraphWords.length, (i) {
                Color bgColor;
                Color textColor;
                if (i < _currentWordIndex) {
                  bgColor = Colors.green.withValues(alpha: 0.2);
                  textColor = Colors.green.shade700;
                } else if (i == _currentWordIndex) {
                  bgColor = _wordStatuses[i].status == _Status.wrong
                      ? Colors.red.withValues(alpha: 0.2)
                      : theme.colorScheme.primaryContainer;
                  textColor = _wordStatuses[i].status == _Status.wrong
                      ? Colors.red
                      : theme.colorScheme.onPrimaryContainer;
                } else {
                  bgColor = theme.colorScheme.surfaceContainerHighest;
                  textColor = theme.colorScheme.onSurfaceVariant;
                }

                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(6),
                    border: i == _currentWordIndex
                        ? Border.all(color: theme.colorScheme.primary, width: 2)
                        : null,
                  ),
                  child: Text(
                    i <= _currentWordIndex
                        ? _paragraphWords[i]
                        : '•' * _paragraphWords[i].length,
                    style: TextStyle(
                      color: textColor,
                      fontWeight: i == _currentWordIndex
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 16,
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Input
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                focusNode: _inputFocus,
                decoration: InputDecoration(
                  hintText: _currentWordIndex < _paragraphWords.length
                      ? 'Type: ${_paragraphWords[_currentWordIndex]}'
                      : 'Done!',
                  prefixIcon: const Icon(Icons.keyboard),
                ),
                onSubmitted: _onSubmit,
                autofocus: true,
                enabled: _currentWordIndex < _paragraphWords.length,
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() => _started = false),
              child: const Text('Stop'),
            ),
          ],
        ),
      ],
    );
  }
}

enum _Status { pending, correct, wrong }

class _WordStatus {
  final String word;
  _Status status;
  int attempts;

  _WordStatus({required this.word})
      : status = _Status.pending,
        attempts = 1;
}
