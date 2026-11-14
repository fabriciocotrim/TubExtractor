/// App-wide state: jobs, settings and the runner. UI listens to this.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/job.dart';
import 'core/formatters.dart';
import 'core/job_runner.dart';
import 'core/languages.dart';
import 'core/models.dart';
import 'core/youtube_client.dart';
import 'core/zip_builder.dart';

/// One deleted job inside its "Desfazer" window. Only the newest one counts
/// down; older ones wait, frozen, until the notices above them close.
class PendingDelete {
  PendingDelete._(this.job, this.wasRunning, this._left, this._elapsed);
  final Job job;

  /// The job was fetching when deleted; undo resumes it.
  final bool wasRunning;
  Duration _left;

  /// Reading of the monotonic clock when the countdown started; null while
  /// frozen.
  Duration? _since;
  Timer? _timer;
  final Duration Function() _elapsed;

  /// Time left before this job is deleted for good.
  Duration get remaining {
    final since = _since;
    if (since == null) return _left;
    final r = _left - (_elapsed() - since);
    return r.isNegative ? Duration.zero : r;
  }
}

class AppState extends ChangeNotifier {
  AppState._(this.store, this.runner, this._prefs, this._all, this.settings, this._elapsed, this._timer, this.undoWindow)
      : themeMode = ThemeMode.values.asNameMap()[_prefs.getString('theme')] ?? ThemeMode.system;

  /// Ids of deleted jobs whose window is still open. Saved so a kill during
  /// the window still deletes them on the next start.
  static const _pendingKey = 'pendingDeletes';

  /// Ids of fetching jobs brought back by "Desfazer" whose run has not ended
  /// yet. On disk they look paused by the user (the delete paused them), so a
  /// kill right after the undo must not leave them stopped.
  static const _resumeKey = 'resumeAfterUndo';

  /// Monotonic clock for the countdown: a change of the phone's clock does
  /// not shorten or stretch the "Desfazer" window.
  final Duration Function() _elapsed;
  final Timer Function(Duration, void Function()) _timer;

  /// How long "Desfazer" stays available for each deleted job.
  final Duration undoWindow;

  final Store store;
  final JobRunner runner;
  final SharedPreferences _prefs;
  /// Every job in list order, including deleted ones still inside their
  /// "Desfazer" window. Undo just shows a job again, so it is back exactly
  /// where it was, whatever the order of the list.
  final List<Job> _all;
  final _hidden = <Job>{};

  /// The jobs on the list, in list order.
  List<Job> get jobs => List.unmodifiable(_all.where((j) => !_hidden.contains(j)));

  JobSettings settings;

