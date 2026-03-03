import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';

class FillBlankScreen extends StatefulWidget {
  final List<Word> words;
  final String title;

  const FillBlankScreen({super.key, required this.words, required this.title});

  @override
  State<FillBlankScreen> createState() => _FillBlankScreenState();
}

class _FillBlankScreenState extends State<FillBlankScreen> {
  int _currentIndex = 0;
  int _score = 0;
  final _answerCtrl = TextEditingController();
  late FocusNode _answerFocus;
  bool _answered = false;
  bool _correct = false;
  late List<Word> _shuffledWords;

  @override
  void initState() {
    super.initState();
    _answerFocus = FocusNode();
    _shuffledWords = List.from(widget.words)..shuffle(Random());
  }

  @override
  void dispose() {
    _answerCtrl.dispose();
    _answerFocus.dispose();
    super.dispose();
  }

  void _check() {
    if (_answered) return;
    final answer = _answerCtrl.text.trim().replaceAll(' ', '').toLowerCase();
    final correct = _shuffledWords[_currentIndex]
        .name
        .trim()
        .replaceAll(' ', '')
        .toLowerCase();
    setState(() {
      _answered = true;
      _correct = answer == correct;
      if (_correct) _score++;
    });
    _answerFocus.requestFocus();
  }

  void _next() {
    if (_currentIndex < _shuffledWords.length - 1) {
      setState(() {
        _currentIndex++;
        _answered = false;
        _correct = false;
        _answerCtrl.clear();
      });
      _answerFocus.requestFocus();
    } else {
      _showResults();
    }
  }

  void _showResults() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Results'),
        content: Text('Score: $_score / ${_shuffledWords.length}\n'
            '${(_score / _shuffledWords.length * 100).toStringAsFixed(0)}% correct'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.pop();
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
    final word = _shuffledWords[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text('Fill Blank - ${widget.title}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: (_currentIndex + 1) / _shuffledWords.length,
                ),
                const SizedBox(height: 8),
                Text('${_currentIndex + 1} / ${_shuffledWords.length}',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Text('What is the word for:',
                            style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 8),
                        Text(word.meaning,
                            style: theme.textTheme.headlineSmall,
                            textAlign: TextAlign.center),
                        if (word.example.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(word.example,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(fontStyle: FontStyle.italic),
                              textAlign: TextAlign.center),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _answerCtrl,
                  focusNode: _answerFocus,
                  decoration: InputDecoration(
                    labelText: 'Type the word',
                    suffixIcon: !_answered
                        ? IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: _check,
                          )
                        : null,
                  ),
                  enabled: !_answered,
                  onFieldSubmitted: (_) => _check(),
                  autofocus: true,
                ),
                if (_answered) ...[
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _correct ? Icons.check_circle : Icons.cancel,
                        color: _correct ? Colors.green : Colors.red,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _correct ? 'Correct!' : 'Wrong! Answer: ${word.name}',
                        style: TextStyle(
                          color: _correct ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _next,
                    child: Text(_currentIndex < _shuffledWords.length - 1
                        ? 'Next'
                        : 'Finish'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
