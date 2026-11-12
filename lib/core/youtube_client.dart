/// Talks to YouTube's internal web API (Innertube) directly from the phone.
///
/// YouTube changes this API from time to time. All knowledge about its shape
/// lives in this file, so a break is fixed in one place.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'languages.dart';
import 'models.dart';
import 'track_picker.dart';

typedef Sleep = Future<void> Function(Duration);

class _Client {
  const _Client(this.name, this.context, this.userAgent);
  final String name;
  final Map<String, dynamic> context;
  final String userAgent;
}

const _android = _Client(
  'ANDROID',
  {
    'clientName': 'ANDROID',
    'clientVersion': '20.10.38',
    'androidSdkVersion': 30,
    'hl': 'en',
    'gl': 'US',
  },
  'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
);

const _ios = _Client(
  'IOS',
  {
    'clientName': 'IOS',
    'clientVersion': '20.10.4',
    'deviceModel': 'iPhone16,2',
    'hl': 'en',
    'gl': 'US',
  },
  'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3 like Mac OS X)',
);

const _web = {'clientName': 'WEB', 'clientVersion': '2.20251101.00.00', 'hl': 'en', 'gl': 'US'};
const _webUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

/// Hard ceiling on videos per job (spec: up to 500).
const maxVideosPerJob = 500;

class FetchOutcome {
  const FetchOutcome(this.transcript, {this.note, this.cacheable = true});
  final Transcript transcript;

  /// False when the result is a fallback that should be retried next time.
  final bool cacheable;

  /// Extra information for the user and manifest, e.g. translation fallback.
  final String? note;
}

class YoutubeClient {
  YoutubeClient({http.Client? httpClient, Sleep? sleep, this.maxRetries = 3})
      : _http = httpClient ?? http.Client(),
        _sleep = sleep ?? Future<void>.delayed;

  final http.Client _http;
  final Sleep _sleep;
  final int maxRetries;

  void close() => _http.close();

  // ---------------------------------------------------------------- HTTP

