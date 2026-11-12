import 'package:flutter/material.dart';

import '../core/job.dart';
import '../core/models.dart';
import 'crystal.dart';
import 'motion.dart';

String jobStatusText(Job j, {required bool running}) {
  final total = j.items.length;
  final done = j.okCount + j.failedCount;
  switch (j.state) {
    case JobState.expanding:
      return running ? 'Buscando a lista de vídeos…' : 'Aguardando';
    case JobState.running:
      return running
          ? 'Processando $done de $total'
          : 'Interrompido · $done de $total';
    case JobState.paused:
      final why = switch (j.pauseReason) {
        FailureReason.network => ': sem conexão',
        FailureReason.rateLimited =>
          ': YouTube bloqueou por excesso de pedidos',
        _ => '',
      };
      return 'Pausado$why · $done de $total';
    case JobState.done:
      return '${j.okCount} pronto${j.okCount == 1 ? '' : 's'}'
          '${j.failedCount > 0 ? ' · ${j.failedCount} com falha' : ''}';
  }
}

class JobTile extends StatelessWidget {
  const JobTile({
    super.key,
    required this.job,
    required this.running,
    required this.onTap,
  });
  final Job job;
  final bool running;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = job.items.length;
    final done = job.okCount + job.failedCount;
    final scheme = Theme.of(context).colorScheme;
    final c = Crystal.of(context);
    final text = Theme.of(context).textTheme;
    final (icon, color) = switch (job.state) {
      JobState.done => (Icons.check_circle_outline, c.success),
      JobState.paused => (
        Icons.pause_circle_outline,
        job.pauseReason == null ? scheme.onSurfaceVariant : scheme.error,
      ),
      _ => (Icons.sync, scheme.primary),
    };
    return Glass(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  job.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleSmall,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Finishing pops the check in with a small overshoot.
                    SwapIn(
                      pop: job.state == JobState.done,
                      child: Icon(
                        icon,
                        key: ValueKey(job.state),
                        size: 16,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextSwap(
                        jobStatusText(job, running: running),
                        style: text.bodySmall,
                        maxLines: 1,
                      ),
                    ),
                    Text(
                      "${job.settings.format.label} · ${job.settings.language}",
                      style: text.bodySmall,
                    ),
                  ],
                ),
                // The rod collapses away when the job finishes.
                Resize(
                  child: job.state == JobState.done
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: CrystalProgress(
                            value: total == 0 ? null : done / total,
                            running: running,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
