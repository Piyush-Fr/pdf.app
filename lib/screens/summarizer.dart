import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_markdown/flutter_markdown.dart';

class SummarizerScreen extends StatefulWidget {
  const SummarizerScreen({super.key});

  @override
  State<SummarizerScreen> createState() => _SummarizerScreenState();
}

class _SummarizerScreenState extends State<SummarizerScreen> {
  static const String _geminiApiKey = 'AIzaSyDbtD-Wj3SjJr3cDpHpucpF6VRPRBJ4GdU';
  bool _loading = false;
  String? _summary;
  String? _fileName;

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

      final summary = await _summarizeWithGeminiPdf(bytes);
      setState(() => _summary = summary);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Summarization failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _summarizeWithGeminiPdf(Uint8List pdfBytes) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
    );
    final prompt =
        'Summarize the attached PDF into concise bullet points with headings, under 250 words.';
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
    };
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(requestBody),
    );
    if (response.statusCode != 200) {
      throw Exception('Gemini error ${response.statusCode}: ${response.body}');
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    final candidates = map['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return 'No summary produced.';
    final content = candidates.first['content'] as Map<String, dynamic>?;
    final parts = content?['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) return 'No summary produced.';
    final text = parts.first['text'] as String?;
    return text ?? 'No summary produced.';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final providedBytes = args != null ? args['pdfBytes'] as Uint8List? : null;
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
                                  ScaffoldMessenger.of(context).showSnackBar(
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
                  color: Colors.white.withOpacity(0.05),
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
