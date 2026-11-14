import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subshaul/core/models.dart';
import 'package:subshaul/core/youtube_client.dart';

import 'l10n_helper.dart';

Map<String, dynamic> player({String status = 'OK', List<Map<String, dynamic>>? tracks, String? reason}) => {
      'playabilityStatus': {'status': status, 'reason': ?reason},
      'videoDetails': {'title': 'Título', 'author': 'Autor'},
      if (tracks != null)
        'captions': {
          'playerCaptionsTracklistRenderer': {'captionTracks': tracks}
        },
    };

Map<String, dynamic> track(String lang, {bool auto = false}) => {
      'baseUrl': 'https://www.youtube.com/api/timedtext?v=x&lang=$lang&fmt=srv3',
      'languageCode': lang,
      'name': {'simpleText': lang},
      'vssId': '.$lang',
      if (auto) 'kind': 'asr',
      'isTranslatable': true,
    };

const json3 = '{"events":[{"tStartMs":0,"dDurationMs":1000,"segs":[{"utf8":"oi"},{"utf8":" mundo"}]},'
    '{"tStartMs":900,"segs":[{"utf8":"\\n"}],"aAppend":1},{"tStartMs":1000,"dDurationMs":500,"segs":[{"utf8":"tchau"}]}]}';

YoutubeClient client(Future<http.Response> Function(http.Request) h) =>
    YoutubeClient(httpClient: MockClient(h), sleep: (_) async {});

