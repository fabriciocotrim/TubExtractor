import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app_state.dart';
import '../core/formatters.dart';
import '../core/job.dart';
import '../core/languages.dart';
import '../core/models.dart';
import '../widgets/crystal.dart';
import '../widgets/job_tile.dart';
import '../widgets/motion.dart';
import '../widgets/options.dart';
import 'transcript_screen.dart';

class JobScreen extends StatefulWidget {
  const JobScreen({super.key, required this.app, required this.job});
  final AppState app;
  final Job job;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

enum _Filter { all, ok, failed }

class _JobScreenState extends State<JobScreen> {
  String _query = '';
  _Filter _filter = _Filter.all;
  bool _busy = false;

  AppState get app => widget.app;
  Job get job => widget.job;

  /// Safe after an await: the screen may have closed meanwhile.
  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String get _zipName {
    final d = job.createdAt;
    String two(int v) => v.toString().padLeft(2, '0');
    return 'tubextractor-${d.year}${two(d.month)}${two(d.day)}-${two(d.hour)}${two(d.minute)}.zip';
  }

  Future<void> _export({required bool share}) async {
    var format = job.settings.format;
    var ts = job.settings.timestamps;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                share ? 'Compartilhar ZIP' : 'Salvar ZIP',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              Labeled(
                'Formato',
                FormatSelector(
                  value: format,
                  onChanged: (f) => set(() => format = f),
                ),
              ),
              Labeled(
                'Timestamps',
                TimestampSelector(
                  value: ts,
                  format: format,
                  onChanged: (t) => set(() => ts = t),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'O ZIP traz uma transcrição por vídeo, mais manifest.csv e manifest.json '
                'com o status de cada um.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(share ? 'Compartilhar' : 'Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final Uint8List bytes = await app.buildJobZip(job, format, ts);
      if (share) {
        final f = await app.writeTemp(_zipName, bytes);
        await SharePlus.instance.share(
          ShareParams(files: [XFile(f.path, mimeType: 'application/zip')]),
        );
      } else {
        final uri = await FilePicker.saveFile(
          fileName: _zipName,
          bytes: bytes,
          mimeType: 'application/zip',
        );
        if (uri != null) _snack('ZIP salvo.');
      }
    } catch (_) {
      _snack('Não foi possível gerar o ZIP. Tente de novo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyAll() async {
    final list = await app.transcriptsOf(job);
    if (list.isEmpty) return _snack('Nenhuma transcrição pronta.');
    final text = list
        .map(
          (t) =>
              '## ${t.title}\n${t.url}\n\n${paragraphs(t.segments).join('\n\n')}',
        )
        .join('\n\n\n');
    await Clipboard.setData(ClipboardData(text: text));
    _snack(
      list.length == 1
          ? '1 transcrição copiada.'
          : '${list.length} transcrições copiadas.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final running = app.isRunning(job);
        final total = job.items.length;
        final done = job.okCount + job.failedCount;
        final q = _query.toLowerCase();
        final items = job.items.where((i) {
          if (_filter == _Filter.ok && i.status != ItemStatus.ok) return false;
          if (_filter == _Filter.failed && i.status != ItemStatus.failed) {
            return false;
          }
          if (q.isEmpty) return true;
          return (i.title ?? '').toLowerCase().contains(q) ||
              i.videoId.toLowerCase().contains(q);
        }).toList();
        final retryable = job.items.any(
          (i) =>
              i.status == ItemStatus.failed &&
              const {
                FailureReason.rateLimited,
                FailureReason.network,
                FailureReason.unknown,
              }.contains(i.reason),
        );

        final text = Theme.of(context).textTheme;
        final scheme = Theme.of(context).colorScheme;
        return CrystalPage(
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Busca'),
              actions: [
                IconButton(
                  tooltip: 'Copiar tudo',
                  icon: const Icon(Icons.copy_all),
                  onPressed: job.okCount == 0 ? null : _copyAll,
                ),
                IconButton(
                  tooltip: 'Compartilhar ZIP',
                  icon: const Icon(Icons.share),
                  onPressed: job.okCount == 0 || _busy
                      ? null
                      : () => _export(share: true),
                ),
              ],
            ),
            body: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                MediaQuery.paddingOf(context).bottom + 12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Glass(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          job.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        // Counts change in place, rising softly.
                        TextSwap(
                          '${jobStatusText(job, running: running)} · ${job.settings.format.label} · ${languageName(job.settings.language)}',
                          style: text.bodySmall,
                        ),
                        // Collapses away when the job finishes; the status line
                        // above already switched to the result.
                        Resize(
                          child: job.state == JobState.done
                              ? const SizedBox(width: double.infinity)
                              : Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: CrystalProgress(
                                    value: total == 0 ? null : done / total,
                                    running: running,
                                  ),
                                ),
                        ),
                        for (final m in job.messages)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              m,
                              style: text.bodySmall?.copyWith(
                                color: scheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              // D-01: Baixar ZIP keeps the brand coral.
                              style: brandFilledStyle(context),
                              onPressed: job.okCount == 0 || _busy
                                  ? null
                                  : () => _export(share: false),
                              icon: SwapIn(
                                child: _busy
                                    ? const SizedBox(
                                        key: ValueKey('busy'),
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.folder_zip_outlined,
                                        key: ValueKey('zip'),
                                      ),
                              ),
                              label: const Text('Baixar ZIP'),
                            ),
                            // Pause and Continue swap in the same slot.
                            if (running ||
                                job.state != JobState.done ||
                                retryable)
                              SwapIn(
                                child: running
                                    ? OutlinedButton.icon(
                                        key: const ValueKey('pause'),
                                        onPressed: () => app.pause(job),
                                        icon: const Icon(Icons.pause),
                                        label: const Text('Pausar'),
                                      )
                                    : job.state != JobState.done
                                    ? OutlinedButton.icon(
                                        key: const ValueKey('resume'),
                                        onPressed: () => app.resume(job),
                                        icon: const Icon(Icons.play_arrow),
                                        label: const Text('Continuar'),
                                      )
                                    : OutlinedButton.icon(
                                        key: const ValueKey('retry'),
                                        onPressed: () => app.resume(job),
                                        icon: const Icon(Icons.refresh),
                                        label: const Text(
                                          'Tentar as falhas de novo',
                                        ),
                                      ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Searching by title only pays off on long lists.
                  if (total >= 10) ...[
                    const SizedBox(height: 14),
                    TextField(
                      decoration: const InputDecoration(
                        isDense: true,
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Filtrar por título',
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ],
                  if (total > 0) ...[
                    const SizedBox(height: 14),
                    // Pill slides to the chosen filter.
                    SlidingTabs<_Filter>(
                      options: [
                        (_Filter.all, 'Todos ($total)'),
                        (_Filter.ok, 'Prontos (${job.okCount})'),
                        (_Filter.failed, 'Falhas (${job.failedCount})'),
                      ],
                      value: _filter,
                      onChanged: (f) => setState(() => _filter = f),
                    ),
                    const SizedBox(height: 14),
                    // One glass sheet for the whole list: one blur, not one per row.
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, box) => Glass(
                          padding: EdgeInsets.zero,
                          child: Material(
                            // Ripples draw on this layer, above the glass tint.
                            type: MaterialType.transparency,
                            child: ListView.separated(
                              // Sheet hugs short lists, scrolls long ones.
                              // A list that surely fills the space skips the
                              // costly hug; both build only the rows on screen.
                              shrinkWrap:
                                  items.length * _minRowHeight < box.maxHeight,
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1, indent: 64),
                              // Keyed by video, and the lookup below finds a
                              // video's row after a filter change, so one
                              // video's animation never moves onto another.
                              findItemIndexCallback: (key) {
                                if (key is! ValueKey<String>) return null;
                                final i = items.indexWhere((it) => it.videoId == key.value);
                                return i < 0 ? null : i;
                              },
                              itemBuilder: (context, i) => _ItemTile(
                                key: ValueKey(items[i].videoId),
                                app: app,
                                job: job,
                                item: items[i],
                              ),
                            ),
                          ),
                        ),
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
}

/// Lower bound for one video row (the shortest ListTile), used to tell
/// whether the list fills the sheet.
const _minRowHeight = 40.0;

class _ItemTile extends StatelessWidget {
  const _ItemTile({
    super.key,
    required this.app,
    required this.job,
    required this.item,
  });
  final AppState app;
  final Job job;
  final JobItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (item.status) {
      // Brand status colors: green ready, amber when a fallback track was used.
      ItemStatus.ok => (
          Icons.check_circle,
          item.note == null ? Crystal.of(context).success : Crystal.of(context).warning,
        ),
      ItemStatus.failed => (Icons.error_outline, scheme.error),
      ItemStatus.pending => (Icons.hourglass_empty, scheme.outline),
    };
    final sub = switch (item.status) {
      ItemStatus.ok => [
        if (item.fromCache) 'cache',
        if (item.note != null) item.note!,
      ].join(' · '),
      ItemStatus.failed => (item.reason ?? FailureReason.unknown).message,
      ItemStatus.pending => 'Na fila',
    };
    return ListTile(
      // A video turning from "in queue" to ready/failed is the moment worth showing.
      leading: SwapIn(
        pop: item.status != ItemStatus.pending,
        child: Icon(icon, key: ValueKey(item.status), color: color),
      ),
      title: Text(
        item.title ?? item.videoId,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: sub.isEmpty
          ? null
          : Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: item.status != ItemStatus.ok
          ? null
          : () async {
              final t = await app.transcriptOf(job, item);
              if (!context.mounted) return;
              if (t == null) {
                // Cache was cleared: fetch this video again.
                app.refetch(job, item);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'A transcrição saiu do cache. Buscando de novo…',
                    ),
                  ),
                );
                return;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TranscriptScreen(
                    app: app,
                    transcript: t,
                    settings: job.settings,
                  ),
                ),
              );
            },
    );
  }
}
