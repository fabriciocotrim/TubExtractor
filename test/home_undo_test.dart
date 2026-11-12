// Tickets 02 and 05: the delete notice and the job brought back by "Desfazer".
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:subshaul/app_state.dart';
import 'package:subshaul/core/job.dart';
import 'package:subshaul/screens/home_screen.dart';
import 'package:subshaul/share_intake.dart';
import 'package:subshaul/widgets/crystal.dart';

import 'app_state_test.dart' show FakeClock;
import 'job_runner_test.dart' show FakeSource;

void main() {
  testWidgets('a busca restaurada fica visível (opacidade 1) logo após o Desfazer', (tester) async {
    tester.view
      ..physicalSize = const Size(800, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Directory dir;
    late AppState app;
    late Job job;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('subshaul_home');
      final store = Store(dir);
      await store.init();
      SharedPreferences.setMockInitialValues({});
      app = await AppState.start(store, FakeSource(), await SharedPreferences.getInstance(), gap: Duration.zero);
      job = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      await untilDone(app, job);
    });
    addTearDown(() => dir.delete(recursive: true));

    await tester.pumpWidget(MaterialApp(
      theme: crystalTheme(Brightness.light),
      home: HomeScreen(app: app, intake: ShareIntake()),
    ));
    await tester.pump(const Duration(seconds: 1)); // entrada da tela

    // Única busca: apagar tira a seção "Histórico" inteira.
    await tester.drag(find.byKey(ValueKey(job.id)), const Offset(-700, 0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(app.jobs, isEmpty);
    expect(find.text('Histórico'), findsNothing);
    expect(find.text('Busca apagada.'), findsOneWidget);

    // Um arrasto no aviso não o descarta (o Desfazer continua lá).
    await tester.drag(find.text('Busca apagada.'), const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Desfazer'), findsOneWidget);

    await tester.tap(find.text('Desfazer'));
    await tester.pump();
    await tester.pump();

    expect(app.jobs, [job]);
    final reveal = find.byKey(ValueKey('tile-${job.id}'));
    expect(reveal, findsOneWidget);
    final fade = tester.widget<FadeTransition>(
      find.descendant(of: reveal, matching: find.byType(FadeTransition)).first,
    );
    expect(fade.opacity.value, 1.0);

    // Não deixa timer pendente: o aviso sumiu e nada mais conta.
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Busca apagada.'), findsNothing);
    expect(app.currentDelete, isNull);
  });

  group('aviso de apagar', () {
    late Directory dir;
    late AppState app;
    late FakeClock clock;

    /// Home screen with [n] finished jobs, on a fake clock for the window.
    /// [disk] replaces the preferences' platform store.
    Future<List<Job>> open(WidgetTester tester,
        {int n = 1, Size size = const Size(800, 2400), SharedPreferencesStorePlatform? disk}) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      clock = FakeClock();
      final jobs = <Job>[];
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('subshaul_home');
        final store = Store(dir);
        await store.init();
        SharedPreferences.setMockInitialValues({});
        if (disk != null) SharedPreferencesStorePlatform.instance = disk;
        app = await AppState.start(store, FakeSource(), await SharedPreferences.getInstance(),
            gap: Duration.zero, elapsed: clock.elapsed, timer: clock.timer);
        for (var i = 0; i < n; i++) {
          final j = app.createJob('https://youtu.be/dQw4w9WgXcQ');
          await untilDone(app, j);
          jobs.add(j);
        }
      });
      addTearDown(() => dir.delete(recursive: true));
      await tester.pumpWidget(MaterialApp(
        theme: crystalTheme(Brightness.light),
        home: HomeScreen(app: app, intake: ShareIntake()),
      ));
      await tester.pump(const Duration(seconds: 1)); // entrada da tela
      return jobs.reversed.toList(); // list order: newest first
    }

    void say(WidgetTester tester, String m) => ScaffoldMessenger.of(tester.element(find.byType(HomeScreen)))
        .showSnackBar(SnackBar(content: Text(m)));

    Future<void> swipe(WidgetTester tester, Job j) async {
      await tester.drag(find.byKey(ValueKey(j.id)), const Offset(-700, 0));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    /// [ms] of fake time in 100 ms frames, so animations and timers advance.
    Future<void> wait(WidgetTester tester, int ms) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<Set<String>> onDisk(WidgetTester tester) async =>
        (await tester.runAsync(() async => {for (final j in await Store(dir).loadJobs()) j.id}))!;

    testWidgets('aparece na hora mesmo com outra mensagem na tela; os 5 s contam dali', (tester) async {
      final jobs = await open(tester);
      say(tester, 'ZIP salvo.');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('ZIP salvo.'), findsOneWidget);

      await swipe(tester, jobs.single);
      expect(find.text('Busca apagada.'), findsOneWidget);
      expect(find.text('Desfazer').hitTestable(), findsOneWidget);
      expect(app.currentDelete!.remaining, const Duration(seconds: 5));

      clock.advance(const Duration(milliseconds: 4999));
      await tester.pump();
      expect(find.text('Desfazer'), findsOneWidget);
      await tester.runAsync(() async {
        clock.advance(const Duration(milliseconds: 1));
        await app.settleDeletes();
      });
      await tester.pump(const Duration(seconds: 1));
      await wait(tester, 500); // the closed notice slides away
      expect(find.text('Busca apagada.'), findsNothing);
      expect(await onDisk(tester), isEmpty, reason: 'os arquivos saíram do disco');
    });

    // Ported (ticket 06): the notice no longer waits in the message queue, so
    // "out of sight" now means another screen on top of the home screen.
    testWidgets('o tempo não corre enquanto outra tela cobre o aviso', (tester) async {
      final jobs = await open(tester);
      say(tester, 'ZIP salvo.');
      say(tester, 'Link recebido. Toque em Buscar transcrições.');
      await tester.pump(const Duration(milliseconds: 500));

      await swipe(tester, jobs.single);
      final p = app.currentDelete!;
      expect(find.text('Desfazer').hitTestable(), findsOneWidget, reason: 'não espera as outras mensagens');
      Navigator.of(tester.element(find.byType(HomeScreen)))
          .push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('outra tela'))));
      await wait(tester, 1000);
      expect(find.text('Desfazer').hitTestable(), findsNothing);
      final left = p.remaining;
      clock.advance(const Duration(seconds: 30));
      expect(app.currentDelete, p);
      expect(p.remaining, left);

      Navigator.of(tester.element(find.text('outra tela'))).pop();
      await wait(tester, 1000);
      expect(find.text('Desfazer').hitTestable(), findsOneWidget);
      clock.advance(left - const Duration(seconds: 1));
      expect(p.remaining, const Duration(seconds: 1));
      await tester.tap(find.text('Desfazer'));
      await tester.pump();
      await tester.pump();
      expect(app.jobs, jobs);
    });

    testWidgets('fim da janela tira só o aviso; mensagens na fila continuam', (tester) async {
      final jobs = await open(tester, n: 2);
      await swipe(tester, jobs.first);
      expect(find.text('Busca apagada.'), findsOneWidget);
      say(tester, 'Link recebido. Toque em Buscar transcrições.');
      say(tester, '1 transcrição copiada.');
      await tester.pump();

      await tester.runAsync(() async {
        clock.advance(const Duration(seconds: 5));
        await app.settleDeletes();
      });
      await tester.pump(const Duration(milliseconds: 500));
      await wait(tester, 500); // the closed notice slides away
      expect(find.text('Busca apagada.'), findsNothing);
      expect(find.text('Link recebido. Toque em Buscar transcrições.'), findsOneWidget);
      expect(await onDisk(tester), {jobs.last.id});

      await wait(tester, 6000);
      expect(find.text('1 transcrição copiada.'), findsOneWidget);
    });

    testWidgets('desfazer o aviso de cima traz de volta o de baixo, que segue funcionando', (tester) async {
      final jobs = await open(tester, n: 3);
      await swipe(tester, jobs[2]);
      final below = app.currentDelete!;
      clock.advance(const Duration(seconds: 1));
      await swipe(tester, jobs[0]);
      expect(find.text('Busca apagada.'), findsOneWidget);

      await tester.tap(find.text('Desfazer'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(app.jobs, [jobs[0], jobs[1]]);
      expect(app.currentDelete, below);
      expect(find.text('Busca apagada.'), findsOneWidget, reason: 'o aviso de baixo reaparece');
      expect(below.remaining, const Duration(seconds: 4));

      await tester.tap(find.text('Desfazer'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(app.jobs, jobs);
      expect(find.text('Busca apagada.'), findsNothing);
    });

    testWidgets('com mensagens na fila, o aviso novo cobre o antigo e Desfazer traz o antigo de volta', (tester) async {
      final jobs = await open(tester, n: 2);
      say(tester, 'ZIP salvo.');
      say(tester, 'Link recebido. Toque em Buscar transcrições.');
      await tester.pump(const Duration(milliseconds: 500));
      await swipe(tester, jobs[0]); // A's notice shows, messages or not
      await swipe(tester, jobs[1]); // B's notice covers it
      final b = app.currentDelete!;
      await wait(tester, 3000);
      expect(find.text('Busca apagada.').hitTestable(), findsOneWidget);
      expect(app.pendingDeletes.length, 2);

      await tester.tap(find.text('Desfazer'));
      await wait(tester, 1000);
      expect(app.jobs, [jobs[1]], reason: 'só B volta');
      expect(app.pendingDeletes.single.job, jobs[0]);
      expect(app.pendingDeletes, isNot(contains(b)));
      expect(find.text('Busca apagada.').hitTestable(), findsOneWidget, reason: 'o aviso de A volta');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a lista rola até a busca restaurada fora da tela', (tester) async {
      final jobs = await open(tester, n: 8, size: const Size(400, 700));
      final last = jobs.last;
      final list = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;
      await tester.scrollUntilVisible(find.byKey(ValueKey(last.id)), 300, scrollable: list);
      await tester.pump(const Duration(seconds: 1));
      await swipe(tester, last);
      // Back to the top: the restored job will be far below.
      await tester.drag(find.byType(ListView), const Offset(0, 5000));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(ValueKey('tile-${last.id}')).hitTestable(), findsNothing);

      await tester.tap(find.text('Desfazer'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final tile = tester.getRect(find.byKey(ValueKey('tile-${last.id}')));
      expect(tile.top, greaterThanOrEqualTo(0));
      expect(tile.bottom, lessThanOrEqualTo(700));
      expect(find.byKey(ValueKey(last.id)).hitTestable(), findsOneWidget);
    });

    testWidgets('busca nova entra com a animação da 1.4.0; só a restaurada aparece na hora', (tester) async {
      await open(tester);
      late Job fresh;
      await tester.runAsync(() async {
        fresh = app.createJob('https://youtu.be/jNQXAC9IVRw');
        await untilDone(app, fresh);
      });
      await tester.pump();
      double opacity() => tester
          .widget<FadeTransition>(
            find.descendant(of: find.byKey(ValueKey('tile-${fresh.id}')), matching: find.byType(FadeTransition)).first,
          )
          .opacity
          .value;
      expect(opacity(), 0, reason: 'começa invisível e sobe');
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(opacity(), 1);
    });

    testWidgets('a marca de apagar está gravada no disco antes de a busca sair da lista', (tester) async {
      final disk = _SlowDisk();
      final jobs = await open(tester, n: 2, disk: disk);
      final a = jobs.first;
      bool? saved;
      void check() {
        if (saved == null && !app.jobs.contains(a)) {
          saved = (disk.saved['flutter.pendingDeletes'] as List?)?.contains(a.id) ?? false;
        }
      }

      app.addListener(check);
      await swipe(tester, a);
      app.removeListener(check);
      expect(saved, isTrue, reason: 'um kill neste instante não ressuscita a busca');
      expect(find.text('Busca apagada.'), findsOneWidget);
      await wait(tester, 1000); // gravações pendentes terminam
    });

    testWidgets('tela fechada entre a marca gravada e a saída da busca: ela não é apagada ao reabrir', (tester) async {
      final disk = _SlowDisk();
      final jobs = await open(tester, n: 2, disk: disk);
      final a = jobs.first;
      bool marked() => (disk.saved['flutter.pendingDeletes'] as List?)?.contains(a.id) ?? false;
      await tester.drag(find.byKey(ValueKey(a.id)), const Offset(-700, 0));
      for (var i = 0; i < 100 && !marked(); i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(marked(), isTrue, reason: 'a marca chegou ao disco');
      expect(app.jobs, contains(a), reason: 'a busca ainda não saiu da lista');

      await tester.pumpWidget(const SizedBox()); // a tela some neste instante
      await tester.pump(const Duration(seconds: 1)); // gravações pendentes terminam
      expect(marked(), isFalse, reason: 'a marca foi desfeita');
      final again = (await tester.runAsync(() async =>
          AppState.start(Store(dir), FakeSource(), await SharedPreferences.getInstance(), gap: Duration.zero)))!;
      expect(again.jobs.map((j) => j.id), contains(a.id), reason: 'a busca que o usuário via continua lá');
    });

    testWidgets('apagar A, apagar B e desfazer B durante a saída do aviso de A: sem chave duplicada', (tester) async {
      final jobs = await open(tester, n: 2);
      await swipe(tester, jobs[0]);
      await tester.drag(find.byKey(ValueKey(jobs[1].id)), const Offset(-700, 0));
      for (var i = 0; i < 100 && app.pendingDeletes.length < 2; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(app.currentDelete?.job, jobs[1]);
      // O aviso de B cresce enquanto o de A sai (250 ms): toca assim que dá.
      for (var i = 0; i < 8 && find.text('Desfazer').hitTestable().evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text('Desfazer'), findsNWidgets(2), reason: 'o aviso de A ainda está saindo');
      await tester.tap(find.text('Desfazer').hitTestable().last);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull);
      }
      expect(app.jobs, [jobs[1]]);
      expect(app.currentDelete?.job, jobs[0]);
      await wait(tester, 1000);
      expect(find.text('Busca apagada.').hitTestable(), findsOneWidget, reason: 'o aviso de A volta');
      expect(find.text('Desfazer').hitTestable(), findsOneWidget);
    });
  });
}

/// Waits, in real time, until [job] is done and stopped. Fails with a clear
/// message instead of hanging.
Future<void> untilDone(AppState app, Job job) async {
  final sw = Stopwatch()..start();
  while (job.state != JobState.done || app.isRunning(job)) {
    if (sw.elapsed > const Duration(seconds: 10)) fail('a busca ${job.id} não terminou em 10 s');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Preferences whose writes reach the "disk" ([saved]) only some time after
/// they are asked for, like a phone's.
class _SlowDisk extends InMemorySharedPreferencesStore {
  _SlowDisk() : super.empty();
  final saved = <String, Object>{};

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    saved[key] = value;
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    saved.remove(key);
    return super.remove(key);
  }
}
