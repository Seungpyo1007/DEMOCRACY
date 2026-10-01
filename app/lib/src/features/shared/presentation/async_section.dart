import 'package:democracy/src/core/network/not_available.dart';
import 'package:democracy/src/core/provenance/source_metadata.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Renders the loading, failed and loaded states of one section together.
///
/// Keeping them in one place is what stops a screen from shipping with only
/// the happy path drawn. A payload rejected for missing provenance is reported
/// as such rather than as a generic failure, because that distinction is the
/// point of the check.
class AsyncSection<T> extends StatelessWidget {
  const AsyncSection({
    required this.value,
    required this.builder,
    this.onRetry,
    super.key,
  });

  final AsyncValue<T> value;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: (data) => builder(context, data),
      loading: () => const InkLoadingRows(),
      error: (error, _) => _SectionError(error: error, onRetry: onRetry),
    );
  }
}

/// The headline and the explanation for a section that did not load.
///
/// Three different things, told apart: data that is not ready for this
/// district, data refused for lacking a source, and a failure to fetch.
/// Shared so the screens that draw their own error state say the same thing.
(String, String) describeLoadError(Object error) {
  return switch (error) {
    NotAvailableException() => (
      '아직 준비 중인 자료입니다.',
      '이 지역구의 자료가 공개 출처에서 정리되는 대로 표시합니다.',
    ),
    MissingSourceException() => (
      '출처가 확인되지 않아 표시하지 않습니다.',
      '원문 주소와 취득 시각이 확인된 자료만 표시합니다.',
    ),
    _ => ('내용을 불러오지 못했습니다.', '연결 상태를 확인한 뒤 다시 시도해 주세요.'),
  };
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final (message, detail) = describeLoadError(error);
    // Retrying cannot produce data that does not exist yet.
    final onRetry = error is NotAvailableException ? null : this.onRetry;

    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral400),
        borderRadius: BorderRadius.circular(surface.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.x2),
            Text(
              detail,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.neutral600),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.x3),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: onRetry,
                  child: const Text('다시 시도'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
