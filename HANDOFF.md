# DEMOCRACY 인계

기준 시각: 2026-08-13 Asia/Seoul
작업 환경: macOS 27.0 / Xcode 26.6. 이전 구간은 Windows 11에서 진행했다.

## 이 문서를 읽는 순서

**macOS를 요구하던 작업은 전부 끝났다.** iOS가 컴파일되고, 시뮬레이터에서 돌고, 390dp 골든이 붙었다. 남은 것은 기능 구현이므로 「남은 작업」과 「백로그」를 보면 된다.

## 현재 상태

M0(재현 가능한 기반)과 M1(Fake 데이터 세로 슬라이스)을 완료했다. M1의 완료 조건인 「네트워크 없이 온보딩 → 홈 → 공약 → 평가 흐름 + 390dp 골든 통과」를 충족한다.

- 원본 디자인 번들은 `design_handoff_democracy_app/`에 그대로 보존했다.
- Flutter 3.44.8을 설치하고 bootstrap으로 Android/iOS 네이티브 프로젝트를 생성했다.
- 온보딩 외부 라우트와 5탭 `StatefulShellRoute.indexedStack`, redirect 가드까지 동작한다.
- 온보딩 → 지역구 홈 → 공약 → 주민 평가 세로 흐름이 네트워크 없이 완결된다.
- 기능별 `{data,domain,application,presentation}` 계층을 갖췄고, 화면은 repository 계약에만 의존한다.
- 출처 없는 외부 수치는 파싱 경계에서 거부된다. 이제 선언이 아니라 강제다.
- 중립성 규칙이 위젯으로 강제된다. 정당색을 넣을 자리가 타입에 없고, 인물 사진은 grayscale이 내장이며, 상태는 색·아이콘·텍스트가 함께 나가고, 수치는 출처 없이 렌더링될 수 없다.
- 하단 탭바는 iOS 26 형태의 떠 있는 캡슐이다. 유리 효과는 없고 색은 Material 3 롤이며, 스크롤 시 축소된다.
- 트래커, AI 분석, 개표는 의도적으로 placeholder다.
- `flutter analyze` 무결, 테스트 54개 통과. Android는 디버그 빌드와 에뮬레이터 실행, iOS는 디바이스 빌드와 시뮬레이터 실행까지 확인했다.
- 390dp Android/iOS 골든 6장이 붙었다. 필수 테스트 8개가 전부 이행됐다.

## macOS 구간에서 끝낸 것 (2026-08-13)

이전 인계가 「macOS에서 할 일」로 남긴 항목의 결과다.

- **iOS 최초 컴파일.** `flutter build ios --no-codesign` 성공. `bootstrap.sh` 전체 체인 종료 코드 0.
- **`bootstrap.sh` 결함 수정.** 아래 「bootstrap.sh의 CocoaPods 분기」 참고. 이전 인계의 Podfile 서술이 틀렸다.
- **Bundle ID 확인 완료.** `project.pbxproj`에서 직접 확인했다. Runner는 `com.democracy.kr`(`:385`, `:564`, `:586`), 테스트 타깃은 `com.democracy.kr.RunnerTests`(`:401`, `:418`, `:433`). Xcode를 열 필요가 없었다. `IPHONEOS_DEPLOYMENT_TARGET`은 생성 기본값 13.0 그대로다. 서명 계정은 여전히 미정이다.
- **iOS 시뮬레이터 실측.** iPhone 17 Pro / iOS 27.0. 결과는 「검증 기록」에 있다.
- **390dp 골든.** Android/iOS 각 3화면. ubuntu CI와 충돌하지 않도록 macOS job으로 분리했다.

**iOS Liquid Glass 패키지 spike는 이 구간에서 하지 않았다.** 「iOS 네이티브 탭바 조사」의 결론대로 M3까지 보류가 이미 결정된 사항이라, 환경이 생겼다는 이유만으로 앞당기지 않았다.

## 남은 작업

macOS 여부와 무관하다. 전부 기능 구현이다.

- 온보딩 3단계 분리와 주소 검색·GPS 권한 거부 폴백. 현재 온보딩은 단일 화면이고 주소 검색 필드는 `readOnly`다. `LinearProgressIndicator(value: 1/3)`이 3단계를 암시하지만 나머지 2단계가 없다.
- 공약 상세와 `/pledges/:id` 딥링크. 지금은 목록까지만 있다.
- 평가 작성 화면. 게이트는 완성됐고 통과 후 진입할 화면이 아직 없다.
- Freezed/Riverpod generator 호환 조합 spike와 codegen 도입 결정.
- 거주지 인증 백엔드 계약. 아래 「실행 중인 앱에서 게이트가 통과 불가」 참고.

## 도구 기준

- 고정 버전: Flutter 3.44.8 / Dart 3.12.2. `app/.fvmrc`, `bootstrap.ps1`, `bootstrap.sh`, `verify.yml` 네 곳의 가드가 동일한 값을 사용한다. 올릴 때는 네 곳을 함께 바꿔야 한다.
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

