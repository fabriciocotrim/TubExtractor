// D-01: in dark mode coral is only on Buscar, Baixar ZIP and "Extractor";
// selections and progress use aqua. The light theme does not change.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subshaul/widgets/crystal.dart';

import 'l10n_helper.dart';

const aqua = Color(0xFF5EE6C8);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Widget _host(Brightness b, Widget child) => MaterialApp(
  theme: crystalTheme(b),
  home: Scaffold(body: Center(child: child)),
);

/// Background and text color the FilledButton actually paints.
(Color, Color) _paint(WidgetTester tester) {
  final m = tester.widget<Material>(
    find.descendant(of: find.byType(FilledButton), matching: find.byType(Material)).first,
  );
  return (m.color!, m.textStyle!.color!);
}

void main() {
  testWidgets('dark: a plain FilledButton is aqua, never coral', (tester) async {
    await tester.pumpWidget(_host(Brightness.dark, FilledButton(onPressed: () {}, child: const Text('Salvar'))));
    final (bg, fg) = _paint(tester);
    expect(bg, isNot(Crystal.night.brand));
    expect(bg, isNot(Crystal.night.peach));
    expect(bg, aqua);
    expect(_contrast(bg, fg), greaterThanOrEqualTo(4.5));
  });

  testWidgets('dark: the brand FilledButton (Baixar ZIP) stays coral', (tester) async {
    await tester.pumpWidget(_host(
      Brightness.dark,
      Builder(builder: (ctx) => FilledButton(style: brandFilledStyle(ctx), onPressed: () {}, child: const Text('Baixar ZIP'))),
    ));
    final (bg, fg) = _paint(tester);
    expect(bg, Crystal.night.brand);
    expect(fg, const Color(0xFF121418));
  });

  testWidgets('light: plain and brand FilledButton keep the brand coral', (tester) async {
    await tester.pumpWidget(_host(Brightness.light, FilledButton(onPressed: () {}, child: const Text('Salvar'))));
    expect(_paint(tester).$1, Crystal.day.brand);
    expect(_paint(tester).$2, const Color(0xFF121418));
    await tester.pumpWidget(_host(
      Brightness.light,
      Builder(builder: (ctx) => FilledButton(style: brandFilledStyle(ctx), onPressed: () {}, child: const Text('Baixar ZIP'))),
    ));
    expect(_paint(tester).$1, Crystal.day.brand);
  });

  test('dark: current search hit is aqua, not peach; light unchanged', () {
    final dark = crystalTheme(Brightness.dark).colorScheme.tertiaryContainer;
    expect(dark.withValues(alpha: 1), aqua);
    final light = crystalTheme(Brightness.light).colorScheme.tertiaryContainer;
    expect(light, Crystal.day.peach.withValues(alpha: 0.26));
  });

  test('wordmark coral stays in both themes', () {
    expect(Crystal.night.brand, const Color(0xFFFF4444));
    expect(Crystal.day.brand, const Color(0xFFD93636));
  });

  testWidgets('progress rod repaints when the theme colors change while paused', (tester) async {
    Widget at(Brightness b) => MediaQuery(
      data: const MediaQueryData(),
      child: Localizations(
        locale: ptLocale,
        delegates: l10nDelegates,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: crystalTheme(b),
            child: const SizedBox(width: 200, child: CrystalProgress(value: 0.5, running: false)),
          ),
        ),
      ),
    );
    CustomPainter rod() => tester
        .widget<CustomPaint>(find.descendant(of: find.byType(CrystalProgress), matching: find.byType(CustomPaint)).first)
        .painter!;

    await tester.pumpWidget(at(Brightness.dark));
    await tester.pumpAndSettle();
    final before = rod();
    await tester.pumpWidget(at(Brightness.light));
    await tester.pumpAndSettle();
    final after = rod();
    expect(after.shouldRepaint(before), isTrue);
  });
}
