import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/dashboard.dart';
import 'screens/study.dart';
import 'screens/login.dart';
import 'screens/summarizer.dart';
import 'screens/quiz_setup.dart';
import 'screens/quiz_screen.dart';
import 'screens/pdf_reader.dart';
import 'screens/flow_state.dart';
import 'widgets/liquid_cursor_overlay.dart';
import 'config/app_config.dart';
import 'screens/benchmark_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  String? initError;
  try {
    await AppConfig.load();
    final supabaseUrl = AppConfig.supabaseUrl;
    final supabaseAnonKey = AppConfig.supabaseAnonKey;
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      initError = 'Missing SUPABASE_URL or SUPABASE_ANON_KEY in env.';
    } else {
      await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
    }
  } catch (e) {
    initError = 'Supabase init failed: $e';
  }
  if (initError != null) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Startup error: $initError\n\nAdd env in assets/app.env and run again.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static const Color accent = Color.fromARGB(
    255,
    255,
    255,
    255,
  ); // Electric blue

  ThemeData _buildTheme() {
    return ThemeData.dark(useMaterial3: true).copyWith(
      colorScheme: ColorScheme.dark(primary: accent, secondary: accent),
      scaffoldBackgroundColor: const Color(0xFF0A0E12),
      splashColor: accent.withAlpha((0.15 * 255).round()),
      highlightColor: Colors.transparent,
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routes: {
        '/': (_) => const _AuthGate(),
        '/study': (_) => const _LiquidBackplate(child: StudyScreen()),
        '/login': (_) => const _LiquidBackplate(child: LoginScreen()),
        '/summarizer': (_) => const _LiquidBackplate(child: SummarizerScreen()),
        '/quizSetup': (_) => const _LiquidBackplate(child: QuizSetupScreen()),
        '/quiz': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments;
          if (args == null || args is! Map<String, dynamic>) {
            return _LiquidBackplate(
              child: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text('Invalid quiz data'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          return _LiquidBackplate(child: QuizScreen(quiz: args));
        },
        '/flow': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map?;
          final bytes = args?['pdfBytes'] as Uint8List?;
          final name = args?['pdfFilename'] as String?;

          if (bytes == null) {
            return _LiquidBackplate(
              child: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text('PDF data is missing'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _LiquidBackplate(
            child: FlowStateScreen(pdfBytes: bytes, filename: name),
          );
        },
        '/benchmark': (ctx) => _LiquidBackplate(child: const BenchmarkScreen()),
        '/pdf': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map?;
          final bytes = args?['pdfBytes'] as Uint8List?;
          final name = args?['pdfFilename'] as String?;

          if (bytes == null) {
            return _LiquidBackplate(
              child: Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text('PDF data is missing'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Go Back'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return _LiquidBackplate(
            child: PdfReaderScreen(bytes: bytes, filename: name),
          );
        },
      },
      builder: (context, child) {
        return Stack(
          children: [if (child != null) child, const LiquidCursorOverlay()],
        );
      },
    );
  }
}

class _LiquidBackplate extends StatelessWidget {
  const _LiquidBackplate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/background.jpg', fit: BoxFit.cover),
          ),
          // Ambient droplets removed per request
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class _AnimatedGradientBackground extends StatefulWidget {
  const _AnimatedGradientBackground();

  @override
  State<_AnimatedGradientBackground> createState() =>
      _AnimatedGradientBackgroundState();
}

class _AnimatedGradientBackgroundState
    extends State<_AnimatedGradientBackground>
    with SingleTickerProviderStateMixin {
  static const double _periodSeconds = 8.0;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _hsv(double hue, double sat, double val, double opacity) {
    return HSVColor.fromAHSV(opacity, hue % 360, sat, val).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final elapsed =
            (_controller.lastElapsedDuration?.inMicroseconds ?? 0) / 1000000.0;
        // Use unbounded elapsed time to avoid any modulo edge; sin/cos are periodic.
        final p =
            elapsed * (2 * pi / _periodSeconds); // phase for seamless loop
        final white = const Color(0xFFFFFFFF);
        final sky = _hsv(
          200 + 18 * sin(p),
          0.20 + 0.03 * sin(p + 1.3),
          0.95,
          1.0,
        );
        final lilac = _hsv(
          270 + 18 * sin(p + 2.1),
          0.18 + 0.03 * sin(p + .7),
          0.92,
          1.0,
        );

        final begin = Alignment(
          -0.8 + 0.25 * sin(p * 0.8),
          -1.0 + 0.2 * cos(p * 0.7),
        );
        final end = Alignment(
          1.0 + 0.1 * cos(p * 0.9),
          0.8 + 0.2 * sin(p * 0.85),
        );

        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: begin,
                    end: end,
                    colors: [white, sky, lilac],
                    stops: const [0.0, 0.55, 1.0],
                  ),
                ),
              ),
            ),
            const Positioned.fill(child: _GrainOverlay()),
          ],
        );
      },
    );
  }
}

class _GrainOverlay extends StatefulWidget {
  const _GrainOverlay();

  @override
  State<_GrainOverlay> createState() => _GrainOverlayState();
}

class _GrainOverlayState extends State<_GrainOverlay> {
  late List<Offset> _points;
  late List<double> _sizes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.of(context).size;
    final count = (size.width * size.height / 9000).clamp(200, 800).toInt();
    final rnd = Random(42);
    _points = List.generate(
      count,
      (_) =>
          Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
    );
    _sizes = List.generate(count, (_) => rnd.nextDouble() * 1.2 + 0.4);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GrainPainter(points: _points, sizes: _sizes),
      ),
    );
  }
}

class _GrainPainter extends CustomPainter {
  _GrainPainter({required this.points, required this.sizes});
  final List<Offset> points;
  final List<double> sizes;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final light = Paint()
      ..color = Colors.white.withAlpha((0.035 * 255).round());
    final dark = Paint()..color = Colors.black.withAlpha((0.025 * 255).round());
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final r = sizes[i];
      canvas.drawCircle(p, r, i.isEven ? light : dark);
    }
  }

  @override
  bool shouldRepaint(covariant _GrainPainter oldDelegate) => false;
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      return const _LiquidBackplate(child: DashboardScreen());
    }
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final active = Supabase.instance.client.auth.currentSession != null;
        if (active) {
          return const _LiquidBackplate(child: DashboardScreen());
        }
        return const _LiquidBackplate(child: LoginScreen());
      },
    );
  }
}
