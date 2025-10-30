import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class QuizSetupScreen extends StatefulWidget {
  const QuizSetupScreen({super.key});

  @override
  State<QuizSetupScreen> createState() => _QuizSetupScreenState();
}

class _QuizSetupScreenState extends State<QuizSetupScreen> {
  static const String _geminiApiKey = 'AIzaSyBKRquBMtDQsyM7dw8OZlZZe3whX29GrZo';
  final TextEditingController _contextController = TextEditingController();
  bool _loading = false;
  String? _fileName;
  Uint8List? _pdfBytes;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _pickAndGenerate() async {
    if (_loading) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      setState(() {
        _fileName = picked.name;
        _pdfBytes = picked.bytes;
      });
      if (_pdfBytes == null) {
        throw Exception('Failed to read selected file');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF selection failed: $e')));
    }
  }

  Future<Map<String, dynamic>> _generateQuiz(
    Uint8List pdfBytes,
    String contextText,
  ) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
    );
    final systemPrompt =
        'You are a strict quiz generator. Return ONLY valid JSON.';
    final userPrompt =
        'Create a minimum of 10 multiple-choice questions (prefer more if possible) based on the attached PDF and this context: "${contextText}". Do NOT stop at fewer than 10.'
        '\nEach question and option MUST be concise.'
        '\nReturn ONLY pure JSON in this format: '
        '{"questions": [{"question": string, "options": [string,string,string,string], "correctIndex": number 0-3}]}'
        '\nNo markdown. No triple backticks. No commentary. No explanations. No comments. No code fences. Only machine-readable JSON!';

    final body = {
      'system_instruction': {
        'role': 'system',
        'parts': [
          {'text': systemPrompt},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': userPrompt},
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Encode(pdfBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 4096,
        'response_mime_type': 'application/json',
      },
      'safetySettings': [
        {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
        {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
        {
          'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'threshold': 'BLOCK_NONE',
        },
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_NONE',
        },
      ],
    };

    final resp = await _postGeminiWithRetry(
      uri,
      body,
    );

    assert(() {
      print('Raw Gemini quiz API response: ${resp.body}');
      return true;
    }());

    if (resp.statusCode != 200) {
      throw Exception('Gemini error ${resp.statusCode}: ${resp.body}');
    }
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    assert(() {
      try {
        final cands = data['candidates'] as List?;
        final first = (cands != null && cands.isNotEmpty) ? cands.first as Map<String, dynamic> : null;
        final finishReason = first != null ? first['finishReason'] : null;
        print('Quiz finishReason: $finishReason');
      } catch (_) {}
      return true;
    }());
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw Exception('No quiz produced');
    }
    // Concatenate any text parts if model returns multiple parts
    final parts =
        (candidates.first['content']?['parts'] as List?)
                ?.whereType<Map>()
                .toList() ??
            [];
    final buffer = StringBuffer();
    for (final p in parts) {
      final t = p['text'];
      if (t is String) buffer.write(t);
    }
    final text = buffer.toString().trim();

    assert(() {
      print('Extracted model output for quiz parsing: $text');
      return true;
    }());

    if (text.isEmpty) {
      final retry = await _retryContextOnly(contextText, prevFail: true);
      if (retry == null || retry.trim().isEmpty) {
        throw Exception('Empty response from model.');
      }
      return _safeParseQuizJson(retry);
    }

    // Try parse JSON safely
    try {
      final parsed = _safeParseQuizJson(text);
      if (parsed['questions'] is! List) {
        throw Exception('Malformed quiz JSON');
      }
      return parsed;
    } catch (e) {
      // Show partial output in error snackbar, debug print for diagnosis
      assert(() {
        print('Quiz JSON parse error! Raw model text: $text');
        print('Parse exception: $e');
        return true;
      }());
      throw FormatException('Failed to parse quiz JSON.\nModel output: $text');
    }
  }

  Future<String?> _retryContextOnly(String contextText, {bool prevFail = false}) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
    );
    final prompt = prevFail
        ? 'Last time you did NOT return valid JSON. This time, RETURN ONLY MACHINE-READABLE JSON. No markdown, code fences, commentary. Format: {"questions": [{"question": string, "options": [string,string,string,string], "correctIndex": 0-3}]}\nContext: ${contextText}'
        : 'Create a minimum of 10 MCQs from this context only (no PDF available). Do NOT stop at fewer than 10. Use STRICT JSON. Return pure JSON: {"questions": [{"question": string, "options": [string,string,string,string], "correctIndex": 0-3}]}\nContext: ${contextText}';
    final body = {
      'system_instruction': {
        'role': 'system',
        'parts': [
          {'text': 'Return ONLY JSON. No commentary.'},
        ],
      },
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 2048,
        'response_mime_type': 'application/json',
      },
      'safetySettings': [
        {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
        {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
        {
          'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
          'threshold': 'BLOCK_NONE',
        },
        {
          'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
          'threshold': 'BLOCK_NONE',
        },
      ],
    };
    final resp = await _postGeminiWithRetry(
      uri,
      body,
    );
    assert(() {
      print('Raw Gemini retry response: ${resp.body}');
      return true;
    }());
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts =
        (candidates.first['content']?['parts'] as List?)
                ?.whereType<Map>()
                .toList() ??
            [];
    final buffer = StringBuffer();
    for (final p in parts) {
      final t = p['text'];
      if (t is String) buffer.write(t);
    }
    return buffer.toString();
  }

  Future<http.Response> _postGeminiWithRetry(Uri uri, Map<String, dynamic> body) async {
    const int maxAttempts = 3;
    int attempt = 0;
    Duration delay = const Duration(seconds: 1);
    http.Response? lastResp;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        final resp = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        // Detect overload via status code or error payload
        bool overloaded = resp.statusCode == 429 || resp.statusCode == 503;
        if (!overloaded && resp.statusCode >= 500 && resp.statusCode < 600) {
          overloaded = true;
        }
        if (!overloaded) {
          // Also inspect JSON error payload if provided
          try {
            final parsed = jsonDecode(resp.body);
            final err = parsed is Map ? parsed['error'] as Map? : null;
            if (err != null) {
              final status = err['status']?.toString();
              if (status == 'UNAVAILABLE') overloaded = true;
            }
          } catch (_) {}
        }
        if (!overloaded) return resp;
        lastResp = resp;
        assert(() {
          print('Gemini overloaded (attempt $attempt/${maxAttempts}). Retrying in ${delay.inSeconds}s...');
          return true;
        }());
      } catch (e) {
        // Network or transient error, retry
        assert(() {
          print('Gemini HTTP error on attempt $attempt: $e');
          return true;
        }());
      }
      await Future.delayed(delay);
      delay *= 2;
    }
    return lastResp ?? http.Response('Retry attempts exhausted', 503);
  }

  Map<String, dynamic> _safeParseQuizJson(String raw) {
    String s = raw.trim();
    s = s.replaceAll('```json', '').replaceAll('```', '');
    // Normalize smart quotes
    s = s
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'");
    // Remove trailing commas before closing tokens
    s = s.replaceAll(RegExp(r",\s*(\]|\})"), r"$1");
    // Attempt 1: direct parse
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {}
    // Attempt 2: trim outermost {...}
    final start = s.indexOf('{');
    final endLast = s.lastIndexOf('}');
    if (start != -1 && endLast != -1 && endLast > start) {
      final sub = s.substring(start, endLast + 1);
      try {
        return jsonDecode(sub) as Map<String, dynamic>;
      } catch (_) {}
      // Attempt 3: find first valid {...} substring
      final reg = RegExp(r'\{[^}]*\}');
      final matches = reg.allMatches(s);
      for (final match in matches) {
        try {
          final candidate = s.substring(match.start, match.end);
          return jsonDecode(candidate) as Map<String, dynamic>;
        } catch (_) {}
      }
      // Attempt 4: balance braces/brackets by appending closers
      final balanced = _balanceJsonBrackets(sub);
      try {
        return jsonDecode(balanced) as Map<String, dynamic>;
      } catch (_) {}
    }
    throw const FormatException('Failed to parse quiz JSON');
  }

  String _balanceJsonBrackets(String input) {
    final buffer = StringBuffer(input.trim());
    int curlies = 0;
    int squares = 0;
    for (int i = 0; i < buffer.length; i++) {
      final ch = buffer.toString()[i];
      if (ch == '{') curlies++;
      if (ch == '}') curlies--;
      if (ch == '[') squares++;
      if (ch == ']') squares--;
    }
    while (squares > 0) {
      buffer.write(']');
      squares--;
    }
    while (curlies > 0) {
      buffer.write('}');
      curlies--;
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    if (args != null && _pdfBytes == null) {
      _pdfBytes = args['pdfBytes'] as Uint8List?;
      _fileName = args['pdfFilename'] as String?;
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Card(
            color: Colors.white.withOpacity(0.06),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Quiz Setup',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _contextController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      hintText:
                          'Add context/instructions (e.g., focus topics, difficulty, number of questions)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _pickAndGenerate,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                          ),
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Select PDF'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (!_loading && _pdfBytes != null)
                              ? () async {
                                  setState(() => _loading = true);
                                  try {
                                    final quiz = await _generateQuiz(
                                      _pdfBytes!,
                                      _contextController.text.trim(),
                                    );
                                    if (!mounted) return;
                                    Navigator.of(
                                      context,
                                    ).pushNamed('/quiz', arguments: quiz);
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Quiz generation failed: $e',
                                        ),
                                      ),
                                    );
                                  } finally {
                                    if (mounted)
                                      setState(() => _loading = false);
                                  }
                                }
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                          ),
                          icon: _loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.play_arrow),
                          label: Text(
                            _loading ? 'Generating…' : 'Generate Quiz',
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_fileName != null) ...[
                    const SizedBox(height: 8),
                    Text('Selected: $_fileName'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
