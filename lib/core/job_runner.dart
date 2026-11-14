/// Runs jobs: expands links into videos, then fetches transcripts in a
/// polite queue. State is saved after every change, so work resumes after a
/// restart.
library;

import 'dart:async';
import 'dart:io';

import 'job.dart';
import 'models.dart';
import 'url_parser.dart';
import 'youtube_client.dart';

/// Abstraction over [YoutubeClient] so tests can run without network.
abstract class TranscriptSource {
  Future<String> resolveChannel(String url);
  Future<List<String>> channelVideos(String channelId, {int limit});
  Future<List<String>> playlistVideos(String playlistId, {int limit});
  Future<FetchOutcome> fetchTranscript(String videoId, String preferredLanguage);
}

class YoutubeSource implements TranscriptSource {
  YoutubeSource(this.client);
  final YoutubeClient client;
  @override
  Future<String> resolveChannel(String url) => client.resolveChannel(url);
  @override
  Future<List<String>> channelVideos(String channelId, {int limit = maxVideosPerJob}) =>
      client.channelVideos(channelId, limit: limit);
  @override
  Future<List<String>> playlistVideos(String playlistId, {int limit = maxVideosPerJob}) =>
      client.playlistVideos(playlistId, limit: limit);
  @override
  Future<FetchOutcome> fetchTranscript(String videoId, String preferredLanguage) =>
      client.fetchTranscript(videoId, preferredLanguage);
}

class JobRunner {
  JobRunner({
    required this.store,
    required this.source,
    this.concurrency = 2,
    this.gap = const Duration(milliseconds: 400),
    this.rateLimitPauseAfter = 3,
    this.onChanged,
  });

  final Store store;
  final TranscriptSource source;
  final int concurrency;

  /// Pause between two requests of the same worker.
  final Duration gap;

  /// Consecutive rate-limit failures before the job pauses itself.
  final int rateLimitPauseAfter;
  final void Function(Job job)? onChanged;

  final _running = <String, Future<void>>{};
  final _cancel = <String>{};

  bool isRunning(String jobId) => _running.containsKey(jobId);

  /// Starts or resumes [job]. Returns when the job stops (done or paused).
  Future<void> run(Job job) {
    final existing = _running[job.id];
    if (existing != null) return existing;
    _cancel.remove(job.id);
    // Block body: returning the removed Future here would make it await itself.
    final f = _run(job).whenComplete(() {
      _running.remove(job.id);
    });
    _running[job.id] = f;
    return f;
  }

  /// Asks a running job to stop after the current requests.
  void pause(String jobId) {
    if (_running.containsKey(jobId)) _cancel.add(jobId);
  }

  /// Pauses and waits until the job has fully stopped.
  Future<void> stop(String jobId) async {
    pause(jobId);
    await _running[jobId];
  }

  Future<void> _changed(Job job) async {
    try {
      await store.saveJob(job);
    } on FileSystemException {
      // A failed save (disk full, file busy) must not kill the job; the next
      // save writes the whole state again.
    }
    onChanged?.call(job);
  }

  Future<void> _run(Job job) async {
    job.pauseReason = null;
    if (job.state == JobState.expanding || job.items.isEmpty) {
      job.state = JobState.expanding;
      await _changed(job);
      final ok = await _expand(job);
      if (!ok) return;
    }
    job.state = JobState.running;
    await _changed(job);

    var consecutiveRateLimits = 0;
    final queue = job.items.where((i) => i.status == ItemStatus.pending).toList();
    var next = 0;

    Future<void> worker() async {
      while (true) {
        if (_cancel.contains(job.id) || job.pauseReason != null) return;
        if (next >= queue.length) return;
        final item = queue[next++];
        final hadNetwork = await _process(job, item);
        if (item.reason == FailureReason.rateLimited) {
          consecutiveRateLimits++;
          if (consecutiveRateLimits >= rateLimitPauseAfter) job.pauseReason = FailureReason.rateLimited;
        } else if (item.status == ItemStatus.ok && !item.fromCache) {
          // Only a real answer from YouTube shows the block is over.
          consecutiveRateLimits = 0;
        }
        if (!hadNetwork) job.pauseReason = FailureReason.network;
        await _changed(job);
        if (!item.fromCache) await Future<void>.delayed(gap);
      }
    }

    await Future.wait(List.generate(concurrency, (_) => worker()));

    _cancel.remove(job.id);
    if (job.pendingCount == 0) {
      job.state = JobState.done;
      job.pauseReason = null;
    } else {
      // Stopped by the user, by a pause reason, or items re-queued mid-run.
      job.state = JobState.paused;
    }
    await _changed(job);
  }