  /// Light, dark, or follow the phone (until the user taps the theme button).
  ThemeMode themeMode;

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    notifyListeners();
    await _prefs.setString('theme', m.name);
  }

  static Future<AppState> create() async {
    final dir = await getApplicationSupportDirectory();
    final store = Store(dir);
    await store.init();
    final prefs = await SharedPreferences.getInstance();
    return start(store, YoutubeSource(YoutubeClient()), prefs);
  }

  /// Builds the state from its parts and resumes cut-off jobs. Tests pass a
  /// fake [source] and a temporary [store].
  @visibleForTesting
  static Future<AppState> start(Store store, TranscriptSource source, SharedPreferences prefs,
      {String? deviceLanguage,
      Duration gap = const Duration(milliseconds: 400),
      Duration Function()? elapsed,
      Timer Function(Duration, void Function()) timer = Timer.new,
      Duration undoWindow = const Duration(seconds: 5)}) async {
    if (elapsed == null) {
      final watch = Stopwatch()..start();
      elapsed = () => watch.elapsed;
    }
    final jobs = await store.loadJobs();
    final settings = JobSettings(
      language: await _captionLanguage(prefs, jobs, deviceLanguage ?? PlatformDispatcher.instance.locale.toLanguageTag()),
      format: OutputFormat.values.asNameMap()[prefs.getString('format')] ?? OutputFormat.txt,
      timestamps: TimestampMode.values.asNameMap()[prefs.getString('timestamps')] ?? TimestampMode.off,
      limit: prefs.getInt('limit') ?? maxVideosPerJob,
    );
    // The app closed while a delete could still be undone: finish it (D-06 A).
    final doomed = prefs.getStringList(_pendingKey) ?? const <String>[];
    // A failed delete never keeps the app from opening. The job stays marked
    // and hidden, and the next start tries again.
    final failed = <String>{};
    if (doomed.isNotEmpty) {
      for (final id in doomed) {
        try {
          await store.deleteJob(id);
        } catch (_) {
          failed.add(id);
        }
      }
      jobs.removeWhere((j) => doomed.contains(j.id));
      if (failed.isEmpty) {
        await prefs.remove(_pendingKey);
      } else {
        await prefs.setStringList(_pendingKey, failed.toList());
      }
    }
    final undone = (prefs.getStringList(_resumeKey) ?? const <String>[]).toSet();
    late AppState app;
    final runner = JobRunner(
      store: store,
      source: source,
      gap: gap,
      onChanged: (_) => app.notifyListeners(),
    );
    app = AppState._(store, runner, prefs, jobs, settings, elapsed, timer, undoWindow);
    app._purgeFailed.addAll(failed);
    app._resumeInterrupted(undone);
    return app;
  }

  /// Preference keys of version 1.4.1 and later: any of them means the app
  /// was used before.
  static const _usedKeys = ['language', 'format', 'timestamps', 'limit', 'theme', _pendingKey, _resumeKey];

  /// Caption language (D-29 A). A saved choice never changes. Someone who
  /// installs the app gets the phone's language when it is on the list, else
  /// English; someone who already used 1.4.1 without choosing keeps English,
  /// the default of that version. The answer is saved, so it stays put even
  /// if the phone's language changes later.
  static Future<String> _captionLanguage(SharedPreferences prefs, List<Job> jobs, String deviceTag) async {
    final saved = prefs.getString('language');
    if (saved != null) return saved;
    final usedBefore = jobs.isNotEmpty || _usedKeys.any(prefs.containsKey);
    final lang = usedBefore ? 'en' : defaultCaptionLanguage(deviceTag);
    await prefs.setString('language', lang);
    return lang;
  }

  /// Jobs cut off by the app closing continue on their own (spec story 8),
  /// as do fetching jobs whose "Desfazer" came just before the close. Their
  /// "resume after undo" mark stays until the run has saved its own state.
  void _resumeInterrupted(Set<String> undone) {
    for (final j in jobs) {
      if (j.state != JobState.done && undone.remove(j.id)) {
        final ticket = Object();
        _resumeMark[j.id] = ticket;
        unawaited(runner.run(j).then((_) => _dropResumeMark(j.id, ticket)));
      } else if (shouldResumeOnOpen(j)) {
        unawaited(runner.run(j));
      }
    }
    // Marks of jobs that are done or gone.
    for (final id in undone) {
      _saveResuming(remove: id);
    }
  }

  Future<void> updateSettings(JobSettings s) async {
    settings = s;
    notifyListeners();
    await _prefs.setString('language', s.language);
    await _prefs.setString('format', s.format.name);
    await _prefs.setString('timestamps', s.timestamps.name);
    await _prefs.setInt('limit', s.limit);
  }

  static var _seq = 0;

  Job createJob(String input) {
    final job = Job(
      // Counter suffix: two jobs in the same clock tick must not share a file.
      id: '${DateTime.now().microsecondsSinceEpoch}-${_seq++}',
      createdAt: DateTime.now(),
      input: input.trim(),
      settings: settings,
    );
    _all.insert(0, job);
    notifyListeners();
    unawaited(runner.run(job));
    return job;
  }

  /// False for a deleted job, hidden or gone: nothing may fetch for it.
  bool _listed(Job job) => _all.contains(job) && !_hidden.contains(job);

  void resume(Job job) {
    if (!_listed(job) || runner.isRunning(job.id)) return;
    _userPaused.remove(job.id);
    runner.requeueRetryable(job);
    job.pauseReason = null;
    unawaited(runner.run(job));
    notifyListeners();
  }

  /// Fetches one item again, e.g. after the cache was cleared.
  void refetch(Job job, JobItem item) {
    if (!_listed(job) || runner.isRunning(job.id)) return;
    item
      ..status = ItemStatus.pending
      ..reason = null
      ..note = null;
    resume(job);
  }

  /// The user's pause always wins, also over a resume after "Desfazer" that
  /// is still waiting for the old run to stop.
  void pause(Job job) {
    if (runner.isRunning(job.id) || _resumeTicket.containsKey(job.id)) _userPaused.add(job.id);
    _resumeTicket.remove(job.id);
    if (_resumeMark.remove(job.id) != null) _saveResuming(remove: job.id);
    runner.pause(job.id);
    notifyListeners();
  }

  bool isRunning(Job job) => runner.isRunning(job.id);

  /// Deletes a hidden job for good.
  Future<void> _purge(Job job) async {
    // Wait for the runner to stop, or its next save would bring the job back.
    await runner.stop(job.id);
    await store.deleteJob(job.id);
  }

  final _pending = <PendingDelete>[];
  final _purging = <String, Future<void>>{};
  final _purgeFailed = <String>{};

  /// Jobs brought back by "Desfazer" that will resume once their paused run
  /// has stopped. Each undo makes a new ticket; only the newest one resumes.
  final _resumeTicket = <String, Object>{};

  /// Owner of each job's "resume after undo" mark on disk: the newest undo,
  /// or the resume at start-up. Only the owner removes the mark, once its
  /// run has saved its own state.
  final _resumeMark = <String, Object>{};

  /// Jobs the user paused. A delete does not count them as fetching, so
  /// "Desfazer" leaves them paused.
  final _userPaused = <String>{};

  /// Deleted jobs that can still be undone, oldest first.
  List<PendingDelete> get pendingDeletes => List.unmodifiable(_pending);

  /// The notice on screen: the newest delete.
  PendingDelete? get currentDelete => _pending.isEmpty ? null : _pending.last;

  /// Whether the home screen, which draws the notice, is in front of the
  /// user. Null until a screen says so (tests, start-up): then the newest
  /// notice counts at once.
  bool? _visible;

  /// The home screen whose word on visibility counts: the last one to speak.
  Object? _screen;

  /// The home screen tells when its notice can be seen: it is the screen on
  /// top and the app is in the foreground. Time out of sight does not count.
  /// [screen] is who tells.
  void noticesVisible(bool visible, {Object? screen}) {
    _screen = screen;
    _visible = visible;
    _reschedule();
  }

  /// [screen] is gone. A newer home screen may already have taken over (a
  /// screen replaced in one frame): then its word stands.
  void noticesClosed(Object screen) {
    if (!identical(_screen, screen)) return;
    noticesVisible(false);
  }

  /// Saves [job]'s delete mark and waits until it is on disk. The screen
  /// calls this before the job leaves the list ([deleteWithUndo]), so a kill
  /// at that instant does not bring the job back.
  Future<void> markForDelete(Job job) async {
    if (!_listed(job) || !_marked.add(job.id)) return;
    await _savePending();
  }

  /// The swipe of [job] did not end in [deleteWithUndo] (e.g. the screen
  /// closed first): its mark goes, so a job the user still sees is never
  /// deleted at the next start.
  Future<void> unmarkForDelete(Job job) async {
    if (!_marked.remove(job.id)) return;
    await _savePending();
  }

  /// Jobs marked by [markForDelete] that have not entered [_pending] yet.
  final _marked = <String>{};

  /// Swipe-to-delete (D-04): the job leaves the list now and stays on disk
  /// until its own window closes without [undoDelete]. A fetching job pauses
  /// (D-05 A). The notice below it freezes its countdown. Null when [job] is
  /// not on the list (e.g. already deleted): a job has one notice at most.
  PendingDelete? deleteWithUndo(Job job) {
    if (!_listed(job)) return null;
    _marked.remove(job.id); // now tracked by its notice
    final running = !_userPaused.contains(job.id) &&
        (runner.isRunning(job.id) || _resumeTicket.containsKey(job.id));
    if (running) runner.pause(job.id);
    _hidden.add(job);
    final p = PendingDelete._(job, running, undoWindow, _elapsed);
    _pending.add(p);
    _reschedule();
    // Already on disk when the screen used [markForDelete].
    unawaited(_savePending());
    notifyListeners();
    return p;
  }

  /// "Desfazer": only [p]'s job comes back, at its place in the list.
  void undoDelete(PendingDelete p) {
    if (!_pending.remove(p)) return;
    _freeze(p);
    _hidden.remove(p.job);
    if (p.wasRunning && p.job.state != JobState.done) {
      final ticket = Object();
      _resumeTicket[p.job.id] = ticket;
      _resumeMark[p.job.id] = ticket;
      // Saved before the delete mark goes, so no kill can lose both.
      _saveResuming(add: p.job.id);
      unawaited(_resumeAfterUndo(p.job, ticket));
    }
    unawaited(_savePending());
    _reschedule();
    notifyListeners();
  }

  Future<void> _resumeAfterUndo(Job job, Object ticket) async {
    // The paused run may still be finishing its last request.
    await runner.stop(job.id);
    // A newer undo took over, or the user paused meanwhile.
    if (!identical(_resumeTicket[job.id], ticket)) return;
    _resumeTicket.remove(job.id);
    if (!_listed(job) || job.state == JobState.done || runner.isRunning(job.id)) {
      _dropResumeMark(job.id, ticket);
      return;
    }
    final run = runner.run(job);
    notifyListeners();
    await run;
    // The run saved its own state (done, or paused for a reason): that state
    // now says whether to resume on the next start.
    _dropResumeMark(job.id, ticket);
  }

  /// Removes [id]'s resume mark if [ticket] still owns it.
  void _dropResumeMark(String id, Object ticket) {
    if (!identical(_resumeMark[id], ticket)) return;
    _resumeMark.remove(id);
    _saveResuming(remove: id);
  }

  void _saveResuming({String? add, String? remove}) {
    final ids = {...?_prefs.getStringList(_resumeKey), ?add}..remove(remove);
    unawaited(ids.isEmpty ? _prefs.remove(_resumeKey) : _prefs.setStringList(_resumeKey, ids.toList()));
  }

  void _count(PendingDelete p) {
    p._since = _elapsed();
    p._timer = _timer(p._left, () => _expire(p));
  }

  void _freeze(PendingDelete p) {
    if (p._timer == null) return;
    p._timer!.cancel();
    p._timer = null;
    p._left = p.remaining;
    p._since = null;
  }

  /// Only the newest notice counts, and only while it can be seen.
  void _reschedule() {
    final top = currentDelete;
    for (final p in _pending) {
      final runs = identical(p, top) && (_visible ?? true);
      if (runs && p._timer == null) _count(p);
      if (!runs) _freeze(p);
    }
  }

  void _expire(PendingDelete p) {
    if (!_pending.remove(p)) return;
    p._timer = null;
    final id = p.job.id;
    // Tracked as purging before anyone hears of it: a save made by a
    // listener still marks the job for deletion.
    final gone = Completer<void>();
    _purging[id] = gone.future;
    _hidden.remove(p.job);
    _all.remove(p.job);
    _userPaused.remove(id);
    _resumeTicket.remove(id);
    if (_resumeMark.remove(id) != null) _saveResuming(remove: id);
    _reschedule();
    notifyListeners();
    unawaited(() async {
      try {
        await _purge(p.job);
      } catch (_) {
        // Left on disk: it stays marked, so the next start deletes it.
        _purgeFailed.add(id);
      }
      _purging.remove(id);
      try {
        await _savePending();
      } finally {
        gone.complete();
      }
    }());
  }

  /// Waits until every expired delete is gone from disk.
  @visibleForTesting
  Future<void> settleDeletes() async {
    while (_purging.isNotEmpty) {
      await Future.wait(_purging.values.toList());
    }
  }

  /// Saves the ids still to delete, including jobs being swiped away.
  Future<void> _savePending() async {
    final ids = {for (final p in _pending) p.job.id, ..._purging.keys, ..._purgeFailed, ..._marked}.toList();
    await (ids.isEmpty ? _prefs.remove(_pendingKey) : _prefs.setStringList(_pendingKey, ids));
  }

  Future<Transcript?> transcriptOf(Job job, JobItem item) async =>
      (await store.readCache(item.videoId, job.settings.language))?.transcript;

  Future<List<Transcript>> transcriptsOf(Job job) async {
    final out = <Transcript>[];
    for (final i in job.items.where((i) => i.status == ItemStatus.ok)) {
      final t = await transcriptOf(job, i);
      if (t != null) out.add(t);
    }
    return out;
  }

  /// [labels] and [noteText] write the files in the app's language;
  /// [notProcessed] is the note of a video still in the queue.
  Future<Uint8List> buildJobZip(Job job, OutputFormat format, TimestampMode ts,
      {required ExportLabels labels, required String Function(Notice) noteText, required String notProcessed}) async {
    final entries = <ExportEntry>[];
    for (final i in job.items) {
      final t = i.status == ItemStatus.ok ? await transcriptOf(job, i) : null;
      entries.add(ExportEntry(
        videoId: i.videoId,
        title: i.title,
        transcript: t,
        reason: i.status == ItemStatus.ok
            ? (t == null ? FailureReason.unknown : null)
            : (i.reason ?? (i.status == ItemStatus.pending ? null : FailureReason.unknown)),
        note: i.status == ItemStatus.pending ? notProcessed : (i.note == null ? null : noteText(i.note!)),
      ));
    }
    return compute(_zipIsolate, (entries, format, ts, labels));
  }

  Future<String> cacheSize() async {
    final b = await store.cacheSizeBytes();
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  Future<void> clearCache() => store.clearCache();

  Future<File> writeTemp(String name, List<int> bytes) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsBytes(bytes, flush: true);
    return f;
  }
}

Uint8List _zipIsolate((List<ExportEntry>, OutputFormat, TimestampMode, ExportLabels) a) =>
    buildZip(a.$1, a.$2, a.$3, a.$4).bytes;
