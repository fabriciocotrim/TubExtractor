import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../core/job.dart';
import '../core/url_parser.dart';
import '../share_intake.dart';
import '../widgets/crystal.dart';
import '../widgets/job_tile.dart';
import '../widgets/motion.dart';
import '../widgets/options.dart';
import 'job_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app, required this.intake});
  final AppState app;
  final ShareIntake intake;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Where the list was when each pending job was swiped away: the job was on
  /// screen then, so Desfazer can go back there if it is now far away.
  final _deletedAt = <String, double>{};

  /// Jobs whose swipe saved a delete mark but has not removed the row yet.
  final _swiping = <Job>{};

  AppState get app => widget.app;

  /// The job brought back by Desfazer: it shows at once, without the
  /// entrance delay, and the list scrolls to it. Cleared once it is in view.
  String? _restoredId;

  /// This screen is the one on top (no job or transcript screen over it).
  bool _onTop = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _input.addListener(() => setState(() {}));
    widget.intake.initialText().then((t) {
      if (t != null) _receive(t);
    });
    widget.intake.listen(_receive);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Rebuilt by the route when another screen covers this one or leaves.
    _onTop = ModalRoute.isCurrentOf(context) ?? true;
    _tellVisible();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _tellVisible();

  /// The delete notice counts down only while the user can see it: this
  /// screen on top and the app in the foreground.
  void _tellVisible() {
    final life = WidgetsBinding.instance.lifecycleState;
    app.noticesVisible(_onTop && (life == null || life == AppLifecycleState.resumed), screen: this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Only if no newer home screen has spoken since (one replaced in a
    // single frame starts before the old one goes).
    app.noticesClosed(this);
    // Swipes cut short: those jobs stay, so their delete marks go.
    for (final j in _swiping) {
      unawaited(app.unmarkForDelete(j));
    }
    widget.intake.stop();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _receive(String text) {
    if (!mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    final current = _input.text.trim();
    _input.text = current.isEmpty ? text.trim() : '$current\n${text.trim()}';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link recebido. Toque em Buscar transcrições.'),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text?.trim();
    if (t == null || t.isEmpty) return;
    final current = _input.text.trim();
    _input.text = current.isEmpty ? t : '$current\n$t';
  }

  void _start() {
    final parsed = parseInput(_input.text);
    if (parsed.targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum link do YouTube reconhecido. Cole um vídeo, playlist, canal, @handle ou Shorts.',
          ),
        ),
      );
      return;
    }
    FocusScope.of(context).unfocus();
    final job = app.createJob(_input.text);
    _input.clear();
    _open(job);
  }

  void _open(Job job) => Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => JobScreen(app: app, job: job),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final s = app.settings;
        final jobs = app.jobs;
        final parsed = parseInput(_input.text);
        final text = Theme.of(context).textTheme;
        return CrystalPage(
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 48,
              actions: [
                IconButton(
                  tooltip: 'Sobre e cache',
                  icon: const Icon(Icons.info_outline),
                  onPressed: () => _about(context),
                ),
                _ThemeButton(app: app),
                const SizedBox(width: 4),
              ],
            ),
            // The one primary action stays in reach while the options scroll.
            extendBody: true,
            // The delete notice sits right above the bar, where a floating
            // message would; other messages float above both.
            bottomNavigationBar: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _UndoNotice(current: app.currentDelete, onUndo: _undo),
                GlassBar(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: CrystalButton(
                      onPressed: parsed.targets.isEmpty ? null : _start,
                      icon: Icons.download,
                      label: 'Buscar transcrições',
                    ),
                  ),
                ),
              ],
            ),
            // Builder: this context sees the padding the glass bar adds.
            body: Builder(
              builder: (context) => ListView(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.paddingOf(context).bottom + 20,
                ),
                children: [
                  // Brand lockup: symbol, wordmark and signature line.
                  // Blocks rise in one after another on opening (Reveal).
                  Reveal(
                    index: 0,
                    child: Row(
                      children: [
                        const BrandSymbol(height: 60),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Wordmark(style: text.headlineMedium),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'TRANSCRIÇÕES DO YOUTUBE EM LOTE',
                                style: text.labelSmall?.copyWith(
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Reveal(
                    index: 1,
                    child: Text(
                      'Cole links do YouTube e leve o texto de todos os vídeos de uma vez.',
                      style: text.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Reveal(
                    index: 2,
                    child: Glass(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _input,
                            minLines: 3,
                            maxLines: 8,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              hintText: 'youtube.com/watch?v=…\n@canal\nyoutube.com/playlist?list=…',
                              suffixIcon: SwapIn(
                                child: _input.text.isEmpty
                                    ? IconButton(
                                        key: const ValueKey('paste'),
                                        tooltip: 'Colar',
                                        icon: const Icon(Icons.content_paste),
                                        onPressed: _paste,
                                      )
                                    : IconButton(
                                        key: const ValueKey('clear'),
                                        tooltip: 'Limpar',
                                        icon: const Icon(Icons.clear),
                                        onPressed: _input.clear,
                                      ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                            child: SwapIn(
                              scale: false,
                              child: _input.text.trim().isEmpty
                                  ? Text(
                                      'Vídeo, playlist, canal, @handle ou Shorts. Um link por linha.',
                                      key: const ValueKey('hint'),
                                      style: text.bodySmall,
                                    )
                                  : _InputSummary(parsed: parsed),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Reveal(
                    index: 3,
                    child: Glass(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Labeled(
                            'Formato',
                            FormatSelector(
                              value: s.format,
                              onChanged: (f) =>
                                  app.updateSettings(s.copyWith(format: f)),
                            ),
                          ),
                          Labeled(
                            'Tempo de cada trecho',
                            TimestampSelector(
                              value: s.timestamps,
                              format: s.format,
                              onChanged: (t) =>
                                  app.updateSettings(s.copyWith(timestamps: t)),
                            ),
                          ),
                          Labeled(
                            'Idioma da transcrição',
                            Align(
                              alignment: Alignment.centerLeft,
                              child: LanguageField(
                                code: s.language,
                                onChanged: (c) =>
                                    app.updateSettings(s.copyWith(language: c)),
                              ),
                            ),
                          ),
                          Labeled(
                            'Máximo de vídeos',
                            LimitSelector(
                              value: s.limit,
                              onChanged: (n) =>
                                  app.updateSettings(s.copyWith(limit: n)),
                            ),
                            help: 'Canal: do mais novo ao mais antigo. Playlist: na ordem dela.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (jobs.isNotEmpty) ...[
                    Reveal(
                      index: 4,
                      // Comes back with the only job, restored by Desfazer.
                      instant: jobs.length == 1 && jobs.single.id == _restoredId,
                      child: Text('Histórico', style: text.titleLarge),
                    ),
                    const SizedBox(height: 12),
                    for (final (i, j) in jobs.indexed)
                      Reveal(
                        key: ValueKey('tile-${j.id}'),
                        index: 5 + (i < 4 ? i : 4),
                        // Only the job brought back by Desfazer skips the
                        // entrance; new jobs still rise in (1.4.0).
                        instant: j.id == _restoredId,
                        child: Padding(
                          // Lets Desfazer find the tile to scroll to it.
                          key: GlobalObjectKey(j),
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Dismissible(
                            key: ValueKey(j.id),
                            direction: DismissDirection.endToStart,
                            background: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Container(
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 24),
                                color: Theme.of(context).colorScheme.error
                                    .withValues(alpha: 0.25),
                                child: Icon(
                                  Icons.delete_outline,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ),
                            // The delete mark is on disk before the job
                            // leaves the list: a kill then does not bring
                            // it back.
                            confirmDismiss: (_) async {
                              _swiping.add(j);
                              await app.markForDelete(j);
                              if (mounted) return true;
                              return false; // dispose rolls the mark back
                            },
                            onDismissed: (_) {
                              _swiping.remove(j);
                              _deletedAt.removeWhere((id, _) => !app.pendingDeletes.any((p) => p.job.id == id));
                              if (_scroll.hasClients) _deletedAt[j.id] = _scroll.offset;
                              app.deleteWithUndo(j);
                            },
                            child: JobTile(
                              job: j,
                              running: app.isRunning(j),
                              onTap: () => _open(j),
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Text(
                        'Deslize uma busca para a esquerda para apagar.',
                        style: text.bodySmall,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// "Desfazer" on the notice. Swiping is easy to do by accident: the job
  /// left the list at once, but is only deleted when its notice closes
  /// without this. Notices stack (D-04): [AppState] keeps them and their
  /// countdown; this screen just draws the newest.
  void _undo(PendingDelete p) {
    // A notice still fading out is not the one on screen any more.
    if (!identical(p, app.currentDelete)) return;
    final back = _deletedAt.remove(p.job.id);
    _restoredId = p.job.id;
    app.undoDelete(p); // rebuilds the list with the job back
    WidgetsBinding.instance.addPostFrameCallback((_) => _bringIntoView(p.job, back));
  }

  /// Scrolls to the restored tile. [back] is where the list was when it was
  /// swiped away, for a tile so far from the screen that it is not built.
  void _bringIntoView(Job job, double? back) {
    if (!mounted || job.id != _restoredId) return;
    final ctx = GlobalObjectKey(job).currentContext;
    final box = ctx?.findRenderObject();
    if (ctx == null || box is! RenderBox || !box.attached) {
      if (back == null || !_scroll.hasClients) {
        _restoredId = null;
        return;
      }
      final pos = _scroll.position;
      _scroll.jumpTo(back.clamp(pos.minScrollExtent, pos.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) => _bringIntoView(job, null));
      return;
    }
    // The tile is built and has skipped its entrance: nothing else needs it.
    _restoredId = null;
    // Off screen, or under the app bar, the bottom bar or the notice:
    // bring it to the middle.
    final top = box.localToGlobal(Offset.zero).dy;
    final screen = MediaQuery.sizeOf(context).height;
    if (top >= 100 && top + box.size.height <= screen - 160) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: Motion.of(context, Motion.medium),
      curve: Motion.smoothOut,
    );
  }

  Future<void> _about(BuildContext context) async {
    final size = await app.cacheSize();
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('TubExtractor'),
        content: Text(
          'Baixa legendas públicas do YouTube direto do seu celular. Não tem conta, servidor nem coleta de dados.\n\n'
          'Só funciona com vídeos que têm legenda. Legendas automáticas mantêm a pontuação do YouTube.\n\n'
          'Não é afiliado ao YouTube nem ao Google.\n\n'
          'Cache no aparelho: $size',
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await app.clearCache();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Limpar cache'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }
}

/// The delete notice: "Busca apagada." with "Desfazer", for the newest
/// pending delete. Drawn by this screen from [AppState], not by the shared
/// message queue, so no other message can hide or replace it. A new notice
/// grows in over the old one; the one leaving can no longer be tapped.
class _UndoNotice extends StatelessWidget {
  const _UndoNotice({required this.current, required this.onUndo});
  final PendingDelete? current;
  final void Function(PendingDelete) onUndo;

  @override
  Widget build(BuildContext context) {
    final p = current;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.fast),
      switchInCurve: Motion.smoothOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, a) => AnimatedBuilder(
        animation: a,
        builder: (_, child) => IgnorePointer(ignoring: a.status != AnimationStatus.forward && a.status != AnimationStatus.completed, child: child),
        child: FadeTransition(
          opacity: a,
          child: SizeTransition(sizeFactor: a, alignment: Alignment.bottomCenter, child: child),
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, ?current],
      ),
      child: p == null
          ? const SizedBox(width: double.infinity)
          : _NoticeCard(key: ObjectKey(p), onUndo: () => onUndo(p)),
    );
  }
}

/// Looks like the app's floating message (theme `snackBarTheme`, Material 3
/// defaults): rounded, inverse colors, text on the left, action on the right.
class _NoticeCard extends StatelessWidget {
  const _NoticeCard({super.key, required this.onUndo});
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final snack = theme.snackBarTheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: snack.insetPadding ?? const EdgeInsets.fromLTRB(15, 5, 15, 10),
          child: Material(
            shape: snack.shape,
            elevation: snack.elevation ?? 6,
            color: snack.backgroundColor ?? scheme.inverseSurface,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        'Busca apagada.',
                        style: snack.contentTextStyle ??
                            theme.textTheme.bodyMedium?.copyWith(color: scheme.onInverseSurface),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TextButton(
                      onPressed: onUndo,
                      style: TextButton.styleFrom(
                        foregroundColor: snack.actionTextColor ?? scheme.inversePrimary,
                        overlayColor: snack.actionTextColor ?? scheme.inversePrimary,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                      child: const Text('Desfazer'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One line under the input. Only the ignored part is red: two good links and
/// one bad one is not an error state.
class _InputSummary extends StatelessWidget {
  const _InputSummary({required this.parsed});
  final ParseResult parsed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall;
    final none = parsed.targets.isEmpty;
    final ignored = parsed.ignoredText;
    return SwapIn(
      scale: false,
      child: Text.rich(
        key: ValueKey(parsed.summary),
        TextSpan(
          children: [
            TextSpan(
              text: parsed.recognizedText,
              style: TextStyle(
                color: none ? scheme.error : scheme.onSurfaceVariant,
              ),
            ),
            if (ignored != null) ...[
              TextSpan(
                text: ' · ',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              TextSpan(
                text: ignored,
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
        style: style,
      ),
    );
  }
}

/// Light / dark switch, top right. Shows the moon in light mode and the sun in
/// dark mode (what a tap leads to); the icons swap with a quarter turn and the
/// whole theme cross-fades.
class _ThemeButton extends StatelessWidget {
  const _ThemeButton({required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: dark ? 'Tema claro' : 'Tema escuro',
      onPressed: () =>
          app.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
      icon: SwapIn(
        turn: true,
        child: Icon(
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey(dark),
        ),
      ),
    );
  }
}