  Future<http.Response> _send(
    Future<http.Response> Function() call, {
    int? retries,
  }) async {
    final max = retries ?? maxRetries;
    for (var attempt = 0;; attempt++) {
      http.Response r;
      try {
        r = await call().timeout(const Duration(seconds: 30));
      } on SocketException catch (e) {
        throw TranscriptException(FailureReason.network, e.message);
      } on http.ClientException catch (e) {
        throw TranscriptException(FailureReason.network, e.message);
      } on TimeoutException {
        if (attempt >= max) throw TranscriptException(FailureReason.network, 'timeout');
        await _sleep(Duration(seconds: 2 << attempt));
        continue;
      }
      final retryable = r.statusCode == 429 || r.statusCode >= 500;
      if (!retryable) return r;
      if (attempt >= max) {
        throw TranscriptException(
          r.statusCode == 429 ? FailureReason.rateLimited : FailureReason.unknown,
          'HTTP ${r.statusCode}',
        );
      }
      await _sleep(Duration(seconds: 2 << attempt));
    }
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> body, String ua) async {
    final r = await _send(() => _http.post(
          Uri.parse('https://www.youtube.com/youtubei/v1/$path?prettyPrint=false'),
          headers: {'content-type': 'application/json', 'user-agent': ua},
          body: jsonEncode(body),
        ));
    if (r.statusCode == 404 || r.statusCode == 400) {
      throw TranscriptException(FailureReason.unavailable, 'HTTP ${r.statusCode}');
    }
    if (r.statusCode != 200) throw TranscriptException(FailureReason.unknown, 'HTTP ${r.statusCode}');
    try {
      return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true)) as Map<String, dynamic>;
    } on FormatException {
      throw TranscriptException(FailureReason.unknown, 'resposta inválida');
    }
  }

  // ---------------------------------------------------------- Expansion

  /// Resolves a handle / custom URL to a UC… channel ID.
  Future<String> resolveChannel(String url) async {
    final j = await _postJson('navigation/resolve_url', {
      'context': {'client': _web},
      'url': url,
    }, _webUa);
    final id = (j['endpoint']?['browseEndpoint']?['browseId']) as String?;
    if (id == null || !id.startsWith('UC')) {
      throw TranscriptException(FailureReason.unavailable, 'canal não encontrado');
    }
    return id;
  }

  /// Video IDs of a channel's uploads, newest first.
  Future<List<String>> channelVideos(String channelId, {int limit = maxVideosPerJob}) =>
      playlistVideos('UU${channelId.substring(2)}', limit: limit);

  static final _watchEndpoint =
      RegExp(r'"watchEndpoint":\{"videoId":"([A-Za-z0-9_-]{11})","playlistId":"[^"]+","index":(\d+)');
  static final _continuation = RegExp(r'"continuationCommand":\{"token":"([^"]+)"');

  /// Video IDs of a playlist, in playlist order, up to [limit].
  Future<List<String>> playlistVideos(String playlistId, {int limit = maxVideosPerJob}) async {
    final cap = limit.clamp(1, maxVideosPerJob);
    final ids = <String>[];
    final seen = <String>{};
    Map<String, dynamic> body = {
      'context': {'client': _web},
      'browseId': 'VL$playlistId',
    };
    for (var page = 0; page < 50; page++) {
      final r = await _send(() => _http.post(
            Uri.parse('https://www.youtube.com/youtubei/v1/browse?prettyPrint=false'),
            headers: {'content-type': 'application/json', 'user-agent': _webUa},
            body: jsonEncode(body),
          ));
      if (r.statusCode != 200) {
        if (page == 0) throw TranscriptException(FailureReason.unavailable, 'playlist HTTP ${r.statusCode}');
        break;
      }
      final text = utf8.decode(r.bodyBytes, allowMalformed: true);
      final before = ids.length;
      for (final m in _watchEndpoint.allMatches(text)) {
        if (seen.add(m[1]!)) ids.add(m[1]!);
        if (ids.length >= cap) return ids;
      }
      final tokens = _continuation.allMatches(text).toList();
      if (ids.length == before || tokens.isEmpty) break;
      body = {
        'context': {'client': _web},
        'continuation': tokens.last[1],
      };
    }
    if (ids.isEmpty) throw TranscriptException(FailureReason.unavailable, 'playlist vazia ou privada');
    return ids;
  }

  // -------------------------------------------------------- Transcripts

  /// Downloads the transcript of [videoId] in [preferredLanguage], following
  /// the language rules in the spec.
  Future<FetchOutcome> fetchTranscript(String videoId, String preferredLanguage) async {
    TranscriptException? last;
    for (final client in const [_android, _ios]) {
      try {
        return await _fetchWith(client, videoId, preferredLanguage);
      } on TranscriptException catch (e) {
        // A definitive answer about the video does not change with the client.
        if (const {
          FailureReason.membersOnly,
          FailureReason.ageRestricted,
          FailureReason.network,
          FailureReason.rateLimited,
        }.contains(e.reason)) {
          rethrow;
        }
        last = e;
      }
    }
    throw last ?? TranscriptException(FailureReason.unknown);
  }

  Future<FetchOutcome> _fetchWith(_Client client, String videoId, String preferred) async {
    final j = await _postJson('player', {
      'context': {'client': client.context},
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    }, client.userAgent);

    final playability = j['playabilityStatus'] as Map<String, dynamic>? ?? const {};
    final status = playability['status'] as String? ?? 'UNKNOWN';
    if (status != 'OK') throw TranscriptException(classifyPlayability(playability), status);

    final details = j['videoDetails'] as Map<String, dynamic>? ?? const {};
    final title = (details['title'] as String?) ?? videoId;
    final channel = (details['author'] as String?) ?? '';

    final tracks = parseTracks(j);
    final choice = pickTrack(tracks, preferred);
    if (choice == null) throw TranscriptException(FailureReason.noCaptions, null, title);

    String? note;
    List<Segment>? segments;
    var used = choice.track;
    var translated = false;
    if (choice.translateTo != null) {
      try {
        segments = await _downloadSegments(client, choice.track.baseUrl, tlang: choice.translateTo);
        translated = segments.isNotEmpty;
      } on TranscriptException catch (e) {
        if (e.reason == FailureReason.network) rethrow;
      }
      if (!translated) {
        note = 'Tradução para ${languageName(choice.translateTo!)} indisponível. Veio a legenda original';
        used = tracks.firstWhere((t) => !t.isAutoGenerated, orElse: () => tracks.first);
        segments = null;
      }
    } else if (baseLang(used.languageCode) != baseLang(preferred)) {
      note = 'Sem legenda em ${languageName(preferred)}. Veio a de ${languageName(used.languageCode)}';
    }
    segments ??= await _downloadSegments(client, used.baseUrl);
    if (segments.isEmpty) throw TranscriptException(FailureReason.noCaptions, 'faixa vazia (${client.name})', title);

    return FetchOutcome(
      Transcript(
        videoId: videoId,
        title: title,
        channel: channel,
        languageCode: translated ? choice.translateTo! : used.languageCode,
        languageName: translated ? languageName(choice.translateTo!) : used.name,
        isAutoGenerated: used.isAutoGenerated,
        isTranslated: translated,
        segments: segments,
      ),
      note: note,
      // A failed translation may work later; do not pin the fallback in the cache.
      cacheable: !(choice.translateTo != null && !translated),
    );
  }

  Future<List<Segment>> _downloadSegments(_Client client, String baseUrl, {String? tlang}) async {
    final uri = Uri.parse(baseUrl);
    final q = Map<String, String>.from(uri.queryParameters)..['fmt'] = 'json3';
    if (tlang != null) q['tlang'] = tlang;
    if (uri.scheme != 'https' || !(uri.host == 'youtube.com' || uri.host.endsWith('.youtube.com'))) throw TranscriptException(FailureReason.unknown, 'host inesperado');
    final r = await _send(
      () => _http.get(uri.replace(queryParameters: q), headers: {'user-agent': client.userAgent}),
      // A blocked translation should fail fast and fall back to the original.
      retries: tlang == null ? null : 0,
    );
    if (r.statusCode != 200) throw TranscriptException(FailureReason.unknown, 'timedtext HTTP ${r.statusCode}');
    if (r.bodyBytes.isEmpty) return const [];
    return parseJson3(utf8.decode(r.bodyBytes, allowMalformed: true));
  }
}

