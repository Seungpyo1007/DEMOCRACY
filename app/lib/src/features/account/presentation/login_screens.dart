import 'dart:async';

import 'package:democracy/src/app/app_routes.dart';
import 'package:democracy/src/core/account/account.dart';
import 'package:democracy/src/core/account/auth_controller.dart';
import 'package:democracy/src/core/account/auth_repository.dart';
import 'package:democracy/src/core/account/auth_state.dart';
import 'package:democracy/src/core/time/clock_providers.dart';
import 'package:democracy/src/design/app_motion.dart';
import 'package:democracy/src/design/app_tokens.dart';
import 'package:democracy/src/design/components/app_card.dart';
import 'package:democracy/src/design/components/editorial.dart';
import 'package:democracy/src/design/components/ink_loading.dart';
import 'package:democracy/src/design/components/motion.dart';
import 'package:democracy/src/features/account/presentation/account_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Follows a sign-in from the screen it happened on. The router's redirect
/// cannot do this: login is pushed over the tab it was opened from, and a
/// redirect only sees the location beneath a pushed page.
void listenForSignIn(WidgetRef ref, BuildContext context, String? next) {
  ref.listen(authControllerProvider, (previous, state) {
    if (!context.mounted) {
      return;
    }
    switch (state) {
      case AuthNeedsConsent():
        context.pushReplacement(AppRoutes.withNext(AppRoutes.consent, next));
      case AuthSignedIn():
        context.go(next ?? AppRoutes.home);
      default:
    }
  });
}

void _leave(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.home);
  }
}

