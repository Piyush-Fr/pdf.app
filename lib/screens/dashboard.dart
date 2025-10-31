import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdfx/pdfx.dart';
import '../utils/error_handler.dart';

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

  @override
  void initState() {
    super.initState();
    _loadExistingFromSupabase();
  }

  Future<void> _loadExistingFromSupabase() async {
    try {
      final client = Supabase.instance.client;

      // Add timeout to prevent hanging
      final items = await client.storage
          .from(_bucketName)
          .list(path: 'uploads')
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () => throw TimeoutException('Loading files timed out'),
          );

      // Sort newest first
      items.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      final List<_PdfCard> fetched = [];

      for (final obj in items) {
        final name = obj.name;
        if (name.isEmpty) continue; // Skip empty names

        final path = 'uploads/$name';
        Uint8List? thumb;
        try {
          final data = await client.storage
              .from(_bucketName)
              .download(path)
              .timeout(const Duration(seconds: 10));
          thumb = await _generatePdfThumbnail(data);
        } catch (e) {
          debugPrint('Failed to load thumbnail for $name: $e');
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
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(
        context,
        'Loading timed out',
        details: e.toString(),
      );
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.showError(
        context,
        'Failed to load files',
        details: ErrorHandler.formatErrorMessage(e),
      );
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
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    // Benchmark button (Glassmorphism)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () async {
                          final res = await Navigator.of(
                            context,
                          ).pushNamed('/benchmark');
                          if (!mounted) return;
                          if (res is Map) {
                            try {
                              final fileName = res['fileName'] as String?;
                              final storagePath = res['storagePath'] as String?;
                              final benchmark = res['benchmark'] as int? ?? 0;
                              final ctx = res['context'] as String? ?? '';
                              if (fileName != null && storagePath != null) {
                                Uint8List? thumb;
                                try {
                                  final data = await Supabase
                                      .instance
                                      .client
                                      .storage
                                      .from(_bucketName)
                                      .download(storagePath)
                                      .timeout(const Duration(seconds: 10));
                                  thumb = await _generatePdfThumbnail(data);
                                } catch (_) {
                                  thumb = null;
                                }
                                setState(() {
                                  _cards.insert(
                                    0,
                                    _PdfCard(
                                      title: fileName,
                                      benchmark: benchmark,
                                      context: ctx,
                                      previewBytes: thumb,
                                      storagePath: storagePath,
                                    ),
                                  );
                                });
                              }
                            } catch (_) {}
                          }
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: BackdropFilter(
                            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                            child: Container(
                              width: 130,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withAlpha(
                                      (0.16 * 255).round(),
                                    ),
                                    Colors.white.withAlpha(
                                      (0.08 * 255).round(),
                                    ),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withAlpha(
                                    (0.18 * 255).round(),
                                  ),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(
                                    Icons.analytics,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Benchmark',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Import PDF button removed earlier
                  ],
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
                      final navigator = Navigator.of(context);
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        final bytes = await Supabase.instance.client.storage
                            .from(_bucketName)
                            .download(card.storagePath);
                        if (!context.mounted) return;
                        navigator.pushNamed(
                          '/study',
                          arguments: {
                            'centerPanel': true,
                            'pdfBytes': bytes,
                            'pdfFilename': card.title,
                          },
                        );
                      } catch (e) {
                        if (!context.mounted) return;
                        messenger.showSnackBar(
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
