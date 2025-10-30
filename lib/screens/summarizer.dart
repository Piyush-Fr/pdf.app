import 'dart:convert';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';
import '../utils/error_handler.dart';
import '../config/app_config.dart';

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  bool _loading = false;
  String? _summary;
  String? _fileName;

  Future<http.Response> _postGeminiWithRetry(Uri uri, Map<String, dynamic> body) async {
    const int maxAttempts = 5;
    int attempt = 0;
    Duration delay = const Duration(seconds: 2);
    http.Response? lastResp;
    while (attempt < maxAttempts) {
      attempt++;
      try {
        final resp = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );
        bool overloaded = resp.statusCode == 429 || resp.statusCode == 503;
        if (!overloaded && resp.statusCode >= 500 && resp.statusCode < 600) {
          overloaded = true;
        }
        if (!overloaded) {
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
        if (kDebugMode) {
          debugPrint('Gemini summarizer overloaded (attempt $attempt/$maxAttempts). Retrying in ${delay.inSeconds}s...');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Gemini summarizer HTTP error on attempt $attempt: $e');
        }
      }
      await Future.delayed(delay);
      delay = Duration(seconds: (delay.inSeconds * 2).clamp(2, 32));
    }
    return lastResp ?? http.Response('{"error":{"status":"UNAVAILABLE","message":"Retry attempts exhausted"}}', 503);
  }

  Future<void> _pickAndSummarize() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _summary = null;
      _fileName = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _loading = false);
        return;
      }
      final picked = result.files.first;
      _fileName = picked.name;
      final bytes = picked.bytes;
      
      if (bytes == null) {
        throw Exception('Failed to read selected file');
      }
      
      // Validate file size (50MB max)
      if (!ErrorHandler.validateFileSize(bytes.length, maxMB: 50)) {
        throw Exception('File size must not exceed 50MB');
      }

      final summary = await _summarizeWithGeminiPdf(bytes);
      setState(() => _summary = summary);
    } on TimeoutException {
      if (!mounted) return;
      ErrorHandler.showError(
        context,
        'Summarization timed out',
        details: 'The request took too long. Please try again.',
      );
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(
        context,
        'Summarization failed',
        details: ErrorHandler.formatErrorMessage(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _summarizeWithGeminiPdf(List<int> pdfBytes) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
    );
    final prompt =
        'Summarize the attached PDF into at most 10 concise bullet points with short headings.'
        '\nHard cap: total <= 200 words. Keep each bullet <= 20 words.'
        '\nNo long prose, no code, no tables. Output plain text only.';
    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
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
        'temperature': 0.2,
        'maxOutputTokens': 4096,
        'response_mime_type': 'text/plain',
      },
      'safetySettings': [
        {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
        {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
        {'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT', 'threshold': 'BLOCK_NONE'},
        {'category': 'HARM_CATEGORY_DANGEROUS_CONTENT', 'threshold': 'BLOCK_NONE'},
      ],
    };
    final response = await _postGeminiWithRetry(uri, requestBody);
    if (kDebugMode) {
      debugPrint('Raw Gemini summary response: ${response.body}');
    }
    if (response.statusCode != 200) {
      throw Exception('Gemini error ${response.statusCode}: ${response.body}');
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = map['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return 'No summary produced (model returned no candidates).';
    final first = candidates.first as Map<String, dynamic>;
    final finishReason = first['finishReason']?.toString();
    if (kDebugMode) {
      debugPrint('Summarizer finishReason: $finishReason');
    }
    final content = first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      if (finishReason == 'MAX_TOKENS') {
        return 'Summary truncated by model output limit. Please try again or pick a smaller PDF.';
      }
      return 'No summary produced.';
    }
    final buffer = StringBuffer();
    for (final part in parts) {
      final t = (part as Map)['text'];
      if (t is String && t.trim().isNotEmpty) buffer.writeln(t);
    }
    final text = buffer.toString().trim();
    if (kDebugMode) {
      debugPrint('Summarizer extracted text length: ${text.length}');
    }
    if (text.isEmpty) {
      // Fallback user-facing hint
      return 'No summary produced.';
    }
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final providedBytes = args != null ? args['pdfBytes'] as List<int>? : null;
    final providedName = args != null ? args['pdfFilename'] as String? : null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : (providedBytes != null
                            ? () async {
                                setState(() {
                                  _loading = true;
                                  _summary = null;
                                  _fileName = providedName;
                                });
                                try {
                                  final s = await _summarizeWithGeminiPdf(
                                    providedBytes,
                                  );
                                  if (!mounted) return;
                                  setState(() => _summary = s);
                                } catch (e) {
                                  if (!mounted) return;
                                  // ignore: use_build_context_synchronously
                                  final messenger = ScaffoldMessenger.of(context);
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('Summarization failed: $e'),
                                    ),
                                  );
                                } finally {
                                  if (mounted) setState(() => _loading = false);
                                }
                              }
                            : _pickAndSummarize),
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  icon: _loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.description),
                  label: Text(
                    _loading
                        ? 'Processing…'
                        : (providedBytes != null
                              ? 'Summarize PDF'
                              : 'Pick PDF to Summarize'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_fileName != null || providedName != null)
              Text(
                'Selected: ${_fileName ?? providedName}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            const SizedBox(height: 12),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha((0.05 * 255).round()),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(16),
                child: _summary == null
                    ? const Center(
                        child: Text('No summary yet. Pick a PDF to begin.'),
                      )
                    : Markdown(data: _summary!, selectable: true),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
