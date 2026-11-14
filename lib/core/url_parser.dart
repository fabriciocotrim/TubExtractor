/// Turns pasted or shared text into YouTube targets.
///
/// Only YouTube hosts and well-formed IDs are accepted. Everything else is
/// reported as invalid, never fetched.
library;

enum TargetKind { video, playlist, channel }

class Target {
  const Target(this.kind, this.value, this.source);

  final TargetKind kind;

  /// video: 11-char ID. playlist: list ID. channel: a UC… channel ID, or a
  /// youtube.com URL (handle, /c/, /user/) that must be resolved.
  final String value;

  /// The original input line.
  final String source;

  bool get needsResolution => kind == TargetKind.channel && !value.startsWith('UC');

  @override
  bool operator ==(Object other) => other is Target && other.kind == kind && other.value == value;
  @override
  int get hashCode => Object.hash(kind, value);
  @override
  String toString() => 'Target($kind, $value)';
}

class ParseResult {
  const ParseResult(this.targets, this.invalid);
  final List<Target> targets;
  final List<String> invalid;

  /// How many targets of [kind] were understood. The screen turns the
  /// counts into "Recognized: 2 videos, 1 channel · 1 link ignored".
  int count(TargetKind kind) => targets.where((t) => t.kind == kind).length;
}

// A token that looks like a YouTube link, not just a word such as "youtuber".
final _linkLike = RegExp(r'(^|[/.])(youtu\.be|youtube\.com|youtube-nocookie\.com)(/|$)', caseSensitive: false);
final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _playlistId = RegExp(r'^[A-Za-z0-9_-]{10,64}$');
final _channelId = RegExp(r'^UC[A-Za-z0-9_-]{22}$');
final _handle = RegExp(r'^@[\p{L}\p{N}._\-·]{1,100}$', unicode: true);
final _slug = RegExp(r'^[A-Za-z0-9._\-%]{1,100}$');
const _hosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
  'youtu.be',
  'www.youtu.be',
  'youtube-nocookie.com',
  'www.youtube-nocookie.com',
};

ParseResult parseInput(String text) {
  final targets = <Target>[];
  final invalid = <String>[];
  // A line may hold several links (e.g. shared text "Title https://youtu.be/x").
  for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final tokens = line.split(RegExp(r'\s+'));
    final urlTokens = tokens.where((t) => _linkLike.hasMatch(t) || t.startsWith('@') || t.startsWith('http')).toList();
    final candidates = urlTokens.isNotEmpty ? urlTokens : (tokens.length == 1 ? tokens : <String>[]);
    if (candidates.isEmpty) {
      invalid.add(line);
      continue;
    }
    for (final c in candidates) {
      final t = parseOne(c);
      if (t == null) {
        invalid.add(c);
      } else if (!targets.contains(t)) {
        targets.add(t);
      }
    }
  }
  return ParseResult(targets, invalid);
}

Target? parseOne(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (_videoId.hasMatch(s)) return Target(TargetKind.video, s, input);
  if (_handle.hasMatch(s)) {
    return Target(TargetKind.channel, 'https://www.youtube.com/$s', input);
  }
  if (_channelId.hasMatch(s)) return Target(TargetKind.channel, s, input);
  if (!s.contains('://')) s = 'https://$s';

  final Uri uri;
  try {
    uri = Uri.parse(s);
  } on FormatException {
    return null;
  }
  if (uri.scheme != 'https' && uri.scheme != 'http') return null;
  final host = uri.host.toLowerCase();
  if (!_hosts.contains(host)) return null;
  final seg = uri.pathSegments.where((p) => p.isNotEmpty).toList();

  if (host.endsWith('youtu.be')) {
    if (seg.isNotEmpty && _videoId.hasMatch(seg[0])) return Target(TargetKind.video, seg[0], input);
    return null;
  }

  final v = uri.queryParameters['v'];
  if (seg.isNotEmpty && seg[0] == 'watch') {
    if (v != null && _videoId.hasMatch(v)) return Target(TargetKind.video, v, input);
    return null;
  }
  if (seg.isEmpty) return null;

  final first = seg[0];
  if (first == 'playlist') {
    final list = uri.queryParameters['list'];
    if (list != null && _playlistId.hasMatch(list)) return Target(TargetKind.playlist, list, input);
    return null;
  }
  if (const {'shorts', 'live', 'embed', 'v', 'e'}.contains(first)) {
    if (seg.length > 1 && _videoId.hasMatch(seg[1])) return Target(TargetKind.video, seg[1], input);
    return null;
  }
  if (first == 'channel') {
    if (seg.length > 1 && _channelId.hasMatch(seg[1])) return Target(TargetKind.channel, seg[1], input);
    return null;
  }
  if (first.startsWith('@')) {
    // pathSegments is already decoded; decoding again could throw on "%".
    if (!_handle.hasMatch(first)) return null;
    return Target(TargetKind.channel, Uri.https('www.youtube.com', '/$first').toString(), input);
  }
  if (first == 'c' || first == 'user') {
    if (seg.length > 1 && _slug.hasMatch(seg[1])) {
      return Target(TargetKind.channel, 'https://www.youtube.com/$first/${seg[1]}', input);
    }
    return null;
  }
  return null;
}