  /// Returns false when the network failed (item stays pending).
  Future<bool> _process(Job job, JobItem item) async {
    final lang = job.settings.language;
    final cached = await store.readCache(item.videoId, lang);
    if (cached != null && cached.cacheable) {
      _markOk(item, cached, fromCache: true);
      return true;
    }
    // Paused (or deleted) while reading the cache: the item stays pending and
    // no request leaves after the pause.
    if (_cancel.contains(job.id)) return true;
    try {
      final out = await source.fetchTranscript(item.videoId, lang);
      await store.writeCache(lang, out);
      _markOk(item, out, fromCache: false);
    } on TranscriptException catch (e) {
      if (e.reason == FailureReason.network) return false;
      item
        ..status = ItemStatus.failed
        ..reason = e.reason
        ..title ??= e.title;
    } catch (_) {
      item
        ..status = ItemStatus.failed
        ..reason = FailureReason.unknown;
    }
    return true;
  }

  void _markOk(JobItem item, FetchOutcome o, {required bool fromCache}) {
    item
      ..status = ItemStatus.ok
      ..reason = null
      ..title = o.transcript.title
      ..note = o.note
      ..fromCache = fromCache;
  }

  Future<bool> _expand(Job job) async {
    final parsed = parseInput(job.input);
    job.messages
      ..clear()
      ..addAll(parsed.invalid.map((s) => Notice(NoticeCode.linkIgnored, [s])));
    final limit = job.settings.limit.clamp(1, maxVideosPerJob);
    final ids = <String>[];
    final seen = <String>{};
    void add(Iterable<String> vs) {
      for (final v in vs) {
        if (ids.length >= limit) return;
        if (seen.add(v)) ids.add(v);
      }
    }

    for (final t in parsed.targets) {
      if (_cancel.contains(job.id)) {
        // Paused or deleted during expansion: expand again from scratch later.
        job.state = JobState.paused;
        await _changed(job);
        return false;
      }
      if (ids.length >= limit) {
        job.messages.add(Notice(NoticeCode.limitReached, ['$limit']));
        break;
      }
      try {
        switch (t.kind) {
          case TargetKind.video:
            add([t.value]);
          case TargetKind.playlist:
            // Full limit: duplicates across links are dropped by add().
            add(await source.playlistVideos(t.value, limit: limit));
          case TargetKind.channel:
            final id = t.needsResolution ? await source.resolveChannel(t.value) : t.value;
            add(await source.channelVideos(id, limit: limit));
        }
      } on TranscriptException catch (e) {
        if (e.reason == FailureReason.network) {
          job
            ..state = JobState.paused
            ..pauseReason = FailureReason.network;
          await _changed(job);
          return false;
        }
        final what = t.kind == TargetKind.playlist ? NoticeCode.playlistNotFound : NoticeCode.channelNotFound;
        job.messages.add(Notice(what, [t.source]));
      }
    }
    job.items
      ..clear()
      ..addAll(ids.map(JobItem.new));
    if (ids.isEmpty && job.messages.isEmpty) job.messages.add(const Notice(NoticeCode.noVideos));
    await _changed(job);
    return true;
  }

  /// Puts failed items with a temporary reason back in the queue.
  int requeueRetryable(Job job) {
    var n = 0;
    for (final i in job.items) {
      if (i.status == ItemStatus.failed &&
          const {FailureReason.rateLimited, FailureReason.network, FailureReason.unknown}.contains(i.reason)) {
        i
          ..status = ItemStatus.pending
          ..reason = null;
        n++;
      }
    }
    return n;
  }
}
