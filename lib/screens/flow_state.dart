import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../utils/error_handler.dart';
import '../config/app_config.dart';

class FlowStateScreen extends StatefulWidget {
  const FlowStateScreen({super.key, required this.pdfBytes, this.filename});
  final Uint8List pdfBytes;
  final String? filename;

  @override
  State<FlowStateScreen> createState() => _FlowStateScreenState();
}

class _FlowStateScreenState extends State<FlowStateScreen> {
  Map<String, dynamic>? _graph;
  bool _loading = false;
  String? _error;
  final TextEditingController _contextController = TextEditingController();
  String? _ascii;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _generateGraph(String contextText) async {
    try {
      // Validate input
      final validation = ErrorHandler.validateInput(
        contextText,
        fieldName: 'Context',
        minLength: 3,
        maxLength: 500,
      );

      if (validation != null) {
        throw Exception(validation);
      }

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
      );
      final prompt =
          'Analyze the attached PDF and produce a concise flow diagram for the requested context.\n'
          'OUTPUT FORMAT (STRICT): Provide ONLY a JSON object wrapped in <json>...</json> tags, no commentary.\n'
          '{"nodes": [{"id": string, "label": string}], "edges": [{"from": string, "to": string}]}\n'
          'Rules: 6–12 nodes, labels <= 5 words.\n'
          'Context: $contextText';
      final body = {
        'system_instruction': {
          'role': 'system',
          'parts': [
            {
              'text':
                  'You output machine-readable JSON only. No code fences, no commentary.',
            },
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
              {
                'inline_data': {
                  'mime_type': 'application/pdf',
                  'data': base64Encode(widget.pdfBytes),
                },
              },
            ],
          },
        ],
        'generationConfig': {
          'temperature': 0.2,
          'maxOutputTokens': 3072,
          'response_mime_type': 'text/plain',
        },
      };

