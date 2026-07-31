import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/features/district/domain/district_profile.dart';
import 'package:democracy/src/features/pledges/domain/pledge.dart';
import 'package:flutter/material.dart';

/// The attribution that has to accompany every external figure.
///
/// Takes [SourceMetadata] rather than loose strings, so it is impossible to
/// render a badge for a figure that never carried provenance.
class SourceBadge extends StatelessWidget {
  const SourceBadge({required this.source, super.key});

  final SourceMetadata source;

  @override
  Widget build(BuildContext context) {
    final caption = Theme.of(context).textTheme.bodySmall;

    return Semantics(
      label: '출처 ${source.sourceUrl}',
      child: Row(
        children: [
          const Icon(Icons.link, size: 14, color: AppColors.neutral600),
          const SizedBox(width: AppSpacing.x1),
          Expanded(
            child: Text(
              '출처: ${source.publisher} · ${source.asOfLabel}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: caption?.copyWith(color: AppColors.neutral600),
            ),
          ),
        ],
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
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral400),
        borderRadius: BorderRadius.circular(AppRadii.androidChip),
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
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
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
            borderRadius: BorderRadius.circular(AppRadii.androidCard),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.neutral200, AppColors.neutral400],
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
/// Colour alone would be unreadable for a colour-blind reader and is barred by
/// the design rules, so the glyph and the label are not optional.
class PledgeStatusChip extends StatelessWidget {
  const PledgeStatusChip({required this.status, super.key});

  final PledgeStatus status;

  Color get _color => switch (status) {
    PledgeStatus.fulfilled => AppColors.fulfilled,
    PledgeStatus.inProgress => AppColors.inProgress,
    PledgeStatus.unfulfilled => AppColors.neutral600,
    PledgeStatus.reversed => AppColors.reversed,
  };

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: _color),
        borderRadius: BorderRadius.circular(AppRadii.androidChip),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2,
          vertical: 2,
        ),
        child: Text(
          status.display,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _color),
        ),
      ),
    );
  }
}
