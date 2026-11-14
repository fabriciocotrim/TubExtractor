/// TubExtractor visual language: frosted glass panels over a base lit by a
/// faint, slowly drifting glow (glacier in dark, coral in light). Colors come
/// from the brand guidelines (artefatos/docs/BRAND_GUIDELINES.md).
///
/// Dark (native) / light:
///   base     #141A1F / #F3F4F7  page (dark: green graphite, D-01)
///   surface  #1C1F26 / #FFFFFF  dialogs, sheets
///   border   #2D333F / #D9DDE5  dividers, outlines
///   accent   #5EE6C8 / #D93636  selection, focus, progress, plain buttons
///   coral    #FF4444 / #D93636  dark: only Buscar, Baixar ZIP, "Extractor"
///   peach    #FF7864 / #E8604C  gradient end; light: search highlight
///   text     #FFFFFF / #121418
///   muted    #94A3B8 / #5B6474  timestamps, counters, metadata
///   success  #10B981, warning #F59E0B, error #EF4444  item status
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import 'motion.dart';

@immutable
class Crystal extends ThemeExtension<Crystal> {
  const Crystal({
    required this.base,
    required this.lights,
    required this.glassFill,
    required this.edgeBright,
    required this.edgeFaint,
    required this.shadow,
    required this.brand,
    required this.peach,
    required this.rodEnd,
    required this.success,
    required this.warning,
  });

  final Color base;

  /// Background light sources, drawn as soft radial glows.
  final List<Color> lights;
  final Color glassFill;
  final Color edgeBright;
  final Color edgeFaint;
  final Color shadow;
  /// Brand coral: main action button and the "Extractor" of the wordmark.
  final Color brand;
  final Color peach;

  /// End color of the progress rod (starts at the accent color).
  final Color rodEnd;
  final Color success;
  final Color warning;

  static const night = Crystal(
    // D-01 = C (PO, 2026-11-11): dark mode was "too red and black". Base is a
    // slightly green graphite, the glow is a faint glacier, selections and
    // progress use glacier; coral stays on the main action and the wordmark.
    base: Color(0xFF141A1F),
    lights: [Color(0x2E1FBFA3), Color(0x1F2B6CB0)],
    glassFill: Color(0x12FFFFFF),
    edgeBright: Color(0x4DFFFFFF),
    edgeFaint: Color(0x0AFFFFFF),
    shadow: Color(0x80000000),
    brand: Color(0xFFFF4444),
    peach: Color(0xFFFF7864),
    rodEnd: Color(0xFF7FC8FF),
    success: Color(0xFF10B981),
    warning: Color(0xFFF59E0B),
  );

  static const day = Crystal(
    base: Color(0xFFF3F4F7),
    lights: [Color(0x2EFF4444), Color(0x24FF7864)],
    glassFill: Color(0xA6FFFFFF),
    edgeBright: Color(0xF2FFFFFF),
    edgeFaint: Color(0x4DFFFFFF),
    shadow: Color(0x1F121418),
    brand: Color(0xFFD93636),
    peach: Color(0xFFE8604C),
    rodEnd: Color(0xFFE8604C),
    success: Color(0xFF0B8A60),
    warning: Color(0xFFB86E00),
  );

  static Crystal of(BuildContext context) =>
      Theme.of(context).extension<Crystal>()!;

  @override
  Crystal copyWith() => this;

  @override
  Crystal lerp(Crystal? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return Crystal(
      base: l(base, other.base),
      lights: [for (var i = 0; i < lights.length && i < other.lights.length; i++) l(lights[i], other.lights[i])],
      glassFill: l(glassFill, other.glassFill),
      edgeBright: l(edgeBright, other.edgeBright),
      edgeFaint: l(edgeFaint, other.edgeFaint),
      shadow: l(shadow, other.shadow),
      brand: l(brand, other.brand),
      peach: l(peach, other.peach),
      rodEnd: l(rodEnd, other.rodEnd),
      success: l(success, other.success),
      warning: l(warning, other.warning),
    );
  }
}

