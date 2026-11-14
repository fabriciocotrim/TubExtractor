/// Builds the export ZIP: transcripts/ + manifest.csv + manifest.json.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'formatters.dart';
import 'models.dart';

/// One row of the manifest. [transcript] is null when the video failed.
/// [note] is already written in the app's language.
class ExportEntry {
  const ExportEntry({
    required this.videoId,
    this.title,
    this.transcript,
    this.reason,
    this.note,
  });
  final String videoId;
  final String? title;
  final Transcript? transcript;
  final FailureReason? reason;
  final String? note;
}

/// A file name safe on Android, Windows and macOS, with no path separators.
String safeFileName(String title, String videoId, String ext, {int copy = 1}) {
  var base = title
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  // Remove leading/trailing dots so names like ".." or "..." cannot appear.
  base = base.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  if (base.length > 80) base = base.substring(0, 80).trim();
  // The copy suffix goes after truncation, so it can never be cut off.
  final suffix = copy > 1 ? ' ($copy)' : '';
  final name = base.isEmpty ? '$videoId$suffix' : '$base [$videoId]$suffix';
  return '$name.$ext';
}

String _csvCell(String v) {
  // Neutralise spreadsheet formula injection, then quote.
  var s = v;
  if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
  return '"${s.replaceAll('"', '""')}"';
}

class ZipResult {
  const ZipResult(this.bytes, this.fileNames);
  final Uint8List bytes;
  final Map<String, String> fileNames; // videoId -> path in zip
}

ZipResult buildZip(List<ExportEntry> entries, OutputFormat format, TimestampMode ts, ExportLabels labels) {
  final archive = Archive();
  final used = <String>{};
  final files = <String, String>{};
  final rows = <Map<String, Object?>>[];

  for (final e in entries) {
    String? path;
    final t = e.transcript;
    if (t != null) {
      var name = safeFileName(t.title, t.videoId, format.extension);
      var n = 2;
      while (used.contains(name.toLowerCase())) {
        name = safeFileName(t.title, t.videoId, format.extension, copy: n);
        n++;
      }
      used.add(name.toLowerCase());
      path = 'transcripts/$name';
      final data = utf8.encode(render(t, format, ts, labels));
      archive.addFile(ArchiveFile(path, data.length, data));
      files[t.videoId] = path;
    }
    rows.add({
      'video_id': e.videoId,
      'title': t?.title ?? e.title ?? '',
      'channel': t?.channel ?? '',
      'url': 'https://www.youtube.com/watch?v=${e.videoId}',
      'status': t != null ? 'ok' : 'missing',
      'reason': t != null ? '' : (e.reason ?? FailureReason.unknown).code,
      'reason_text': t != null ? '' : labels.reasons[e.reason ?? FailureReason.unknown] ?? '',
      'track': t == null ? '' : labels.track(t),
      'file': path ?? '',
      'note': e.note ?? '',
    });
  }

  const cols = ['video_id', 'title', 'channel', 'url', 'status', 'reason', 'reason_text', 'track', 'file', 'note'];
  final csv = StringBuffer()..writeln(cols.join(','));
  for (final r in rows) {
    csv.writeln(cols.map((c) => _csvCell('${r[c]}')).join(','));
  }
  // BOM so Excel opens accents correctly.
  final csvBytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csv.toString())];
  archive.addFile(ArchiveFile('manifest.csv', csvBytes.length, csvBytes));

  final json = utf8.encode(const JsonEncoder.withIndent('  ').convert({
    'format': format.extension,
    'timestamps': format.supportsTimestampOption ? ts.name : 'embedded',
    'total': rows.length,
    'ok': rows.where((r) => r['status'] == 'ok').length,
    'videos': rows,
  }));
  archive.addFile(ArchiveFile('manifest.json', json.length, json));

  return ZipResult(Uint8List.fromList(ZipEncoder().encode(archive)), files);
}
