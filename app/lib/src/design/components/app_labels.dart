import 'package:democracy/src/design/app_tokens.dart';
import 'package:flutter/material.dart';

/// The tracked, uppercase-weight heading that opens a section.
///
/// `현직 의원`, `출마 후보`, `카테고리별 이행률`. Distinct from a data label:
/// this one names a region of the page, so it carries wider tracking.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.sectionLabel.copyWith(color: AppColors.neutral600),
    );
  }
}

/// A small label above a value: `내 지역구`, `감지된 지역구`.
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.microLabel.copyWith(color: AppColors.neutral600),
    );
  }
}

/// One figure in the dashboard's three-up row: the number over its name.
///
/// The number leads because the guide sets it heavier and larger than the
/// label -- the reader is meant to scan figures, then find out what they are.
class StatCell extends StatelessWidget {
  const StatCell({required this.value, required this.label, super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    // Prefer FigureStat for a number: it counts up. This stays for values
    // that are not numbers.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.statValue.copyWith(color: AppColors.ink),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral600),
        ),
      ],
    );
  }
}

/// The tick that marks a verified thing.
///
/// `인증 가능` before verification, `주민 인증됨` after, `인증` on a review.
/// An ink outline, not a colour: the accent is kept for action and for one
/// data meaning, and a verification is neither. The tick and the word carry
/// the state.
///
/// Affirmative only. A state that is *not* a verification -- read-only,
/// awaiting review -- gets a [StatusChip] instead: putting a tick on
/// `읽기 전용` would mark the absence of verification as verified.
class VerifiedBadge extends StatelessWidget {
  const VerifiedBadge({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ink),
        borderRadius: BorderRadius.circular(
          surface.isGlass ? 999 : AppRadii.androidChip,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x2 + 2,
          vertical: 3,
        ),
        child: Text(
          '✓ $label',
          style: AppTextStyles.badge.copyWith(
            color: AppColors.ink,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// A neutral state, worn in the same place a [VerifiedBadge] would be.
///
/// Same shape and position so the header never reflows between states, and no
/// colour that implies approval or fault.
class StatusChip extends StatelessWidget {
  const StatusChip({required this.label, super.key});

  final String label;

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
          horizontal: AppSpacing.x2 + 2,
          vertical: 3,
        ),
        child: Text(
          label,
          style: AppTextStyles.badge.copyWith(
            color: AppColors.neutral700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

/// How the app says "this is not what it might look like".
///
/// Two of them exist because the two notices carry different weight. The AI
/// one is a standing disclosure pinned to the top of the screen, so it is a
/// full-width ink band -- the heaviest thing on the page, deliberately. The
/// community one is a rule about who may write, so it gets a dashed outline:
/// visibly a note, not a result.
enum DisclaimerTone { pinned, note }

class DisclaimerBox extends StatelessWidget {
  const DisclaimerBox({
    required this.text,
    this.tone = DisclaimerTone.note,
    this.action,
    super.key,
  });

  final String text;
  final DisclaimerTone tone;

  /// The AI notice has to carry a link to the open algorithm.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    if (tone == DisclaimerTone.pinned) {
      return ColoredBox(
        color: AppColors.ink,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screen,
            vertical: AppSpacing.x3 + 2,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.ground,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.x2),
                  Expanded(
                    child: Text(
                      text,
                      style: AppTextStyles.cardBody.copyWith(
                        color: AppColors.ground,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(left: 26, top: AppSpacing.x1),
                  child: DefaultTextStyle.merge(
                    style: const TextStyle(color: AppColors.ground),
                    child: action!,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final radius = surface.isGlass ? 6.0 : 4.0;
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: AppColors.neutral500,
        radius: radius,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.x3 + 2,
          vertical: AppSpacing.x3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'ⓘ $text',
              style: AppTextStyles.cardBody.copyWith(
                color: AppColors.neutral700,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 3), action!],
          ],
        ),
      ),
    );
  }
}

/// A dashed outline. Flutter's [Border] only draws solid, and the guide asks
/// for a dashed one specifically so the community notice does not read as
/// another card.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color, required this.radius});

  static const _dash = 4.0;
  static const _gap = 3.0;

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + _dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}