ThemeData crystalTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final c = dark ? Crystal.night : Crystal.day;
  // Accent for selection, focus and progress: glacier in dark (D-01 = C),
  // brand coral in light.
  final primary = dark ? const Color(0xFF5EE6C8) : const Color(0xFFD93636);
  final text = dark ? Colors.white : const Color(0xFF121418);
  final mist = dark ? const Color(0xFF94A3B8) : const Color(0xFF5B6474);
  final border = dark ? const Color(0xFF2D333F) : const Color(0xFFD9DDE5);
  final scheme = ColorScheme.fromSeed(seedColor: primary, brightness: b)
      .copyWith(
        primary: primary,
        // Dark ink on the accent: white on #FF4444 is only 3.6:1.
        onPrimary: dark ? const Color(0xFF032019) : const Color(0xFF121418),
        secondary: c.peach,
        tertiary: c.warning,
        surface: dark ? const Color(0xFF1C1F26) : Colors.white,
        onSurface: text,
        onSurfaceVariant: mist,
        outline: dark ? const Color(0xFF3A4150) : const Color(0xFFC3C8D2),
        outlineVariant: border,
        secondaryContainer: primary.withValues(alpha: dark ? 0.20 : 0.12),
        onSecondaryContainer: text,
        // Current search hit in the reader: aqua in dark (D-03), peach in light.
        tertiaryContainer: dark
            ? primary.withValues(alpha: 0.34)
            : c.peach.withValues(alpha: 0.26),
        error: dark ? const Color(0xFFEF4444) : const Color(0xFFC62828),
      );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
  );
  TextStyle? display(TextStyle? s, {double? spacing, FontWeight w = FontWeight.w800}) =>
      s?.copyWith(fontWeight: w, letterSpacing: spacing);
  final t = base.textTheme;
  final textTheme = t
      .copyWith(
        displaySmall: display(t.displaySmall, spacing: -1.4),
        headlineMedium: display(t.headlineMedium, spacing: -0.8),
        headlineSmall: display(t.headlineSmall, spacing: -0.6),
        titleLarge: display(t.titleLarge, spacing: -0.4, w: FontWeight.w700),
        titleMedium: t.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        titleSmall: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        labelLarge: t.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodySmall: t.bodySmall?.copyWith(color: mist),
      )
      .apply(bodyColor: text, displayColor: text);

  final field = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: BorderSide(color: scheme.outlineVariant),
  );

  return base.copyWith(
    textTheme: textTheme,
    scaffoldBackgroundColor: Colors.transparent,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      foregroundColor: text,
      titleTextStyle: textTheme.titleLarge,
      // Status bar icons follow the theme, not the transparent bar.
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0x0FFFFFFF) : const Color(0x99FFFFFF),
      border: field,
      enabledBorder: field,
      focusedBorder: field.copyWith(
        borderSide: BorderSide(color: primary, width: 1.6),
      ),
      hintStyle: TextStyle(color: mist.withValues(alpha: 0.8)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      color: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.secondaryContainer : Colors.transparent,
      ),
      selectedColor: scheme.secondaryContainer,
      // Selected option gets an accent rim (aqua in dark, coral in light).
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? BorderSide(color: primary, width: 1.4)
            : BorderSide(color: scheme.outline),
      ),
      shape: const StadiumBorder(),
      labelStyle: textTheme.labelLarge,
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: WidgetStatePropertyAll(BorderSide(color: scheme.outline)),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (dark ? primary : const Color(0xFFB02A2A))
              : text,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : Colors.transparent,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      // D-01: dark FilledButtons use the aqua selection color; coral is kept
      // for Baixar ZIP via [brandFilledStyle]. Light stays brand coral.
      style: FilledButton.styleFrom(
        backgroundColor: dark ? primary : c.brand,
        foregroundColor: dark ? scheme.onPrimary : const Color(0xFF121418),
        textStyle: textTheme.labelLarge?.copyWith(fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(side: BorderSide(color: scheme.outline)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface.withValues(alpha: 0.96),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface.withValues(alpha: 0.97),
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primary),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
          backgroundColor: Colors.transparent,
        ),
      },
    ),
  );
}

