/// The app's two languages and the sentences built from domain codes.
///
/// Every sentence on screen comes from the translation files (app_en.arb,
/// app_pt.arb). This file only picks the language and joins the pieces.
library;

import 'package:flutter/widgets.dart';

import '../core/formatters.dart';
import '../core/job.dart';
import '../core/languages.dart';
import '../core/models.dart';
import '../core/url_parser.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// Languages the app speaks. English is the model file.
const appLocales = [Locale('en'), Locale('pt')];

/// D-27 A: a phone in any Portuguese (Brazil, Portugal…) gets Portuguese;
/// any other language gets English. Only the phone's first language counts
/// (on Android 13+ that is the per-app language when one is set).
Locale resolveAppLocale(List<Locale>? phone) {
  final first = (phone == null || phone.isEmpty) ? null : phone.first;
  return first?.languageCode.toLowerCase() == 'pt' ? const Locale('pt') : const Locale('en');
}

/// The app's sentences for [context].
AppLocalizations l10nOf(BuildContext context) => AppLocalizations.of(context);

extension AppTexts on AppLocalizations {
  /// "pt" or "en".
  String get appLanguage => localeName.startsWith('pt') ? 'pt' : 'en';

  /// Caption language name in the app's language ("Portuguese" / "Português").
  String language(String code) => languageName(code, appLanguage);

  String failure(FailureReason r) => switch (r) {
        FailureReason.noCaptions => failNoCaptions,
        FailureReason.membersOnly => failMembersOnly,
        FailureReason.ageRestricted => failAgeRestricted,
        FailureReason.unavailable => failUnavailable,
        FailureReason.rateLimited => failRateLimited,
        FailureReason.network => failNetwork,
        FailureReason.unknown => failUnknown,
      };

  /// A job notice or caption note as a sentence. Links and old sentences go
  /// in as plain text: nothing inside them is read as a placeholder.
  String notice(Notice n) {
    String arg(int i) => i < n.args.length ? n.args[i] : '';
    return switch (n.code) {
      NoticeCode.linkIgnored => noticeLinkIgnored(arg(0)),
      NoticeCode.limitReached => noticeLimitReached(int.tryParse(arg(0)) ?? 0),
      NoticeCode.playlistNotFound => noticePlaylistNotFound(arg(0)),
      NoticeCode.channelNotFound => noticeChannelNotFound(arg(0)),
      NoticeCode.noVideos => noticeNoVideos,
      NoticeCode.translationUnavailable => noteTranslationUnavailable(language(arg(0))),
      NoticeCode.otherLanguage => noteOtherLanguage(language(arg(0)), language(arg(1))),
      NoticeCode.text => arg(0),
    };
  }

  /// Short name of a job for the history and the job screen.
  String jobLabel(Job j) {
    final l = j.label;
    return l.more > 0 ? jobLabelMore(l.name, l.more) : l.name;
  }

  /// One line about a job: "Processing 3 of 10", "2 ready · 1 failed"…
  String jobStatus(Job j, {required bool running}) {
    final total = j.items.length;
    final done = j.okCount + j.failedCount;
    switch (j.state) {
      case JobState.expanding:
        return running ? statusExpanding : statusWaiting;
      case JobState.running:
        return running ? statusProcessing(done, total) : statusInterrupted(done, total);
      case JobState.paused:
        return switch (j.pauseReason) {
          FailureReason.network => statusPausedNetwork(done, total),
          FailureReason.rateLimited => statusPausedRateLimited(done, total),
          _ => statusPaused(done, total),
        };
      case JobState.done:
        return [statusReady(j.okCount), if (j.failedCount > 0) statusFailed(j.failedCount)].join(' · ');
    }
  }

  /// What the input line understood: "Recognized: 1 video, 1 channel", or
  /// that nothing was recognized.
  String recognizedText(ParseResult p) {
    final v = p.count(TargetKind.video);
    final pl = p.count(TargetKind.playlist);
    final ch = p.count(TargetKind.channel);
    final kinds = [
      if (v > 0) videoCount(v),
      if (pl > 0) playlistCount(pl),
      if (ch > 0) channelCount(ch),
    ];
    return kinds.isEmpty ? noLinkRecognized : recognized(kinds.join(', '));
  }

  /// "1 link ignored", or null when every link was understood.
  String? ignoredText(ParseResult p) => p.invalid.isEmpty ? null : linksIgnored(p.invalid.length);

  String track(Transcript t) => trackLabel(t, auto: trackAuto, translated: trackTranslated);

  /// Words for exported files, in the app's language now.
  ExportLabels get exportLabels => ExportLabels(
        channel: headerChannel,
        video: headerVideo,
        language: headerLanguage,
        text: headerText,
        withTimestamps: headerWithTimestamps,
        auto: trackAuto,
        translated: trackTranslated,
        reasons: {for (final r in FailureReason.values) r: failure(r)},
      );
}
