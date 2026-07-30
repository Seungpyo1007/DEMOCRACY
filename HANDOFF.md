# DEMOCRACY 초기 인계

기준 시각: 2026-07-30 Asia/Seoul

## 현재 상태

- 원본 디자인 번들은 `design_handoff_democracy_app/`에 그대로 보존했다.
- Flutter 앱 골격은 `app/`에 추가했다.
- 온보딩 외부 라우트와 5탭 `StatefulShellRoute.indexedStack` 구조를 잡았다.
- 디자인 토큰, 지역구 식별자·검증 증거를 포함한 주소 상태, 출처 메타데이터, `VerifiedGate`를 추가했다.
- 라우트·앱바·탭바·다이얼로그·햅틱은 표준 플랫폼 폴백을 구현했고, 네이티브 인증은 경계 인터페이스만 정의했다.
- 트래커, AI 분석, 커뮤니티, 개표는 의도적으로 placeholder다.
- Git 저장소를 초기화했고 bootstrap 이전 상태를 첫 커밋으로 남겼다.
- Flutter 3.44.8을 `C:\src\flutter`에 설치하고 사용자 PATH에 등록했다.
- bootstrap을 실행해 Android/iOS 네이티브 프로젝트를 생성했다.
- 골격의 컴파일 오류를 복구했고 `flutter analyze`와 `flutter test`가 통과한다.

M0 완료 조건을 충족했다. 남은 미검증 항목은 실기기 빌드뿐이다. Android 빌드는 JDK와 Android SDK, iOS 빌드는 macOS와 Xcode가 필요하다.

## 도구 기준

- 고정 버전: Flutter 3.44.8 / Dart 3.12.2. `app/.fvmrc`와 `bootstrap.ps1`의 가드가 동일한 값을 사용한다.
- 해석된 직접 의존성: `flutter_riverpod 3.4.2`, `go_router 17.3.0`, `flutter_lints 6.0.0`.
- `app/pubspec.lock`을 커밋했다.
- Android: compileSdk 36, targetSdk 36, minSdk 24, NDK 28.2.13676358, JVM target 17. 값은 Flutter Gradle 플러그인 기본값이며 `build.gradle.kts`에 하드코딩돼 있지 않다.
- README의 "API 34+"가 minSdk를 뜻하는지 미확정이라 minSdk 24는 생성값 그대로 두었다. 상향이 필요하면 별도 결정이 필요하다.
- 해석된 `analyzer`는 12.1.0이다. 최신 Freezed 3.2.5는 `analyzer <11`, Riverpod generator 4.0.8은 `analyzer ^13`을 요구해 어느 쪽도 현재 조합에 들어오지 못한다. codegen 의존성은 M1 호환성 spike까지 계속 제외한다.

## 설치 및 환경

- Flutter SDK: `C:\src\flutter` (공식 `flutter_windows_3.44.8-stable.zip`)
- 사용자 PATH에 `C:\src\flutter\bin` 추가
- FVM은 설치하지 않았다. `bootstrap.ps1`은 PATH에 `fvm`이 있으면 무조건 우선하는데, FVM 래퍼가 stdout에 배너를 출력하면 버전 확인의 `ConvertFrom-Json`이 깨진다.
- Android Studio 2026.1.2.10: `C:\Program Files\Android\Android Studio`
- JDK: Android Studio 동봉 OpenJDK 21.0.10. `flutter config --jdk-dir`로 연결했다.
- Android SDK: `C:\Users\29\AppData\Local\Android\Sdk`. platform android-36/36.1, build-tools 36.0.0, NDK 28.2.13676358, CMake 3.22.1. 라이선스 7종 수락 완료.
- cmdline-tools는 설정 마법사가 설치하지 않아 리비전 15859902를 별도로 `cmdline-tools\latest`에 넣었다. 이것이 없으면 `flutter doctor`가 라이선스 상태를 확인하지 못한다.
- `flutter analyze`와 `flutter test`는 Android SDK 없이도 동작한다. SDK는 실기기·에뮬레이터 빌드에만 필요하다.
- Visual Studio 미설치는 Windows 데스크톱 타깃 전용 항목이라 이 프로젝트와 무관하다.

## bootstrap.ps1 수정

`Get-Command flutter -CommandType Application`이 Windows에서 항상 두 개(`flutter`, `flutter.bat`)를 반환해 `$flutterCommand.Source`가 두 경로를 이어붙인 문자열이 되고 실행이 실패했다. `fvm`, `flutter`, `dart` 조회 세 곳에 `Select-Object -First 1`을 추가했다. PATHEXT 순서상 `.bat`이 먼저 오며 Windows에서는 그쪽이 올바른 실행 파일이다.

이 결함은 이 머신 한정이 아니라 Windows의 모든 표준 Flutter 설치에서 재현된다.

## 명세 우선순위

1. `design_handoff_democracy_app/README.md`: 제품, 중립성, 플랫폼, 데이터 요구
2. `design_handoff_democracy_app/DEMOCRACY UI Guide.dc.html`: 390dp 화면과 인터랙션
3. `_ds/.../styles.css`: 보조 토큰
4. `support.js`, `_ds_bundle.js`: 프리뷰 런타임 전용

HTML 안내문은 1단계를 주소 인증·지역구 조회·공약·주민 평가로 정의한다. README의 6개 화면은 전체 목표로 보고, 초기 MVP에서는 나머지 탭을 placeholder로 둔다.

## 구현된 최소 기반