/// Brand coral for a FilledButton. D-01: in dark mode only Baixar ZIP wears
/// it; other FilledButtons take the selection color from the theme.
ButtonStyle brandFilledStyle(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: Crystal.of(context).brand,
  foregroundColor: const Color(0xFF121418),
);

/// A screen: drifting aurora behind a transparent [child] Scaffold.
class CrystalPage extends StatelessWidget {
  const CrystalPage({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Crystal.of(context).base,
    child: Stack(
      children: [
        const Positioned.fill(child: RepaintBoundary(child: Aurora())),
        Positioned.fill(child: child),
      ],
    ),
  );
}

/// Shared clock, so the light does not jump when a new screen opens.
final _clock = Stopwatch()..start();

/// Soft lights drifting on slow, different orbits (~40 s loop).
class Aurora extends StatefulWidget {
  const Aurora({super.key});
  @override
  State<Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<Aurora> with SingleTickerProviderStateMixin {
  /// Time between repaints. The orbits move under a pixel per step, so ~20
  /// fps looks the same as 60–120 fps and saves the blurs above a lot of work.
  static const frameGap = Duration(milliseconds: 50);

  // One tick per repaint: the ticker stops after each tick and a timer wakes
  // it. The ticker is muted on covered screens (TickerMode) and gets no
  // frames while the app is in the background, so the light then stops.
  late final Ticker _ticker = createTicker(_tick);
  final _t = ValueNotifier<double>(_clock.elapsedMilliseconds / 1000);
  Timer? _wait;
  bool _still = false;

  void _tick(Duration _) {
    _t.value = _clock.elapsedMilliseconds / 1000;
    _ticker.stop();
    _wait = Timer(frameGap, () {
      _wait = null;
      if (mounted && !_still && !_ticker.isActive) _ticker.start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (_still) {
      _wait?.cancel();
      _wait = null;
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive && _wait == null) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: _AuroraPainter(_t, Crystal.of(context).lights),
    size: Size.infinite,
  );
}

class _AuroraPainter extends CustomPainter {
  _AuroraPainter(this.t, this.lights) : super(repaint: t);
  final ValueNotifier<double> t;
  final List<Color> lights;

  // Anchor (fraction of screen), orbit radius, speed, phase, size.
  static const _orbits = [
    (0.15, 0.18, 0.10, 0.11, 0.0, 0.95),
    (0.90, 0.42, 0.12, 0.08, 2.1, 0.85),
    (0.30, 0.88, 0.14, 0.13, 4.2, 0.70),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final s = t.value;
    final d = math.max(size.width, size.height);
    for (var i = 0; i < lights.length && i < _orbits.length; i++) {
      final (ax, ay, r, speed, phase, scale) = _orbits[i];
      final a = s * speed + phase;
      final center = Offset(
        size.width * (ax + r * math.cos(a)),
        size.height * (ay + r * 0.6 * math.sin(a * 1.3)),
      );
      final radius = d * 0.55 * scale;
      final paint = Paint()
        ..shader = ui.Gradient.radial(center, radius, [
          lights[i],
          lights[i].withValues(alpha: 0),
        ]);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) => old.lights != lights;
}

/// Frosted glass: blurs what is behind, a thin tint, and a lit edge that is
/// bright at the top-left and fades toward the bottom-right, like light
/// catching the bevel of a crystal.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 24,
    this.blur = 22,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final c = Crystal.of(context);
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: c.shadow,
            blurRadius: 30,
            offset: const Offset(0, 14),
            spreadRadius: -10,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: CustomPaint(
            foregroundPainter: _EdgePainter(r, c.edgeBright, c.edgeFaint),
            child: ColoredBox(
              color: c.glassFill,
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter(this.radius, this.bright, this.faint);
  final BorderRadius radius;
  final Color bright;
  final Color faint;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = radius.toRRect(rect).deflate(0.6);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          bright,
          faint,
          faint,
          bright.withValues(alpha: bright.a * 0.35),
        ],
        stops: const [0, 0.45, 0.8, 1],
      ).createShader(rect);
    canvas.drawRRect(rr, paint);
  }

  @override
  bool shouldRepaint(_EdgePainter old) =>
      old.bright != bright || old.faint != faint;
}

/// Progress as a crystal rod: accent-to-[Crystal.rodEnd] fill (aqua to blue in
/// dark, coral to peach in light) that glides to each value,
/// with a band of light sweeping across while the job is running.
class CrystalProgress extends StatefulWidget {
  const CrystalProgress({super.key, required this.value, this.running = true});

  /// Null shows an indeterminate sweep (list still being fetched).
  final double? value;
  final bool running;

  @override
  State<CrystalProgress> createState() => _CrystalProgressState();
}

class _CrystalProgressState extends State<CrystalProgress>
    with SingleTickerProviderStateMixin {
  late final _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(CrystalProgress old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final move =
        widget.running && MediaQuery.maybeDisableAnimationsOf(context) != true;
    if (move && !_sweep.isAnimating) _sweep.repeat();
    if (!move && _sweep.isAnimating) _sweep.stop();
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = Crystal.of(context);
    return Semantics(
      label: l10nOf(context).progress,
      value: widget.value == null ? null : '${(widget.value! * 100).round()}%',
      child: SizedBox(
        height: 8,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: scheme.onSurface.withValues(alpha: 0.10),
            child: TweenAnimationBuilder<double>(
              // Null (list still loading) is an empty rod, so the first real
              // value grows from empty instead of shrinking from full.
              tween: Tween(end: widget.value ?? 0),
              duration: Motion.of(context, Motion.medium),
              curve: Motion.smoothOut,
              builder: (context, v, _) => AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => CustomPaint(
                  painter: _RodPainter(
                    fill: v.clamp(0, 1),
                    sweep: _sweep.value,
                    showSweep: _sweep.isAnimating,
                    from: scheme.primary,
                    to: c.rodEnd,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RodPainter extends CustomPainter {
  _RodPainter({
    required this.fill,
    required this.sweep,
    required this.showSweep,
    required this.from,
    required this.to,
  });
  final double fill;
  final double sweep;
  final bool showSweep;
  final Color from;
  final Color to;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * fill;
    if (w > 0) {
      final rect = Rect.fromLTWH(0, 0, w, size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size.height)),
        Paint()
          ..shader = LinearGradient(colors: [from, to])
              .createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );
    }
    if (!showSweep) return;
    // The light band travels across the whole track (also when fill is 0,
    // which reads as "looking for the videos").
    final band = size.width * 0.28;
    final x = -band + (size.width + band) * sweep;
    final r = Rect.fromLTWH(x, 0, band, size.height);
    canvas.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(r),
    );
  }

  @override
  bool shouldRepaint(_RodPainter o) =>
      o.fill != fill ||
      o.sweep != sweep ||
      o.showSweep != showSweep ||
      o.from != from ||
      o.to != to;
}

/// Small section heading inside a glass panel.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

/// The primary action: a rod of light from coral to peach with a lit top
/// edge. Disabled, it turns to plain frosted glass.
class CrystalButton extends StatelessWidget {
  const CrystalButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = Crystal.of(context);
    final on = onPressed != null;
    final fg = on ? const Color(0xFF121418) : scheme.onSurface.withValues(alpha: 0.42);
    final r = BorderRadius.circular(28);
    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      curve: Motion.smoothOut,
      height: 56,
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: on
            ? LinearGradient(colors: [c.brand, c.peach])
            : LinearGradient(
                colors: [
                  scheme.onSurface.withValues(alpha: 0.08),
                  scheme.onSurface.withValues(alpha: 0.08),
                ],
              ),
        boxShadow: on
            ? [
                BoxShadow(
                  color: c.peach.withValues(alpha: 0.35),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                  spreadRadius: -8,
                ),
              ]
            : const [],
      ),
      // Light catching the top bevel.
      foregroundDecoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: on ? 0.30 : 0.06),
            Colors.white.withValues(alpha: 0),
          ],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 10),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: fg, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom bar of frosted glass: the list scrolls under it and blurs.
class GlassBar extends StatelessWidget {
  const GlassBar({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = Crystal.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.glassFill.withValues(alpha: c.glassFill.a * 0.6),
            border: Border(
              top: BorderSide(
                color: c.edgeBright.withValues(alpha: c.edgeBright.a * 0.5),
              ),
            ),
          ),
          child: SafeArea(top: false, child: child),
        ),
      ),
    );
  }
}

