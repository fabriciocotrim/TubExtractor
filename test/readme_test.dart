import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// The repository page is what clients read. A broken image or link there is a
// visible defect, so both language versions are checked like code.

const _pages = ['README.md', 'README.pt-BR.md'];

/// Local targets of Markdown links/images and HTML src/href attributes.
List<String> _localTargets(String md) {
  final targets = <String>[
    ...RegExp(r'\]\(([^)\s]+)').allMatches(md).map((m) => m.group(1)!),
    ...RegExp(r'''(?:src|href)="([^"]+)"''').allMatches(md).map((m) => m.group(1)!),
  ];
  return targets
      .where((t) => !t.startsWith('http://') && !t.startsWith('https://'))
      .where((t) => !t.startsWith('#') && !t.startsWith('mailto:'))
      .map((t) => t.split('#').first)
      .where((t) => t.isNotEmpty)
      .toList();
}

List<String> _sections(String md) =>
    md.split('\n').where((l) => l.startsWith('## ')).toList();

void main() {
  for (final page in _pages) {
    test('$page exists', () {
      expect(File(page).existsSync(), isTrue, reason: '$page is missing');
    });

    test('every local link and image in $page points to an existing file', () {
      final md = File(page).readAsStringSync();
      final targets = _localTargets(md);
      expect(targets, isNotEmpty);
      final missing = targets.where((t) => !File(t).existsSync() && !Directory(t).existsSync());
      expect(missing, isEmpty, reason: 'broken targets in $page');
    });

    test('$page shows the app screens and the demo', () {
      final targets = _localTargets(File(page).readAsStringSync());
      expect(targets.where((t) => t.startsWith('docs/media/')).length, greaterThanOrEqualTo(9));
      expect(targets, contains('docs/media/demo.gif'));
    });
  }

  test('English and Portuguese pages link to each other', () {
    expect(_localTargets(File('README.md').readAsStringSync()), contains('README.pt-BR.md'));
    expect(_localTargets(File('README.pt-BR.md').readAsStringSync()), contains('README.md'));
  });

  test('both pages have the same number of sections', () {
    final en = _sections(File('README.md').readAsStringSync());
    final pt = _sections(File('README.pt-BR.md').readAsStringSync());
    expect(en, isNotEmpty);
    expect(pt.length, en.length, reason: 'EN: $en\nPT: $pt');
  });

  test('both pages carry the contact, license and non-affiliation notice', () {
    for (final page in _pages) {
      final md = File(page).readAsStringSync();
      expect(md, contains('linkedin.com/in/fabr%C3%ADcio-cotrim-b565a073'), reason: page);
      expect(md, contains('Apache-2.0'), reason: page);
      expect(md, contains('YouTube'), reason: page);
      expect(md.toLowerCase(), anyOf(contains('not affiliated'), contains('não é afiliado')), reason: page);
      expect(md, isNot(contains('gmail.com')), reason: page);
    }
  });
}
