// ignore_for_file: avoid_print
// Live check against the real YouTube. Not part of `flutter test` (needs
// network and can be rate-limited). Run: dart run tool/live_check.dart
// Use it when YouTube changes something and the app stops fetching.
import 'dart:io';

import 'package:subshaul/core/formatters.dart';
import 'package:subshaul/core/job.dart';
import 'package:subshaul/core/job_runner.dart';
import 'package:subshaul/core/models.dart';
import 'package:subshaul/core/youtube_client.dart';
import 'package:subshaul/core/zip_builder.dart';

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('subshaul_live');
  final store = Store(dir);
  await store.init();
  final runner = JobRunner(store: store, source: YoutubeSource(YoutubeClient()));
  var failures = 0;

  Future<Job> run(String input, {String lang = 'en', int limit = 5}) async {
    final job = Job(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: DateTime.now(),
      input: input,
      settings: JobSettings(language: lang, limit: limit),
    );
    final sw = Stopwatch()..start();
    await runner.run(job);
    print('\n== $input [$lang] -> ${job.state.name}, ${job.okCount} ok / ${job.failedCount} falhas / '
        '${job.items.length} itens em ${sw.elapsedMilliseconds} ms');
    for (final m in job.messages) {
      print('   msg: $m');
    }
    for (final i in job.items) {
      print('   ${i.status.name.padRight(7)} ${i.videoId} ${i.title ?? ''} ${i.reason?.name ?? ''} ${i.note ?? ''}');
    }
    return job;
  }

  void check(bool ok, String what) {
    print(ok ? '   OK  $what' : '   FALHOU  $what');
    if (!ok) failures++;
  }

  var j = await run('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  check(j.okCount == 1, 'vídeo único');
  j = await run('https://www.youtube.com/watch?v=dQw4w9WgXcQ', lang: 'pt-BR');
  check(j.okCount == 1, 'vídeo em pt-BR');
  j = await run('https://www.youtube.com/watch?v=dQw4w9WgXcQ');
  check(j.items.single.fromCache, 'cache na segunda vez');
  j = await run('https://www.youtube.com/playlist?list=PLBCF2DAC6FFB574DE', limit: 4);
  check(j.items.length == 4, 'playlist com limite 4');
  j = await run('@mkbhd', limit: 3);
  check(j.items.length == 3 && j.okCount >= 1, 'canal por @handle');
  j = await run('https://www.youtube.com/shorts/LXb3EKWsInQ');
  check(j.items.length == 1, 'shorts reconhecido');
  j = await run('https://www.youtube.com/watch?v=aaaaaaaaaaa');
  check(j.failedCount == 1, 'vídeo inexistente vira falha com motivo');

  final entries = <ExportEntry>[];
  for (final i in j.items) {
    entries.add(ExportEntry(videoId: i.videoId, reason: i.reason));
  }
  final t = await store.readCache('dQw4w9WgXcQ', 'en');
  entries.add(ExportEntry(videoId: 'dQw4w9WgXcQ', transcript: t!.transcript));
  // This command-line check runs without Flutter, so it cannot read the
  // translation files; English words stand in for them.
  const labels = ExportLabels(
    channel: 'Channel',
    video: 'Video',
    language: 'Language',
    text: 'Text',
    withTimestamps: 'With timestamps',
    auto: 'auto',
    translated: 'translated',
    reasons: {},
  );
  final zip = buildZip(entries, OutputFormat.srt, TimestampMode.on, labels);
  check(zip.bytes.length > 500, 'ZIP gerado (${zip.bytes.length} bytes)');

  await dir.delete(recursive: true);
  print(failures == 0 ? '\nTUDO OK' : '\n$failures FALHA(S)');
  exit(failures == 0 ? 0 : 1);
}