      // Add timeout
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(
            const Duration(seconds: 90),
            onTimeout: () =>
                throw TimeoutException('Flow generation timed out'),
          );

      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}: ${resp.body}');
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw Exception('Empty response');
      }
      final parts = (candidates.first['content']?['parts'] as List?) ?? [];
      final text = parts.map((p) => (p['text'] ?? '') as String).join();
      final block = _extractBetween(text, '<json>', '</json>') ?? text;
      var graph = _safeParseGraphJson(block);
      if ((graph['nodes'] as List? ?? []).length < 2) {
        // Retry with a simpler linear-steps prompt, then synthesize nodes/edges
        final linear = await _retryLinear(contextText);
        if (linear != null && linear.trim().isNotEmpty) {
          graph = _synthesizeLinearGraph(linear);
        } else {
          // Final retry: ask for bullets and synthesize
          final bullets = await _retryBullets(contextText);
          if (bullets != null && bullets.trim().isNotEmpty) {
            graph = _synthesizeBulletsGraph(bullets);
          }
        }
      }
      setState(() {
        _graph = graph;
        _loading = false;
      });
    } on TimeoutException catch (e) {
      setState(() {
        _error = 'Timeout: ${e.toString()}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = ErrorHandler.formatErrorMessage(e);
        _loading = false;
      });
    }
  }

  Future<String?> _retryLinear(String contextText) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
    );
    final prompt =
        'Read the attached PDF and output a single line that describes the main flow using arrows, like: A -> B -> C -> D. '
        'No commentary, no code fences, just that one line. Context: $contextText';
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Encode(widget.pdfBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 256,
        'response_mime_type': 'text/plain',
      },
    };
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = (candidates.first['content']?['parts'] as List?) ?? [];
    return parts.map((p) => (p['text'] ?? '') as String).join();
  }

  Map<String, dynamic> _synthesizeLinearGraph(String text) {
    // Parse patterns like "A -> B -> C" or multi-line steps into nodes/edges
    String s = text.replaceAll('```', '').trim();
    if (s.contains('->')) {
      final labels = s
          .split('->')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final nodes = <Map<String, String>>[];
      final edges = <Map<String, String>>[];
      for (int i = 0; i < labels.length; i++) {
        nodes.add({'id': 'n$i', 'label': labels[i]});
        if (i > 0) edges.add({'from': 'n${i - 1}', 'to': 'n$i'});
      }
      if (nodes.isNotEmpty) return {'nodes': nodes, 'edges': edges};
    }
    final lines = s
        .split(RegExp(r'\r?\n'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final nodes = <Map<String, String>>[];
    final edges = <Map<String, String>>[];
    for (int i = 0; i < lines.length; i++) {
      nodes.add({'id': 'n$i', 'label': lines[i]});
      if (i > 0) edges.add({'from': 'n${i - 1}', 'to': 'n$i'});
    }
    return nodes.isNotEmpty
        ? {'nodes': nodes, 'edges': edges}
        : {
            'nodes': [
              {'id': 'doc', 'label': 'Document'},
            ],
            'edges': [],
          };
  }

  Future<String?> _retryBullets(String contextText) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
    );
    final prompt =
        'From the attached PDF, list 6-12 key steps as a simple bullet list.\n'
        'One step per line, no numbering, no commentary. Keep each step <= 6 words.\n'
        'Context: $contextText';
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Encode(widget.pdfBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 512,
        'response_mime_type': 'text/plain',
      },
    };
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = (candidates.first['content']?['parts'] as List?) ?? [];
    return parts.map((p) => (p['text'] ?? '') as String).join();
  }

  Map<String, dynamic> _synthesizeBulletsGraph(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((e) => e.replaceFirst(RegExp(r'^[\-\*\d\.)\s]+'), ''))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final nodes = <Map<String, String>>[];
    final edges = <Map<String, String>>[];
    for (int i = 0; i < lines.length; i++) {
      nodes.add({'id': 'b$i', 'label': lines[i]});
      if (i > 0) edges.add({'from': 'b${i - 1}', 'to': 'b$i'});
    }
    return nodes.isNotEmpty
        ? {'nodes': nodes, 'edges': edges}
        : {
            'nodes': [
              {'id': 'doc', 'label': 'Document'},
            ],
            'edges': [],
          };
  }

  Map<String, dynamic> _safeParseGraphJson(String raw) {
    String s = raw.trim();
    s = s.replaceAll('```json', '').replaceAll('```', '');
    s = s
        .replaceAll('\u201c', '"')
        .replaceAll('\u201d', '"')
        .replaceAll('\u2018', "'")
        .replaceAll('\u2019', "'");
    s = s.replaceAll(RegExp(r",\s*(\]|\})"), r"$1");
    try {
      return jsonDecode(s) as Map<String, dynamic>;
    } catch (_) {
      /* fallthrough */
    }
    final start = s.indexOf('{');
    final end = s.lastIndexOf('}');
    if (start != -1 && end != -1 && end > start) {
      final sub = s.substring(start, end + 1);
      try {
        return jsonDecode(sub) as Map<String, dynamic>;
      } catch (_) {
        final balanced = _balanceJsonBrackets(sub);
        return jsonDecode(balanced) as Map<String, dynamic>;
      }
    }
    return {
      'nodes': [
        {'id': 'doc', 'label': 'Document'},
      ],
      'edges': [],
    };
  }

  String _balanceJsonBrackets(String input) {
    final buf = StringBuffer(input.trim());
    int curlies = 0, squares = 0;
    for (final ch in buf.toString().runes) {
      final c = String.fromCharCode(ch);
      if (c == '{') curlies++;
      if (c == '}') curlies--;
      if (c == '[') squares++;
      if (c == ']') squares--;
    }
    while (squares > 0) {
      buf.write(']');
      squares--;
    }
    while (curlies > 0) {
      buf.write('}');
      curlies--;
    }
    return buf.toString();
  }

  String? _extractBetween(String source, String start, String end) {
    final i = source.indexOf(start);
    if (i == -1) return null;
    final j = source.indexOf(end, i + start.length);
    if (j == -1) return null;
    return source.substring(i + start.length, j);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: Text(
            widget.filename != null
                ? 'Flow State • ${widget.filename}'
                : 'Flow State',
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _contextController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: 'Add context (e.g., "data ingestion pipeline")',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _loading = true;
                          _graph = null;
                          _error = null;
                          _ascii = null;
                        });
                        _generateAsciiThenGraph(_contextController.text.trim());
                      },
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_graph),
                label: Text(_loading ? 'Generating…' : 'Generate Flow Diagram'),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_error != null)
                    ? Center(child: Text('Failed: $_error'))
                    : (_ascii != null)
                    ? _AsciiView(ascii: _ascii!)
                    : (_graph == null)
                    ? const Center(child: Text('Add context and generate'))
                    : _FlowGraphView(graph: _graph!),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _generateAsciiThenGraph(String contextText) async {
    try {
      final ascii = await _generateAscii(contextText);
      if (ascii != null && ascii.trim().isNotEmpty) {
        setState(() {
          _ascii = _cleanupAscii(ascii);
          _loading = false;
        });
        return;
      }
    } catch (_) {
      // fall back to graph
    }
    await _generateGraph(contextText);
  }

  Future<String?> _generateAscii(String contextText) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
    );
    final prompt =
        'Create a clear ASCII flowchart for the attached PDF and context below.\n'
        'Use ONLY plain ASCII characters: +-|/\\, arrows like ->, labels, and boxes.\n'
        'Keep width <= 70 chars; multiline boxes allowed; include simple branching labels (Yes/No) if relevant.\n'
        'No code fences, no commentary. Output the flowchart only.\n'
        'Context: $contextText';
    final body = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': 'application/pdf',
                'data': base64Encode(widget.pdfBytes),
              },
            },
          ],
        },
      ],
      'generationConfig': {
        'temperature': 0.2,
        'maxOutputTokens': 2048,
        'response_mime_type': 'text/plain',
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
    final resp = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final candidates = data['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) return null;
    final parts = (candidates.first['content']?['parts'] as List?) ?? [];
    return parts.map((p) => (p['text'] ?? '') as String).join();
  }

  String _cleanupAscii(String s) {
    var t = s.trim();
    t = t.replaceAll('```', '');
    return t;
  }
}