/// `01 계정` -- reading needs no account; only writing does.
///
/// Also where a failed attempt lands: the reason is set above the buttons,
/// with the same buttons below it to try again or pick another way.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({this.next, super.key});

  final String? next;

  static const headline = '읽는 데는\n계정이 필요 없습니다.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForSignIn(ref, context, next);
    final state = ref.watch(authControllerProvider);
    // Ordered here, by the page's own platform: Apple first on iOS, Google
    // first on Android, email always last.
    final order = Theme.of(context).platform == TargetPlatform.iOS
        ? const [
            SignInProvider.apple,
            SignInProvider.kakao,
            SignInProvider.google,
          ]
        : const [
            SignInProvider.google,
            SignInProvider.kakao,
            SignInProvider.apple,
          ];
    final offered = ref.watch(signInProvidersProvider).toSet();
    final providers = [
      for (final provider in order)
        if (offered.contains(provider)) provider,
      if (offered.contains(SignInProvider.email)) SignInProvider.email,
    ];
    final busy = state is AuthSigningIn ? state.provider : null;
    final failure = state is AuthFailed ? state.failure : null;
    final controller = ref.read(authControllerProvider.notifier);

    return AccountPage(
      title: '로그인',
      onBack: () {
        controller.dismissFailure();
        _leave(context);
      },
      children: [
        const SectionHeader(number: '01', label: '계정'),
        const SizedBox(height: AppSpacing.x6),
        const _Headline(headline),
        const SizedBox(height: AppSpacing.x3),
        const LeadText(
          '리뷰, 채팅, 공약 이행 제보처럼 글을 남길 때만 로그인합니다. '
          '이름, 전화번호, 생년월일은 받지 않습니다.',
        ),
        const Align(
          alignment: AlignmentDirectional.centerEnd,
          child: MarginNote('실명 확인은 하지 않아요', underline: false),
        ),
        if (failure != null) ...[
          const SizedBox(height: AppSpacing.x6),
          ShakeOnce(child: _FailureNotice(failure)),
        ],
        const SizedBox(height: AppSpacing.x8),
        for (final provider in providers)
          if (provider == SignInProvider.email)
            _EmailLink(
              onPressed: busy != null
                  ? null
                  : () => context.push(
                      AppRoutes.withNext(AppRoutes.loginEmail, next),
                    ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.x3 - 2),
              child: ProviderButton(
                provider: provider,
                retry: failure?.provider == provider,
                busy: busy == provider,
                onPressed: busy != null
                    ? null
                    : () => controller.signIn(provider),
              ),
            ),
        const SizedBox(height: AppSpacing.x3),
        const FactRow(label: '받는 정보', value: '로그인 제공자 식별자, 이메일(제공될 때)'),
        Center(
          child: TextLink(
            label: '로그인 없이 계속 둘러보기',
            small: true,
            onTap: () {
              controller.dismissFailure();
              _leave(context);
            },
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  const _Headline(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Text(
      text,
      style: ios
          ? AppTextStyles.onboardingHeadlineIos
          : AppTextStyles.onboardingHeadlineAndroid,
    );
  }
}

/// Why the last attempt did not finish. Descriptive, like the rest of the
/// app: what happened and what can be done, never blame.
class _FailureNotice extends StatelessWidget {
  const _FailureNotice(this.failure);

  final AuthFailure failure;

  static (String, String) copyFor(AuthFailure failure) {
    final name = failure.provider?.label ?? '';
    return switch (failure.kind) {
      AuthFailureKind.cancelled => (
        '$name 로그인을 마치지 못했어요',
        '로그인 창이 닫혔습니다. 다시 시도하거나 다른 방법을 고르세요.',
      ),
      AuthFailureKind.linked => (
        '이미 다른 방법으로 가입한 이메일이에요',
        '처음 가입할 때 쓴 방법으로 로그인하세요.',
      ),
      AuthFailureKind.disabled => (
        '이 계정으로는 로그인할 수 없어요',
        '운영 정책에 따라 이용이 제한된 계정입니다.',
      ),
      AuthFailureKind.network ||
      AuthFailureKind.invalidCode ||
      AuthFailureKind.unknown => (
        '연결이 끊겼어요',
        '네트워크를 확인한 뒤 다시 시도하세요. 둘러보기는 저장된 기록으로 계속할 수 있습니다.',
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (title, body) = copyFor(failure);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const InkRule(color: AppColors.systemError),
          const SizedBox(height: AppSpacing.x3),
          Text(
            title,
            style: AppTextStyles.cardBody.copyWith(
              color: AppColors.systemError,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.x1 + 2),
          LeadText(body),
        ],
      ),
    );
  }
}

/// A provider's own button, in the provider's colours: Apple black, Kakao
/// yellow, Google white. The marks are stand-ins until the official button
/// assets are added.
class ProviderButton extends StatelessWidget {
  const ProviderButton({
    required this.provider,
    required this.onPressed,
    this.busy = false,
    this.retry = false,
    super.key,
  });

  final SignInProvider provider;
  final VoidCallback? onPressed;
  final bool busy;
  final bool retry;

  // Kakao's login design guide: container #FEE500, symbol #000000 (drawn
  // as #191919 in the official resource), label black at 85%.
  static const _kakaoYellow = Color(0xFFFEE500);
  static const _kakaoSymbol = Color(0xFF191919);
  static const _kakaoLabel = Color(0xD9000000);

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (provider) {
      SignInProvider.apple => (Colors.black, Colors.white, null),
      SignInProvider.kakao => (_kakaoYellow, _kakaoLabel, null),
      _ => (AppColors.white, AppColors.ink, AppColors.neutral400),
    };
    final mark = switch (provider) {
      SignInProvider.apple => Icon(Icons.apple, size: 20, color: foreground),
      SignInProvider.kakao => const CustomPaint(
        size: Size.square(18),
        painter: _KakaoSymbol(_kakaoSymbol),
      ),
      _ => Text(
        'G',
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w800,
          color: foreground,
        ),
      ),
    };
    // Kakao's guide fixes the label to 카카오 로그인; the others read as a
    // continuation, since the same button signs up and signs in.
    final label = switch ((provider, retry)) {
      (SignInProvider.kakao, false) => '카카오 로그인',
      (SignInProvider.kakao, true) => '카카오 로그인 다시 시도',
      (_, true) => '${provider.label}로 다시 시도',
      _ => '${provider.label}로 계속하기',
    };

    return PressScale(
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: Material(
          color: background,
          shape: StadiumBorder(
            side: border == null ? BorderSide.none : BorderSide(color: border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (busy)
                  InkStampIndicator(size: 20, color: foreground, delayed: false)
                else
                  ExcludeSemantics(child: mark),
                const SizedBox(width: AppSpacing.x2),
                Text(
                  label,
                  style: AppTextStyles.cta.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Kakao's symbol, traced from the official login button resource
/// (developers.kakao.com → 리소스 다운로드 → 카카오 로그인), so it is the
/// guide's shape rather than a look-alike. The source path sits in a
/// 12.9555-unit square; it is scaled to the paint size.
class _KakaoSymbol extends CustomPainter {
  const _KakaoSymbol(this.color);

  final Color color;

  static const _unit = 12.9555;

  static Path _path() => Path()
    ..moveTo(6.4785, 0)
    ..cubicTo(2.8997, 0, 0, 2.4812, 0, 5.5416)
    ..cubicTo(0, 7.5087, 1.1994, 9.2371, 3.0067, 10.2198)
    ..lineTo(2.3956, 12.6888)
    ..cubicTo(2.3729, 12.7625, 2.3907, 12.8415, 2.4394, 12.8959)
    ..cubicTo(2.475, 12.9345, 2.5236, 12.9555, 2.5706, 12.9555)
    ..cubicTo(2.6112, 12.9555, 2.6517, 12.9415, 2.6857, 12.9116)
    ..lineTo(5.3115, 10.9919)
    ..cubicTo(5.6892, 11.0498, 6.0782, 11.0814, 6.4769, 11.0814)
    ..cubicTo(10.0542, 11.0814, 12.9555, 8.6001, 12.9555, 5.5398)
    ..cubicTo(12.9555, 2.4795, 10.0558, 0, 6.4785, 0)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.shortestSide / _unit;
    canvas
      ..save()
      ..scale(scale)
      ..drawPath(_path(), Paint()..color = color)
      ..restore();
  }

  @override
  bool shouldRepaint(_KakaoSymbol old) => old.color != color;
}

class _EmailLink extends StatelessWidget {
  const _EmailLink({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 48),
          foregroundColor: AppColors.signal,
          textStyle: AppTextStyles.ctaSmall.copyWith(fontSize: 15),
        ),
        child: const Text('이메일로 로그인 코드 받기'),
      ),
    );
  }
}

/// `01 이메일로 로그인` -- a code is mailed; no password is ever made.
class EmailEntryScreen extends ConsumerStatefulWidget {
  const EmailEntryScreen({this.next, super.key});

  final String? next;

  @override
  ConsumerState<EmailEntryScreen> createState() => _EmailEntryScreenState();
}

class _EmailEntryScreenState extends ConsumerState<EmailEntryScreen> {
  final _field = TextEditingController();
  bool _sending = false;

  bool get _valid {
    final text = _field.text.trim();
    final at = text.indexOf('@');
    return at > 0 && text.indexOf('.', at) > at + 1;
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    await ref
        .read(authControllerProvider.notifier)
        .sendEmailCode(_field.text.trim());
    if (!mounted) {
      return;
    }
    setState(() => _sending = false);
    final state = ref.read(authControllerProvider);
    if (state is AuthAwaitingCode) {
      unawaited(
        context.push(AppRoutes.withNext(AppRoutes.loginCode, widget.next)),
      );
    } else if (state is AuthFailed) {
      context.pop();
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: '이메일로 로그인',
      onBack: () => _leave(context),
      action: AppPrimaryButton(
        label: _sending ? '보내는 중' : '코드 받기',
        onPressed: _valid && !_sending ? _send : null,
      ),
      children: [
        const SectionHeader(number: '01', label: '이메일로 로그인'),
        const SizedBox(height: AppSpacing.x6),
        const _Headline('로그인 코드를\n보내 드릴게요.'),
        const SizedBox(height: AppSpacing.x3),
        const LeadText('비밀번호는 만들지 않습니다. 메일로 받은 6자리 코드만 입력하면 됩니다.'),
        const SizedBox(height: AppSpacing.x8),
        TextField(
          controller: _field,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          autocorrect: false,
          style: AppTextStyles.cardBody.copyWith(fontSize: 20),
          decoration: const InputDecoration(
            labelText: '이메일',
            hintText: 'name@example.com',
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _valid ? _send() : null,
        ),
        const SizedBox(height: AppSpacing.x2),
        Text(
          '이 주소는 로그인에만 씁니다. 알림 메일은 따로 동의할 때만 보냅니다.',
          style: AppTextStyles.statLabel.copyWith(color: AppColors.neutral700),
        ),
      ],
    );
  }
}

/// `02 코드 확인` -- six cells over one field, the cursor cell blinking.
class EmailCodeScreen extends ConsumerStatefulWidget {
  const EmailCodeScreen({this.next, super.key});

  final String? next;

  static const length = 6;

  /// How long after a send another may be asked for.
  static const resendAfter = Duration(seconds: 60);

  @override
  ConsumerState<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends ConsumerState<EmailCodeScreen> {
  final _field = TextEditingController();
  final _focus = FocusNode();
  Timer? _tick;
  bool _checking = false;
  bool _wrong = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The countdown only ticks where time moves; tests hold the clock still.
    if (_tick == null && AppMotion.loopsEnabled) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _check(String code) async {
    setState(() {
      _checking = true;
      _wrong = false;
    });
    try {
      await ref.read(authControllerProvider.notifier).verifyEmailCode(code);
    } on AuthFailure {
      if (mounted) {
        _field.clear();
        setState(() => _wrong = true);
      }
    }
    if (mounted) {
      setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    listenForSignIn(ref, context, widget.next);
    final state = ref.watch(authControllerProvider);
    final email = state is AuthAwaitingCode ? state.email : '';
    final sentAt = state is AuthAwaitingCode ? state.sentAt : null;
    final now = ref.watch(clockProvider).now().utc;
    final wait = sentAt == null
        ? Duration.zero
        : EmailCodeScreen.resendAfter - now.difference(sentAt);
    final canResend = wait <= Duration.zero;
    final seconds = wait.inSeconds.clamp(0, 60);

    return AccountPage(
      title: '코드 확인',
      onBack: () => _leave(context),
      action: AppPrimaryButton(
        label: _checking ? '확인하는 중' : '확인',
        onPressed: _field.text.length == EmailCodeScreen.length && !_checking
            ? () => _check(_field.text)
            : null,
      ),
      children: [
        const SectionHeader(number: '02', label: '코드 확인'),
        const SizedBox(height: AppSpacing.x6),
        const _Headline('메일로 보낸 코드를\n입력하세요.'),
        const SizedBox(height: AppSpacing.x3),
        LeadText('$email으로 보냈습니다.'),
        const SizedBox(height: AppSpacing.x8),
        _CodeCells(
          controller: _field,
          focus: _focus,
          onChanged: (code) {
            setState(() => _wrong = false);
            if (code.length == EmailCodeScreen.length) {
              _check(code);
            }
          },
        ),
        if (_wrong) ...[
          const SizedBox(height: AppSpacing.x3),
          ShakeOnce(
            child: Text(
              '코드가 맞지 않거나 시간이 지났어요. 다시 입력하거나 새 코드를 받으세요.',
              style: AppTextStyles.statLabel.copyWith(
                color: AppColors.systemError,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.x6),
        RuledRow(
          minHeight: 52,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '메일이 안 왔나요?',
                  style: AppTextStyles.cardBody.copyWith(
                    color: AppColors.neutral700,
                  ),
                ),
              ),
              TextButton(
                onPressed: canResend
                    ? () => ref
                          .read(authControllerProvider.notifier)
                          .sendEmailCode(email)
                    : null,
                child: Text(
                  canResend
                      ? '다시 보내기'
                      : '다시 보내기 · 0:${seconds.toString().padLeft(2, '0')}',
                ),
              ),
            ],
          ),
        ),
        RuledRow(
          minHeight: 52,
          onTap: () => _leave(context),
          child: Text(
            '다른 이메일 쓰기',
            style: AppTextStyles.ctaSmall.copyWith(color: AppColors.signal),
          ),
        ),
      ],
    );
  }
}

/// Six boxes drawn over one invisible field, so paste and the platform's
/// one-time-code autofill work as they would on a plain field.
class _CodeCells extends StatelessWidget {
  const _CodeCells({
    required this.controller,
    required this.focus,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '6자리 코드',
      child: Stack(
        children: [
          Opacity(
            opacity: 0,
            child: TextField(
              controller: controller,
              focusNode: focus,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: EmailCodeScreen.length,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: onChanged,
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: focus.requestFocus,
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                final code = value.text;
                return Row(
                  children: [
                    for (var i = 0; i < EmailCodeScreen.length; i++) ...[
                      if (i > 0) const SizedBox(width: AppSpacing.x2),
                      Expanded(
                        child: i == code.length
                            ? Caret(
                                on: AppColors.signal,
                                off: AppColors.neutral400,
                                builder: (context, color) =>
                                    _Cell(digit: '', border: color, width: 2),
                              )
                            : _Cell(
                                digit: i < code.length ? code[i] : '',
                                border: AppColors.neutral400,
                                width: 1,
                              ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.digit, required this.border, required this.width});

  final String digit;
  final Color border;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border, width: width),
      ),
      child: Text(
        digit,
        style: AppTextStyles.figureSmall.copyWith(fontSize: 26),
      ),
    );
  }
}
