import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/database/app_database.dart';

class McqScreen extends StatefulWidget {
  final List<Word> words;
  final String title;

  const McqScreen({super.key, required this.words, required this.title});

  @override
  State<McqScreen> createState() => _McqScreenState();
}

class _McqScreenState extends State<McqScreen> {
  int _currentIndex = 0;
  int _score = 0;
  int? _selectedOption;
  bool _answered = false;
  late List<Word> _shuffledWords;

  @override
  void initState() {
    super.initState();
    _shuffledWords = List.from(widget.words)..shuffle(Random());
  }

  List<String> _getOptions(Word current) {
    final rng = Random();
    final options = <String>{current.meaning};
    final allMeanings =
        widget.words.map((w) => w.meaning).toSet().toList();

    while (options.length < min(4, allMeanings.length)) {
      options.add(allMeanings[rng.nextInt(allMeanings.length)]);
    }

    return options.toList()..shuffle(rng);
  }

  void _answer(int index, List<String> options, Word word) {
    if (_answered) return;
    setState(() {
      _selectedOption = index;
      _answered = true;
      if (options[index] == word.meaning) {
        _score++;
      }
    });
  }

  void _next() {
    if (_currentIndex < _shuffledWords.length - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
        _answered = false;
      });
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
        content: Text(
            'Score: $_score / ${_shuffledWords.length}\n'
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
    final options = _getOptions(word);

    return Scaffold(
      appBar: AppBar(
        title: Text('MCQ - ${widget.title}'),
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
                Text(
                    '${_currentIndex + 1} / ${_shuffledWords.length}',
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(word.name,
                        style: theme.textTheme.headlineMedium,
                        textAlign: TextAlign.center),
                  ),
                ),
                const SizedBox(height: 24),
                ...List.generate(options.length, (i) {
                  Color? bgColor;
                  if (_answered) {
                    if (options[i] == word.meaning) {
                      bgColor = Colors.green.withValues(alpha: 0.2);
                    } else if (i == _selectedOption) {
                      bgColor = Colors.red.withValues(alpha: 0.2);
                    }
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () => _answer(i, options, word),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: bgColor,
                          padding: const EdgeInsets.all(16),
                        ),
                        child: Text(options[i],
                            textAlign: TextAlign.center),
                      ),
                    ),
                  );
                }),
                if (_answered) ...[
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
