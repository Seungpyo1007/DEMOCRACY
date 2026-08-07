# DEMOCRACY 인계

기준 시각: 2026-07-31 Asia/Seoul
작업 환경: Windows 11. **다음 작업자는 macOS로 이어받는다.**

## 이 문서를 읽는 순서

Windows에서 할 수 있는 범위는 전부 끝났다. 남은 작업은 대부분 macOS를 요구한다. 「macOS에서 할 일」과 「macOS 없이도 할 수 있는 일」을 먼저 보면 된다.

## 현재 상태

M0(재현 가능한 기반)과 M1(Fake 데이터 세로 슬라이스)의 Windows 가능 범위를 완료했다.

- 원본 디자인 번들은 `design_handoff_democracy_app/`에 그대로 보존했다.
- Flutter 3.44.8을 설치하고 bootstrap으로 Android/iOS 네이티브 프로젝트를 생성했다.
- 온보딩 외부 라우트와 5탭 `StatefulShellRoute.indexedStack`, redirect 가드까지 동작한다.
- 온보딩 → 지역구 홈 → 공약 → 주민 평가 세로 흐름이 네트워크 없이 완결된다.
- 기능별 `{data,domain,application,presentation}` 계층을 갖췄고, 화면은 repository 계약에만 의존한다.
- 출처 없는 외부 수치는 파싱 경계에서 거부된다. 이제 선언이 아니라 강제다.
- 중립성 규칙이 위젯으로 강제된다. 정당색을 넣을 자리가 타입에 없고, 인물 사진은 grayscale이 내장이며, 상태는 색·아이콘·텍스트가 함께 나가고, 수치는 출처 없이 렌더링될 수 없다.
- 하단 탭바는 iOS 26 형태의 떠 있는 캡슐이다. 유리 효과는 없고 색은 Material 3 롤이며, 스크롤 시 축소된다.
- 트래커, AI 분석, 개표는 의도적으로 placeholder다.
- `flutter analyze` 무결, 테스트 41개 통과, Android 디버그 빌드와 에뮬레이터 실행까지 확인했다.

## macOS에서 할 일

이 항목들은 Windows에서 시도할 수 없다. 순서대로 진행하면 된다.

0. **`CLAUDE.md`는 클론에 없다.** 의도적으로 추적 제외했으므로 Windows 머신에서 직접 복사해 와야 한다. 없으면 작업 규칙 없이 시작하게 된다.
1. **사전 준비.** Xcode(App Store) → `sudo xcode-select --switch /Applications/Xcode.app` → `sudo xcodebuild -license accept` → `xcodebuild -runFirstLaunch`. CocoaPods는 `brew install cocoapods`. Flutter는 정확히 3.44.8이어야 한다.
2. **`./tool/bootstrap.sh` 실행.** 버전 가드부터 `pod install`, `flutter build ios --no-codesign`까지 한 번에 돈다. `Podfile`과 `Podfile.lock`은 이때 처음 생성되므로 커밋 대상이다.
3. **Bundle ID 확인.** `ios/Runner.xcodeproj`의 `PRODUCT_BUNDLE_IDENTIFIER`가 `com.democracy.kr`, 테스트 타깃이 `com.democracy.kr.RunnerTests`인지 Xcode에서 확인한다. 서명 계정은 아직 미정이다.
4. **iOS 실기기·시뮬레이터 확인.** 특히 `PlatformAdaptiveRoute`의 스와이프 백, `PlatformAdaptiveAppBar`의 `CupertinoNavigationBar`, `PlatformAdaptiveHaptics`. 현재 iOS 분기는 위젯 테스트로만 검증돼 있다.
5. **390dp 골든 테스트.** `docs/INITIAL_PLAN.md`의 필수 테스트 8개 중 유일한 미구현 항목이다. 폰트가 시스템 폴백이라 렌더링이 플랫폼마다 달라, 골든은 생성 환경을 macOS로 고정해야 안정적이다.
6. **iOS Liquid Glass 패키지 spike.** 「iOS 네이티브 탭바 조사」에 후보와 기각 사유를 정리해 뒀다. 탭 상태 보존을 어떻게 유지할지가 선결 과제다.

## macOS 없이도 할 수 있는 일

Mac이 손에 없을 때 이어서 할 수 있는 작업이다.

- 온보딩 3단계 분리와 주소 검색·GPS 권한 거부 폴백. 현재 온보딩은 단일 화면이고 주소 검색 필드는 `readOnly`다.
- 공약 상세와 `/pledges/:id` 딥링크. 지금은 목록까지만 있다.
- 평가 작성 화면. 게이트는 완성됐고 통과 후 진입할 화면이 아직 없다.
- Freezed/Riverpod generator 호환 조합 spike와 codegen 도입 결정.
- 셸 스크롤 축소 배선의 테스트. 실제 스크롤 가능한 화면이 생기면 붙일 수 있다.

