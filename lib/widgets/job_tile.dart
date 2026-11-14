import 'package:flutter/material.dart';

import '../core/job.dart';
import '../core/models.dart';
import '../l10n/l10n.dart';
import 'crystal.dart';
import 'motion.dart';

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
    final l = l10nOf(context);
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
                  l.jobLabel(job),
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
                        l.jobStatus(job, running: running),
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
