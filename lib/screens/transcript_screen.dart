import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../core/formatters.dart';
import '../core/job.dart';
import '../core/models.dart';
import '../core/zip_builder.dart';
import '../widgets/crystal.dart';
import '../widgets/motion.dart';

class TranscriptScreen extends StatefulWidget {
  const TranscriptScreen({
    super.key,
    required this.app,
    required this.transcript,
    required this.settings,
  });
  final AppState app;
  final Transcript transcript;
  final JobSettings settings;

  @override
  State<TranscriptScreen> createState() => _TranscriptScreenState();
}

class _TranscriptScreenState extends State<TranscriptScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  bool _showTime = true;
  bool _searching = false;
  List<int> _matches = const [];
  int _current = 0;

  Transcript get t => widget.transcript;

  // One key per line that was ever built, so search can find a line on
  // screen. Lines are built lazily: a 3-hour video has ~3,000.
  final _keys = <int, GlobalKey>{};

  /// Bumped on each jump, so an older jump in progress gives up.
  int _jumpId = 0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    final s = q.trim().toLowerCase();
    setState(() {
      _matches = s.isEmpty
          ? const []
          : [
              for (var i = 0; i < t.segments.length; i++)
                if (t.segments[i].text.toLowerCase().contains(s)) i,
            ];
      _current = 0;
    });
    _jump();
  }

  void _step(int d) {
    if (_matches.isEmpty) return;
    setState(() => _current = (_current + d) % _matches.length);
    _jump();
  }

  void _jump() {
    if (_matches.isEmpty) return;
    final index = _matches[_current];
    final id = ++_jumpId;
    // A line far away is not built yet: jump near its estimated place, let
    // the list build it, then glide it into view.
    void attempt(int triesLeft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || id != _jumpId) return;
        final ctx = _keys[index]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.3,
            duration: const Duration(milliseconds: 250),
          );
          return;
        }
        if (triesLeft == 0 || !_scroll.hasClients) return;
        final p = _scroll.position;
        final total = p.maxScrollExtent + p.viewportDimension;
        final guess = total * index / t.segments.length -
            p.viewportDimension * 0.3;
        final target = guess.clamp(p.minScrollExtent, p.maxScrollExtent);
        if (target == p.pixels) return;
        p.jumpTo(target);
        attempt(triesLeft - 1);
      });
    }

    attempt(10);
  }

  Future<void> _copy() async {
    final text = _showTime
        ? t.segments
              .map((s) => '[${formatClock(s.startMs)}] ${s.text}')
              .join('\n')
        : paragraphs(t.segments).join('\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Transcrição copiada.')));
    }
  }

  Future<void> _exportFile({required bool share}) async {
    final f = widget.settings.format;
    final content = render(t, f, widget.settings.timestamps);
    final name = safeFileName(t.title, t.videoId, f.extension);
    final bytes = utf8.encode(content);
    try {
      if (share) {
        final file = await widget.app.writeTemp(name, bytes);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(file.path, mimeType: 'text/plain')]),
        );
      } else {
        final uri = await FilePicker.saveFile(
          fileName: name,
          bytes: bytes,
          mimeType: 'text/plain',
        );
        if (uri != null && mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Arquivo salvo.')));
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              share
                  ? 'Não foi possível compartilhar o arquivo.'
                  : 'Não foi possível salvar o arquivo.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openAt(int ms) => launchUrl(
    Uri.parse('${t.url}&t=${ms ~/ 1000}s'),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final scheme = Theme.of(context).colorScheme;
    return CrystalPage(
      child: Scaffold(
        appBar: AppBar(
          // The title and the search field swap in place.
          title: SwapIn(
            scale: false,
            child: _searching
                ? TextField(
                    key: const ValueKey('search'),
                    controller: _search,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: 'Buscar na transcrição',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onChanged: _onSearch,
                    onSubmitted: (_) => _step(1),
                  )
                : Text(
                    t.title,
                    key: const ValueKey('title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          actions: _searching
              ? [
                  Center(
                    child: Text(
                      q.isEmpty
                          ? ''
                          : _matches.isEmpty
                          ? 'Nenhum'
                          : '${_current + 1} de ${_matches.length}',
                    ),
                  ),
                  IconButton(
                    tooltip: 'Anterior',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: () => _step(-1),
                  ),
                  IconButton(
                    tooltip: 'Próximo',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: () => _step(1),
                  ),
                  IconButton(
                    tooltip: 'Fechar busca',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _searching = false;
                      _search.clear();
                      _matches = const [];
                    }),
                  ),
                ]
              : [
                  IconButton(
                    tooltip: 'Buscar',
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => _searching = true),
                  ),
                  IconButton(
                    tooltip: 'Copiar tudo',
                    icon: const Icon(Icons.copy),
                    onPressed: _copy,
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Mais opções',
                    onSelected: (v) => switch (v) {
                      'time' => setState(() => _showTime = !_showTime),
                      'save' => _exportFile(share: false),
                      'share' => _exportFile(share: true),
                      'yt' => _openAt(0),
                      _ => null,
                    },
                    itemBuilder: (_) => [
                      CheckedPopupMenuItem(
                        value: 'time',
                        checked: _showTime,
                        child: const Text('Mostrar tempo'),
                      ),
                      PopupMenuItem(
                        value: 'save',
                        child: Text('Salvar ${widget.settings.format.label}'),
                      ),
                      PopupMenuItem(
                        value: 'share',
                        child: Text(
                          'Compartilhar ${widget.settings.format.label}',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'yt',
                        child: Text('Abrir no YouTube'),
                      ),
                    ],
                  ),
                ],
        ),
        body: Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            0,
            16,
            MediaQuery.paddingOf(context).bottom + 12,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.channel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Legenda: ${t.trackLabel} · ${t.segments.length} trechos',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // Hugs short transcripts, scrolls long ones.
              Flexible(
                child: LayoutBuilder(
                  builder: (context, box) => Glass(
                    padding: EdgeInsets.zero,
                    child: Material(
                      type: MaterialType.transparency,
                      // Builds only the lines on screen. A transcript that
                      // surely fills the space skips the costly hug.
                      child: ListView.builder(
                        controller: _scroll,
                        shrinkWrap:
                            t.segments.length * _minLineHeight < box.maxHeight,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: t.segments.length,
                        itemBuilder: (context, i) {
                          final s = t.segments[i];
                          final isMatch =
                              q.isNotEmpty && s.text.toLowerCase().contains(q);
                          final isCurrent =
                              _matches.isNotEmpty && _matches[_current] == i;
                          return InkWell(
                            key: _keys.putIfAbsent(i, () => GlobalKey()),
                            onTap: () => _openAt(s.startMs),
                            child: AnimatedContainer(
                              duration: Motion.of(context, Motion.quick),
                              color: isCurrent
                                  ? scheme.tertiaryContainer
                                  : isMatch
                                  ? scheme.primary.withValues(alpha: 0.12)
                                  : scheme.secondaryContainer.withValues(
                                      alpha: 0,
                                    ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_showTime)
                                    SizedBox(
                                      width: 64,
                                      child: Text(
                                        formatClock(s.startMs),
                                        // Brand: timestamps in JetBrains Mono, muted.
                                        style: TextStyle(
                                          fontFamily: 'JetBrains Mono',
                                          fontSize: 13,
                                          height: 1.6,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                    ),
                                  Expanded(child: Text(s.text)),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lower bound for one transcript line, used to tell whether the list
/// fills the space.
const _minLineHeight = 24.0;
