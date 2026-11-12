import 'package:flutter_test/flutter_test.dart';
import 'package:subshaul/core/url_parser.dart';

void main() {
  const id = 'dQw4w9WgXcQ';

  group('vídeos', () {
    for (final input in [
      'https://www.youtube.com/watch?v=$id',
      'https://youtube.com/watch?v=$id&t=42s',
      'https://m.youtube.com/watch?v=$id',
      'https://music.youtube.com/watch?v=$id',
      'https://youtu.be/$id?si=abc',
      'https://www.youtube.com/shorts/$id',
      'youtube.com/shorts/$id',
      'https://www.youtube.com/live/$id',
      'https://www.youtube.com/embed/$id',
      'https://www.youtube.com/watch?v=$id&list=PLBCF2DAC6FFB574DE',
      id,
    ]) {
      test(input, () {
        final t = parseOne(input)!;
        expect(t.kind, TargetKind.video);
        expect(t.value, id);
      });
    }
  });

  test('playlist', () {
    final t = parseOne('https://www.youtube.com/playlist?list=PLBCF2DAC6FFB574DE')!;
    expect(t.kind, TargetKind.playlist);
    expect(t.value, 'PLBCF2DAC6FFB574DE');
  });

  test('canal por ID não precisa resolver', () {
    final t = parseOne('https://www.youtube.com/channel/UCBJycsmduvYEL83R_U4JriQ/videos')!;
    expect(t.kind, TargetKind.channel);
    expect(t.needsResolution, isFalse);
  });

  for (final input in ['@mkbhd', 'https://www.youtube.com/@mkbhd/videos', 'youtube.com/c/mkbhd', 'https://www.youtube.com/user/marquesbrownlee']) {
    test('canal a resolver: $input', () {
      final t = parseOne(input)!;
      expect(t.kind, TargetKind.channel);
      expect(t.needsResolution, isTrue);
      expect(t.value, startsWith('https://www.youtube.com/'));
    });
  }

  group('Proteção: entrada maliciosa ou de outro host é rejeitada', () {
    for (final input in [
      'https://evil.com/watch?v=$id',
      'https://youtube.com.evil.com/watch?v=$id',
      'https://evil.com/youtu.be/$id',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'https://www.youtube.com/watch?v=../../etc',
      'https://www.youtube.com/watch?v=abc',
      'https://www.youtube.com/feed/trending',
      'https://www.youtube.com/@a/../../x',
      'ftp://youtube.com/watch?v=$id',
    ]) {
      test(input, () => expect(parseOne(input), isNull));
    }
  });

  test('várias linhas, duplicatas removidas, inválidos reportados', () {
    final r = parseInput('''
https://youtu.be/$id
https://www.youtube.com/watch?v=$id

https://evil.com/x
@mkbhd
''');
    expect(r.targets.length, 2);
    expect(r.invalid, ['https://evil.com/x']);
  });

  test('texto compartilhado pelo app do YouTube', () {
    final r = parseInput('Never Gonna Give You Up https://youtu.be/$id?si=xyz');
    expect(r.targets.single.value, id);
    expect(r.invalid, isEmpty);
  });

  group('Revisão Gemini', () {
    test('handle com % sobrando não derruba o app', () {
      expect(() => parseOne('https://www.youtube.com/@canal%25'), returnsNormally);
      expect(() => parseInput('https://www.youtube.com/@canal%25\nhttps://youtube.com/@x%'), returnsNormally);
    });

    test('handle com acento é aceito', () {
      final t = parseOne('https://www.youtube.com/@canalçã')!;
      expect(t.kind, TargetKind.channel);
      expect(Uri.parse(t.value).host, 'www.youtube.com');
    });
  });

  test('Juiz: palavra "youtuber" no texto compartilhado não gera aviso', () {
    final r = parseInput('Melhor youtuber do ano https://youtu.be/$id');
    expect(r.targets.single.value, id);
    expect(r.invalid, isEmpty);
  });
}