import 'dart:convert';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import '../utils/error_handler.dart';
import '../config/app_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BenchmarkScreen extends StatefulWidget {
  const BenchmarkScreen({super.key});

  @override
  State<BenchmarkScreen> createState() => _BenchmarkScreenState();
}

class _BenchmarkScreenState extends State<BenchmarkScreen> {
  final TextEditingController _contextController = TextEditingController();
  bool _loading = false;
  String? _fileName;
  List<int>? _pdfBytes;
  BenchmarkResult? _result;

  @override
  void dispose() {
    _contextController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    if (kDebugMode) {
      debugPrint('=== PDF SELECTION START ===');
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (kDebugMode) {
          debugPrint('User cancelled PDF selection');
        }
        return;
      }

      final picked = result.files.first;

      if (kDebugMode) {
        debugPrint('PDF selected: ${picked.name}');
        debugPrint('PDF size: ${picked.size} bytes');
        debugPrint('Extension: ${picked.extension}');
      }

      if (picked.bytes == null) {
        if (kDebugMode) {
          debugPrint('❌ Failed to read PDF bytes');
        }
        throw Exception('Failed to read selected file');
      }

      // Validate file size (50MB max)
      if (!ErrorHandler.validateFileSize(picked.bytes!.length, maxMB: 50)) {
        if (kDebugMode) {
          debugPrint(
            '❌ File too large: ${(picked.bytes!.length / 1024 / 1024).toStringAsFixed(2)} MB (max 50MB)',
          );
        }
        throw Exception('File size must not exceed 50MB');
      }

      if (kDebugMode) {
        debugPrint('✓ PDF validation passed');
      }

      setState(() {
        _fileName = picked.name;
        _pdfBytes = picked.bytes;
        _result = null; // Clear previous results
      });

      if (kDebugMode) {
        debugPrint('✓ PDF loaded successfully');
        debugPrint('=== PDF SELECTION COMPLETE ===');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ PDF selection error: $e');
      }
      if (!mounted) {
        return;
      }
      ErrorHandler.showError(
        context,
        'PDF selection failed',
        details: ErrorHandler.formatErrorMessage(e),
      );
    }
  }

  Future<void> _runBenchmark() async {
    if (kDebugMode) {
      debugPrint('\n');
      debugPrint('╔══════════════════════════════════════════════╗');
      debugPrint('║     BENCHMARK RUN INITIATED                  ║');
      debugPrint('╚══════════════════════════════════════════════╝');
    }

    if (_pdfBytes == null) {
      if (kDebugMode) {
        debugPrint('❌ No PDF selected');
      }
      ErrorHandler.showError(context, 'Please select a PDF first');
      return;
    }

    final contextText = _contextController.text.trim();

    if (kDebugMode) {
      debugPrint('Validating context input...');
      debugPrint('Context length: ${contextText.length} characters');
    }

    final validation = ErrorHandler.validateInput(
      contextText,
      fieldName: 'Context',
      minLength: 3,
      maxLength: 1000,
      required: true,
    );

    if (validation != null) {
      if (kDebugMode) {
        debugPrint('❌ Validation failed: $validation');
      }
      ErrorHandler.showError(context, validation);
      return;
    }

    if (kDebugMode) {
      debugPrint('✓ Validation passed');
    }

    setState(() {
      _loading = true;
      _result = null;
    });

    try {
      if (kDebugMode) {
        debugPrint('Starting Gemini API analysis...');
      }

      final result = await _analyzePdfWithGemini(_pdfBytes!, contextText);

      if (!mounted) {
        return;
      }

      if (kDebugMode) {
        debugPrint('✓ Analysis complete, updating UI');
      }

      setState(() => _result = result);

      if (kDebugMode) {
        debugPrint('╔══════════════════════════════════════════════╗');
        debugPrint('║     BENCHMARK RUN COMPLETED SUCCESSFULLY     ║');
        debugPrint('╚══════════════════════════════════════════════╝');
      }
    } on TimeoutException catch (e) {
      if (kDebugMode) {
        debugPrint('❌ TIMEOUT EXCEPTION: $e');
      }
      if (!mounted) {
        return;
      }
      ErrorHandler.showError(
        context, // ignore: use_build_context_synchronously
        'Benchmark analysis timed out',
        details: 'The request took too long. Please try again.',
      );
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ BENCHMARK FAILED');
        debugPrint('Exception: $e');
        debugPrint('Stack trace:');
        debugPrint(stackTrace.toString());
      }
      if (!mounted) {
        return;
      }
      ErrorHandler.showError(
        context, // ignore: use_build_context_synchronously
        'Benchmark analysis failed',
        details: ErrorHandler.formatErrorMessage(e),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<BenchmarkResult> _analyzePdfWithGemini(
    List<int> pdfBytes,
    String contextText,
  ) async {
    if (kDebugMode) {
      debugPrint('=== BENCHMARK ANALYSIS START ===');
      debugPrint(
        'PDF size: ${pdfBytes.length} bytes (${(pdfBytes.length / 1024 / 1024).toStringAsFixed(2)} MB)',
      );
      debugPrint('Context text: $contextText');
      debugPrint('Model: gemini-2.5-flash');
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConfig.geminiApiKey}',
    );

    if (kDebugMode) {
      debugPrint(
        'API endpoint: ${uri.toString().replaceAll(AppConfig.geminiApiKey, "***KEY_HIDDEN***")}',
      );
    }

    final prompt =
        '''
You are an expert educational content evaluator. Analyze the attached PDF study material for relevance and quality in the context of the student's exam: "$contextText"

CRITICAL: First, determine if the PDF content is RELEVANT to the exam context "$contextText". If the material is NOT relevant (e.g., a DAA textbook when the exam is for Hindi), you MUST score accordingly:
- If the material has NO relevance to the context: Content Coverage = 0-5 points, Overall Score should reflect this major mismatch (typically 15-35/100)
- If the material has PARTIAL relevance: Adjust scores proportionally (Content Coverage = 5-15 points)
- If the material is FULLY relevant: Score normally using the criteria below

Rate the material from a student's perspective who has ONE WEEK before their exam on "$contextText". Use this scoring criteria:

1. **Content Coverage (25 points)**: How comprehensive is the material FOR THE EXAM CONTEXT "$contextText"? Does it cover the key topics, definitions, formulas, and concepts needed for THIS SPECIFIC EXAM? If the material doesn't match the exam context, this score MUST be low (0-10 points). Only give high scores (15-25) if the material directly covers topics relevant to "$contextText".

2. **Clarity & Organization (20 points)**: Is the content well-structured, easy to follow, and clearly explained? Are there headings, bullet points, diagrams, or visual aids?

3. **Exam Readiness (25 points)**: Does it include practice problems, examples, summaries, or key takeaways RELEVANT TO "$contextText"? Is it conducive to quick revision for this specific exam?

4. **Depth vs. Brevity Balance (15 points)**: Is the content detailed enough without being overwhelming for a week of study? Does it prioritize important concepts RELEVANT TO "$contextText"?

5. **Practical Application (15 points)**: Are there real-world examples, case studies, or application scenarios RELEVANT TO "$contextText" that aid understanding?

Return ONLY a JSON object in this exact format (no markdown, no code fences):
{
  "overallScore": <number 0-100>,
  "contentCoverage": {
    "score": <number 0-25>,
    "feedback": "<2-3 sentence explanation>"
  },
  "clarity": {
    "score": <number 0-20>,
    "feedback": "<2-3 sentence explanation>"
  },
  "examReadiness": {
    "score": <number 0-25>,
    "feedback": "<2-3 sentence explanation>"
  },
  "depthBalance": {
    "score": <number 0-15>,
    "feedback": "<2-3 sentence explanation>"
  },
  "practicalApplication": {
    "score": <number 0-15>,
    "feedback": "<2-3 sentence explanation>"
  },
  "strengths": ["<strength 1>", "<strength 2>", "<strength 3>"],
  "improvements": ["<improvement 1>", "<improvement 2>", "<improvement 3>"],
  "studyRecommendation": "<1-2 sentence recommendation SPECIFICALLY for the exam context '$contextText'. If the material is not relevant, clearly state that this material is NOT suitable for the '$contextText' exam and recommend finding appropriate study material.>"
}

Be honest and constructive. The scores should add up to the overallScore. ALWAYS consider the relevance of the material to the exam context "$contextText" when scoring.
''';

    final body = {
      'system_instruction': {
        'role': 'system',
        'parts': [
          {
            'text':
                'You are an educational content evaluator. You MUST evaluate material relevance to the exam context FIRST. If material doesn\'t match the context, score it low. Return ONLY valid JSON, no commentary, no markdown.',
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

    if (kDebugMode) {
      final genConfig = body['generationConfig'] as Map<String, dynamic>?;
      debugPrint('Request body configuration:');
      debugPrint('  - Temperature: ${genConfig?['temperature']}');
      debugPrint('  - Max tokens: ${genConfig?['maxOutputTokens']}');
      debugPrint('  - Response format: ${genConfig?['response_mime_type']}');
      debugPrint(
        '  - PDF encoded: ${base64Encode(pdfBytes).length} characters',
      );
    }

    if (kDebugMode) {
      debugPrint('Sending POST request to Gemini API...');
      debugPrint('Request headers: Content-Type: application/json');
    }

    final startTime = DateTime.now();

    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(
          const Duration(seconds: 120),
          onTimeout: () {
            if (kDebugMode) {
              debugPrint('❌ REQUEST TIMEOUT after 120 seconds');
            }
            throw TimeoutException('Benchmark timed out');
          },
        );

    final duration = DateTime.now().difference(startTime);

    if (kDebugMode) {
      debugPrint(
        '✓ Response received in ${duration.inSeconds}.${duration.inMilliseconds % 1000}s',
      );
      debugPrint('Response status code: ${resp.statusCode}');
      debugPrint('Response headers: ${resp.headers}');
    }

    if (resp.statusCode != 200) {
      if (kDebugMode) {
        debugPrint('❌ API ERROR ${resp.statusCode}');
        debugPrint('Error response body: ${resp.body}');
      }
      throw Exception('Gemini API error ${resp.statusCode}: ${resp.body}');
    }

    if (kDebugMode) {
      debugPrint('=== RAW GEMINI RESPONSE ===');
      debugPrint(resp.body);
      debugPrint('=== END RAW RESPONSE ===');
    }

    if (kDebugMode) {
      debugPrint('Parsing JSON response...');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;

    if (kDebugMode) {
      debugPrint('Response structure keys: ${data.keys.toList()}');
    }

    final candidates = data['candidates'] as List<dynamic>?;

    if (candidates == null || candidates.isEmpty) {
      if (kDebugMode) {
        debugPrint('❌ No candidates in response');
        debugPrint('Full response data: $data');
      }
      throw Exception('No benchmark data received from API');
    }

    if (kDebugMode) {
      debugPrint('Number of candidates: ${candidates.length}');
      debugPrint('First candidate structure: ${candidates.first}');
    }

    final firstCandidate = candidates.first as Map<String, dynamic>;
    final finishReason = firstCandidate['finishReason'];

    if (kDebugMode) {
      debugPrint('Finish reason: $finishReason');
    }

    if (finishReason != null && finishReason != 'STOP') {
      if (kDebugMode) {
        debugPrint('⚠️ Unexpected finish reason: $finishReason');
      }
      if (finishReason == 'MAX_TOKENS') {
        throw Exception(
          'Response was truncated due to token limit. The PDF analysis was too detailed. '
          'Try a shorter PDF or more specific context.',
        );
      }
    }

    final parts = (firstCandidate['content']?['parts'] as List?) ?? [];

    if (kDebugMode) {
      debugPrint('Number of parts: ${parts.length}');
    }

    final text = parts.map((p) => (p['text'] ?? '') as String).join().trim();

    if (kDebugMode) {
      debugPrint('=== EXTRACTED TEXT ===');
      debugPrint(text);
      debugPrint('=== END EXTRACTED TEXT ===');
      debugPrint('Text length: ${text.length} characters');
    }

    if (text.isEmpty) {
      if (kDebugMode) {
        debugPrint('❌ Empty text extracted from response');
      }
      throw Exception('Empty response from benchmark API');
    }

    // Parse the JSON response
    if (kDebugMode) {
      debugPrint('Attempting to parse benchmark JSON...');
    }

    try {
      final resultJson = jsonDecode(text) as Map<String, dynamic>;

      if (kDebugMode) {
        debugPrint('✓ JSON parsed successfully');
        debugPrint('Result keys: ${resultJson.keys.toList()}');
        debugPrint('Overall score: ${resultJson['overallScore']}');
      }

      final result = BenchmarkResult.fromJson(resultJson);

      if (kDebugMode) {
        debugPrint('✓ BenchmarkResult object created');
        debugPrint('=== BENCHMARK ANALYSIS COMPLETE ===');
      }

      return result;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ JSON PARSE ERROR');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $stackTrace');
        debugPrint('Failed text content: $text');
      }
      throw FormatException('Invalid benchmark response format: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;

    // Check if PDF was passed from another screen
    if (args != null && _pdfBytes == null) {
      _pdfBytes = args['pdfBytes'] as List<int>?;
      _fileName = args['pdfFilename'] as String?;
    }

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('Notes Benchmark'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // PDF Selection Card
              _buildSelectionCard(accent),
              const SizedBox(height: 16),

              // Context Input Card
              _buildContextCard(accent),
              const SizedBox(height: 16),

              // Benchmark Button
              _buildBenchmarkButton(accent),
              const SizedBox(height: 24),

              // Results Display
              if (_result != null) _buildResultsCard(accent, _result!),
              if (_loading) _buildLoadingCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionCard(Color accent) {
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: Colors.white.withAlpha((0.08 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.file_present, color: accent, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Select PDF',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_fileName != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withAlpha((0.15 * 255).round()),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: accent, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _fileName!,
                          style: const TextStyle(fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _pickPdf,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.upload_file),
                  label: Text(_fileName == null ? 'Choose PDF' : 'Change PDF'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContextCard(Color accent) {
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: Colors.white.withAlpha((0.08 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.subject, color: accent, size: 28),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Study Context',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _contextController,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText:
                      'e.g., "Final exam for Data Structures & Algorithms - focus on trees, graphs, sorting algorithms, and dynamic programming"',
                  hintStyle: TextStyle(
                    color: Colors.white.withAlpha((0.5 * 255).round()),
                    fontSize: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withAlpha((0.2 * 255).round()),
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: Colors.white.withAlpha((0.2 * 255).round()),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accent, width: 2),
                  ),
                  filled: true,
                  fillColor: Colors.white.withAlpha((0.05 * 255).round()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBenchmarkButton(Color accent) {
    return FilledButton.icon(
      onPressed: (_loading || _pdfBytes == null) ? null : _runBenchmark,
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        padding: const EdgeInsets.symmetric(vertical: 16),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      icon: _loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.analytics, size: 24),
      label: Text(_loading ? 'Analyzing...' : 'Import'),
    );
  }

  Widget _buildLoadingCard() {
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: Colors.white.withAlpha((0.08 * 255).round()),
        child: const Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Analyzing your study material...',
                style: TextStyle(fontSize: 16),
              ),
              SizedBox(height: 8),
              Text(
                'This may take up to 2 minutes',
                style: TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultsCard(Color accent, BenchmarkResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Overall Score Card
        _buildOverallScoreCard(accent, result),
        const SizedBox(height: 16),

        // Detailed Scores
        _buildDetailedScoresCard(accent, result),
        const SizedBox(height: 16),

        // Strengths & Improvements
        _buildFeedbackCard(accent, result),
        const SizedBox(height: 16),

        // Study Recommendation
        _buildRecommendationCard(accent, result),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _loading || _pdfBytes == null ? null : _importToLibrary,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: const Icon(Icons.cloud_upload),
          label: const Text('Import to Library'),
        ),
      ],
    );
  }

  Widget _buildOverallScoreCard(Color accent, BenchmarkResult result) {
    final score = result.overallScore;
    final color = _getScoreColor(score);
    final grade = _getGrade(score);

    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: Colors.white.withAlpha((0.08 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text(
                'Overall Score',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 12,
                      backgroundColor: Colors.white.withAlpha(
                        (0.1 * 255).round(),
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        score.toStringAsFixed(0),
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                      Text(
                        grade,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _getScoreMessage(score),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailedScoresCard(Color accent, BenchmarkResult result) {
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: Colors.white.withAlpha((0.08 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Detailed Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              _buildScoreItem(
                'Content Coverage',
                result.contentCoverage.score,
                25,
                result.contentCoverage.feedback,
                accent,
              ),
              const SizedBox(height: 16),
              _buildScoreItem(
                'Clarity & Organization',
                result.clarity.score,
                20,
                result.clarity.feedback,
                accent,
              ),
              const SizedBox(height: 16),
              _buildScoreItem(
                'Exam Readiness',
                result.examReadiness.score,
                25,
                result.examReadiness.feedback,
                accent,
              ),
              const SizedBox(height: 16),
              _buildScoreItem(
                'Depth vs. Brevity',
                result.depthBalance.score,
                15,
                result.depthBalance.feedback,
                accent,
              ),
              const SizedBox(height: 16),
              _buildScoreItem(
                'Practical Application',
                result.practicalApplication.score,
                15,
                result.practicalApplication.feedback,
                accent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScoreItem(
    String title,
    double score,
    int maxScore,
    String feedback,
    Color accent,
  ) {
    final percentage = (score / maxScore) * 100;
    final color = _getScoreColor(percentage);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '${score.toStringAsFixed(1)}/$maxScore',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: score / maxScore,
            minHeight: 8,
            backgroundColor: Colors.white.withAlpha((0.1 * 255).round()),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          feedback,
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white70,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackCard(Color accent, BenchmarkResult result) {
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: Colors.white.withAlpha((0.08 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Strengths
              Row(
                children: [
                  Icon(Icons.star, color: Colors.amber, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Strengths',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...result.strengths.map(
                (strength) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '✓ ',
                        style: TextStyle(color: Colors.green, fontSize: 16),
                      ),
                      Expanded(
                        child: Text(
                          strength,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Areas for Improvement
              Row(
                children: [
                  Icon(Icons.lightbulb, color: Colors.orange, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Areas for Improvement',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ...result.improvements.map(
                (improvement) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '• ',
                        style: TextStyle(color: Colors.orange, fontSize: 16),
                      ),
                      Expanded(
                        child: Text(
                          improvement,
                          style: const TextStyle(fontSize: 14, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecommendationCard(Color accent, BenchmarkResult result) {
    return OCLiquidGlassGroup(
      settings: const OCLiquidGlassSettings(
        refractStrength: -0.08,
        blurRadiusPx: 3.5,
        specStrength: 1.1,
        lightbandColor: Colors.white,
      ),
      child: OCLiquidGlass(
        width: double.infinity,
        height: null,
        borderRadius: 16,
        color: accent.withAlpha((0.12 * 255).round()),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.school, color: accent, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Study Recommendation',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                result.studyRecommendation,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 80) return Colors.green;
    if (score >= 60) return Colors.lightGreen;
    if (score >= 40) return Colors.orange;
    return Colors.red;
  }

  String _getGrade(double score) {
    if (score >= 90) return 'A+';
    if (score >= 85) return 'A';
    if (score >= 80) return 'A-';
    if (score >= 75) return 'B+';
    if (score >= 70) return 'B';
    if (score >= 65) return 'B-';
    if (score >= 60) return 'C+';
    if (score >= 55) return 'C';
    if (score >= 50) return 'C-';
    if (score >= 40) return 'D';
    return 'F';
  }

  String _getScoreMessage(double score) {
    if (score >= 85) {
      return 'Excellent study material! Well-prepared for exams.';
    }
    if (score >= 70) {
      return 'Good notes! Some improvements could make them better.';
    }
    if (score >= 55) {
      return 'Decent material, but consider supplementing with other resources.';
    }
    if (score >= 40) {
      return 'Needs improvement. Consider creating more comprehensive notes.';
    }
    return 'These notes need significant work. Seek additional study materials.';
  }

  Future<void> _importToLibrary() async {
    if (_pdfBytes == null) {
      return;
    }
    final client = Supabase.instance.client;
    final bucket = 'documents';
    final fileName = (_fileName == null || _fileName!.isEmpty)
        ? 'document_${DateTime.now().millisecondsSinceEpoch}.pdf'
        : _fileName!;
    final storagePath =
        'uploads/${DateTime.now().millisecondsSinceEpoch}_$fileName';
    try {
      await client.storage
          .from(bucket)
          .uploadBinary(
            storagePath,
            Uint8List.fromList(_pdfBytes!),
            fileOptions: const FileOptions(
              contentType: 'application/pdf',
              upsert: false,
            ),
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported to Library: $fileName')));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop({
        'fileName': fileName,
        'storagePath': storagePath,
        'benchmark': (_result?.overallScore ?? 0).round(),
        'context': _contextController.text.trim(),
      }); // return to dashboard with data
    } catch (e) {
      if (!mounted) {
        return;
      }
      ErrorHandler.showError(
        context,
        'Import failed',
        details: ErrorHandler.formatErrorMessage(e),
      );
    }
  }
}

// Data models
class BenchmarkResult {
  final double overallScore;
  final CategoryScore contentCoverage;
  final CategoryScore clarity;
  final CategoryScore examReadiness;
  final CategoryScore depthBalance;
  final CategoryScore practicalApplication;
  final List<String> strengths;
  final List<String> improvements;
  final String studyRecommendation;

  BenchmarkResult({
    required this.overallScore,
    required this.contentCoverage,
    required this.clarity,
    required this.examReadiness,
    required this.depthBalance,
    required this.practicalApplication,
    required this.strengths,
    required this.improvements,
    required this.studyRecommendation,
  });

  factory BenchmarkResult.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      debugPrint('Parsing BenchmarkResult from JSON...');
      debugPrint('JSON keys present: ${json.keys.toList()}');
    }

    try {
      final result = BenchmarkResult(
        overallScore: (json['overallScore'] as num).toDouble(),
        contentCoverage: CategoryScore.fromJson(json['contentCoverage']),
        clarity: CategoryScore.fromJson(json['clarity']),
        examReadiness: CategoryScore.fromJson(json['examReadiness']),
        depthBalance: CategoryScore.fromJson(json['depthBalance']),
        practicalApplication: CategoryScore.fromJson(
          json['practicalApplication'],
        ),
        strengths: (json['strengths'] as List).cast<String>(),
        improvements: (json['improvements'] as List).cast<String>(),
        studyRecommendation: json['studyRecommendation'] as String,
      );

      if (kDebugMode) {
        debugPrint('✓ BenchmarkResult parsed successfully');
        debugPrint('  Overall score: ${result.overallScore}');
        debugPrint('  Strengths: ${result.strengths.length}');
        debugPrint('  Improvements: ${result.improvements.length}');
      }

      return result;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('❌ Failed to parse BenchmarkResult');
        debugPrint('Error: $e');
        debugPrint('Stack trace: $stackTrace');
        debugPrint('JSON data: $json');
      }
      rethrow;
    }
  }
}

class CategoryScore {
  final double score;
  final String feedback;

  CategoryScore({required this.score, required this.feedback});

  factory CategoryScore.fromJson(Map<String, dynamic> json) {
    if (kDebugMode) {
      debugPrint(
        '  Parsing CategoryScore: score=${json['score']}, feedback length=${(json['feedback'] as String).length}',
      );
    }

    try {
      return CategoryScore(
        score: (json['score'] as num).toDouble(),
        feedback: json['feedback'] as String,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('  ❌ Failed to parse CategoryScore: $e');
        debugPrint('  JSON: $json');
      }
      rethrow;
    }
  }
}
