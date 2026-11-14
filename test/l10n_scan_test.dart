// Ticket 05: no screen sentence lives outside the translation files.
//
// The scan reads every Dart file of the app and fails on a quoted text that
// looks like words for people: two words in a row, or a Portuguese letter.
// A short, explicit list covers what is not screen text.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that may hold words: the generated translations and the caption
/// language names (data with both names side by side).
bool _skipFile(String path) {
  final p = path.replaceAll('\\', '/');
  return RegExp(r'lib/l10n/app_localizations(_\w+)?\.dart$').hasMatch(p) || p.endsWith('lib/core/languages.dart');
}

/// Quoted texts that are not screen text, by file. Each one says why.
const _allowed = <String, Set<String>>{
  // 1.4.1 saved Portuguese sentences; these patterns read them back.
  'lib/core/models.dart': {
    r'^Link ignorado \(não é do YouTube ou está incompleto\): (.*)$',
    r'^Chegou ao máximo de (\d+) vídeos\. O resto ficou de fora\.$',
    r'^Playlist não encontrada ou privada: (.*)$',
    r'^Canal não encontrado ou privado: (.*)$',
    r'^Nenhum vídeo encontrado\.$',
    r'^Tradução para (.+) indisponível\. Veio a legenda original$',
    r'^Sem legenda em (.+)\. Veio a de (.+)$',
  },
  // YouTube's own English answers, matched to classify a failure.
  'lib/core/youtube_client.dart': {
    'join this channel',
    'not a bot',
    'unusual traffic',
    'confirm your age',
    'age restricted',
    'inappropriate for some users',
    // Client names sent to YouTube.
    'com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip',
    'com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3 like Mac OS X)',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36',
    // Details of a failure for debugging (TranscriptException.detail); the
    // screen shows only the reason code, translated.
    'invalid response',
    'channel not found',
    'playlist HTTP \${r.statusCode}',
    'empty or private playlist',
    'timedtext HTTP \${r.statusCode}',
    'empty track (\${client.name})',
    'unexpected host',
    'invalid captions',
  },
  // A font name.
  'lib/screens/transcript_screen.dart': {'JetBrains Mono'},
  // Accent folding for the language search, not text.
  'lib/widgets/options.dart': {'[áàâã]', '[éê]', 'í', '[óôõ]', 'ú', 'ç'},
};

/// Quoted texts of one Dart source, without comments and imports.
List<String> _literals(String src) {
  final out = <String>[];
  final code = src
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .where((l) => !l.startsWith('import ') && !l.startsWith('export '))
      .join('\n');
  // Raw or plain, single or double quotes; one line each.
  final re = RegExp(r"r?'((?:[^'\\\n]|\\.)*)'" '|' r'r?"((?:[^"\\\n]|\\.)*)"');
  for (final m in re.allMatches(code)) {
    out.add(m.group(1) ?? m.group(2)!);
  }
  return out;
}

/// Looks like words for people: a Portuguese letter, or two words in a row
/// once code inside ${…} and $name is taken out.
bool _looksLikeText(String s) {
  if (RegExp('[ãõçáéíóúâêôàÃÕÇÁÉÍÓÚÂÊÔ]').hasMatch(s)) return true;
  final plain = s.replaceAll(RegExp(r'\$\{[^}]*\}'), ' ').replaceAll(RegExp(r'\$\w+'), ' ');
  return RegExp(r'[A-Za-z]{2,},? +[A-Za-z]{2,}').hasMatch(plain);
}

/// A single word is not caught by [_looksLikeText] ("Pause"), so a quoted
/// text given straight to a widget that shows it counts too.
final _shown = RegExp(
    r"(?:\bText\(|\b(?:tooltip|hintText|labelText|helperText|semanticsLabel|label|message|title|help):)\s*'([^'\n]*[A-Za-z]{2,}[^'\n]*)'");

/// The brand: the same in every language.
const _brand = 'TubExtractor';

List<String> scan() {
  final found = <String>[];
  final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
  for (final f in files) {
    if (_skipFile(f.path)) continue;
    final key = f.path.replaceAll('\\', '/');
    final allowed = _allowed[key] ?? const {};
    final src = f.readAsStringSync();
    for (final lit in _literals(src)) {
      if (_looksLikeText(lit) && !allowed.contains(lit)) found.add('$key: "$lit"');
    }
    for (final m in _shown.allMatches(src)) {
      final lit = m.group(1)!;
      final words = lit.replaceAll(RegExp(r'\$\{[^}]*\}'), ' ').replaceAll(RegExp(r'\$\w+'), ' ');
      if (!RegExp('[A-Za-z]{2,}').hasMatch(words)) continue; // only code inside
      if (lit != _brand && !allowed.contains(lit)) found.add('$key: shown "$lit"');
    }
  }
  return found;
}

void main() {
  test('no screen sentence outside the translation files', () {
    expect(scan(), isEmpty, reason: 'move these to lib/l10n/app_en.arb and app_pt.arb');
  });

  test('the scan catches a sentence in English and one in Portuguese', () {
    expect(_looksLikeText('Link ignored'), isTrue);
    expect(_looksLikeText('Vídeo'), isTrue);
    expect(_looksLikeText('Stopped at \$done of \$total'), isTrue);
    expect(_shown.hasMatch("Text('Pause')"), isTrue);
    expect(_shown.hasMatch("tooltip: 'Undo',"), isTrue);
    expect(_shown.hasMatch("Text(l.pause)"), isFalse);
    expect(_looksLikeText('manifest.csv'), isFalse);
    expect(_looksLikeText('video_id'), isFalse);
    expect(_looksLikeText('\${t.languageCode} (\$auto)'), isFalse);
  });

  test('every allowed text still exists, so the list stays short', () {
    for (final e in _allowed.entries) {
      final lits = _literals(File(e.key).readAsStringSync()).toSet();
      for (final a in e.value) {
        expect(lits, contains(a), reason: '${e.key}: "$a" is no longer used; remove it from the list');
      }
    }
  });
}
