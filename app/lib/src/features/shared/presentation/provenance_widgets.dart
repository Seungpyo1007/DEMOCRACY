import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// The attribution that has to accompany every external figure.
///
/// Takes [SourceMetadata] rather than loose strings, so it is impossible to
/// render a badge for a figure that never carried provenance.
///
/// Tapping opens the original. That is the point of the rule rather than a
/// convenience: an attribution the reader cannot follow is an assertion, and
/// the whole design turns on figures being checkable.
class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.source, this.onOpen, super.key});

  final SourceMetadata source;

  /// Injected so tests can assert what would be opened without launching a
  /// browser. Defaults to [launchUrl].
  final Future<void> Function(Uri url)? onOpen;

  Future<void> _open() async {
    final open = onOpen ?? _launch;
    await open(source.sourceUrl);
  }

  static Future<void> _launch(Uri url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      label: '출처 ${source.sourceUrl}',
      child: InkWell(
        onTap: _open,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 24),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              '출처 ${source.publisher} · ${source.asOfLabel} ↗',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.disclaimer.copyWith(
                color: AppColors.neutral600,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.neutral400,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A party rendered as a grey outline tag.
///
/// There is no colour parameter. Party colour is barred from the interface,
/// and the way to keep that true over time is to give callers no way to pass
/// one in.
class PartyTag extends StatelessWidget {
  const PartyTag({required this.party, super.key});

  final PartyRef party;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral500),
        borderRadius: BorderRadius.circular(
          surface.isGlass ? 999 : AppRadii.androidChip,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: 2,
        ),
        child: Text(
          party.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.tag.copyWith(color: AppColors.neutral700),
        ),
      ),
    );
  }
}

/// A portrait, always desaturated.
///
/// The grayscale rule exists to keep colour from biasing how a face reads, so
/// the filter is applied here rather than left to each caller. No portraits
/// ship with the app yet, so this currently draws a neutral placeholder.
class GrayscalePortrait extends StatelessWidget {
  const GrayscalePortrait({
    required this.name,
    this.imageUrl,
    this.width = 56,
    this.height = 70,
    super.key,
  });

  final String name;
  final String? imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    // Small radii: a portrait is a photograph on the page, not a control.
    final radius = surface.isGlass ? 6.0 : 4.0;

    return Semantics(
      label: '$name 사진',
      image: true,
      child: ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0, //
          0, 0, 0, 1, 0, //
        ]),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.neutral300, AppColors.neutral500],
            ),
          ),
          alignment: Alignment.center,
          child: const Icon(
            Icons.person_outline,
            color: AppColors.neutral600,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// A pledge status shown as colour, glyph and word together.
///
/// Set as a label, not a filled chip: three of the four statuses are a
/// lightness ramp of ink, and only 번복 carries the accent. Colour alone would
/// be unreadable for a colour-blind reader and is barred by the design rules,
/// so the glyph and the label are not optional.
class PledgeStatusChip extends StatelessWidget {
  const PledgeStatusChip({required this.status, this.large = false, super.key});

  final PledgeStatus status;

  /// The serif display size used at the top of a pledge's own page.
  final bool large;

  /// The colour the status carries as a bar or swatch.
  static Color barColor(PledgeStatus status) => switch (status) {
    PledgeStatus.fulfilled => AppColors.fulfilled,
    PledgeStatus.inProgress => AppColors.inProgress,
    PledgeStatus.unfulfilled => AppColors.unfulfilled,
    PledgeStatus.reversed => AppColors.reversed,
  };

  /// The colour the status carries as text, which the lighter bar colours
  /// are not dark enough to be.
  static Color textColor(PledgeStatus status) => switch (status) {
    PledgeStatus.fulfilled => AppColors.fulfilledText,
    PledgeStatus.inProgress => AppColors.inProgressText,
    PledgeStatus.unfulfilled => AppColors.unfulfilledText,
    PledgeStatus.reversed => AppColors.reversedText,
  };

  @override
  Widget build(BuildContext context) {
    final style = large
        ? Theme.of(context).textTheme.headlineSmall!.copyWith(fontSize: 24)
        : AppTextStyles.badge;

    return Text(
      status.display,
      maxLines: 1,
      style: style.copyWith(color: textColor(status)),
    );
  }
}
