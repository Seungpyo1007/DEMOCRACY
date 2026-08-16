import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_labels.dart';
import 'package:flutter/material.dart';

/// What stands where a figure the law forbids publishing would have been.
///
/// It names the provision. A panel that simply goes blank reads as a bug, and
/// a reader who cannot tell a legal restriction from a broken screen learns
/// the wrong thing about both -- so the restriction is stated, along with when
/// it lifts. That is the same reasoning as `AsyncSection` reporting a missing
/// source as a missing source rather than as a generic failure.
class EmbargoNotice extends StatelessWidget {
  const EmbargoNotice({required this.article, required this.notice, super.key});

  /// The provision being complied with, e.g. '공직선거법 제108조제1항'.
  final String article;

  final String notice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screen,
        vertical: AppSpacing.x4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(article),
          const SizedBox(height: AppSpacing.x2),
          Text(
            notice,
            style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral700),
          ),
        ],
      ),
    );
  }
}
