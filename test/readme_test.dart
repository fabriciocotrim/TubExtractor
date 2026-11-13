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

/// 8 screenshots (4 screens × light/dark) + the demo animation.
const _minMediaItems = 9;

String _read(String page) => File(page).readAsStringSync();

/// Heading levels in order (e.g. [2, 2, 3, 3, 2]); titles differ by language,
/// the structure must not.
List<int> _outline(String md) => md
    .split('\n')
    .where((l) => RegExp(r'^#{2,3} ').hasMatch(l))
    .map((l) => l.indexOf(' '))
    .toList();

void main() {
  for (final page in _pages) {
    test('$page exists', () {
      expect(File(page).existsSync(), isTrue, reason: '$page is missing');
    });

    test('every local link and image in $page points to an existing file', () {
      final md = _read(page);
      final targets = _localTargets(md);
      expect(targets, isNotEmpty);
      final missing = targets.where((t) => !File(t).existsSync() && !Directory(t).existsSync());
      expect(missing, isEmpty, reason: 'broken targets in $page');
    });

    test('$page shows the app screens and the demo', () {
      final targets = _localTargets(_read(page));
      expect(targets.where((t) => t.startsWith('docs/media/')).length, greaterThanOrEqualTo(_minMediaItems));
      expect(targets, contains('docs/media/demo.gif'));
    });
  }

  test('English and Portuguese pages link to each other', () {
    expect(_localTargets(_read('README.md')), contains('README.pt-BR.md'));
    expect(_localTargets(_read('README.pt-BR.md')), contains('README.md'));
  });

  test('both pages have the same section structure', () {
    final en = _outline(_read('README.md'));
    final pt = _outline(_read('README.pt-BR.md'));
    expect(en, isNotEmpty);
    expect(pt, en, reason: 'heading levels differ between EN and PT');
  });

  test('both pages carry the contact, license and non-affiliation notice', () {
    for (final page in _pages) {
      final md = _read(page);
      expect(md, contains('linkedin.com/in/fabr%C3%ADcio-cotrim-b565a073'), reason: page);
      expect(md, contains('Apache-2.0'), reason: page);
      expect(md, contains('YouTube'), reason: page);
      expect(md.toLowerCase(), anyOf(contains('not affiliated'), contains('não é afiliado')), reason: page);
      expect(md, isNot(contains('gmail.com')), reason: page);
    }
  });

  // D-26: the rest of the public repository speaks both languages too.
  test('security policy tells, in English and Portuguese, how to report privately', () {
    final md = _read('SECURITY.md');
    expect(md, contains('## Reporting a vulnerability'));
    expect(md, contains('## Como relatar uma vulnerabilidade'));
    expect('Report a vulnerability'.allMatches(md).length, greaterThanOrEqualTo(2));
    expect(md, isNot(contains('gmail.com')));
  });

  test('bug report form asks every question in English and Portuguese', () {
    final form = _read('.github/ISSUE_TEMPLATE/bug.yml');
    final labels = RegExp(r'^\s+label: (.+)$', multiLine: true).allMatches(form).map((m) => m.group(1)!).toList();
    expect(labels, hasLength(5));
    for (final label in labels) {
      expect(label, contains(' · '), reason: 'label "$label" is not bilingual');
    }
    expect(form, contains('SECURITY.md'));
  });
}
