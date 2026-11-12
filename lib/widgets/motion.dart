/// Shared motion scale. Every animation in the app reads from here, so timing
/// stays consistent and the system "Remove animations" setting turns it off.
/// Durations and curves follow the transitions.dev motion tokens.
library;

import 'dart:async';

import 'package:flutter/material.dart';

abstract final class Motion {
  /// Per-item stagger offset.
  static const stagger = Duration(milliseconds: 60);

  /// Text and icon swaps, highlight changes.
  static const quick = Duration(milliseconds: 150);

  /// Icon swaps with scale, button swaps, sliding tabs.
  static const fast = Duration(milliseconds: 250);

  /// Size changes: a block that appears, grows or collapses.
  static const medium = Duration(milliseconds: 350);

  /// Text reveal, success pop, theme change.
  static const slow = Duration(milliseconds: 500);

  /// Confident arrival: decelerates hard, no overshoot.
  static const smoothOut = Cubic(0.22, 1, 0.36, 1);

  /// Small overshoot for a "done" moment.
  static const bounce = Cubic(0.34, 1.36, 0.64, 1);

  /// Zero when the user turned animations off in Android settings.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
}

/// Cross-fades [child] when its key changes, with a slight scale so an icon
/// swap reads as a change of state, not a flicker. [pop] gives the arrival a
/// small overshoot (used when something finishes); [turn] adds a quarter turn
/// (used by the theme button, sun to moon).
class SwapIn extends StatelessWidget {
  const SwapIn({super.key, required this.child, this.scale = true, this.pop = false, this.turn = false});
  final Widget child;
  final bool scale;
  final bool pop;
  final bool turn;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(context, pop ? Motion.slow : Motion.fast),
        reverseDuration: Motion.of(context, Motion.quick),
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, a) {
          final arrive = CurvedAnimation(parent: a, curve: pop ? Motion.bounce : Motion.smoothOut);
          Widget w = child;
          if (scale) w = ScaleTransition(scale: Tween(begin: pop ? 0.4 : 0.8, end: 1.0).animate(arrive), child: w);
          if (turn) w = RotationTransition(turns: Tween(begin: -0.25, end: 0.0).animate(arrive), child: w);
          return FadeTransition(opacity: CurvedAnimation(parent: a, curve: Motion.smoothOut), child: w);
        },
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        child: child,
      );
}

/// A line of text that changes in place: the old value fades out while the
/// new one rises 4 px into place. For status lines and counters.
class TextSwap extends StatelessWidget {
  const TextSwap(this.text, {super.key, this.style, this.maxLines});
  final String text;
  final TextStyle? style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: Motion.of(context, Motion.fast),
        reverseDuration: Motion.of(context, Motion.quick),
        switchInCurve: Motion.smoothOut,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        child: Text(text, key: ValueKey(text), style: style, maxLines: maxLines, overflow: TextOverflow.ellipsis),
      );
}

/// Animates height changes of [child], e.g. a line that appears or a block
/// that collapses when a job finishes.
class Resize extends StatefulWidget {
  const Resize({super.key, required this.child});
  final Widget child;

  @override
  State<Resize> createState() => _ResizeState();
}

class _ResizeState extends State<Resize> {
  // Moves [child] between the two shapes below without remounting it, so
  // switching "remove animations" keeps its state.
  final _keep = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final d = Motion.of(context, Motion.medium);
    final child = KeyedSubtree(key: _keep, child: widget.child);
    // A zero-length AnimatedSize re-dirties itself during layout (a
    // framework assertion); with animations off the size just snaps.
    if (d == Duration.zero) return child;
    return AnimatedSize(
      duration: d,
      curve: Motion.smoothOut,
      alignment: Alignment.topCenter,
      child: child,
    );
  }
}

/// Entrance for stacked blocks: fades in while rising 12 px, each block
/// [index] x 60 ms after the previous one. Plays once, when first built.
/// [instant] shows it at full opacity at once, e.g. a block that comes back
/// after the screen opened (an undone delete must not hide behind a delay).
class Reveal extends StatefulWidget {
  const Reveal({super.key, required this.index, required this.child, this.instant = false});
  final int index;
  final Widget child;
  final bool instant;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: Motion.slow);
  late final _a = CurvedAnimation(parent: _c, curve: Motion.smoothOut);
  Timer? _delay;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.instant || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _c.value = 1;
    } else {
      _delay = Timer(Motion.stagger * widget.index, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _a,
        child: AnimatedBuilder(
          animation: _a,
          builder: (_, child) => Transform.translate(offset: Offset(0, 12 * (1 - _a.value)), child: child),
          child: widget.child,
        ),
      );
}

/// Segmented choice with a pill that slides to the chosen option. Options
/// share the width equally; labels shrink to fit instead of wrapping.
class SlidingTabs<T> extends StatelessWidget {
  const SlidingTabs({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelLarge;
    final index = options.indexWhere((o) => o.$1 == value).clamp(0, options.length - 1);
    const h = 46.0;
    final r = BorderRadius.circular(h / 2);
    return Container(
      height: h,
      decoration: BoxDecoration(borderRadius: r, border: Border.all(color: scheme.outline)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / options.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: Motion.of(context, Motion.fast),
            curve: Motion.smoothOut,
            left: w * index,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: r,
                color: scheme.secondaryContainer,
                border: Border.all(color: scheme.primary, width: 1.4),
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < options.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  child: InkWell(
                    borderRadius: r,
                    onTap: () => onChanged(options[i].$1),
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.of(context, Motion.fast),
                            style: (text ?? const TextStyle()).copyWith(
                              color: i == index ? scheme.primary : scheme.onSurface,
                            ),
                            child: Text(options[i].$2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}