## bootstrap.sh의 CocoaPods 분기

이전 인계는 「`Podfile`과 `Podfile.lock`은 이때 처음 생성되므로 커밋 대상이다」라고 적었다. **틀렸다.**

`bootstrap.sh`는 Darwin 분기에서 `pod install`을 무조건 실행했는데, 이 저장소에는 `Podfile`이 존재한 적이 없다. 직접 의존성이 `flutter_riverpod`와 `go_router`뿐이고 둘 다 순수 Dart라, Flutter 툴이 CocoaPods 통합 자체를 건너뛰고 `Podfile`을 만들지 않는다. `set -euo pipefail` 아래에서 `No Podfile found in the project directory`가 스크립트를 중단시켜 `flutter build ios`에 도달하지 못했다.

이제 `ios/Podfile` 존재 여부로 분기한다. 없으면 알리고 넘어가며, `pod` 미설치 하드 실패도 Podfile이 실제로 있는 경우로 한정했다. iOS 네이티브 코드를 가진 플러그인이 추가돼 Flutter가 `Podfile`을 생성하면 이 분기가 스스로 되살아난다. 그때는 `Podfile`과 `Podfile.lock`이 커밋 대상이 맞다(`.gitignore`는 `app/ios/Pods/`만 무시한다).

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

완료: 지역구 홈의 의원·후보·공약 카드, 모든 수치의 출처 뱃지와 기준일, 주민 평가 읽기, 미인증 작성 차단, iOS 빌드와 시뮬레이터 검증, 390dp 골든.

- 온보딩 3단계와 주소 검색/GPS 실패 폴백
- 평가 작성 화면. 게이트 통과 후 진입할 대상이 아직 없다
- 공약 상세와 `/pledges/:id` 딥링크
- Freezed/Riverpod generator 호환 버전 spike 후 codegen 도입 여부 결정
- 거주지 인증 백엔드 계약과 opaque verification token 저장

위 셋 중 **푸시되는 화면이 처음 생기는 것**(공약 상세 또는 평가 작성)에서 `PlatformAdaptiveRoute`의 스와이프 백을 함께 검증해야 한다. 지금은 검증 대상 자체가 없다.

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

기준: Flutter 3.44.8 / Dart 3.12.2. Windows 11에서 시작해 macOS 27.0 / Xcode 26.6에서 마무리했다.

| 항목 | 상태 | 비고 |
|---|---|---|
| 원본 README/HTML 확인 | 완료 | UTF-8 기준 |
| Flutter/Dart 탐지 | 완료 | `frameworkVersion 3.44.8`, `dartSdkVersion 3.12.2` |
| Bootstrap SDK 가드 | 완료 | 두 버전 조건 모두 통과 |
| `flutter create` | 완료 | android/ios 생성. `pubspec.yaml`·`analysis_options.yaml`·`.fvmrc` diff 0 |
| `flutter pub get` | 완료 | `pubspec.lock` 생성 및 커밋 |
| `dart format` | 완료 | 최초 19개 중 16개 재포맷, 이후 재실행 시 0 changed |
| `flutter analyze` | 완료 | `No issues found!` |
| `flutter test` | 완료 | 54개 통과 (골든 7 포함) |
| bootstrap 전체 체인 | 완료 | 종료 코드 0. macOS에서 iOS 빌드까지 포함해 재확인 |
| 코드 생성 | 보류 | 해석된 analyzer 12.1.0. 호환 조합 spike 필요 |
| `flutter doctor` | 완료 | macOS에서 `No issues found!`. Android·Xcode 툴체인 모두 √ |
| Android 빌드 | 완료 | `flutter build apk --debug` 성공. APK 패키지명 `com.democracy.kr` 확인 |
| 에뮬레이터 실행 | 완료 | AVD `democracy_api36` (Pixel 5, API 36). fixture 기반 세로 흐름 확인. logcat 오류 0건 |
| iOS 빌드 | 완료 | `flutter build ios --no-codesign` → `Runner.app` 16.4MB. **저장소 최초 컴파일** |
| CocoaPods | 해당 없음 | 순수 Dart 의존성뿐이라 Flutter가 통합을 생성하지 않는다. 위 「bootstrap.sh의 CocoaPods 분기」 참고 |
| iOS 시뮬레이터 실행 | 완료 | iPhone 17 Pro / iOS 27.0. 아래 「iOS 시뮬레이터에서 확인한 것」 |
| 390dp 골든 | 완료 | Android/iOS 각 3화면, 390×844px. macOS CI job에서 검증 |

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
| 5탭 전환과 각 탭 상태 보존 | 완료. `app_shell_test.dart`가 브랜치별 스크롤 오프셋 보존을 증명한다 |
| 390dp Android/iOS 골든 | 완료 |

**8/8.** `docs/INITIAL_PLAN.md`가 요구하는 필수 테스트가 전부 이행됐다.

### 에뮬레이터에서 확인한 것

AVD는 `pixel_5` 프로파일(1080×2340 @440dpi = 393×851dp)로 만들었다. 목업 기준 390dp에 가장 가깝다.

