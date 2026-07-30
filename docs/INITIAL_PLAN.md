# 초기 구현 계획

## 목표

전체 6화면을 한 번에 구현하지 않는다. 먼저 정치적 중립성과 출처 무결성을 구조로 강제하고, 주소 설정에서 지역구 정보와 주민 평가까지 이어지는 한 개의 세로 흐름을 완성한다.

## 범위 결정

HTML 디자인 가이드의 단계 구분을 기준으로 다음처럼 나눈다.

### MVP 1차

- 온보딩/주소 설정
- 지역구 홈
- 공약 목록·상세와 출처
- 주민 평가 읽기·작성 진입
- 주소 인증 상태와 쓰기 권한 게이트

### MVP 2차

- 공약이행률 트래커
- AI 맞춤 후보 분석
- 지역 채팅·정책 토론
- 개표 지도와 실시간 갱신
- 네이티브 위젯·Live Activities·FCM

MVP 2차 화면은 초기부터 5탭 라우트에 연결하되, 실제 서비스처럼 보이지 않는 명시적 placeholder만 둔다.

## 단계

### M0. 재현 가능한 기반

현재 인계 범위다.

- Flutter 버전과 최소 의존성 고정
- 원본 디자인 번들과 앱 소스 분리
- ProviderScope와 go_router 부트스트랩
- 온보딩 외부 라우트, 상태 보존 5탭 셸
- 색상·타이포·간격 토큰
- 플랫폼 폴백 5종과 네이티브 인증 계약
- `AddressStatus`, `districtProvider`, `VerifiedGate`
- `SourceMetadata`의 런타임 유효성 검증
- smoke/unit/widget 테스트 초안

완료 조건은 SDK 환경에서 `flutter analyze`와 `flutter test`가 통과하는 것이다.

### M1. Fake 데이터 세로 슬라이스

- 주소 수동 선택과 GPS 권한 거부 폴백
- Freezed/Riverpod generator 호환 조합 spike와 codegen 도입 결정
- 계정 인증과 거주지 인증 상태 분리
- Fake district/legislator/pledge/review repository
- 지역구 홈의 공약·의원·후보 콘텐츠
- 후보 기본 가나다순과 동일 카드 규격
- 주민 평가 읽기 및 `VerifiedGate` 작성 진입
- 로딩, 빈 상태, 오류, 오프라인 fixture
- 출처 URL과 취득 시각이 없는 fixture 거부 테스트

완료 조건은 네트워크 없이 온보딩 → 홈 → 공약 → 평가 진입 흐름이 작동하고 390dp 골든 테스트가 통과하는 것이다.

### M2. 실제 REST 연동

- BFF/API 계약 확정
- Dio/Retrofit client와 오류 모델
- 주소 원문을 앱에 오래 보관하지 않는 verification token 흐름
- 국회·선관위 출처 모델과 기준일 표시
- Drift 캐시와 stale 상태
- API 키 및 flavor 환경 분리

완료 조건은 Fake/실제 repository를 DI로 교체할 수 있고, 화면 코드가 전송 계층을 직접 참조하지 않는 것이다.

### M3. 실시간·AI·네이티브 확장

- SSE 개표와 폴링 폴백
- WebSocket 채팅과 재연결
- 서버 경유 LLM 스트리밍, 산출 근거와 raw audit log
- Google Map/GeoJSON
- iOS Liquid Glass 단일 패키지 spike
- WidgetKit/Glance와 Live Updates

각 항목은 독립 spike와 성능·접근성 검증 후 채택한다.

## 아키텍처 경계

```text
presentation → application/provider → domain ← repository contract
                                      ↑
                         data implementation
             REST      SSE/WS      LLM stream
```

- 화면은 repository 구현체나 API SDK를 직접 import하지 않는다.
- REST, SSE/WebSocket, LLM 스트림은 별도 인터페이스다.
- 외부 수치는 DTO 파싱 시 `sourceUrl`과 `fetchedAt`이 없으면 실패한다.
- 캐시 데이터에는 기준일과 stale 상태를 함께 전달한다.
- LLM과 주소 검증 비밀은 클라이언트가 아닌 BFF에 둔다.

## 라우트

| 경로 | 단계 | 초기 상태 |
|---|---|---|
| `/onboarding` | MVP 1차 | 기본 골격 |
| `/` | MVP 1차 | 기본 골격 |
| `/tracker` | MVP 2차 | placeholder |
| `/ai-match` | MVP 2차 | placeholder + 고지 |
| `/community` | 혼합 | 평가 진입 골격, 나머지 placeholder |
| `/results` | MVP 2차 | placeholder |

후속 딥링크 후보는 `/pledges/:id`, `/decisions/:id`, `/ai-match/log`다. 외부 도메인과 공유 정책 확정 전에는 활성화하지 않는다.

## 필수 테스트

- 출처 URL이 상대 경로이거나 스킴이 HTTP(S)가 아니면 거부
- 미인증 쓰기 액션은 실행되지 않고 인증 안내가 표시
- 인증된 쓰기 액션은 한 번만 실행
- 읽기 전용 온보딩 종료 후 홈 진입
- 5탭 전환과 각 탭 상태 보존
- 후보 가나다순 및 동일 정보 순서
- 상태 색상에 아이콘과 텍스트가 항상 병기
- 390dp Android/iOS 골든

## 위험과 선행 결정

- `local_auth`와 passkey는 거주지 증명이 아니다. 계정/기기 재인증과 거주지 검증을 분리한다.
- 세 Liquid Glass 패키지를 동시에 사용하면 PlatformView·z-order·성능 위험이 있다.
- Windows에서는 iOS 네이티브 구현을 최종 검증할 수 없다.
- 허위정보 자동 판정과 AI 후보 매칭은 법적·편향 위험이 있어 서버 정책과 감사 기준이 먼저다.
- “출처 누락 assert”는 release에서 무효이므로 생성자와 repository 경계에서 런타임 오류로 처리한다.
- `_ds_manifest.json`이 참조하는 일부 디자인 시스템 파일은 번들에 없으므로 HTML 목업과 README를 기준으로 한다.

## 초기 작업 중단선

기반 검증 전에 다음 작업으로 확장하지 않는다.

- 실제 API 키 발급 또는 외부 서비스 연결
- AI 모델 선택과 프롬프트 작성
- 지도·실시간 채널 구현
- 결제·프리미엄
- 네이티브 위젯과 알림
- 6화면 전체 픽셀 퍼펙트 구현
