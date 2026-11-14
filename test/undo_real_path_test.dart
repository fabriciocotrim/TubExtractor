// Ticket 06: Desfazer pelo caminho real. O app inteiro (SubshaulApp), num
// tamanho de celular, com gesto de deslizar e toque de verdade e quadros a
// ~60 fps. Nada chama métodos internos para apagar ou desfazer.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subshaul/app_state.dart';
import 'package:subshaul/core/job.dart';
import 'package:subshaul/main.dart';
import 'package:subshaul/screens/home_screen.dart';
import 'package:subshaul/share_intake.dart';

import 'home_undo_test.dart' show untilDone;
import 'job_runner_test.dart' show FakeSource;
import 'l10n_helper.dart';

void main() {
  late Directory dir;
  late AppState app;

  /// The whole app with [n] finished jobs. Returns them in list order.
  Future<List<Job>> open(WidgetTester tester, int n, {double height = 2400}) async {
    tester.view
      ..physicalSize = Size(1080, height)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final jobs = <Job>[];
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('subshaul_real');
      final store = Store(dir);
      await store.init();
      SharedPreferences.setMockInitialValues({});
      final t0 = tester.binding.clock.now();
      app = await AppState.start(store, FakeSource(), await SharedPreferences.getInstance(),
          gap: Duration.zero, elapsed: () => tester.binding.clock.now().difference(t0));
      for (var i = 0; i < n; i++) {
        final j = app.createJob('https://youtu.be/dQw4w9WgXcQ');
        await untilDone(app, j);
        jobs.add(j);
      }
    });
    addTearDown(() => dir.delete(recursive: true));
    phoneInPortuguese(tester);
    await tester.pumpWidget(SubshaulApp(app: app, intake: ShareIntake()));
    await frames(tester, 1500);
    return jobs.reversed.toList();
  }

  /// "Reopens" the app: a new state read from the same disk and preferences.
  Future<List<String>> reopened(WidgetTester tester) async {
    // Deletes that started in the test's fake time finish as frames run.
    var settled = false;
    app.settleDeletes().then((_) => settled = true);
    final sw = Stopwatch()..start();
    while (!settled) {
      if (sw.elapsed > const Duration(seconds: 10)) fail('os apagamentos não terminaram em 10 s');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump();
    }
    return (await tester.runAsync(() async {
        final again = await AppState.start(Store(dir), FakeSource(), await SharedPreferences.getInstance(),
            gap: Duration.zero);
        return [for (final j in again.jobs) j.id];
      }))!;
  }

  void say(WidgetTester tester, String m) =>
      ScaffoldMessenger.of(tester.element(find.byType(HomeScreen))).showSnackBar(SnackBar(content: Text(m)));

  Finder notice() => find.text('Busca apagada.').hitTestable();

  testWidgets('apagar 1 de 2 mostra o aviso na hora, mesmo com mensagens na fila', (tester) async {
    final jobs = await open(tester, 2);
    say(tester, 'ZIP salvo.');
    say(tester, 'Link recebido. Toque em Buscar transcrições.');
    await frames(tester, 300);

    await realSwipe(tester, find.byKey(ValueKey(jobs.first.id)));
    await frames(tester, 900);
    expect(app.jobs, [jobs.last]);
    expect(notice(), findsOneWidget);
    expect(find.text('Desfazer').hitTestable(), findsOneWidget);
    expect(find.text('ZIP salvo.'), findsOneWidget, reason: 'a outra mensagem segue na tela');
  });

  testWidgets('apagar a única busca: Desfazer devolve a busca, visível e no disco ao reabrir', (tester) async {
    final jobs = await open(tester, 1);
    await realSwipe(tester, find.byKey(ValueKey(jobs.single.id)));
    await frames(tester, 900);
    expect(app.jobs, isEmpty);
    expect(notice(), findsOneWidget);

    await frames(tester, 2000); // o usuário pensa um pouco
    await tester.tap(find.text('Desfazer'));
    await frames(tester, 600);
    expect(app.jobs, jobs);
    expect(find.byKey(ValueKey(jobs.single.id)).hitTestable(), findsOneWidget, reason: 'visível');
    expect(notice(), findsNothing);

    await frames(tester, 7000); // a janela teria acabado aqui
    expect(app.jobs, jobs);
    expect(await reopened(tester), [jobs.single.id], reason: 'continua no disco');
  });

  testWidgets('apagar A e B; Desfazer B; aviso de A reaparece; Desfazer A; as duas ficam', (tester) async {
    final jobs = await open(tester, 2);
    final a = jobs.first, b = jobs.last;
    await realSwipe(tester, find.byKey(ValueKey(a.id)));
    await frames(tester, 900);
    await realSwipe(tester, find.byKey(ValueKey(b.id)));
    await frames(tester, 900);
    expect(app.jobs, isEmpty);
    expect(notice(), findsOneWidget, reason: 'um aviso por vez: o de B');

    await tester.tap(find.text('Desfazer'));
    await frames(tester, 600);
    expect(app.jobs, [b]);
    expect(notice(), findsOneWidget, reason: 'o aviso de A reaparece');

    await tester.tap(find.text('Desfazer'));
    await frames(tester, 600);
    expect(app.jobs, [a, b]);
    expect(notice(), findsNothing);
    await frames(tester, 7000);
    expect(app.jobs, [a, b]);
    expect(await reopened(tester), [a.id, b.id]);
  });

  testWidgets('sem Desfazer, a busca sai de vez ao fim dos 5 s e o aviso some', (tester) async {
    final jobs = await open(tester, 2);
    await realSwipe(tester, find.byKey(ValueKey(jobs.first.id)));
    await frames(tester, 4000);
    expect(notice(), findsOneWidget);
    await frames(tester, 1500);
    expect(notice(), findsNothing);
    expect(await reopened(tester), [jobs.last.id]);
  });

  testWidgets('tela inicial recriada mostra os avisos pendentes e o contador anda', (tester) async {
    final jobs = await open(tester, 2);
    await realSwipe(tester, find.byKey(ValueKey(jobs.first.id)));
    await frames(tester, 900);
    await tester.pumpWidget(const SizedBox()); // a tela some (ex.: o app é recriado)
    await frames(tester, 3000);
    await tester.pumpWidget(SubshaulApp(app: app, intake: ShareIntake()));
    await frames(tester, 500);
    expect(notice(), findsOneWidget);
    expect(app.pendingDeletes, hasLength(1));
    await frames(tester, 6000);
    expect(app.pendingDeletes, isEmpty, reason: 'o contador andou');
    expect(notice(), findsNothing);
    expect(await reopened(tester), [jobs.last.id]);
  });

  testWidgets('tela inicial trocada por outra no mesmo quadro: o contador continua andando', (tester) async {
    final jobs = await open(tester, 2);
    await realSwipe(tester, find.byKey(ValueKey(jobs.first.id)));
    await frames(tester, 900);
    // Nova árvore no mesmo quadro: a tela nova nasce antes de a antiga sair.
    await tester.pumpWidget(KeyedSubtree(key: UniqueKey(), child: SubshaulApp(app: app, intake: ShareIntake())));
    await frames(tester, 500);
    expect(notice(), findsOneWidget);
    await frames(tester, 6000);
    expect(app.pendingDeletes, isEmpty, reason: 'o contador andou');
    expect(notice(), findsNothing);
    expect(await reopened(tester), [jobs.last.id]);
  });

  testWidgets('o contador para com outra tela por cima e com o app em segundo plano', (tester) async {
    final jobs = await open(tester, 2);
    await realSwipe(tester, find.byKey(ValueKey(jobs.first.id)));
    await frames(tester, 900);
    final p = app.currentDelete!;

    // Abre a outra busca: a tela inicial fica por baixo.
    final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
    await tester.scrollUntilVisible(find.byKey(ValueKey(jobs.last.id)), 200, scrollable: list);
    await tester.tap(find.byKey(ValueKey(jobs.last.id)));
    await frames(tester, 1000);
    final left = p.remaining;
    await frames(tester, 10000);
    expect(app.currentDelete, p);
    expect(p.remaining, left);
    await tester.binding.handlePopRoute(); // voltar
    await frames(tester, 1000);
    expect(notice(), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final paused = p.remaining;
    await frames(tester, 10000);
    expect(app.currentDelete, p);
    expect(p.remaining, paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await frames(tester, paused.inMilliseconds + 500);
    expect(app.currentDelete, isNull);
  });

  // Sequências variadas de apagar, desfazer, esperar, outras mensagens, tema e
  // abrir uma busca. Em cada uma: o aviso aparece na hora, Desfazer devolve a
  // busca do aviso visível e, no fim, o disco bate com a lista.
  for (var seed = 0; seed < 12; seed++) {
    testWidgets('sequência $seed', (tester) async {
      final r = Random(seed);
      final all = await open(tester, 4, height: 4400);
      final log = <String>[];
      for (var step = 0; step < 14; step++) {
        final k = r.nextInt(7);
        if (k <= 1 && app.jobs.isNotEmpty) {
          final j = app.jobs[r.nextInt(app.jobs.length)];
          log.add('apaga ${all.indexOf(j)}');
          await realSwipe(tester, find.byKey(ValueKey(j.id)));
          await frames(tester, 900);
          expect(app.jobs, isNot(contains(j)), reason: log.join(', '));
          expect(notice(), findsOneWidget, reason: 'aviso na hora: ${log.join(', ')}');
        } else if (k == 2 && find.text('Desfazer').hitTestable().evaluate().isNotEmpty) {
          final top = app.currentDelete!.job;
          log.add('desfaz ${all.indexOf(top)}');
          await tester.tap(find.text('Desfazer'));
          await frames(tester, 600);
          expect(app.jobs, contains(top), reason: 'voltou: ${log.join(', ')}');
        } else if (k == 3) {
          final ms = 200 + r.nextInt(6000);
          log.add('espera $ms');
          await frames(tester, ms);
        } else if (k == 4) {
          log.add('mensagem');
          say(tester, 'ZIP salvo.');
          await frames(tester, 300);
        } else if (k == 5) {
          log.add('tema');
          await tester.tap(find.byWidgetPredicate((w) => w is IconButton && (w.tooltip ?? '').startsWith('Tema')));
          await frames(tester, 700);
        } else if (app.jobs.isNotEmpty) {
          final j = app.jobs[r.nextInt(app.jobs.length)];
          log.add('abre ${all.indexOf(j)}');
          final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
          await tester.scrollUntilVisible(find.byKey(ValueKey(j.id)), 200, scrollable: list);
          final rect = tester.getRect(find.byKey(ValueKey(j.id)));
          await tester.tapAt(Offset(rect.center.dx, rect.top + 12));
          await frames(tester, 800);
          await tester.binding.handlePopRoute();
          await frames(tester, 800);
        }
      }
      await frames(tester, 6000);
      final left = [for (final j in app.jobs) j.id];
      expect(await reopened(tester), left, reason: 'o disco bate com a lista: ${log.join(', ')}');
    });
  }
}

/// Frames at ~60 fps for [ms] milliseconds of the test's fake time (no real
/// waiting).
Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// A finger swipe to the left over 250 ms, frame by frame, after scrolling
/// the tile to the middle of the screen like a person would.
Future<void> realSwipe(WidgetTester tester, Finder f) async {
  final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
  await tester.scrollUntilVisible(f, 200, scrollable: list);
  Scrollable.ensureVisible(tester.element(f), alignment: 0.5);
  await frames(tester, 300);
  // Near the tile's top edge: the bottom of the last tile can sit under the
  // notice and the bottom bar, as on a phone.
  final r = tester.getRect(f);
  await tester.timedDragFrom(Offset(r.center.dx, r.top + 12), const Offset(-300, 0), const Duration(milliseconds: 250));
}
