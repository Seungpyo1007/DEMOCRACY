import 'package:democracy/src/core/auth/verified_gate.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/native_controls.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// What a list says when there is nothing in it yet: a real district starts
/// empty, and that should read as a beginning rather than a failure.
class CommunityEmptyNote extends StatelessWidget {
  const CommunityEmptyNote({
    required this.title,
    required this.detail,
    super.key,
  });

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.reading.copyWith(
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          Text(
            detail,
            style: AppTextStyles.cardBody.copyWith(
              color: AppColors.neutral600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// What stands in for a post hidden by reports or staff: the server's
/// placeholder, set apart from what residents wrote.
class HiddenPostBody extends StatelessWidget {
  const HiddenPostBody({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.visibility_off_outlined,
          size: 16,
          color: AppColors.neutral600,
        ),
        const SizedBox(width: AppSpacing.x1 + 2),
        Flexible(
          child: Text(
            text,
            style: AppTextStyles.cardBody.copyWith(color: AppColors.neutral600),
          ),
        ),
      ],
    );
  }
}

/// The send glyph, named for both systems so the iOS field never carries a
/// Material arrow.
const _sendIcon = AppIcon(Icons.send, 'paperplane.fill');

/// The field a message or a reply is written in: a Cupertino text field with
/// a glass send button on iOS, a Material 3 text field with a filled icon
/// button on Android.
///
/// Sending is a write, so it goes through the gate: an unverified resident
/// gets the explanation rather than a dead button.
class CommunityComposer extends StatelessWidget {
  const CommunityComposer({
    required this.controller,
    required this.enabled,
    required this.onSend,
    this.hint = '메시지 보내기',
    this.disabledHint = '주소 인증 주민만 보낼 수 있습니다',
    super.key,
  });

  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;
  final String hint;
  final String disabledHint;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).extension<AppSurfaceTokens>()!;
    final hint = enabled ? this.hint : disabledHint;

    final send = VerifiedGate(
      onVerified: onSend,
      builder: (context, onPressed) {
        if (surface.isGlass) {
          return AppToolbarButton(
            icon: _sendIcon,
            label: '보내기',
            onPressed: onPressed,
          );
        }
        // Tonal until the resident is verified: still pressable, since it
        // explains the gate, but not dressed as the page's live action.
        return enabled
            ? IconButton.filled(
                tooltip: '보내기',
                onPressed: onPressed,
                icon: Icon(_sendIcon.material),
              )
            : IconButton.filledTonal(
                tooltip: '보내기',
                onPressed: onPressed,
                icon: Icon(_sendIcon.material),
              );
      },
    );

    if (surface.isGlass) {
      return AppFloatingBar(
        child: Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: controller,
                enabled: enabled,
                placeholder: hint,
                placeholderStyle: AppTextStyles.cardBody.copyWith(
                  color: AppColors.neutral600,
                ),
                style: AppTextStyles.cardBody.copyWith(color: AppColors.ink),
                textInputAction: TextInputAction.send,
                onSubmitted: enabled ? (_) => onSend() : null,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.x4,
                  vertical: AppSpacing.x3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.85),
                  border: Border.all(color: AppColors.neutral300),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.x2),
            send,
          ],
        ),
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.ground,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.x4,
            AppSpacing.x2,
            AppSpacing.x3,
            AppSpacing.x2,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  textInputAction: TextInputAction.send,
                  onSubmitted: enabled ? (_) => onSend() : null,
                  decoration: InputDecoration(isDense: true, hintText: hint),
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              send,
            ],
          ),
        ),
      ),
    );
  }
}