## 도구 기준

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
      ├─ onboarding/presentation/
      ├─ district/{data,domain,application,presentation}
      ├─ pledges/{data,domain,application}
      ├─ reviews/{data,domain,application,presentation}
      ├─ shell/presentation/
      └─ shared/presentation/   # 출처·중립성 위젯, 비동기 섹션, placeholder

app/assets/fixtures/         # 샘플 payload. 실서비스 데이터가 아니다
```

`pledges`에는 `presentation`이 없다. 공약은 아직 지역구 홈 카드로만 표시되고 전용 화면이 없어서다.

## 아키텍처에서 지켜지는 것

다음은 규약이 아니라 타입과 구조로 강제된다. 새 화면을 붙일 때 우회하지 않도록 유의한다.

- **출처 없는 수치는 도메인에 못 들어온다.** 외부 수치는 전부 `SourcedValue<T>`이고, 파싱이 `sourceUrl`·`fetchedAt`을 요구하며 실패 시 어느 필드가 문제인지 담아 던진다. `SourceBadge`는 `SourceMetadata`를 받으므로 출처 없이 수치를 그릴 방법이 없다.
- **정당색을 넣을 자리가 없다.** `PartyRef`에는 색 필드가 없고 `PartyTag`에도 색 인자가 없다.
- **인물 사진은 grayscale이 내장이다.** `GrayscalePortrait`가 필터를 스스로 적용한다.
- **공약 상태는 색 단독으로 못 나간다.** `PledgeStatus`가 glyph와 label을 함께 들고 다닌다.
- **후보 정렬은 도메인 연산이다.** `DistrictProfile.sortedByName`이 파싱 시점에 적용하고, `sortLabel`을 화면이 표시한다.
- **번복 판정은 근거 링크 없이 못 만든다.** `evidenceUrl`이 없으면 파싱이 거부한다.

## 확인된 제품 미결 사항

- README의 “API 34+”가 minSdk 의미인지 미확정. 현재 minSdk는 생성값 24다.
- 거주지 인증 백엔드 계약과 opaque verification token 저장 방식.

## iOS 네이티브 탭바 조사 (2026-07-31)

결론: **순수 Flutter 구현 유지.** 네이티브 패키지는 도입하지 않았다.

하단 탭바는 두 플랫폼 모두 `PlatformAdaptiveTabBar` 안의 공유 `_FloatingBarFrame`으로 띄운다. iOS는 목업 규격인 radius 30 / margin 14를 쓰고, 분리감은 블러가 아니라 불투명 표면과 그림자로 낸다.

### 후보와 기각 사유

| 패키지 | 상태 | 판정 |
|---|---|---|
| `cupertino_native_better` 1.5.3 | 활발 (73 likes, 6.74k 다운로드) | 아래 두 사유로 보류 |
| `native_tab_bar` 1.0.6 | 3년간 갱신 없음, 0 likes | 유지보수 중단으로 제외 |
| `native_liquid_glass`, `adaptive_platform_ui` | Liquid Glass 전제 | 아래 1번 사유로 제외 |

1. **네이티브와 "Liquid Glass 없음"은 iOS 26에서 양립하지 않는다.** iOS 26은 모든 네이티브 UIKit 컨트롤에 Liquid Glass 스타일을 자동 적용한다. 진짜 `UITabBar`를 쓰는 순간 강제로 따라온다.
2. **`CNTabBarNative.enable()`은 하단 네비게이션 대체용이 아니다.** 위젯 트리 바깥에서 `UITabBarController`를 띄우는 네이티브 takeover이고 `currentIndex`/`onTap` 계약이 없다. 패키지 문서가 Flutter bottom navigation의 drop-in으로 쓰지 말라고, 상태 소스가 충돌해 "두 번 탭해야 하는" 동작과 화면 재빌드가 생긴다고 직접 경고한다. 채택하면 `StatefulShellRoute.indexedStack` 기반 탭 상태 보존을 재설계해야 한다.

추가로 현재 워크스테이션에 macOS/Xcode가 없어 네이티브 의존성은 컴파일 검증조차 불가능하다.

### 재검토 조건

macOS 환경이 확보되고 M3에 진입한 뒤, `CLAUDE.md`의 규칙대로 인터페이스 뒤에서 한 패키지씩 성능·접근성 spike를 거쳐 결정한다. 탭 상태 보존을 어떻게 유지할지가 선결 과제다.

## 백로그

### MVP 1차 (남은 것)

완료: 지역구 홈의 의원·후보·공약 카드, 모든 수치의 출처 뱃지와 기준일, 주민 평가 읽기, 미인증 작성 차단.

- 온보딩 3단계와 주소 검색/GPS 실패 폴백
- 평가 작성 화면. 게이트 통과 후 진입할 대상이 아직 없다
- 공약 상세와 `/pledges/:id` 딥링크
- Freezed/Riverpod generator 호환 버전 spike 후 codegen 도입 여부 결정
- 거주지 인증 백엔드 계약과 opaque verification token 저장
- 390dp iOS/Android 골든 테스트 — **macOS 필요**

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
- iOS Liquid Glass 패키지 최종 선택. M3까지 보류하기로 결정했다. 근거는 위 「iOS 네이티브 탭바 조사」 참고

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
| `flutter test` | 완료 | 41개 통과 |
| bootstrap 전체 체인 | 완료 | 종료 코드 0 |
| 코드 생성 | 보류 | 해석된 analyzer 12.1.0. 호환 조합 spike 필요 |
| `flutter doctor` | 완료 | Android toolchain √. Visual Studio 항목은 Windows 데스크톱 전용이라 해당 없음 |
| Android 빌드 | 완료 | `flutter build apk --debug` 성공. APK 패키지명 `com.democracy.kr` 확인 |
| 에뮬레이터 실행 | 완료 | AVD `democracy_api36` (Pixel 5, API 36). fixture 기반 세로 흐름 확인. logcat 오류 0건 |
| iOS 빌드 | **미실행** | macOS/Xcode 필요. CocoaPods도 미실행 |
| 390dp 골든 | **미구현** | macOS에서 생성 환경 고정 필요 |

### 필수 테스트 이행 현황

`docs/INITIAL_PLAN.md`의 8개 기준이다.

| 항목 | 상태 |
|---|---|
| 출처 URL이 상대 경로이거나 스킴이 HTTP(S)가 아니면 거부 | 완료 |
| 미인증 쓰기 액션은 실행되지 않고 인증 안내가 표시 | 완료 |
| 인증된 쓰기 액션은 한 번만 실행 | 완료 |
| 읽기 전용 온보딩 종료 후 홈 진입 | 완료 |
| 후보 가나다순 및 동일 정보 순서 | 완료 |
| 상태 색상에 아이콘과 텍스트가 항상 병기 | 완료 |
| 5탭 전환과 각 탭 상태 보존 | 부분. 전환은 확인, 스크롤 위치 보존은 미검증 |
| 390dp Android/iOS 골든 | 미구현. macOS 필요 |

### 에뮬레이터에서 확인한 것

AVD는 `pixel_5` 프로파일(1080×2340 @440dpi = 393×851dp)로 만들었다. 목업 기준 390dp에 가장 가깝다.

- 온보딩이 셸 밖에서 열린다. 게이트의 `인증하러 가기`로 복귀했을 때 하단 탭바가 없다.
- `나중에 인증하기` → 홈이 `읽기 전용` 칩으로 진입한다.
- 홈이 fixture에서 의원 카드, 출처 뱃지가 붙은 지표 3종, 3중 부호화된 공약 상태를 렌더링한다.
- `평가 작성하기` 탭 시 `주민 인증이 필요합니다`가 뜨고 작성이 차단된다.
- 떠 있는 캡슐 탭바가 스크롤에 따라 축소·복원된다.

미확인 두 가지. **탭별 스크롤 위치 보존**은 아직 화면이 짧아 행동으로 증명하지 못했다. **셸의 스크롤 축소 배선**은 테스트가 없고 임시 필러로 수동 확인만 했다. 둘 다 스크롤 가능한 실제 화면이 생기면 함께 닫을 수 있다.

### 복구한 결함

| 위치 | 내용 |
|---|---|
| `onboarding_screen.dart` | `DistrictRef` 사용부에 `address_state.dart` import 누락. 오류 2건 |
| `verified_gate_test.dart` | `DistrictRef`, `ResidencyVerificationProof` 사용부에 동일 import 누락. 오류 2건 |
| `app_router.dart` | 미사용 `material.dart` import |
| `address_state.dart` | `prefer_initializing_formals` 2건. 타입 지정 initializing formal로 교체해 non-null 좁힘 유지 |
| `tool/bootstrap.ps1` | Windows에서 `Get-Command`가 두 개를 반환하는 문제 |
| `app_shell.dart` | 스크롤 축소를 `UserScrollNotification.direction`으로 판단하면 드래그를 놓는 순간 `forward`가 한 번 튀어 바가 다시 펴진다. 누적 이동량 임계값 방식으로 교체 |

### 남은 구조적 부채

- `pledges`에 `presentation`이 없다. 공약 전용 화면을 만들 때 채운다.
- 평가 작성 화면이 없어 `VerifiedGate` 통과 후 SnackBar만 띄운다.
- 출처 뱃지가 원문 URL을 열지 않는다. `url_launcher` 도입 결정이 필요해 표시까지만 했다.
- 인물 사진 자산이 없어 `GrayscalePortrait`가 자리표시자를 그린다. 실제 사진이 들어와도 grayscale은 위젯이 보장한다.
- `districtProvider`(`address_controller.dart`)는 선언만 있고 사용처가 없다. 각 feature의 provider가 `addressControllerProvider`를 직접 select 한다.
