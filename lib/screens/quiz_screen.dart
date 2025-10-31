import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.quiz});
  final Map<String, dynamic> quiz;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final List<dynamic> _questions =
      widget.quiz['questions'] as List<dynamic>;
  late final List<int?> _answers = List<int?>.filled(_questions.length, null);
  bool _submitted = false;

  int get _score {
    int s = 0;
    for (var i = 0; i < _questions.length; i++) {
      final correct = (_questions[i]['correctIndex'] as num?)?.toInt();
      if (correct != null && _answers[i] == correct) s++;
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                  const Spacer(),
                  if (_submitted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withAlpha((0.12 * 255).round()),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Score: $_score / ${_questions.length}'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: _questions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final q = _questions[index] as Map<String, dynamic>;
                    final opts = (q['options'] as List).cast<String>();
                    final selected = _answers[index];
                    final correct = (q['correctIndex'] as num?)?.toInt();
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white.withAlpha((0.16 * 255).round()),
                                Colors.white.withAlpha((0.06 * 255).round()),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withAlpha(
                                (0.18 * 255).round(),
                              ),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Q${index + 1}. ${q['question']}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Column(
                                  children: [
                                    for (var i = 0; i < opts.length; i++)
                                      RadioListTile<int>(
                                        // ignore: deprecated_member_use
                                        groupValue: selected,
                                        value: i,
                                        // ignore: deprecated_member_use
                                        onChanged: _submitted
                                            ? null
                                            : (int? v) {
                                                setState(() {
                                                  _answers[index] = v;
                                                });
                                              },
                                        title: Text(opts[i]),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        tileColor: _submitted
                                            ? (i == correct
                                                  ? Colors.green.withAlpha(
                                                      (0.15 * 255).round(),
                                                    )
                                                  : (selected == i
                                                        ? Colors.red.withAlpha(
                                                            (0.15 * 255)
                                                                .round(),
                                                          )
                                                        : null))
                                            : null,
                                        controlAffinity:
                                            ListTileControlAffinity.leading,
                                        activeColor: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitted
                      ? null
                      : () => setState(() => _submitted = true),
                  child: const Text('Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
