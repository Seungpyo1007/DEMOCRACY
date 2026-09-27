import 'package:democracy/src/features/reviews/domain/review_draft.dart';

/// Why a review or a message was not posted, in words the screen can show.
///
/// The BFF answers a refused write with a code; this is that code turned into
/// something the author can act on. A refused session is not one of these --
/// it is a `SessionExpiredException`, answered with the sign-in-again sheet.
class CommunityWriteException implements Exception {
  const CommunityWriteException(
    this.message, {
    this.warning,
    this.residencyLost = false,
  });

  /// From a BFF error code and, for `content_rejected`, its reason.
  factory CommunityWriteException.fromCode(String code, {Object? reason}) {
    switch (code) {
      case 'residency_required':
        return const CommunityWriteException(
          '이 지역구 주민 인증이 확인되지 않았습니다. 주민 인증을 다시 해 주세요.',
          residencyLost: true,
        );
      case 'content_rejected':
        final warning =
            ContentWarning.fromReason(reason) ?? ContentWarning.hate;
        return CommunityWriteException(
          warning.prompt('올리려면'),
          warning: warning,
        );
      case 'rate_limited':
        return const CommunityWriteException(
          '1분에 다섯 번까지 올릴 수 있습니다. 잠시 뒤 다시 시도하세요.',
        );
    }
    return generic;
  }

  static const generic = CommunityWriteException('올리지 못했습니다. 잠시 뒤 다시 시도하세요.');

  final String message;

  /// Set when the server refused the wording: the same interception the app
  /// makes before sending, arriving from the side that cannot be edited out.
  final ContentWarning? warning;

  /// The server no longer holds a residency for this district -- it expired
  /// or was withdrawn elsewhere -- so the app should stop showing one.
  final bool residencyLost;

  @override
  String toString() => 'CommunityWriteException: $message';
}