- 온보딩이 셸 밖에서 열린다. 게이트의 `인증하러 가기`로 복귀했을 때 하단 탭바가 없다.
- `나중에 인증하기` → 홈이 `읽기 전용` 칩으로 진입한다.
- 홈이 fixture에서 의원 카드, 출처 뱃지가 붙은 지표 3종, 3중 부호화된 공약 상태를 렌더링한다.
- `평가 작성하기` 탭 시 `주민 인증이 필요합니다`가 뜨고 작성이 차단된다.
- 떠 있는 캡슐 탭바가 스크롤에 따라 축소·복원된다.

이전 인계가 남긴 미확인 두 가지는 닫혔다. **탭별 스크롤 위치 보존**과 **셸의 스크롤 축소 배선**은 실제 화면이 자라기를 기다리는 대신 `app/test/features/shell/app_shell_test.dart`가 자체 브랜치로 증명한다. 실제 화면 높이에 단언을 묶으면 콘텐츠가 바뀔 때마다 셸과 무관하게 깨지기 때문이다.

### iOS 시뮬레이터에서 확인한 것

iPhone 17 Pro / iOS 27.0. 위젯 테스트로만 검증돼 있던 iOS 분기를 행동으로 확인했다.

- `CupertinoNavigationBar`가 중앙 정렬 타이틀로 렌더링된다. `preferredSize`가 `kToolbarHeight` 고정이지만 레이아웃이 밀리지 않는다.
- 떠 있는 캡슐 탭바가 홈 인디케이터 위에 정상 안착한다.
- 스크롤 시 캡슐이 축소되고 라벨이 사라진다. 선택 캡슐이 목적지 사이를 슬라이드한다.
- 미인증 상태로 `평가 작성하기`를 누르면 `CupertinoAlertDialog`가 뜨고 작성이 차단된다.
- `인증하러 가기`로 온보딩에 복귀하면 하단 탭바가 없다. Android와 동일하다.
- 출처 뱃지, 후보 가나다순, 3중 부호화된 공약 상태가 모두 정상이다.

**미검증 2건:**

- `PlatformAdaptiveHaptics` — 시뮬레이터에 햅틱 하드웨어가 없다. 실기기가 필요하고, 실기기 설치에는 아직 미정인 서명 계정이 필요하다.
- `PlatformAdaptiveRoute`의 스와이프 백 — **검증 대상이 아직 존재하지 않는다.** 아래 항목 참고.

### 스와이프 백은 아직 검증할 수 없다

`lib/` 전체에 `context.push`가 없다. 모든 네비게이션이 `context.go`(스택 교체)이고, 탭 전환은 `StatefulNavigationShell.goBranch`다. 즉 **푸시된 라우트가 하나도 없어서** `PlatformAdaptiveRoute`가 만드는 `CupertinoPage`의 스와이프 백 제스처는 작용할 대상이 없다.

백로그의 공약 상세(`/pledges/:id`)나 평가 작성 화면처럼 실제로 푸시되는 첫 화면이 생기는 시점에 함께 검증해야 한다.

### 실행 중인 앱에서 게이트가 통과 불가

`AddressState.isVerified`는 `status == verified && verification != null`을 요구한다(`address_state.dart:56-57`). 그런데 온보딩은 `requestVerification`(pending)과 `continueReadOnly`(unverified)만 호출하고, **`acceptVerification`을 호출하는 코드가 앱에 없다.** 테스트에만 있다.

따라서 실행 중인 앱에서 `VerifiedGate`는 절대 통과할 수 없고, 인증된 작성 경로는 위젯 테스트로만 도달한다. 게이트의 결함이 아니라 거주지 인증 백엔드 계약(M2)이 아직 없기 때문이다. 그 계약이 정해지기 전에는 평가 작성 화면을 붙여도 실기기에서 열리지 않는다.

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
- **실행 중인 앱에서 `VerifiedGate`가 통과 불가.** 위 「실행 중인 앱에서 게이트가 통과 불가」 참고. 인증된 작성 경로는 위젯 테스트로만 도달한다.
- **축소된 탭바가 placeholder 탭에서 펴지지 않는다.** 셸이 `ScrollUpdateNotification`에서만 재확장하는데(`app_shell.dart:65-68`) 스크롤할 것이 없는 화면은 알림을 보내지 않는다. `app_shell_test.dart`가 현재 동작으로 고정해 뒀다. 오프셋 0인 브랜치에서 바를 펼지 여부는 제품 결정이라 바꾸지 않았다.
- 골든이 정확 일치가 아니라 0.5% 허용 오차로 비교된다(`test/golden/flutter_test_config.dart`). macOS 버전이 다르면 안티에일리어싱만으로 0.04%가 어긋나 CI가 러너 이미지에 따라 깨지기 때문이다.
- `app_router.dart`의 redirect 가드는 `ref.read`를 쓰고 `refreshListenable`이 없어 네비게이션 시점에만 평가된다. 주소 상태가 바뀌어도 현재 화면은 그대로다.