/// The TubExtractor symbol: a play triangle built from caption lines, coral at
/// the top fading to white. Coordinates follow artefatos/vectors/
/// tubextractor-symbol.svg (viewBox 260 x 320). On first show the lines draw
/// in from the left, top to bottom, like captions being written.
class BrandSymbol extends StatefulWidget {
  const BrandSymbol({super.key, this.height = 56, this.animate = true});
  final double height;
  final bool animate;

  @override
  State<BrandSymbol> createState() => _BrandSymbolState();
}

class _BrandSymbolState extends State<BrandSymbol> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = !widget.animate || MediaQuery.maybeDisableAnimationsOf(context) == true;
    if (still) {
      _c.value = 1;
    } else if (_c.value == 0 && !_c.isAnimating) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Semantics(
      label: 'TubExtractor',
      image: true,
      child: SizedBox(
        height: widget.height,
        width: widget.height * 260 / 320,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(painter: _SymbolPainter(_c.value, dark)),
        ),
      ),
    );
  }
}

class _SymbolPainter extends CustomPainter {
  _SymbolPainter(this.t, this.dark);
  final double t;
  final bool dark;

  // (y, x1, x2, color) from the brand SVG.
  static const _lines = [
    (20.0, 20.0, 55.0, 0xFFFF4444),
    (45.0, 20.0, 90.0, 0xFFFF4F4B),
    (70.0, 20.0, 75.0, 0xFFFF5C54),
    (70.0, 90.0, 128.0, 0xFFFF5C54),
    (95.0, 20.0, 165.0, 0xFFFF6A5E),
    (120.0, 20.0, 70.0, 0xFFFF7969),
    (120.0, 85.0, 200.0, 0xFFFF7969),
    (145.0, 20.0, 240.0, 0xFFFF8A7C),
    (170.0, 20.0, 240.0, 0xFFFF9C90),
    (195.0, 20.0, 115.0, 0xFFFFB2A8),
    (195.0, 130.0, 200.0, 0xFFFFB2A8),
    (220.0, 20.0, 165.0, 0xFFFFCCC6),
    (245.0, 20.0, 55.0, 0xFFFFE3E0),
    (245.0, 70.0, 128.0, 0xFFFFE3E0),
    (270.0, 20.0, 90.0, 0xFFF5F5F7),
    (295.0, 20.0, 55.0, 0xFFFFFFFF),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / 320;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 13 * k;
    for (var i = 0; i < _lines.length; i++) {
      final (y, x1, x2, argb) = _lines[i];
      // Each line starts 40 ms after the one above and grows in 400 ms.
      final start = i * 0.036;
      final p = Curves.easeOutCubic.transform(((t - start) / 0.36).clamp(0.0, 1.0));
      if (p == 0) continue;
      var color = Color(argb);
      // On the light theme the white tail of the symbol would vanish; it
      // settles on the brand charcoal instead.
      if (!dark) color = Color.lerp(color, const Color(0xFF121418), (i / (_lines.length - 1)) * 0.85)!;
      paint.color = color.withValues(alpha: p);
      canvas.drawLine(Offset(x1 * k, y * k), Offset((x1 + (x2 - x1) * p) * k, y * k), paint);
    }
  }

  @override
  bool shouldRepaint(_SymbolPainter old) => old.t != t || old.dark != dark;
}

/// "Tub" in the text color, "Extractor" in coral, as in the brand logo.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.style});
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final s = style ?? Theme.of(context).textTheme.displaySmall;
    return Text.rich(
      TextSpan(children: [
        const TextSpan(text: 'Tub'),
        TextSpan(text: 'Extractor', style: TextStyle(color: Crystal.of(context).brand)),
      ]),
      style: s,
      semanticsLabel: 'TubExtractor',
    );
  }
}