class _FlowGraphView extends StatelessWidget {
  const _FlowGraphView({required this.graph});
  final Map<String, dynamic> graph;

  @override
  Widget build(BuildContext context) {
    final nodes = (graph['nodes'] as List? ?? []).cast<Map>();
    final edges = (graph['edges'] as List? ?? []).cast<Map>();

    // Vertically scrollable layout with a left spine and right boxes
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final viewportHeight = c.maxHeight;
        const double top = 24.0;
        const double tileHeight = 56.0;
        const double vGap = 36.0;
        const double tileWidth = 260.0;
        final double contentHeight = (nodes.isEmpty)
            ? viewportHeight
            : top + nodes.length * (tileHeight + vGap) - vGap + 24.0;
        final double spineX = width * 0.22;

        final positions = <String, Offset>{};
        for (var i = 0; i < nodes.length; i++) {
          final y = top + i * (tileHeight + vGap) + tileHeight / 2;
          final x = spineX + 150; // center of tile to the right of spine
          positions[nodes[i]['id'] as String] = Offset(x, y);
        }

        return SingleChildScrollView(
          child: SizedBox(
            width: width,
            height: contentHeight,
            child: CustomPaint(
              painter: _FlowPainter(
                nodes,
                edges,
                positions,
                spineX: spineX,
                tileWidth: tileWidth,
                tileHeight: tileHeight,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter(
    this.nodes,
    this.edges,
    this.pos, {
    required this.spineX,
    required this.tileWidth,
    required this.tileHeight,
  });
  final List<Map> nodes;
  final List<Map> edges;
  final Map<String, Offset> pos;
  final double spineX;
  final double tileWidth;
  final double tileHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()..color = const Color(0x66FFFFFF);
    final border = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final connectorPaint = Paint()
      ..color = Colors.white.withAlpha((0.6 * 255).round())
      ..strokeWidth = 1.5;

    // Draw left vertical spine
    if (pos.isNotEmpty) {
      final ys = pos.values.map((o) => o.dy).toList()..sort();
      final topY = ys.first - tileHeight / 2 - 8;
      final bottomY = ys.last + tileHeight / 2 + 8;
      canvas.drawLine(
        Offset(spineX, topY),
        Offset(spineX, bottomY),
        connectorPaint,
      );
    }

    // Draw nodes
    for (final n in nodes) {
      final p = pos[n['id']];
      if (p == null) continue;
      final rect = Rect.fromCenter(
        center: p,
        width: tileWidth,
        height: tileHeight,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(10));
      // Connect tile to spine with a small node
      final y = p.dy;
      final leftEdgeX = rect.left;
      canvas.drawLine(Offset(spineX, y), Offset(leftEdgeX, y), connectorPaint);
      canvas.drawCircle(Offset(spineX, y), 3.0, connectorPaint);
      canvas.drawRRect(rrect, nodePaint);
      canvas.drawRRect(rrect, border);
      final label = (n['label'] ?? '').toString();
      textPainter.text = TextSpan(
        style: const TextStyle(color: Colors.white),
        text: label,
      );
      textPainter.layout(maxWidth: tileWidth - 24);
      final tp = Offset(
        rect.center.dx - textPainter.width / 2,
        rect.center.dy - textPainter.height / 2,
      );
      textPainter.paint(canvas, tp);
    }
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) => false;
}

class _AsciiView extends StatelessWidget {
  const _AsciiView({required this.ascii});
  final String ascii;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withAlpha((0.06 * 255).round()),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha((0.15 * 255).round())),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: SelectableText(
              ascii,
              style: const TextStyle(
                fontFamily: 'monospace',
                color: Colors.white,
                height: 1.2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
