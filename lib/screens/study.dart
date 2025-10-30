import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import 'package:pdfx/pdfx.dart';

class StudyScreen extends StatefulWidget {
  const StudyScreen({super.key});

  @override
  State<StudyScreen> createState() => _StudyScreenState();
}

class _StudyScreenState extends State<StudyScreen> {
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return SafeArea(
      child: Stack(
        children: [
          // PDF area placeholder
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 360, 16),
              child: OCLiquidGlass(
                width: double.infinity,
                height: double.infinity,
                borderRadius: 16,
                color: Colors.white.withOpacity(0.0),
              ),
            ),
          ),
          // Floating tools panel (static)
          const _DraggableToolsPanel(),
          // Top bar
          Positioned(
            left: 16,
            right: 16,
            top: 8,
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(0.25),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.circle, size: 10, color: accent),
                      const SizedBox(width: 8),
                      Text(
                        'Study Mode',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DraggableToolsPanel extends StatefulWidget {
  const _DraggableToolsPanel({this.centerOnAppear = false});
  final bool centerOnAppear;

  @override
  State<_DraggableToolsPanel> createState() => _DraggableToolsPanelState();
}

class _DraggableToolsPanelState extends State<_DraggableToolsPanel> {
  Uint8List? _thumb;
  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final args = ModalRoute.of(context)?.settings.arguments as Map?;
    final Uint8List? pdfBytes = args != null
        ? args['pdfBytes'] as Uint8List?
        : null;
    final String? pdfFilename = args != null
        ? args['pdfFilename'] as String?
        : null;

    if (_thumb == null && pdfBytes != null) {
      _renderThumb(pdfBytes);
    }

    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        width: 320,
        height: 520,
        child: OCLiquidGlassGroup(
          settings: const OCLiquidGlassSettings(
            refractStrength: -0.06,
            blurRadiusPx: 3.0,
            specStrength: 1.0,
            lightbandColor: Colors.white,
          ),
          child: OCLiquidGlass(
            width: 320,
            height: 520,
            borderRadius: 24,
            color: Colors.white.withOpacity(0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle.merge(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.bubble_chart, color: accent),
                        const SizedBox(width: 8),
                        Text(
                          'Smart Glass Tools',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                        ),
                        const Spacer(),
                        Icon(Icons.adjust, color: Colors.white60),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _ToolTile(
                      icon: Icons.summarize,
                      label: 'Summarizer',
                      onTap: () {
                        final a =
                            ModalRoute.of(context)?.settings.arguments as Map?;
                        Navigator.of(context).pushNamed(
                          '/summarizer',
                          arguments: {
                            'pdfBytes': a != null ? a['pdfBytes'] : null,
                            'pdfFilename': a != null ? a['pdfFilename'] : null,
                          },
                        );
                      },
                    ),
                    _ToolTile(
                      icon: Icons.quiz,
                      label: 'Quiz',
                      onTap: () {
                        final a =
                            ModalRoute.of(context)?.settings.arguments as Map?;
                        Navigator.of(context).pushNamed(
                          '/quizSetup',
                          arguments: {
                            'pdfBytes': a != null ? a['pdfBytes'] : null,
                            'pdfFilename': a != null ? a['pdfFilename'] : null,
                          },
                        );
                      },
                    ),
                    _ToolTile(
                      icon: Icons.bolt,
                      label: 'Flow State',
                      onTap: () => Navigator.of(context).pushNamed(
                        '/flow',
                        arguments: {
                          'pdfBytes': pdfBytes,
                          'pdfFilename': pdfFilename,
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (pdfBytes != null)
                      GestureDetector(
                        onTap: () => Navigator.of(context).pushNamed(
                          '/pdf',
                          arguments: {
                            'pdfBytes': pdfBytes,
                            'pdfFilename': pdfFilename,
                          },
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            height: 220,
                            width: double.infinity,
                            color: Colors.white,
                            child: _thumb != null
                                ? Image.memory(_thumb!, fit: BoxFit.cover)
                                : const Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    // Output panel removed per request
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

extension _PreviewHelpers on _DraggableToolsPanelState {
  Future<void> _renderThumb(Uint8List bytes) async {
    try {
      final doc = await PdfDocument.openData(bytes);
      final page = await doc.getPage(1);
      final img = await page.render(
        width: 600,
        height: 800,
        format: PdfPageImageFormat.png,
      );
      await page.close();
      await doc.close();
      if (!mounted) return;
      setState(() => _thumb = img?.bytes);
    } catch (_) {
      // ignore preview errors
    }
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: accent),
                const SizedBox(width: 10),
                Text(label),
                const Spacer(),
                Icon(Icons.chevron_right, color: Colors.white60),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
