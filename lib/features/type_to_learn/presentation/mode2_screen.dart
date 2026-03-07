import 'dart:async';
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
  int _nextCountdown = 0;
  Timer? _countdownTimer;
  final _countdownNotifier = ValueNotifier<int>(0);

  List<ClassesData> _classes = [];
  List<Paragraph> _paragraphs = [];

  List<String> _chars = [];
  int _currentCharIndex = 0;
  final _inputCtrl = TextEditingController();
  late FocusNode _inputFocus;
  List<_CharStatus> _charStatuses = [];
  final _scrollCtrl = ScrollController();
  int _elapsedSeconds = 0;
  Timer? _timer;
  // Tracks how many committed (non-composing) chars we've already processed
  String _processedInput = '';

  @override
  void initState() {
    super.initState();
    _inputFocus = FocusNode();
    _inputCtrl.addListener(_onControllerChanged);
    _loadData();
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _scrollCtrl.dispose();
    _timer?.cancel();
    _countdownTimer?.cancel();
    _countdownNotifier.dispose();
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

  void _pickRandom() {
    if (_paragraphs.isEmpty) return;
    final rng = DateTime.now().millisecondsSinceEpoch;
    final idx = rng % _paragraphs.length;
    setState(() => _selectedParagraphId = _paragraphs[idx].id);
    _startPractice(paragraphId: _paragraphs[idx].id);
  }

  void _startPractice({int? paragraphId}) {
    final pid = paragraphId ?? _selectedParagraphId;
    if (pid == null) return;
    final para = _paragraphs.firstWhere((p) => p.id == pid);
    final allChars = para.content.split('');
    _chars = allChars;
    _charStatuses = allChars.map((_) => _CharStatus()).toList();
    _currentCharIndex = 0;
    _processedInput = '';
    _inputCtrl.clear();
    _autoSkipSpaces();
    _elapsedSeconds = 0;
    _timer?.cancel();
    setState(() => _started = true);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  void _autoSkipSpaces() {
    while (_currentCharIndex < _chars.length &&
        _chars[_currentCharIndex].trim().isEmpty) {
      _currentCharIndex++;
    }
  }

  /// Called on every TextEditingController change.
  /// Processes committed chars and previews composing text in real-time.
  void _onControllerChanged() {
    if (_currentCharIndex >= _chars.length) return;

    final tv = _inputCtrl.value;
    final composing = tv.composing;
    final bool isComposing = composing.isValid && composing != TextRange.empty;

    final String committed;
    final String composingText;
    if (isComposing) {
      committed = tv.text.substring(0, composing.start) +
          tv.text.substring(composing.end);
      composingText = tv.text.substring(composing.start, composing.end);
    } else {
      committed = tv.text;
      composingText = '';
    }

    bool changed = false;

    // Reset any previously-composing chars back to pending
    for (int i = _currentCharIndex; i < _chars.length; i++) {
      if (_charStatuses[i].status == _Status.composing) {
        _charStatuses[i].status = _Status.pending;
        changed = true;
      } else {
        break; // composing preview chars are always consecutive
      }
    }

    // Reset wrong indicator on current char if field has new content
    if (_charStatuses[_currentCharIndex].status == _Status.wrong &&
        tv.text.isNotEmpty) {
      _charStatuses[_currentCharIndex].status = _Status.pending;
      changed = true;
    }

    // Sync processed pointer down if committed text was deleted
    if (committed.length < _processedInput.length) {
      _processedInput = committed;
      if (changed) setState(() {});
      return;
    }

    // Process newly committed characters
    if (committed.length > _processedInput.length) {
      final newChars = committed.substring(_processedInput.length);
      _processedInput = committed;

      for (final ch in newChars.split('')) {
        if (_currentCharIndex >= _chars.length) break;
        if (ch == _chars[_currentCharIndex]) {
          _charStatuses[_currentCharIndex].status = _Status.correct;
          _currentCharIndex++;
          _autoSkipSpaces();
          changed = true;
        } else {
          _charStatuses[_currentCharIndex].status = _Status.wrong;
          _charStatuses[_currentCharIndex].attempts++;
          changed = true;
          break;
        }
      }
    }

    // Preview composing text against upcoming expected chars
    if (composingText.isNotEmpty && _currentCharIndex < _chars.length) {
      int scanIdx = _currentCharIndex;
      for (final ch in composingText.split('')) {
        // skip spaces in source
        while (scanIdx < _chars.length && _chars[scanIdx].trim().isEmpty) {
          scanIdx++;
        }
        if (scanIdx >= _chars.length) break;
        if (ch == _chars[scanIdx]) {
          _charStatuses[scanIdx].status = _Status.composing;
          scanIdx++;
          changed = true;
        } else {
          break; // stop preview on first mismatch
        }
      }
    }

    if (changed) setState(() {});

    if (_currentCharIndex >= _chars.length) {
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
    final totalTyped =
        _charStatuses.where((s) => s.status != _Status.pending).length;
    final wrongChars = _charStatuses.where((s) => s.attempts > 1).length;
    final elapsed = _elapsedSeconds;

    // Start 5s countdown — pops the dialog and picks next paragraph
    _nextCountdown = 5;
    _countdownNotifier.value = 5;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      _nextCountdown--;
      _countdownNotifier.value = _nextCountdown;
      if (_nextCountdown <= 0) {
        t.cancel();
        // Pop using the screen's own navigator context (safe with GoRouter)
        final nav = Navigator.of(context, rootNavigator: false);
        if (nav.canPop()) nav.pop();
        _pickRandom();
      }
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Completed!'),
        content: ValueListenableBuilder<int>(
          valueListenable: _countdownNotifier,
          builder: (_, countdown, __) => Text(
            'All $totalTyped characters typed!\n'
            'Wrong attempts: $wrongChars chars\n'
            'Time: ${_formatTime(elapsed)}\n\n'
            'Next random paragraph in $countdown s...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _countdownTimer?.cancel();
              Navigator.pop(ctx);
              setState(() {
                _started = false;
                _nextCountdown = 0;
              });
            },
            child: const Text('Back to config'),
          ),
          FilledButton(
            onPressed: () {
              _countdownTimer?.cancel();
              Navigator.pop(ctx);
              _pickRandom();
            },
            child: const Text('Next now'),
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
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedParagraphId,
                    decoration:
                        const InputDecoration(labelText: 'Select Paragraph'),
                    items: _paragraphs
                        .map((p) => DropdownMenuItem<int>(
                            value: p.id, child: Text(p.title)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedParagraphId = v),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Random paragraph',
                  child: IconButton.filled(
                    onPressed: _paragraphs.isEmpty ? null : _pickRandom,
                    icon: const Icon(Icons.shuffle),
                  ),
                ),
              ],
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
    final total = _chars.where((c) => c.trim().isNotEmpty).length;
    final done = _charStatuses.where((s) => s.status == _Status.correct).length;

    return Column(
      children: [
        LinearProgressIndicator(value: total == 0 ? 0 : done / total),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$done / $total chars', style: theme.textTheme.bodySmall),
            Text('Time: ${_formatTime(_elapsedSeconds)}',
                style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 16),
        // Paragraph display — character by character
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            child: _buildCharDisplay(theme),
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
                  hintText: _currentCharIndex < _chars.length
                      ? 'Type: "${_chars[_currentCharIndex]}"'
                      : 'Done!',
                  prefixIcon: const Icon(Icons.keyboard),
                ),
                autofocus: true,
                enabled: _currentCharIndex < _chars.length,
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Skip to random paragraph',
              child: IconButton(
                icon: const Icon(Icons.skip_next),
                onPressed: _paragraphs.length > 1 ? _pickRandom : null,
              ),
            ),
            TextButton(
              onPressed: () {
                _timer?.cancel();
                _countdownTimer?.cancel();
                setState(() => _started = false);
              },
              child: const Text('Stop'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCharDisplay(ThemeData theme) {
    final spans = <InlineSpan>[];
    for (int i = 0; i < _chars.length; i++) {
      final ch = _chars[i];
      if (ch.trim().isEmpty) {
        // whitespace — render as-is
        spans.add(TextSpan(
          text: ch,
          style: const TextStyle(fontSize: 50),
        ));
      } else if (i < _currentCharIndex) {
        spans.add(TextSpan(
          text: ch,
          style: TextStyle(
              fontSize: 50,
              color: Colors.green.shade600,
              fontWeight: FontWeight.w500),
        ));
      } else if (_charStatuses[i].status == _Status.composing) {
        // IME composing preview — amber highlight
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.amber.shade700, width: 1.5),
            ),
            child: Text(
              ch,
              style: TextStyle(
                fontSize: 50,
                fontWeight: FontWeight.bold,
                color: Colors.amber.shade800,
              ),
            ),
          ),
        ));
      } else if (i == _currentCharIndex) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: _charStatuses[i].status == _Status.wrong
                  ? Colors.red.withValues(alpha: 0.25)
                  : theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: _charStatuses[i].status == _Status.wrong
                    ? Colors.red
                    : theme.colorScheme.primary,
                width: 1.5,
              ),
            ),
            child: Text(
              ch,
              style: TextStyle(
                fontSize: 50,
                fontWeight: FontWeight.bold,
                color: _charStatuses[i].status == _Status.wrong
                    ? Colors.red
                    : theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ));
      } else {
        spans.add(TextSpan(
          text: ch,
          style: TextStyle(fontSize: 50, color: theme.colorScheme.onSurface),
        ));
      }
    }
    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.left,
    );
  }
}

enum _Status { pending, correct, wrong, composing }

class _CharStatus {
  _Status status;
  int attempts;
  _CharStatus()
      : status = _Status.pending,
        attempts = 1;
}