// ------------------------------------------------- Pure parsing helpers

FailureReason classifyPlayability(Map<String, dynamic> p) {
  final status = p['status'] as String? ?? '';
  final text = jsonEncode(p).toLowerCase();
  if (text.contains('members') || text.contains('join this channel')) return FailureReason.membersOnly;
  if (text.contains('not a bot') || text.contains('unusual traffic')) return FailureReason.rateLimited;
  // Specific phrases only: the bare word "age" also appears in "message".
  if (text.contains('confirm your age') ||
      text.contains('age-restricted') ||
      text.contains('age restricted') ||
      text.contains('inappropriate for some users')) {
    return FailureReason.ageRestricted;
  }
  if (status == 'LIVE_STREAM_OFFLINE') return FailureReason.noCaptions;
  return FailureReason.unavailable;
}

List<CaptionTrack> parseTracks(Map<String, dynamic> player) {
  final list = player['captions']?['playerCaptionsTracklistRenderer']?['captionTracks'] as List?;
  if (list == null) return const [];
  final out = <CaptionTrack>[];
  final seen = <String>{};
  for (final raw in list) {
    final t = raw as Map<String, dynamic>;
    final url = t['baseUrl'] as String?;
    final code = t['languageCode'] as String?;
    if (url == null || code == null) continue;
    final auto = t['kind'] == 'asr';
    if (!seen.add('$code|$auto|${t['vssId']}')) continue;
    final nameNode = t['name'];
    String name = code;
    if (nameNode is Map) {
      name = (nameNode['simpleText'] as String?) ??
          ((nameNode['runs'] as List?)?.map((r) => r['text']).join() ?? code);
    }
    out.add(CaptionTrack(
      baseUrl: url,
      languageCode: code,
      name: name,
      isAutoGenerated: auto,
      isTranslatable: t['isTranslatable'] == true,
    ));
  }
  return out;
}

List<Segment> parseJson3(String body) {
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(body) as Map<String, dynamic>;
  } on FormatException {
    throw TranscriptException(FailureReason.unknown, 'legenda inválida');
  }
  final out = <Segment>[];
  for (final raw in (j['events'] as List? ?? const [])) {
    final e = raw as Map<String, dynamic>;
    final segs = e['segs'] as List?;
    if (segs == null || e['aAppend'] == 1) continue;
    final text = cleanCaptionText(segs.map((s) => (s as Map)['utf8'] as String? ?? '').join())
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (text.isEmpty) continue;
    out.add(Segment(
      (e['tStartMs'] as num?)?.toInt() ?? 0,
      (e['dDurationMs'] as num?)?.toInt() ?? 0,
      text,
    ));
  }
  return out;
}

final _tag = RegExp(r'</?(b|i|u|s|font|span|c|ruby|rt)(\s[^>]*)?>', caseSensitive: false);
final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos|nbsp);');

/// Uploaded captions may carry formatting tags (`<b>`, `<i>`, `<font>`) and HTML
/// entities. Keep the words only.
String cleanCaptionText(String s) => s.replaceAll(_tag, '').replaceAllMapped(_entity, (m) {
      final e = m[1]!;
      if (e.startsWith('#x')) return String.fromCharCode(int.parse(e.substring(2), radix: 16));
      if (e.startsWith('#')) return String.fromCharCode(int.parse(e.substring(1)));
      return const {'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' '}[e]!;
    });