```text
app/lib/
├─ main.dart
└─ src/
   ├─ app/                  # 앱 부트스트랩과 라우터
   ├─ core/
   │  ├─ adaptive/          # 플랫폼 폴백 5종 + 인증 계약
   │  ├─ auth/              # 주소 상태와 VerifiedGate
   │  └─ provenance/        # 출처 메타데이터
   ├─ design/               # 색상, 간격, 타이포, 테마
   └─ features/
      ├─ onboarding/
      ├─ district/
      ├─ shell/
      └─ shared/            # 후속 화면 placeholder
```

## 바로 할 일

1. README의 “API 34+”가 minSdk 의미인지 확정한다. 현재 minSdk는 생성값 24다.
2. iOS 최종 빌드는 macOS/Xcode 환경에서 검증한다.
3. `SourceMetadata` 검증을 DTO 파싱/리포지토리 경계에도 적용한다. 현재는 생성자에서만 강제되고, 이를 통과하도록 강제되는 호출부가 없다.
4. Fake repository와 JSON fixture로 온보딩 → 홈 → 공약 → 주민 평가 세로 흐름을 완성한다.
5. 라우터에 `redirect` 가드를 넣는다. 현재 온보딩은 `initialLocation`으로만 도달하므로 딥링크로 우회할 수 있다.

## 백로그

### MVP 1차

- 온보딩 3단계와 주소 검색/GPS 실패 폴백
- Freezed/Riverpod generator 호환 버전 spike 후 codegen 도입 여부 결정
- 거주지 인증 백엔드 계약과 opaque verification token 저장
- 지역구 홈의 의원·후보·공약 카드
- 모든 수치의 출처 뱃지와 기준일
- 주민 평가 읽기/작성, 미인증 작성 차단
- 390dp iOS/Android 골든 테스트

### MVP 2차

- 공약 트래커와 판정 타임라인
- AI 매칭, 산출 로그, 고정 중립 고지
- 지역 채팅과 정책 토론
- GeoJSON 개표 지도와 SSE/폴링
- Drift, secure storage, Sentry, Patrol
- WidgetKit/Glance, Live Activities/FCM Live Updates

## 미결정 사항

- 릴리스 서명 계정과 키스토어. 현재 release 빌드는 debug 키로 서명된다
- dev/staging/prod flavor
- “주소 인증”의 법적·기술적 검증 주체와 원주소 폐기 정책
- 국회·선관위·주소·지도 API 계약, 키, 이용 조건
- 딥링크 도메인과 URL 규칙
- AI 모델, 가중치, 공개 범위, 비용 상한, 편향 감사 기준
- 커뮤니티 moderation 및 신고 처리 정책
- Archivo/Pretendard 폰트 파일·사용권과 후보 사진 사용권. 현재는 시스템 폴백 상태
- iOS Liquid Glass 패키지 최종 선택

## 검증 기록

기준: Flutter 3.44.8 / Dart 3.12.2, Windows 11.

| 항목 | 상태 | 비고 |
|---|---|---|
| 원본 README/HTML 확인 | 완료 | UTF-8 기준 |
| Flutter/Dart 탐지 | 완료 | `frameworkVersion 3.44.8`, `dartSdkVersion 3.12.2` |
| Bootstrap SDK 가드 | 완료 | 두 버전 조건 모두 통과 |
| `flutter create` | 완료 | android/ios 생성. `pubspec.yaml`·`analysis_options.yaml`·`.fvmrc` diff 0 |
| `flutter pub get` | 완료 | `pubspec.lock` 생성 및 커밋 |
| `dart format` | 완료 | 최초 19개 중 16개 재포맷, 이후 재실행 시 0 changed |
| `flutter analyze` | 완료 | `No issues found!` |
| `flutter test` | 완료 | 8개 통과 |
| bootstrap 전체 체인 | 완료 | 종료 코드 0 |
| 코드 생성 | 보류 | 해석된 analyzer 12.1.0. M1에서 호환 조합 spike |
| `flutter doctor` | 완료 | Android toolchain √. Visual Studio 항목은 Windows 데스크톱 전용이라 해당 없음 |
| Android 빌드 | 완료 | `flutter build apk --debug` 성공. APK 패키지명 `com.democracy.kr` 확인 |
| iOS 빌드 | 미실행 | macOS/Xcode 필요 |

### 복구한 결함

| 위치 | 내용 |
|---|---|
| `onboarding_screen.dart` | `DistrictRef` 사용부에 `address_state.dart` import 누락. 오류 2건 |
| `verified_gate_test.dart` | `DistrictRef`, `ResidencyVerificationProof` 사용부에 동일 import 누락. 오류 2건 |
| `app_router.dart` | 미사용 `material.dart` import |
| `address_state.dart` | `prefer_initializing_formals` 2건. 타입 지정 initializing formal로 교체해 non-null 좁힘 유지 |
| `tool/bootstrap.ps1` | Windows에서 `Get-Command`가 두 개를 반환하는 문제 |

### 미충족 항목

`docs/INITIAL_PLAN.md`의 필수 테스트 8개 중 3개만 구현돼 있다. 출처 URL 거부, 미인증 쓰기 차단, 인증된 쓰기 1회 실행은 통과한다. 5탭 상태 보존, 후보 가나다순, 상태 색상 3중 부호화, 390dp 골든은 M1 이후 작업이다.

`SourceMetadata`는 생성자에서 `ArgumentError`를 던지는 실제 런타임 검증이며 release에서도 유효하다. 다만 리포지토리와 DTO가 아직 없어 이 경계를 통과하도록 강제되는 코드 경로가 없다.
