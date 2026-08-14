# DEMOCRACY

[![verify](https://github.com/Seungpyo1007/DEMOCRACY/actions/workflows/verify.yml/badge.svg?branch=develop)](https://github.com/Seungpyo1007/DEMOCRACY/actions/workflows/verify.yml?query=branch%3Adevelop)
[![Flutter 3.44.8](https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white)](https://docs.flutter.dev/release/archive)
[![license: AGPL-3.0](https://img.shields.io/github/license/Seungpyo1007/DEMOCRACY?color=blue)](LICENSE)

정당색이나 감정 대신 검증 가능한 정치 데이터로 판단하도록 돕는 Flutter 앱의 초기 작업공간이다.

빌드 상태는 통합 브랜치인 `develop` 기준이다. `main`은 마지막 릴리스(`v0.1.0`) 지점이라 대개 뒤처져 있으며, 그것이 정상이다.

- `design_handoff_democracy_app/`: 원본 제품 명세와 HTML 디자인 레퍼런스. 앱 코드로 복사하지 않는다.
- `app/`: Flutter 앱. 기능별 `{data,domain,application,presentation}` 계층과 생성된 Android/iOS 프로젝트.
- `app/assets/fixtures/`: 샘플 payload. 실서비스 데이터가 아니다.
- `docs/INITIAL_PLAN.md`: MVP 범위, 순서, 완료 조건.
- `HANDOFF.md`: 현재 상태와 다음 실행자용 인계 사항.
- `CONTRIBUTING.md`: 브랜치 전략과 검증 절차.
- `tool/bootstrap.sh` · `tool/bootstrap.ps1`: 툴체인 가드와 기본 검증을 재현하는 스크립트. macOS에서는 iOS 빌드까지 이어진다.

## 요구 사항

| 항목 | 값 |
|---|---|
| Flutter | 3.44.8 (고정) |
| Dart | 3.12.2 |
| Application ID / Bundle ID | `com.democracy.kr` |
| Android | compileSdk 36 · targetSdk 36 · minSdk 24 |

`bootstrap.ps1`은 정확히 Flutter 3.44.8을 요구하며, 버전이 다르면 파일을 변경하기 전에 중단한다.

## 시작

Windows:

```powershell
.\tool\bootstrap.ps1 -Organization "com.democracy.kr"
```

이 스크립트는 멱등하다. `app/android`와 `app/ios`가 이미 있으면 생성을 건너뛰고 `pub get → format → analyze → test`만 수행한다. 네이티브 프로젝트는 이미 커밋돼 있으므로 재생성은 일어나지 않는다.

macOS·Linux:

```bash
./tool/bootstrap.sh
```

같은 버전 가드와 같은 검증 순서를 쓴다. macOS에서는 `flutter build ios --no-codesign`까지 이어서 수행한다.

`pod install`은 `ios/Podfile`이 있을 때만 돈다. 현재 직접 의존성이 모두 순수 Dart라 Flutter가 CocoaPods 통합을 생성하지 않으므로 이 단계는 건너뛴다. iOS 네이티브 코드를 가진 플러그인이 추가되면 자동으로 되살아난다.

## 상태

**명세서의 6화면이 전부 구현됐다.** 온보딩(3스텝) · 지역구 홈 · 공약 트래커 · AI 분석 · 커뮤니티 · 개표. placeholder는 남아 있지 않다.

데이터는 전부 번들된 샘플 payload와 fake repository 뒤에 있다. 화면은 repository 계약에만 의존하므로, 실제 API·LLM·SSE·WebSocket이 생기면 DI 교체로 들어온다. 모든 외부 수치는 원문 주소와 취득 시각을 통과한 경우에만 화면에 오르고, 출처 뱃지를 탭하면 원문이 열린다.

지도 타일은 Google Maps 키가 없어 목업과 같은 회색 격자다. 개표율 농도 채색·선택·내 지역구 아웃라인은 실제로 동작한다.

Android는 디버그 빌드와 에뮬레이터, iOS는 디바이스 빌드와 시뮬레이터에서 확인했다. 390dp Android/iOS 골든이 두 화면 규격을 고정한다. 자세한 인계 사항은 `HANDOFF.md`를 참고한다.

## 기여

Git Flow를 따른다. 기본 브랜치는 `develop`이고, `main`은 출시된 상태만 담는다. 브랜치 규칙과 검증 절차는 [CONTRIBUTING.md](CONTRIBUTING.md)에 있다.

## 라이선스

[GNU AGPL-3.0](LICENSE). 이 프로그램을 수정해 네트워크 서비스로 제공하는 경우에도 해당 소스를 공개해야 한다.

