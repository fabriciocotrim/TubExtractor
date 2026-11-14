/// Renders a transcript as TXT, SRT, VTT, Markdown or JSON.
library;

import 'dart:convert';

import 'models.dart';

/// Words written into exported files, in the app's language at export time
/// (D-30 A). Only TXT and Markdown headers and the manifest's text columns
/// use them; column names, JSON keys, SRT and VTT never change.
class ExportLabels {
  const ExportLabels({
    required this.channel,
    required this.video,
    required this.language,
    required this.text,
    required this.withTimestamps,
    required this.auto,
    required this.translated,
    required this.reasons,
  });

  /// Header words: "Channel", "Video", "Language".
  final String channel;
  final String video;
  final String language;

  /// Markdown section titles when both text and timestamps are exported.
  final String text;
  final String withTimestamps;

  /// Track label words: "en (auto) (translated)".
  final String auto;
  final String translated;

  /// The manifest's reason_text for each failure reason.
  final Map<FailureReason, String> reasons;

  String track(Transcript t) => trackLabel(t, auto: auto, translated: translated);
}

String formatClock(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

String _cueTime(int ms, String sep) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  final f = ms % 1000;
  String p(int v, int w) => v.toString().padLeft(w, '0');
  return '${p(h, 2)}:${p(m, 2)}:${p(s, 2)}$sep${p(f, 3)}';
}

/// Cue end times, clipped so cues never overlap (auto captions often do).
List<int> _cueEnds(List<Segment> segs) => [
      for (var i = 0; i < segs.length; i++)
        () {
          var end = segs[i].endMs;
          if (i + 1 < segs.length && segs[i + 1].startMs < end) end = segs[i + 1].startMs;
          if (end <= segs[i].startMs) end = segs[i].startMs + 1000;
          return end;
        }(),
    ];

/// Plain prose split into paragraphs about once a minute, at a segment end.
List<String> paragraphs(List<Segment> segs) {
  final out = <String>[];
  final buf = StringBuffer();
  var paraStart = segs.isEmpty ? 0 : segs.first.startMs;
  for (final s in segs) {
    if (buf.isNotEmpty && s.startMs - paraStart >= 60000) {
      out.add(buf.toString().trim());
      buf.clear();
      paraStart = s.startMs;
    }
    buf
      ..write(s.text)
      ..write(' ');
  }
  if (buf.isNotEmpty) out.add(buf.toString().trim());
  return out;
}

String render(Transcript t, OutputFormat f, TimestampMode ts, ExportLabels l) => switch (f) {
      OutputFormat.txt => toTxt(t, ts, l),
      OutputFormat.srt => toSrt(t),
      OutputFormat.vtt => toVtt(t),
      OutputFormat.md => toMarkdown(t, ts, l),
      OutputFormat.json => toJson(t),
    };

String toTxt(Transcript t, TimestampMode ts, ExportLabels l) {
  final b = StringBuffer()
    ..writeln(t.title)
    ..writeln(t.channel)
    ..writeln(t.url)
    ..writeln('${l.language}: ${l.track(t)}')
    ..writeln();
  if (ts == TimestampMode.off || ts == TimestampMode.both) {
    b.writeln(paragraphs(t.segments).join('\n\n'));
  }
  if (ts == TimestampMode.both) b.writeln('\n----------------------------------------\n');
  if (ts == TimestampMode.on || ts == TimestampMode.both) {
    for (final s in t.segments) {
      b.writeln('[${formatClock(s.startMs)}] ${s.text}');
    }
  }
  return b.toString();
}

String toSrt(Transcript t) {
  final ends = _cueEnds(t.segments);
  final b = StringBuffer();
  for (var i = 0; i < t.segments.length; i++) {
    final s = t.segments[i];
    b
      ..writeln(i + 1)
      ..writeln('${_cueTime(s.startMs, ',')} --> ${_cueTime(ends[i], ',')}')
      ..writeln(s.text)
      ..writeln();
  }
  return b.toString();
}

String toVtt(Transcript t) {
  final ends = _cueEnds(t.segments);
  final b = StringBuffer()..writeln('WEBVTT')..writeln();
  for (var i = 0; i < t.segments.length; i++) {
    final s = t.segments[i];
    b
      ..writeln('${_cueTime(s.startMs, '.')} --> ${_cueTime(ends[i], '.')}')
      // "-->" inside a cue would end it early.
      ..writeln(s.text.replaceAll('-->', '->'))
      ..writeln();
  }
  return b.toString();
}

String _mdEscape(String s) => s.replaceAllMapped(RegExp(r'([\\`*_\[\]#<>])'), (m) => '\\${m[1]}');

String toMarkdown(Transcript t, TimestampMode ts, ExportLabels l) {
  final b = StringBuffer()
    ..writeln('# ${_mdEscape(t.title)}')
    ..writeln()
    ..writeln('- ${l.channel}: ${_mdEscape(t.channel)}')
    ..writeln('- ${l.video}: <${t.url}>')
    ..writeln('- ${l.language}: ${l.track(t)}')
    ..writeln();
  if (ts == TimestampMode.off || ts == TimestampMode.both) {
    if (ts == TimestampMode.both) b.writeln('## ${l.text}\n');
    b.writeln(paragraphs(t.segments).map(_mdEscape).join('\n\n'));
    b.writeln();
  }
  if (ts == TimestampMode.on || ts == TimestampMode.both) {
    if (ts == TimestampMode.both) b.writeln('## ${l.withTimestamps}\n');
    for (final s in t.segments) {
      b.writeln('[${formatClock(s.startMs)}](${t.url}&t=${s.startMs ~/ 1000}s) ${_mdEscape(s.text)}  ');
    }
  }
  return b.toString();
}

String toJson(Transcript t) => const JsonEncoder.withIndent('  ').convert({
      'videoId': t.videoId,
      'title': t.title,
      'channel': t.channel,
      'url': t.url,
      'language': t.languageCode,
      'languageName': t.languageName,
      'isAutoGenerated': t.isAutoGenerated,
      'isTranslated': t.isTranslated,
      'text': t.plainText,
      'lines': [
        for (final s in t.segments)
          {
            'start': s.startMs / 1000,
            'duration': s.durationMs / 1000,
            'timestamp': formatClock(s.startMs),
            'text': s.text,
          }
      ],
    });
