/// Jobs and their on-disk storage. A job survives app restarts.
library;

import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'url_parser.dart';
import 'youtube_client.dart';

class JobSettings {
  const JobSettings({
    this.language = 'en',
    this.format = OutputFormat.txt,
    this.timestamps = TimestampMode.off,
    this.limit = maxVideosPerJob,
  });
  final String language;
  final OutputFormat format;
  final TimestampMode timestamps;
  final int limit;

  JobSettings copyWith({String? language, OutputFormat? format, TimestampMode? timestamps, int? limit}) =>
      JobSettings(
        language: language ?? this.language,
        format: format ?? this.format,
        timestamps: timestamps ?? this.timestamps,
        limit: limit ?? this.limit,
      );

  Map<String, dynamic> toJson() =>
      {'language': language, 'format': format.name, 'timestamps': timestamps.name, 'limit': limit};

  factory JobSettings.fromJson(Map<String, dynamic> j) => JobSettings(
        language: j['language'] as String? ?? 'en',
        format: OutputFormat.values.asNameMap()[j['format']] ?? OutputFormat.txt,
        timestamps: TimestampMode.values.asNameMap()[j['timestamps']] ?? TimestampMode.off,
        limit: ((j['limit'] as int?) ?? maxVideosPerJob).clamp(1, maxVideosPerJob),
      );
}

enum JobState { expanding, running, paused, done }

enum ItemStatus { pending, ok, failed }

class JobItem {
  JobItem(this.videoId, {this.title, this.status = ItemStatus.pending, this.reason, this.note, this.fromCache = false});
  final String videoId;
  String? title;
  ItemStatus status;
  FailureReason? reason;
  String? note;
  bool fromCache;

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'status': status.name,
        'reason': reason?.name,
        'note': note,
        'fromCache': fromCache,
      };

  factory JobItem.fromJson(Map<String, dynamic> j) => JobItem(
        j['videoId'] as String,
        title: j['title'] as String?,
        status: ItemStatus.values.asNameMap()[j['status']] ?? ItemStatus.pending,
        reason: FailureReason.values.asNameMap()[j['reason']],
        note: j['note'] as String?,
        fromCache: j['fromCache'] as bool? ?? false,
      );
}

class Job {
  Job({
    required this.id,
    required this.createdAt,
    required this.input,
    required this.settings,
    this.state = JobState.expanding,
    List<JobItem>? items,
    List<String>? messages,
    this.pauseReason,
  })  : items = items ?? [],
        messages = messages ?? [];

  final String id;
  final DateTime createdAt;
  final String input;
  final JobSettings settings;
  JobState state;
  final List<JobItem> items;

  /// Problems with the input itself (invalid link, private playlist…).
  final List<String> messages;
  FailureReason? pauseReason;

  int get okCount => items.where((i) => i.status == ItemStatus.ok).length;
  int get failedCount => items.where((i) => i.status == ItemStatus.failed).length;
  int get pendingCount => items.where((i) => i.status == ItemStatus.pending).length;
  bool get isActive => state == JobState.expanding || state == JobState.running;


  /// Short name for the history: the video title when there is one video,
  /// else the first valid link without "https://www." plus how many more.
  String get label {
    if (items.length == 1 && items.single.title != null) return items.single.title!;
    final links = parseInput(input).targets.map((t) => t.source).toList();
    if (links.isEmpty) return input.trim();
    final first = links.first.replaceFirst(RegExp(r'^https?://', caseSensitive: false), '').replaceFirst('www.', '');
    final more = links.length - 1;
    return more > 0 ? '$first e mais $more' : first;
  }

  Map<String, dynamic> toJson() => {
        'v': 1,
        'id': id,
        'createdAt': createdAt.toIso8601String(),
        'input': input,
        'settings': settings.toJson(),
        'state': state.name,
        'pauseReason': pauseReason?.name,
        'messages': messages,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        input: j['input'] as String,
        settings: JobSettings.fromJson(j['settings'] as Map<String, dynamic>),
        state: JobState.values.asNameMap()[j['state']] ?? JobState.paused,
        pauseReason: FailureReason.values.asNameMap()[j['pauseReason']],
        messages: (j['messages'] as List? ?? const []).cast<String>(),
        items: (j['items'] as List? ?? const []).map((e) => JobItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Jobs that continue on their own when the app opens: those cut off by the
/// app closing, and those paused only for lack of internet. Jobs paused by the
/// user or by a YouTube block wait for the user.
bool shouldResumeOnOpen(Job j) =>
    j.state == JobState.expanding ||
    j.state == JobState.running ||
    (j.state == JobState.paused && j.pauseReason == FailureReason.network);

/// Stores jobs and the transcript cache as JSON files under [root].
class Store {
  Store(this.root);
  final Directory root;

  Directory get _jobs => Directory('${root.path}/jobs');
  Directory get _cache => Directory('${root.path}/cache');

  static final _safeId = RegExp(r'^[A-Za-z0-9_-]+$');

  Future<void> init() async {
    await _jobs.create(recursive: true);
    await _cache.create(recursive: true);
  }

  final _saveChain = <String, Future<void>>{};

  /// Saves are serialised per job, so two workers never write the same file.
  Future<void> saveJob(Job job) {
    final data = jsonEncode(job.toJson());
    final prev = _saveChain[job.id] ?? Future<void>.value();
    final next = prev.then((_) async {
      final f = File('${_jobs.path}/${job.id}.json');
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path); // atomic replace: a crash never leaves half a file
    });
    _saveChain[job.id] = next.catchError((_) {});
    return next;
  }

  Future<List<Job>> loadJobs() async {
    if (!await _jobs.exists()) return [];
    final out = <Job>[];
    await for (final e in _jobs.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        out.add(Job.fromJson(jsonDecode(await e.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // A corrupt file must not hide the other jobs.
      }
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<void> deleteJob(String id) async {
    if (!_safeId.hasMatch(id)) return;
    final f = File('${_jobs.path}/$id.json');
    if (await f.exists()) await f.delete();
  }

  String _key(String videoId, String lang) => '${videoId}_${lang.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '')}';

  Future<FetchOutcome?> readCache(String videoId, String lang) async {
    if (!_safeId.hasMatch(videoId)) return null;
    final f = File('${_cache.path}/${_key(videoId, lang)}.json');
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return FetchOutcome(
        Transcript.fromJson(j['transcript'] as Map<String, dynamic>),
        note: j['note'] as String?,
        cacheable: j['cacheable'] as bool? ?? true,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> writeCache(String lang, FetchOutcome o) async {
    final f = File('${_cache.path}/${_key(o.transcript.videoId, lang)}.json');
    await f.writeAsString(jsonEncode({'transcript': o.transcript.toJson(), 'note': o.note, 'cacheable': o.cacheable}));
  }

  Future<int> cacheSizeBytes() async {
    var total = 0;
    if (!await _cache.exists()) return 0;
    await for (final e in _cache.list()) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  Future<void> clearCache() async {
    if (await _cache.exists()) await _cache.delete(recursive: true);
    await _cache.create(recursive: true);
  }
}
