// Covers on the machine what CT-10, CT-11 and CT-12 asked the PO to test by hand.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:subshaul/app_state.dart';
import 'package:subshaul/core/job.dart';
import 'package:subshaul/core/job_runner.dart';
import 'package:subshaul/core/url_parser.dart';
import 'package:subshaul/core/youtube_client.dart';

import 'job_runner_test.dart' show FakeSource;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Store store;
  late FakeSource src;

  Future<AppState> open() async {
    SharedPreferences.setMockInitialValues({});
    return AppState.start(store, src, await SharedPreferences.getInstance(), gap: Duration.zero);
  }

  Future<void> until(bool Function() ok) async {
    // Generous limit: the first test runs while the VM warms up and other test
    // files run in parallel.
    final sw = Stopwatch()..start();
    while (!ok() && sw.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(ok(), isTrue);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('subshaul_app');
    store = Store(dir);
    await store.init();
    src = FakeSource();
  });
  tearDown(() => dir.delete(recursive: true));

  test('CT-11: link de outro site é ignorado e só o vídeo do YouTube é buscado', () async {
    const input = 'https://google.com\nhttps://youtu.be/dQw4w9WgXcQ';
    expect(parseInput(input).summary, 'Reconhecido: 1 vídeo · 1 link ignorado');

    final app = await open();
    final j = app.createJob(input);
    await until(() => j.state == JobState.done && !app.isRunning(j));
    expect(src.fetched, ['dQw4w9WgXcQ']);
    expect(j.items.length, 1);
    expect(j.messages.single, contains('google.com'));
  });

  group('apagar com avisos em sequência', () {
    late FakeClock clock;
    late SharedPreferences prefs;

    Future<AppState> openWithClock({TranscriptSource? source}) async {
      return AppState.start(store, source ?? src, prefs,
          gap: Duration.zero, elapsed: clock.elapsed, timer: clock.timer);
    }

    setUp(() async {
      clock = FakeClock();
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    Future<Set<String>> onDisk() async => {for (final j in await Store(dir).loadJobs()) j.id};

    test('CT-12: job apagado no meio da busca não volta ao reabrir o app', () async {
      src.channelSize = 30;
      final app = await openWithClock();
      final j = app.createJob('@mkbhd');
      await until(() => j.okCount >= 2);
      app.deleteWithUndo(j); // apagado no meio da busca
      clock.advance(const Duration(seconds: 5));
      await app.settleDeletes();
      expect(app.jobs, isEmpty);
      expect(await Store(dir).loadJobs(), isEmpty);
    });

    test('apagar por engano: desfazer devolve a busca, sem perder nada do disco', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://youtu.be/jNQXAC9IVRw');
      await until(() => !app.isRunning(a) && !app.isRunning(b));
      final p = app.deleteWithUndo(a)!;
      expect(app.jobs, [b]);
      expect((await Store(dir).loadJobs()).length, 2, reason: 'ainda no disco');
      app.undoDelete(p);
      expect(app.jobs, [b, a]);

      app.deleteWithUndo(a);
      clock.advance(const Duration(seconds: 5));
      await app.settleDeletes();
      expect(app.jobs, [b]);
      expect((await Store(dir).loadJobs()).single.id, b.id);
    });

    test('desfazer devolve à posição original mesmo fora da ordem por data', () async {
      // A job dated in the future sits below newer jobs: the list is not in
      // date order, so only the original position is right.
      final later = Job(id: 'futuro', createdAt: DateTime(2099), input: '@x', settings: const JobSettings())
        ..state = JobState.done;
      await store.saveJob(later);
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      await until(() => !app.isRunning(a));
      expect(app.jobs.map((j) => j.id), [a.id, 'futuro']);

      app.undoDelete(app.deleteWithUndo(a)!);
      expect(app.jobs.map((j) => j.id), [a.id, 'futuro']);
    });

    test('desfazer em ordem inversa à do apagar devolve cada uma ao seu lugar', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://youtu.be/jNQXAC9IVRw');
      final c = app.createJob('https://youtu.be/9bZkp7q19f0');
      await until(() => app.jobs.every((j) => !app.isRunning(j)));
      final pb = app.deleteWithUndo(b)!;
      final pa = app.deleteWithUndo(a)!;
      final pc = app.deleteWithUndo(c)!;
      expect(app.jobs, isEmpty);
      app.undoDelete(pa);
      app.undoDelete(pc);
      app.undoDelete(pb);
      expect(app.jobs, [c, b, a]);
    });

    test('apagar a mesma busca duas vezes não cria dois avisos nem apaga a busca restaurada', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      await until(() => !app.isRunning(a));
      final p = app.deleteWithUndo(a)!;
      expect(app.deleteWithUndo(a), isNull);
      expect(app.pendingDeletes, [p]);

      app.undoDelete(p);
      clock.advance(const Duration(seconds: 30));
      await app.settleDeletes();
      expect(app.jobs, [a]);
      expect(await onDisk(), {a.id});
    });

    test('o tempo só corre enquanto o aviso está na tela', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      await until(() => !app.isRunning(a));
      app.noticesVisible(false); // a tela inicial não está à vista (outra tela por cima)
      final p = app.deleteWithUndo(a)!;
      clock.advance(const Duration(seconds: 10));
      expect(app.currentDelete, p);
      expect(p.remaining, const Duration(seconds: 5));

      app.noticesVisible(true);
      clock.advance(const Duration(seconds: 2));
      app.noticesVisible(false); // o app foi para segundo plano
      clock.advance(const Duration(seconds: 10));
      expect(p.remaining, const Duration(seconds: 3));

      app.noticesVisible(true);
      clock.advance(const Duration(seconds: 3));
      expect(app.currentDelete, isNull);
      await app.settleDeletes();
      expect(await onDisk(), isEmpty);
    });

    test('o contador usa um relógio monotônico, não o relógio de parede', () async {
      var mono = Duration.zero; // o relógio de parede pode pular; este só anda
      final app = await AppState.start(store, src, prefs,
          gap: Duration.zero, elapsed: () => mono, timer: clock.timer);
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      await until(() => !app.isRunning(a));
      final p = app.deleteWithUndo(a)!;
      mono += const Duration(seconds: 2);
      expect(p.remaining, const Duration(seconds: 3));
    });

    test('Gemini: desfazer não retoma busca concluída nem pausada pelo usuário', () async {
      final slow = SlowSource()..channelSize = 30;
      final app = await openWithClock(source: slow);
      final done = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final paused = app.createJob('@mkbhd');
      await until(() => !app.isRunning(done) && paused.okCount >= 2);
      app.pause(paused); // o usuário pausou e apagou logo em seguida
      final pd = app.deleteWithUndo(paused)!;
      await until(() => !app.isRunning(paused));
      final before = slow.started.length;

      app.undoDelete(app.deleteWithUndo(done)!);
      app.undoDelete(pd);
      await pumpEventQueue(times: 100);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(app.isRunning(done), isFalse);
      expect(app.isRunning(paused), isFalse);
      expect(slow.started.length, before, reason: 'nenhum pedido novo');
      expect(paused.state, JobState.paused);
    });

    test('Gemini: apagar e desfazer duas vezes seguidas retoma a busca uma vez só', () async {
      final slow = SlowSource()..channelSize = 30;
      final app = await openWithClock(source: slow);
      final j = app.createJob('@mkbhd');
      await until(() => j.okCount >= 2);
      app.undoDelete(app.deleteWithUndo(j)!);
      app.undoDelete(app.deleteWithUndo(j)!); // de novo, antes de a 1ª retomada começar
      await until(() => j.state == JobState.done && !app.isRunning(j));
      expect(j.okCount, 30);
      expect(slow.started.toSet().length, slow.started.length, reason: 'nada buscado duas vezes');
    });

    test('Gemini: fechar o app logo após Desfazer não perde o estado "em andamento"', () async {
      final slow = SlowSource()..channelSize = 30;
      final app = await openWithClock(source: slow);
      final j = app.createJob('@mkbhd');
      await until(() => j.okCount >= 2);
      final p = app.deleteWithUndo(j)!;
      await until(() => !app.isRunning(j)); // a busca parou e salvou "pausada"
      app.undoDelete(p);

      // O app é morto aqui: copia o disco e as preferências deste instante.
      final killed = Directory.systemTemp.createTempSync('subshaul_killed');
      addTearDown(() => killed.delete(recursive: true));
      _copyTree(dir, killed);
      final saved = {for (final k in prefs.getKeys()) k: prefs.get(k)!};
      SharedPreferences.setMockInitialValues(saved);
      final again = await AppState.start(Store(killed), FakeSource()..channelSize = 30,
          await SharedPreferences.getInstance(), gap: Duration.zero);
      final back = again.jobs.single;
      await until(() => back.state == JobState.done && !again.isRunning(back));
      expect(back.okCount, 30, reason: 'a busca continuou sozinha ao reabrir');
      // The first app also resumed it; let it finish before the folders go.
      await until(() => j.state == JobState.done && !app.isRunning(j));
    });

    test('Gemini: fim da janela não abre brecha sem rastreio entre o aviso e o apagar do disco', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://youtu.be/jNQXAC9IVRw');
      await until(() => app.jobs.every((j) => !app.isRunning(j)));
      app.deleteWithUndo(a);
      var reentered = false;
      void onChange() {
        // Quem ouve o fim da janela de A apaga B na mesma hora (salva a lista).
        if (!reentered && app.currentDelete == null && !app.jobs.contains(a)) {
          reentered = true;
          app.deleteWithUndo(b);
        }
      }

      app.addListener(onChange);
      clock.advance(const Duration(seconds: 5));
      app.removeListener(onChange);
      expect(reentered, isTrue);
      expect(prefs.getStringList('pendingDeletes'), containsAll([a.id, b.id]),
          reason: 'A segue marcada para apagar até sair do disco');
    });

    test('Gemini: retomar ou buscar de novo ignora busca apagada', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://youtu.be/jNQXAC9IVRw');
      await until(() => app.jobs.every((j) => !app.isRunning(j)));
      final fetched = src.fetched.length;
      app.deleteWithUndo(a); // oculta, dentro da janela
      app.deleteWithUndo(b);
      clock.advance(const Duration(seconds: 5)); // B sai de vez
      await app.settleDeletes();

      app.resume(a);
      app.refetch(a, a.items.single);
      app.resume(b);
      app.refetch(b, b.items.single);
      await pumpEventQueue(times: 100);
      expect(app.isRunning(a), isFalse);
      expect(app.isRunning(b), isFalse);
      expect(src.fetched.length, fetched);
      expect(a.items.single.status, ItemStatus.ok, reason: 'nada mudou na busca oculta');
      expect(await onDisk(), {a.id}, reason: 'B não volta ao disco');
    });

    // Ticket 07 replaces ticket 05's "não se repete": the job stays marked and
    // hidden, and every start tries again; the app always opens.
    test('falha ao apagar do disco na abertura: a busca segue oculta e o app tenta de novo a cada abertura', () async {
      for (final id in ['condenada', 'outra']) {
        await store.saveJob(Job(id: id, createdAt: DateTime(2026), input: '@x', settings: const JobSettings())
          ..state = JobState.done);
      }
      SharedPreferences.setMockInitialValues({
        'pendingDeletes': ['condenada'],
      });
      prefs = await SharedPreferences.getInstance();
      final broken = _BrokenStore(dir);

      final app = await AppState.start(broken, src, prefs, gap: Duration.zero);
      expect(app.jobs.map((j) => j.id), ['outra'], reason: 'o app abre e ela fica fora da lista');
      expect(broken.deletes, 1);
      expect(prefs.getStringList('pendingDeletes'), ['condenada'], reason: 'segue marcada para apagar');
      // Saving the pending list again in this session keeps the mark.
      app.undoDelete(app.deleteWithUndo(app.jobs.single)!);
      expect(prefs.getStringList('pendingDeletes'), ['condenada']);

      for (final n in [2, 3]) {
        final again = await AppState.start(broken, src, prefs, gap: Duration.zero);
        expect(again.jobs.map((j) => j.id), ['outra'], reason: 'não aparece na abertura $n');
        expect(broken.deletes, n, reason: 'tenta de novo na abertura $n');
      }

      broken.broken = false; // o disco volta a funcionar
      final fixed = await AppState.start(broken, src, prefs, gap: Duration.zero);
      expect(fixed.jobs.map((j) => j.id), ['outra']);
      expect(await onDisk(), {'outra'}, reason: 'saiu do disco');
      expect(prefs.getStringList('pendingDeletes'), isNull);
    });

    for (final stopped in [false, true]) {
      test('pausar durante a retomada pós-Desfazer impede a retomada (busca ${stopped ? 'já parada' : 'parando'})',
          () async {
        final slow = SlowSource()..channelSize = 30;
        final app = await openWithClock(source: slow);
        final j = app.createJob('@mkbhd');
        await until(() => j.okCount >= 2);
        final p = app.deleteWithUndo(j)!;
        if (stopped) await until(() => !app.isRunning(j));
        app.undoDelete(p); // a retomada espera a busca parar
        app.pause(j); // o usuário pausa nessa espera
        await until(() => !app.isRunning(j));
        await pumpEventQueue(times: 100);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final asked = slow.started.length;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(app.isRunning(j), isFalse, reason: 'a pausa do usuário vence');
        expect(slow.started.length, asked, reason: 'nenhum pedido novo');
        expect(j.state, JobState.paused);
        expect(prefs.getStringList('resumeAfterUndo'), isNull, reason: 'reabrir o app não retoma');
      });
    }

    for (final how in ['retomar', 'buscar de novo']) {
      test('$how limpa a pausa do usuário: apagar a busca retomada a pausa e Desfazer a retoma', () async {
        final slow = SlowSource()..channelSize = 30;
        final app = await openWithClock(source: slow);
        final j = app.createJob('@mkbhd');
        await until(() => j.okCount >= 2);
        app.pause(j);
        await until(() => !app.isRunning(j));
        if (how == 'retomar') {
          app.resume(j);
        } else {
          app.refetch(j, j.items.firstWhere((i) => i.status == ItemStatus.pending));
        }
        expect(app.isRunning(j), isTrue);

        final p = app.deleteWithUndo(j)!;
        expect(p.wasRunning, isTrue, reason: 'a busca retomada conta como rodando');
        await until(() => !app.isRunning(j));
        final asked = slow.started.length;
        await pumpEventQueue(times: 100);
        expect(slow.started.length, asked, reason: 'pausada durante a janela');

        app.undoDelete(p);
        await until(() => j.state == JobState.done && !app.isRunning(j));
        expect(j.okCount, 30);
      });
    }

    test('marca de retomar: um ciclo antigo não apaga a marca de um ciclo novo', () async {
      final slow = SlowSource()..channelSize = 30;
      final app = await openWithClock(source: slow);
      final j = app.createJob('@mkbhd');
      await until(() => j.okCount >= 2);
      final first = app.deleteWithUndo(j)!;
      await until(() => !app.isRunning(j));
      app.undoDelete(first);
      await until(() => app.isRunning(j)); // 1º ciclo: a busca voltou a rodar

      // A kill at any moment before the job is done must find the mark.
      var lost = false;
      void check() {
        final marked = prefs.getStringList('resumeAfterUndo') ?? const <String>[];
        if (j.state != JobState.done && !marked.contains(j.id)) lost = true;
      }

      app.addListener(check);
      app.undoDelete(app.deleteWithUndo(j)!); // 2º ciclo, com a 1ª retomada ainda terminando
      check();
      await until(() => j.state == JobState.done && !app.isRunning(j));
      app.removeListener(check);
      expect(lost, isFalse, reason: 'o fim do 1º ciclo não apagou a marca do 2º');
      expect(j.okCount, 30);
      expect(prefs.getStringList('resumeAfterUndo'), isNull, reason: 'sai quando a busca termina');
    });

    test('na abertura, a marca de retomar só sai depois que a retomada gravou "rodando"', () async {
      final cut = Job(id: 'desfeita', createdAt: DateTime(2026), input: '@mkbhd', settings: const JobSettings())
        ..state = JobState.paused
        ..items.addAll(List.generate(6, (i) => JobItem('c${i.toString().padLeft(10, '0')}')));
      for (final i in cut.items.take(2)) {
        i.status = ItemStatus.ok;
      }
      await store.saveJob(cut);
      SharedPreferences.setMockInitialValues({
        'resumeAfterUndo': ['desfeita'],
      });
      prefs = await SharedPreferences.getInstance();

      final app = await AppState.start(store, SlowSource()..channelSize = 6, prefs, gap: Duration.zero);
      expect(prefs.getStringList('resumeAfterUndo'), ['desfeita'], reason: 'o disco ainda diz "pausada"');
      final j = app.jobs.single;
      await until(() => j.state == JobState.done && !app.isRunning(j));
      expect(j.okCount, 6);
      expect(prefs.getStringList('resumeAfterUndo'), isNull);
    });

    test('apagar A e B; desfazer B devolve só B; A segue com Desfazer e só some no fim do seu tempo', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://youtu.be/jNQXAC9IVRw');
      final c = app.createJob('https://youtu.be/9bZkp7q19f0');
      await until(() => app.jobs.every((j) => !app.isRunning(j)));
      expect(app.jobs, [c, b, a]);

      final pa = app.deleteWithUndo(a)!;
      clock.advance(const Duration(seconds: 1));
      final pb = app.deleteWithUndo(b)!;
      expect(app.jobs, [c]);
      expect(app.currentDelete, pb, reason: 'o aviso mais novo aparece por cima');

      clock.advance(const Duration(seconds: 2));
      app.undoDelete(pb);
      expect(app.jobs, [c, b], reason: 'só B volta, na posição original');
      expect(app.currentDelete, pa, reason: 'o aviso de A reaparece');
      expect(app.currentDelete!.remaining, const Duration(seconds: 4), reason: 'com o tempo que faltava');

      clock.advance(const Duration(milliseconds: 3999));
      expect(app.currentDelete, pa);
      expect(await onDisk(), {a.id, b.id, c.id});

      clock.advance(const Duration(milliseconds: 1));
      expect(app.currentDelete, isNull);
      await app.settleDeletes();
      expect(await onDisk(), {b.id, c.id});
      expect(app.jobs, [c, b]);
    });

    test('desfazer A depois de B ter sido apagada de vez devolve A intacta', () async {
      final app = await openWithClock();
      // A and B share a video: deleting B must not take A's transcript along.
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
      await until(() => app.jobs.every((j) => !app.isRunning(j)));
      expect(b.items.single.videoId, a.items.single.videoId);

      final pa = app.deleteWithUndo(a)!;
      app.deleteWithUndo(b);
      clock.advance(const Duration(seconds: 5)); // B fecha sem desfazer
      await app.settleDeletes();
      expect(await onDisk(), {a.id});
      expect(app.currentDelete, pa);

      app.undoDelete(pa);
      expect(app.jobs, [a]);
      final saved = (await Store(dir).loadJobs()).single;
      expect(saved.id, a.id);
      expect(saved.items.single.status, ItemStatus.ok);
      expect(a.items.single.status, ItemStatus.ok);
      expect((await app.transcriptOf(a, a.items.single))?.videoId, 'dQw4w9WgXcQ');
      expect(await store.readCache('dQw4w9WgXcQ', a.settings.language), isNotNull);
      clock.advance(const Duration(seconds: 30));
      await app.settleDeletes();
      expect(await onDisk(), {a.id}, reason: 'nada mais é apagado');
    });

    test('busca rodando pausa ao apagar e retoma de onde parou ao desfazer', () async {
      final slow = SlowSource()..channelSize = 30;
      final app = await openWithClock(source: slow);
      final j = app.createJob('@mkbhd');
      await until(() => j.okCount >= 2);

      final p = app.deleteWithUndo(j)!;
      final startedAtDelete = slow.started.length;
      await until(() => !app.isRunning(j));
      // Stopped: only a new run could ask for more. Let every queued task run.
      await pumpEventQueue(times: 100);
      expect(slow.started.length, startedAtDelete, reason: 'nenhum pedido novo durante a janela');
      expect(j.state, isNot(JobState.done));

      app.undoDelete(p);
      await until(() => j.state == JobState.done && !app.isRunning(j));
      expect(j.okCount, 30);
      expect(slow.started.toSet().length, slow.started.length, reason: 'nada buscado duas vezes');
    });

    test('app reiniciado dentro da janela: a busca apagada não volta e sai do disco', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      final b = app.createJob('https://youtu.be/jNQXAC9IVRw');
      await until(() => app.jobs.every((j) => !app.isRunning(j)));
      app.deleteWithUndo(a);
      expect(await onDisk(), {a.id, b.id});

      // O app é morto aqui: o timer nunca dispara.
      final again = await openWithClock();
      expect(again.jobs.map((j) => j.id), [b.id]);
      expect(await onDisk(), {b.id});
      expect(again.currentDelete, isNull);
    });

    test('nada sai do disco antes de o aviso daquela busca fechar sem desfazer', () async {
      final app = await openWithClock();
      final a = app.createJob('https://youtu.be/dQw4w9WgXcQ');
      await until(() => !app.isRunning(a));
      app.deleteWithUndo(a);
      clock.advance(const Duration(milliseconds: 4999));
      await app.settleDeletes(); // would finish a delete started too early
      expect(await onDisk(), {a.id});
      clock.advance(const Duration(milliseconds: 1));
      await app.settleDeletes();
      expect(await onDisk(), isEmpty);
    });
  });

  test('tema escolhido fica salvo', () async {
    final app = await open();
    expect(app.themeMode, ThemeMode.system);
    await app.setThemeMode(ThemeMode.dark);
    final again = await AppState.start(store, src, await SharedPreferences.getInstance(), gap: Duration.zero);
    expect(again.themeMode, ThemeMode.dark);
  });

  test('CT-12: depois de limpar o cache, o vídeo é buscado de novo e abre', () async {
    final app = await open();
    final j = app.createJob('https://youtu.be/dQw4w9WgXcQ');
    // Done and fully stopped: the runner saves once more after "done".
    await until(() => j.state == JobState.done && !app.isRunning(j));
    final item = j.items.single;
    expect(await app.transcriptOf(j, item), isNotNull);

    await app.clearCache();
    expect(await app.transcriptOf(j, item), isNull);

    app.refetch(j, item); // o que a tela faz ao tocar no vídeo sem cache
    await until(() => !app.isRunning(j) && j.state == JobState.done);
    expect(src.fetched, ['dQw4w9WgXcQ', 'dQw4w9WgXcQ']);
    expect(await app.transcriptOf(j, item), isNotNull);
  });

  test('nome da busca no histórico: título, ou primeiro link válido e quantos mais', () {
    Job j(String input) => Job(id: 'x', createdAt: DateTime.now(), input: input, settings: const JobSettings());
    expect(j('https://google.com https://youtu.be/dQw4w9WgXcQ https://www.youtube.com/@mkbhd').label,
        'youtu.be/dQw4w9WgXcQ e mais 1');
    expect(j('@mkbhd').label, '@mkbhd');
    final one = j('https://youtu.be/dQw4w9WgXcQ')..items.add(JobItem('dQw4w9WgXcQ')..title = 'Never Gonna');
    expect(one.label, 'Never Gonna');
  });

  test('CT-10: ao abrir, o app retoma sozinho o job cortado no meio', () async {
    src.channelSize = 6;
    final cut = Job(id: 'cortado', createdAt: DateTime.now(), input: '@mkbhd', settings: const JobSettings())
      ..state = JobState.running
      ..items.addAll(List.generate(6, (i) => JobItem('c${i.toString().padLeft(10, '0')}')));
    for (final i in cut.items.take(2)) {
      i.status = ItemStatus.ok;
    }
    await store.saveJob(cut);

    final app = await open(); // "abrir o app de novo"
    final j = app.jobs.single;
    // Done and fully stopped: the runner saves once more after "done".
    await until(() => j.state == JobState.done && !app.isRunning(j));
    expect(j.okCount, 6);
    expect(src.fetched.length, 4, reason: 'só os que faltavam');
  });
}

