# DEMOCRACY 초기 인계

기준 시각: 2026-07-30 Asia/Seoul

## 현재 상태

- 원본 디자인 번들은 `design_handoff_democracy_app/`에 그대로 보존했다.
- Flutter 앱 골격은 `app/`에 추가했다.
- 온보딩 외부 라우트와 5탭 `StatefulShellRoute.indexedStack` 구조를 잡았다.
- 디자인 토큰, 지역구 식별자·검증 증거를 포함한 주소 상태, 출처 메타데이터, `VerifiedGate`를 추가했다.
- 라우트·앱바·탭바·다이얼로그·햅틱은 표준 플랫폼 폴백을 구현했고, 네이티브 인증은 경계 인터페이스만 정의했다.
- 트래커, AI 분석, 커뮤니티, 개표는 의도적으로 placeholder다.
- 이 작업공간은 아직 Git 저장소가 아니다.
- 현재 머신의 PATH에는 Flutter와 Dart가 없다.

따라서 Dart 포맷, 의존성 해석, 정적 분석, 단위·위젯 테스트, Android/iOS 빌드는 실행하지 못했다. 소스는 후속 실행자가 SDK 준비 직후 검증해야 한다.

## 도구 기준

- 권장 고정 버전: Flutter 3.44.8 / Dart 3.12.2
- `app/.fvmrc`에 Flutter 버전을 기록했다.
- `pubspec.yaml`의 Riverpod과 go_router 버전은 2026-07-30 pub.dev 기준으로 잡았다.
- 최신 Freezed 3.2.5와 Riverpod generator 4.0.8은 각각 `analyzer <11`, `analyzer ^13`을 요구해 함께 해석되지 않는다. 현재 코드가 생성 파일을 쓰지 않으므로 codegen 의존성은 M1 호환성 spike까지 제외했다.
- lockfile은 SDK가 없는 상태에서 임의 생성하지 않았다.

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

1. 사용자에게 실제 조직 도메인과 앱 식별자를 확인한다.
2. Flutter 3.44.8을 설치하거나 FVM으로 연결한다.
3. Git 초기화 여부를 사용자에게 확인하고 bootstrap 전 초기 커밋 또는 백업을 만든다.
4. `.\tool\bootstrap.ps1 -Organization "<확정 도메인>"`을 실행한다.
5. 생성된 Android 설정에서 target/compile API 34 이상을 확인한다. README의 “API 34+”가 minSdk 의미인지는 사용자와 별도 확정한다.
6. iOS 최종 빌드는 macOS/Xcode 환경에서 검증한다.
7. 포맷·분석·테스트 오류를 모두 고친 뒤 첫 기능 작업을 시작한다.
8. `SourceMetadata` 검증을 DTO 파싱/리포지토리 경계에도 적용한다.
9. Fake repository와 JSON fixture로 온보딩 → 홈 → 공약 → 주민 평가 세로 흐름을 완성한다.

## Claude Code 백로그

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

- Bundle ID/Application ID와 서명 계정
- dev/staging/prod flavor
- “주소 인증”의 법적·기술적 검증 주체와 원주소 폐기 정책
- 국회·선관위·주소·지도 API 계약, 키, 이용 조건
- 딥링크 도메인과 URL 규칙
- AI 모델, 가중치, 공개 범위, 비용 상한, 편향 감사 기준
- 커뮤니티 moderation 및 신고 처리 정책
- Archivo/Pretendard 폰트 파일·사용권과 후보 사진 사용권. 현재는 시스템 폴백 상태
- iOS Liquid Glass 패키지 최종 선택

## 검증 기록

| 항목 | 상태 | 비고 |
|---|---|---|
| 원본 README/HTML 확인 | 완료 | UTF-8 기준 |
| YAML/JSON 및 PowerShell 문법 | 완료 | 로컬 정적 파서 통과 |
| Dart 구분자·내부 import 순환 검사 | 완료 | 19개 파일, 오류·순환 0 |
| 기능 계층의 직접 플랫폼 분기 검사 | 완료 | 0건 |
| Flutter/Dart 탐지 | 실패 | PATH 및 일반 설치 위치에 없음 |
| Bootstrap SDK 가드 | 완료 | SDK 부재 시 파일 변경 전에 명시적으로 중단 |
| `flutter pub get` | 미실행 | SDK 필요, codegen 묶음은 호환성 문제로 제외 |
| 코드 생성 | 보류 | M1에서 호환 패키지 조합 spike |
| `dart format` | 미실행 | SDK 필요 |
| `flutter analyze` | 미실행 | SDK 필요 |
| `flutter test` | 미실행 | SDK 필요 |
| Android 빌드 | 미실행 | SDK/JDK 필요 |
| iOS 빌드 | 미실행 | macOS/Xcode 필요 |
