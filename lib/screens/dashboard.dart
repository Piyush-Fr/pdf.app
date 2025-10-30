import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import 'dart:convert'; // add for base64 and JSON
import 'package:http/http.dart' as http; // add for Gemini call

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  static const String _bucketName = 'documents';
  final List<_PdfCard> _cards = [];

  Future<Uint8List?> _generatePdfThumbnail(Uint8List pdfBytes) async {
    try {
      final doc = await PdfDocument.openData(pdfBytes);
      final page = await doc.getPage(1);
      final rendered = await page.render(
        width: 600,
        height: 800,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await doc.close();
      return rendered?.bytes;
    } catch (_) {
      return null;
    }
  }

  void _showImportBenchmarkDialog() async {
    await showDialog(
      context: context,
      builder: (context) => _ImportBenchmarkDialog(
        onImported:
            (
              String fileName,
              Uint8List pdfBytes,
              String contextText,
              int benchmarkScore,
            ) async {
              final client = Supabase.instance.client;
              final storagePath =
                  'uploads/ ${DateTime.now().millisecondsSinceEpoch}_$fileName';
              try {
                final thumb = await _generatePdfThumbnail(pdfBytes);
                if (!mounted) return;
                await client.storage
                    .from(_bucketName)
                    .uploadBinary(
                      storagePath,
                      pdfBytes,
                      fileOptions: const FileOptions(
                        contentType: 'application/pdf',
                        upsert: false,
                      ),
                    );
                // Here, you should also save the benchmark/context metadata, e.g. in a separate table,
                // or encode as JSON in object metadata if Supabase supports it.
                // For now, we'll add locally to the dashboard only:
                setState(() {
                  _cards.insert(
                    0,
                    _PdfCard(
                      title: fileName,
                      benchmark: benchmarkScore,
                      context: contextText,
                      previewBytes: thumb,
                      storagePath: storagePath,
                    ),
                  );
                });
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Uploaded and benchmarked: $fileName'),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Upload/benchmark failed: $e')),
                );
              }
            },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadExistingFromSupabase();
  }

  Future<void> _loadExistingFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      final items = await client.storage
          .from(_bucketName)
          .list(path: 'uploads');
      // Sort newest first
      items.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      final List<_PdfCard> fetched = [];
      for (final obj in items) {
        final name = obj.name;
        final path = 'uploads/$name';
        Uint8List? thumb;
        try {
          final data = await client.storage.from(_bucketName).download(path);
          thumb = await _generatePdfThumbnail(data);
        } catch (_) {
          thumb = null;
        }
        fetched.add(
          _PdfCard(
            title: name,
            benchmark: 72,
            context:
                '', // Fix: pass empty string for context when loading legacy PDFs
            previewBytes: thumb,
            storagePath: path,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _cards
            ..clear()
            ..addAll(fetched);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load files: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final _PdfCard? top = _cards.isEmpty
        ? null
        : _cards.reduce((a, b) => a.benchmark >= b.benchmark ? a : b);
    final width = MediaQuery.of(context).size.width;
    final crossAxisCount = (width ~/ 220).clamp(2, 6);
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            'Your Library',
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: _showImportBenchmarkDialog,
                child: OCLiquidGlassGroup(
                  settings: const OCLiquidGlassSettings(
                    refractStrength: -0.06,
                    blurRadiusPx: 3.0,
                    specStrength: 1.0,
                    lightbandColor: Colors.white,
                  ),
                  child: OCLiquidGlass(
                    width: 150,
                    height: 40,
                    borderRadius: 12,
                    color: Colors.white.withAlpha((0.10 * 255).round()),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Import PDF',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: CustomScrollView(
          cacheExtent: 1000,
          slivers: [
            if (_cards.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text('No PDFs yet. Tap "Import PDF" to add one.'),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 4 / 5,
                ),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final card = _cards[index];
                  final isTop = top != null && card == top;
                  return _PdfGlassCard(
                    data: card,
                    isTop: isTop,
                    onTap: () async {
                      try {
                        final bytes = await Supabase.instance.client.storage
                            .from(_bucketName)
                            .download(card.storagePath);
                        if (!mounted) return;
                        Navigator.of(context).pushNamed(
                          '/study',
                          arguments: {
                            'centerPanel': true,
                            'pdfBytes': bytes,
                            'pdfFilename': card.title,
                          },
                        );
                      } catch (e) {
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Open failed: $e')),
                        );
                      }
                    },
                  );
                }, childCount: _cards.length),
              ),
            ),
            // Extra space at bottom so glass shaders don't sample beyond content
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _PdfGlassCard extends StatefulWidget {
  const _PdfGlassCard({
    required this.data,
    required this.isTop,
    required this.onTap,
  });
  final _PdfCard data;
  final bool isTop;
  final VoidCallback onTap;

  @override
  State<_PdfGlassCard> createState() => _PdfGlassCardState();
}

class _PdfGlassCardState extends State<_PdfGlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return RepaintBoundary(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withAlpha((0.16 * 255).round()),
                              Colors.white.withAlpha((0.06 * 255).round()),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withAlpha((0.18 * 255).round()),
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    color: Colors.white,
                                    child: widget.data.previewBytes != null
                                        ? Image.memory(
                                            widget.data.previewBytes!,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white.withAlpha(
                                                (0.04 * 255).round(),
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                widget.data.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.data.context,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: Colors.white70),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.bolt, size: 16, color: accent),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      '${widget.data.benchmark} benchmark',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Subtle border to distinguish tile edges over the background
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withAlpha((0.10 * 255).round()),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Top-card glow removed per request
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PdfCard {
  _PdfCard({
    required this.title,
    required this.benchmark,
    required this.context,
    this.previewBytes,
    required this.storagePath,
  });
  final String title;
  final int benchmark;
  final String context;
  final Uint8List? previewBytes;
  final String storagePath;
}

class _ImportBenchmarkDialog extends StatefulWidget {
  final Function(
    String fileName,
    Uint8List pdfBytes,
    String contextText,
    int benchmarkScore,
  )
  onImported;
  const _ImportBenchmarkDialog({required this.onImported});
  @override
  State<_ImportBenchmarkDialog> createState() => __ImportBenchmarkDialogState();
}

class __ImportBenchmarkDialogState extends State<_ImportBenchmarkDialog> {
  Uint8List? _pdfBytes;
  String? _fileName;
  final TextEditingController _contextController = TextEditingController();
  bool _benchmarking = false;
  int? _benchmarkScore;
  String? _errorMsg;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
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
      _benchmarkScore = null;
      _errorMsg = null;
    });
  }

  Future<void> _runBenchmark() async {
    if (_pdfBytes == null) return;
    setState(() {
      _benchmarking = true;
      _errorMsg = null;
    });
    try {
      final contextText = _contextController.text.trim();
      print('--- BENCHMARKING DEBUG START ---');
      print('Context: $contextText');

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=AIzaSyBKRquBMtDQsyM7dw8OZlZZe3whX29GrZo',
      );
      final prompt =
          'You are a PDF benchmarking expert. Your task is to evaluate the relevance of the attached document to a given context.\n'
          'Context: "$contextText"\n'
          'Based on this context, provide a score from 0 to 100, where 100 means the document is perfectly relevant and 0 means it is completely irrelevant.\n'
          'IMPORTANT: Respond with ONLY the integer score. Do not include any other words, symbols, or explanations.';

      print('Prompt sent to Gemini:\n$prompt');

      final body = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'application/pdf',
                  'data': base64Encode(_pdfBytes!),
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.0,
          'maxOutputTokens': 100,
          'response_mime_type': 'text/plain',
        },
      };
      final resp = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      print('Gemini response status: ${resp.statusCode}');

      if (resp.statusCode != 200) {
        print('Gemini error response body: ${resp.body}');
        throw Exception('Benchmark error: ${resp.body}');
      }

      final bodyJson = jsonDecode(resp.body);
      print('Decoded response JSON: $bodyJson');

      final candidates = bodyJson['candidates'] as List?;
      String numberStr = '';
      if (candidates != null && candidates.isNotEmpty) {
        final content = candidates[0]['content'];
        if (content != null &&
            content['parts'] != null &&
            content['parts'] is List &&
            content['parts'].isNotEmpty) {
          final part = content['parts'][0];
          if (part['text'] != null) {
            numberStr = part['text'].toString().trim();
          }
        }
      }

      print('Extracted model output for parsing: "$numberStr"');

      // Gemini may wrap the number; parse extract an int
      final match = RegExp(r'(\d{1,3})').firstMatch(numberStr);
      print('RegExp match on extracted output: ${match?.group(1)}');

      int score = match != null ? int.parse(match.group(1)!) : 0;
      print('Parsed score (before clamp): $score');

      score = score.clamp(0, 100);
      print('Final score (after clamp): $score');
      print('--- BENCHMARKING DEBUG END ---');

      setState(() {
        _benchmarkScore = score;
        _benchmarking = false;
      });
    } catch (e) {
      print('--- BENCHMARKING ERROR ---');
      print('Error during benchmark: $e');
      print('--- END BENCHMARKING ERROR ---');
      setState(() {
        _errorMsg = 'Benchmarking failed: $e';
        _benchmarking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Import & Benchmark PDF'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _contextController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Context/Topic',
                hintText: 'Enter topic for benchmarking...',
              ),
            ),
            const SizedBox(height: 12),
            _pdfBytes == null
                ? ElevatedButton.icon(
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Select PDF'),
                    onPressed: _pickPdf,
                  )
                : Column(
                    children: [
                      Text(_fileName ?? ''),
                      ElevatedButton.icon(
                        icon: _benchmarking
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bolt),
                        label: Text(
                          _benchmarkScore == null
                              ? 'Run Benchmark'
                              : 'Benchmark: $_benchmarkScore',
                        ),
                        onPressed: (_benchmarking || _benchmarkScore != null)
                            ? null
                            : _runBenchmark,
                      ),
                    ],
                  ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (!mounted) return;
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
        if (_pdfBytes != null && _benchmarkScore != null)
          ElevatedButton(
            onPressed: () async {
              await widget.onImported(
                _fileName!,
                _pdfBytes!,
                _contextController.text.trim(),
                _benchmarkScore!,
              );
              if (!mounted) return;
              Navigator.of(context).pop();
            },
            child: const Text('Save to Dashboard'),
          ),
      ],
    );
  }
}