/// Copies a folder as it is at this instant (a killed app leaves it so).
void _copyTree(Directory from, Directory to) {
  for (final e in from.listSync(recursive: true)) {
    final rel = e.path.substring(from.path.length);
    if (e is Directory) {
      Directory('${to.path}$rel').createSync(recursive: true);
    } else if (e is File) {
      File('${to.path}$rel')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(e.readAsBytesSync());
    }
  }
}

/// Clock and timers the test moves by hand, so the 5 s undo window takes no
/// real time and never fires early or late.
class FakeClock {
  static final _start = DateTime(2026);
  DateTime _t = _start;
  final _timers = <_FakeTimer>[];

  /// Monotonic time since the clock was made.
  Duration elapsed() => _t.difference(_start);

  Timer timer(Duration d, void Function() cb) {
    final t = _FakeTimer(_t.add(d), cb);
    _timers.add(t);
    return t;
  }

  void advance(Duration d) {
    _t = _t.add(d);
    // A firing timer can start another one; fire in due order until none left.
    while (true) {
      final due = _timers.where((t) => t.isActive && !t.due.isAfter(_t)).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) return;
      due.first.fire();
    }
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this._cb);
  final DateTime due;
  final void Function() _cb;
  bool _active = true;

  void fire() {
    _active = false;
    _cb();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

/// Store whose deletes fail while [broken], e.g. a file locked by another
/// process.
class _BrokenStore extends Store {
  _BrokenStore(super.root);
  int deletes = 0;
  bool broken = true;

  @override
  Future<void> deleteJob(String id) async {
    deletes++;
    if (broken) throw const FileSystemException('locked');
    return super.deleteJob(id);
  }
}

/// Each request takes a few milliseconds, so a test can act mid-job.
class SlowSource extends FakeSource {
  final started = <String>[];

  @override
  Future<FetchOutcome> fetchTranscript(String videoId, String preferredLanguage) async {
    started.add(videoId);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    return super.fetchTranscript(videoId, preferredLanguage);
  }
}