void main() {
  test('baixa a legenda e junta segmentos', () async {
    final c = client((r) async {
      if (r.url.path.endsWith('/player')) return ok(jsonEncode(player(tracks: [track('en')])));
      expect(r.url.queryParameters['fmt'], 'json3');
      return ok(json3);
    });
    final o = await c.fetchTranscript('dQw4w9WgXcQ', 'en');
    expect(o.transcript.title, 'Título');
    expect(o.transcript.segments.map((s) => s.text), ['oi mundo', 'tchau']);
    expect(o.note, isNull);
  });

  test('Proteção: 429 tenta de novo e depois funciona', () async {
    var calls = 0;
    final c = client((r) async {
      if (r.url.path.endsWith('/player')) {
        calls++;
        if (calls < 3) return http.Response('', 429);
        return ok(jsonEncode(player(tracks: [track('en')])));
      }
      return ok(json3);
    });
    final o = await c.fetchTranscript('dQw4w9WgXcQ', 'en');
    expect(o.transcript.segments, isNotEmpty);
    expect(calls, 3);
  });

  test('Proteção: 429 esgotado vira "limitado pelo YouTube"', () async {
    final c = client((r) async => http.Response('', 429));
    expect(
      () => c.fetchTranscript('dQw4w9WgXcQ', 'en'),
      throwsA(isA<TranscriptException>().having((e) => e.reason, 'reason', FailureReason.rateLimited)),
    );
  });

  test('sem legendas', () async {
    final c = client((r) async => ok(jsonEncode(player())));
    expect(() => c.fetchTranscript('dQw4w9WgXcQ', 'en'),
        throwsA(isA<TranscriptException>().having((e) => e.reason, 'reason', FailureReason.noCaptions)));
  });

  test('exclusivo para membros', () async {
    final c = client((r) async => http.Response(
        jsonEncode(player(status: 'UNPLAYABLE', reason: 'Join this channel to get access to members-only content')), 200));
    expect(() => c.fetchTranscript('dQw4w9WgXcQ', 'en'),
        throwsA(isA<TranscriptException>().having((e) => e.reason, 'reason', FailureReason.membersOnly)));
  });

  test('privado/removido', () async {
    final c = client((r) async => ok(jsonEncode(player(status: 'ERROR', reason: 'Video unavailable'))));
    expect(() => c.fetchTranscript('dQw4w9WgXcQ', 'en'),
        throwsA(isA<TranscriptException>().having((e) => e.reason, 'reason', FailureReason.unavailable)));
  });

  test('tradução bloqueada usa a faixa original e registra nota', () async {
    final c = client((r) async {
      if (r.url.path.endsWith('/player')) return ok(jsonEncode(player(tracks: [track('en')])));
      if (r.url.queryParameters.containsKey('tlang')) return http.Response('', 429);
      return ok(json3);
    });
    final o = await c.fetchTranscript('dQw4w9WgXcQ', 'pt');
    expect(o.transcript.languageCode, 'en');
    expect(o.transcript.isTranslated, isFalse);
    expect(o.note, const Notice(NoticeCode.translationUnavailable, ['pt']));
    expect(pt.notice(o.note!), 'Tradução para Português indisponível. Veio a legenda original');
    expect(en.notice(o.note!), 'Translation to Portuguese unavailable. Using the original captions');
  });

  test('Proteção: playlist com mais de 500 vídeos para em 500', () async {
    var page = 0;
    final c = client((r) async {
      page++;
      final items = List.generate(
          100,
          (i) =>
              '"watchEndpoint":{"videoId":"${(page * 1000 + i).toString().padLeft(11, 'v')}","playlistId":"UUx","index":$i}');
      return http.Response('{${items.join(',')},"continuationCommand":{"token":"t$page"}}', 200);
    });
    final ids = await c.channelVideos('UCBJycsmduvYEL83R_U4JriQ', limit: 9999);
    expect(ids.length, 500);
    expect(page, 5);
  });

  test('resolve handle', () async {
    final c = client((r) async {
      expect(r.url.path, endsWith('navigation/resolve_url'));
      return http.Response('{"endpoint":{"browseEndpoint":{"browseId":"UCBJycsmduvYEL83R_U4JriQ"}}}', 200);
    });
    expect(await c.resolveChannel('https://www.youtube.com/@mkbhd'), 'UCBJycsmduvYEL83R_U4JriQ');
  });

  test('Proteção: URL de legenda fora do YouTube não é buscada', () async {
    final bad = track('en')..['baseUrl'] = 'https://evil.com/api/timedtext?x=1';
    var evilCalled = false;
    final c = client((r) async {
      if (r.url.host == 'evil.com') evilCalled = true;
      return ok(jsonEncode(player(tracks: [bad])));
    });
    await expectLater(c.fetchTranscript('dQw4w9WgXcQ', 'en'), throwsA(isA<TranscriptException>()));
    expect(evilCalled, isFalse);
  });

  test('Revisão Gemini: fallback para IOS usa o User-Agent do IOS na legenda', () async {
    String? captionUa;
    final c = client((r) async {
      if (r.url.path.endsWith('/player')) {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        final name = body['context']['client']['clientName'];
        if (name == 'ANDROID') return ok(jsonEncode(player()));
        return ok(jsonEncode(player(tracks: [track('en')])));
      }
      captionUa = r.headers['user-agent'];
      return ok(json3);
    });
    await c.fetchTranscript('dQw4w9WgXcQ', 'en');
    expect(captionUa, contains('ios'));
  });

  test('Revisão Gemini: tradução falha não é fixada no cache; tradução ok tem nome do idioma', () async {
    var block = true;
    final c = client((r) async {
      if (r.url.path.endsWith('/player')) return ok(jsonEncode(player(tracks: [track('en')])));
      if (r.url.queryParameters.containsKey('tlang') && block) return http.Response('', 429);
      return ok(json3);
    });
    final failed = await c.fetchTranscript('dQw4w9WgXcQ', 'pt');
    expect(failed.cacheable, isFalse);
    block = false;
    final good = await c.fetchTranscript('dQw4w9WgXcQ', 'pt');
    expect(good.cacheable, isTrue);
    expect(good.transcript.isTranslated, isTrue);
    // Data in the exported JSON: English, like the track names YouTube sends.
    expect(good.transcript.languageName, 'Portuguese');
  });

  test('Juiz: "message" não vira restrição por idade', () {
    expect(classifyPlayability({'status': 'ERROR', 'messages': ['This video is unavailable']}), FailureReason.unavailable);
    expect(classifyPlayability({'status': 'LOGIN_REQUIRED', 'reason': 'Sign in to confirm your age'}), FailureReason.ageRestricted);
  });

  test('Teste no aparelho: marcação e códigos HTML saem do texto', () {
    final segs = parseJson3('{"events":[{"tStartMs":0,"dDurationMs":1,"segs":[{"utf8":"<b>Tom &amp; Jerry</b> <i>it&#39;s</i> <font color=\\"#fff\\">ok</font> 2 &lt; 3"}]}]}');
    expect(segs.single.text, "Tom & Jerry it's ok 2 < 3");
  });
}

http.Response ok(String body) => http.Response.bytes(utf8.encode(body), 200);