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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://lxmyznmgbvbxzjwvbfnr.supabase.co/',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imx4bXl6bm1nYnZieHpqd3ZiZm5yIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjA2MjQ4OTAsImV4cCI6MjA3NjIwMDg5MH0.CQ3VvR0khlJfd2vrqJwX2jL_FXgLQ5rQoo33QGPQUfg',
  );
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
    final base = ThemeData.dark();
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: accent,
        secondary: accent,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A0E12),
      splashColor: accent.withOpacity(0.15),
      highlightColor: Colors.transparent,
      useMaterial3: true,
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
          final args =
              ModalRoute.of(ctx)?.settings.arguments as Map<String, dynamic>;
          return _LiquidBackplate(child: QuizScreen(quiz: args));
        },
        '/flow': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map?;
          final bytes = args?['pdfBytes'] as Uint8List?;
          final name = args?['pdfFilename'] as String?;
          return _LiquidBackplate(
            child: FlowStateScreen(pdfBytes: bytes!, filename: name),
          );
        },
        '/pdf': (ctx) {
          final args = ModalRoute.of(ctx)?.settings.arguments as Map?;
          final bytes = args?['pdfBytes'] as Uint8List?;
          final name = args?['pdfFilename'] as String?;
          return _LiquidBackplate(
            child: PdfReaderScreen(bytes: bytes!, filename: name),
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
    final light = Paint()..color = Colors.white.withOpacity(0.035);
    final dark = Paint()..color = Colors.black.withOpacity(0.025);
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
