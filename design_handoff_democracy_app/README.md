# Handoff: DEMOCRACY — 정치 데이터 플랫폼 Flutter 앱

## Overview
"당이 아닌 인물로, 감정이 아닌 데이터로 투표하는 세상"을 미션으로 하는 정치 데이터 플랫폼 앱.
6개 핵심 화면(온보딩/주소 인증, 지역구 대시보드, 공약이행률 트래커, AI 맞춤 후보 분석, 주민 평가·커뮤니티, 개표 지도)을 **iOS(iOS 26 Liquid Glass) / Android(Material 3) 분리 설계**로 구현한다.

## About the Design Files
`DEMOCRACY UI Guide.dc.html`은 **HTML로 제작된 디자인 레퍼런스**다. 프로덕션 코드가 아니며 그대로 복사하지 않는다.
과업은 이 디자인을 **Flutter(Dart) 앱으로 재구현**하는 것이다. 아래 명세와 HTML 목업(브라우저에서 열어 확인)을 기준으로 삼는다.

## Fidelity
**High-fidelity.** 색상·타이포·간격·컴포넌트 셰이프·카피가 최종 의도다. 픽셀 퍼펙트로 재현하되, 수치는 CSS px = Flutter dp로 치환한다. 목업 폭 390dp 기준.

---

## 기술 스택 (필수)

```yaml
# 상태/DI
flutter_riverpod: ^3.x   # + riverpod_generator, freezed, json_serializable
# 라우팅
go_router: # ShellRoute 5탭, 딥링크(공약 상세/판정문 공유 URL)
# 네트워크/실시간
dio + retrofit, web_socket_channel(채팅), flutter_client_sse(개표), LLM 스트리밍 SDK
# 시각화/지도
fl_chart(도넛·바·레이더·라인), google_maps_flutter(hybrid composition, GeoJSON 폴리곤), flutter_animate
# 네이티브 통합
home_widget, live_activities(iOS), local_auth, passkeys, geolocator + geocoding, firebase_messaging, app_links
# iOS Liquid Glass (직접 그리지 말 것 — 패키지 사용)
native_liquid_glass        # UiKitView로 순정 Apple Liquid Glass 임베드, iOS 26+ 자동, 구버전 시스템 폴백
cupertino_native_better    # 탭바·버튼·슬라이더·스위치 등 네이티브 컨트롤 (하이브리드 컴포지션)
liquid_glass_widgets       # 네이티브 컨트롤이 없는 커스텀 카드/패널용 셰이더 글라스 (GlassScaffold/GlassTabBar, Reduce Transparency 자동 대응)
# 저장/품질
drift(오프라인 캐시), flutter_secure_storage(주소 토큰), sentry_flutter, patrol(E2E)
```

## 플랫폼 분기 전략 (핵심 규칙)
- 화면 구조·데이터·차트·콘텐츠 위젯(카드 내용, 타임라인, 차트)은 **100% 공유**.
- 분기는 위젯 내 if문이 아니라 `PlatformAdaptive*` 래퍼 6종으로만: 라우트 전환, 앱바, 탭바, 다이얼로그, 햅틱, 인증.
- 네이티브 채널 코드(WidgetKit/Glance, ActivityKit)는 `packages/native_*`로 격리.
- **iOS**: Liquid Glass — 반투명 블러 서피스, 플로팅 캡슐 탭바(하단 여백 14, radius 30), 캡슐 CTA(radius 24~27), 유리 카드(radius 18~22). CupertinoPageRoute 스와이프백, Live Activities(개표), WidgetKit 홈 위젯, App Intents/Siri, Face ID/패스키.
- **Android (API 34+, M3)**: 불투명 서피스 — 카드 radius 12, 칩 radius 8, 버튼 pill(radius 24), Extended FAB(radius 16, 제보/평가 작성), NavigationBar 80dp(pill 인디케이터), DraggableScrollableSheet(상단 radius 28 + 드래그 핸들), Predictive Back(PopScope), Credential Manager 패스키, Glance 홈 위젯, FCM Live Updates. **Material You 동적 컬러는 의도적으로 비활성화**(당색 우연 일치 리스크).

---

## Design Tokens

### Color
| 토큰 | 값 | 용도 |
|---|---|---|
| Ink | `#201E1D` | 기본 텍스트, 채워진 요소 |
| Ground | `#F3F2F2` | 배경 |
| Signal | `#EC3013` | 브랜드·CTA·활성 탭 **전용** (데이터 의미로는 '번복'에서만 재사용) |
| Neutral 100–900 | 회색 램프 | 보조 텍스트/보더/비활성 |
| 이행 완료 | `oklch(0.58 0.13 155)` ≈ `#3D9A63` | 초록 |
| 진행 중 | `oklch(0.72 0.13 80)` ≈ `#C9922E` | 앰버 |
| 미이행 | Neutral 400 ≈ `#B8B4B1` | 회색 |
| 번복 | Accent 700 ≈ `#A82310` | 딥 레드 |
| iOS 배경 | `linear-gradient(165deg,#EDEAE7,#F7F6F5 45%,#E6E3E0)` | 글라스가 읽히는 그라디언트 |
| iOS 글라스 서피스 | `rgba(255,255,255,.5~.65)` + blur 14–24 + 보더 `rgba(255,255,255,.7~.8)` 1px + 그림자 `0 10px 28px rgba(32,30,29,.09~.14)` | |

이행 상태는 항상 **색+아이콘+텍스트 3중 부호화**: ✓ 이행 완료 / ◐ 진행 중 / — 미이행 / ↩ 번복.

### Typography (Archivo, 국문 Pretendard fontFamilyFallback)
Display 28/800 · H1 22/800 · 화면 타이틀 19/800 · H2 17/700 · Body 15/400(lh 1.55) · Caption 12/400 · Data-Label 11/600 letter-spacing .08em UPPERCASE. 최소 폰트 10sp.

### Shape & Elevation
- **공용 문서/브랜드 규격**: radius 0, 그림자 대신 1–2px 보더 — 단 앱 UI에서는 플랫폼 셰이프가 우선(위 분기 규칙).
- Spacing 4dp 그리드: 4/8/12/16/24/32/48. 화면 좌우 패딩 20.

### 정치적 중립 규칙 (기능 요구사항 수준으로 준수)
1. **N-1 당색 금지** — 정당은 회색 아웃라인 태그+텍스트로만. 지도 채색은 당색이 아닌 개표율 농도(회색 램프).
2. **N-2 동일 규격 카드** — 모든 후보 카드 크기·사진·정보 순서 동일, 기본 정렬 가나다순, 정렬 기준 항상 노출.
3. **N-3 흑백 인물 사진** — 프로필 사진 grayscale 처리.
4. **N-4 출처 우선** — 모든 수치에 출처 뱃지+원문 URL. 모델에 `sourceUrl, fetchedAt` 필수 필드, 출처 없는 수치는 렌더 계층 assert로 차단.
5. **N-5 판단 언어 금지** — UI 카피는 서술형만("출석률 92%").
6. **N-6 AI 결과 = 참고 자료** — AI 매칭 화면 상단 고지 배너 고정(pinned) + '오픈소스 알고리즘 검증' 링크.

---

## Screens

### 1. 온보딩 & 주소 인증 (`/onboarding`)
- 3-스텝: 주소/GPS → 프로필 칩·슬라이더(선택) → 완료. 상단 스텝 프로그레스(높이 2, iOS는 직선 / Android는 radius 2 + accent).
- 구성(위→아래): 헤드라인 26/800 → 개인정보 안내 캡션 → 주소 검색 필드(카카오/도로명 자동완성 BottomSheet) → "◎ 현재 위치(GPS)로 자동 설정" 버튼 → 감지된 지역구 카드("서울 마포구 을" + `✓ 인증 가능` 초록 뱃지) → 프로필 FilterChip Wrap(30대/자영업/1인 가구/부동산/세금/복지/교육/청년…) → 관심도 Slider(divisions 4) → 하단 CTA "지역구 설정 완료" + "나중에 인증하기" 텍스트 버튼.
- 위젯: `Scaffold > SafeArea > Column [ LinearProgressIndicator, Expanded > ListView, BottomAppBar > FilledButton ]`
- 스킵 시 읽기 전용 모드 고지. GPS: geolocator 권한 → 역지오코딩 → 지역구 카드 fade-in, 실패 시 수동 선택 폴백.
- 인증 상태 enum: `unverified / pending / verified` — 전역 게이트.

### 2. 지역구 의원 대시보드 (`/` 홈)
- 고정 헤더: "내 지역구" 라벨 + "서울 마포구 을 ▾"(19/800, nowrap) + `✓ 주민 인증됨` 뱃지.
- 현직 의원 카드: 흑백 사진 64×80, 이름 17 + 당 태그("가나당 · 재선"), 3열 스탯(92% 출석률 / 31 발의 법안 / 58% 공약 이행 — 수치 16/800), 내부 TabBar(공약·법안·출석·표결, 활성 탭 하단 accent 보더), 공약 리스트(제목 + 상태 뱃지), 푸터 "🔗 출처: 열린국회정보 · 선관위 공보" + "전체 24건 →".
- 출마 후보 가로 스크롤(150dp 카드, 가나다순, 스크롤 피크 의도적), 정렬 기준 셀렉터 노출.
- 하단 5탭: 지역구 / 트래커 / AI 분석 / 커뮤니티 / 개표. iOS = 플로팅 글라스 캡슐 바(활성 항목 accent 캡슐), Android = NavigationBar 80dp(아이콘 pill 인디케이터 + 라벨).
- 위젯: `CustomScrollView [ SliverAppBar(pinned), SliverToBoxAdapter(의원 카드 + TabBarView), 가로 ListView ]`. Pull-to-refresh. 탭 콘텐츠 스와이프 전환, 출석/표결 탭에 fl_chart 스파크라인, 출처 뱃지 탭 → 외부 브라우저.

### 3. 공약이행률 트래커 (`/tracker`)
- 3단 줌: ① 도넛(fl_chart PieChart, 중앙 58% 종합 이행률, 4분포: 이행 9건 38% / 진행 8건 33% / 미이행 5건 21% / 번복 2건 8%) + 범례 ② 카테고리 바(교통 72% / 주거 55% / 복지 41%, 800ms ease-out 채움 1회) ③ 개별 공약 → 판정 타임라인.
- 판정 파이프라인 타임라인(3노드): AI 1차 판단 → 시민 제보 12건 → 전문가 위원회 최종 판정("판정문 보기 →"). '번복' 판정엔 근거 원문 diff 링크 필수.
- 제보 CTA: iOS = 하단 글라스 바 내 캡슐 버튼 "이행 제보하기" / Android = Extended FAB "＋ 이행 제보". verified만 활성, 미인증 탭 시 인증 유도 BottomSheet.
- 도넛 섹션 탭 → 해당 상태로 목록 필터 + 햅틱.

### 4. AI 맞춤 후보 분석 (`/ai-match`)
- 헤더: "나에게 유리한 후보는?" + 프로필 요약(탭 시 수정 sheet).
- 중립 고지 배너(SliverPersistentHeader pinned): "ⓘ 공약 원문 기반 참고 자료 · 공인 평가 아님 · 오픈소스 알고리즘 검증 →".
- 1위 MatchCard: 다크 헤더 바("1위 매칭" + 87점 20/800) → 프로필 행(흑백 56×70 + 이름 + 당 태그 + 근거 요약) → fl_chart RadarChart(5축 = 사용자 관심 분야: 세금 92/부동산 88/복지 74/교육/청년, accent 반투명 필) + 항목별 점수 바(AnimatedFractionallySizedBox) → ExpansionTile "왜 유리한가"(LLM 근거 + 공보 원문 링크, 스트리밍 토큰 렌더).
- 2·3위: 컴팩트 행(순위 + 이름 + 당 태그 + 점수), 탭 시 확장.
- 하단 CTA "상세 분석 리포트 (프리미엄)". 분석 중 skeleton + "분석 중 · 공약 42건 대조". 레이더 축 탭 → 해당 근거로 스크롤. 산출 로그(가중치·입력값) raw JSON 조회 페이지.

### 5. 주민 평가 & 커뮤니티 (`/community`)
- `DefaultTabController(3)`: 주민 평가 / 지역 채팅 / 정책 토론.
- 평가 탭: 요약 헤더(평균 3.8 30/800 + "주민 412명 평가" + 4축 바: 소통 4.1 / 공약이행 3.5 / 지역발전 3.9 / 도덕성 3.7) → 리뷰 카드(작성자 + `✓ 인증` 초록 뱃지 + 별점 + 본문).
- 작성: showModalBottomSheet — 4축 별점(드래그 지원) + TextField + 익명/실명 Switch(작성 후 변경 불가 고지).
- 안내: "ⓘ 주소 인증 주민만 작성 가능 · 조작 방지 알고리즘 · 혐오·허위정보 자동 필터링"(dashed 보더 박스).
- 채팅 탭: ListView.reverse + WebSocket StreamBuilder, 전송 전 혐오/허위 감지 인터셉트. 토론 탭: 법안 발의 시 이슈 스레드 자동 생성.
- CTA: iOS = 글라스 바(익명 pill 토글 + "평가 작성하기" 캡슐) / Android = 익명 토글 pill + "✎ 평가 작성" Extended FAB.

### 6. 개표 및 선거 결과 (`/results`)
- 헤더: "실시간 개표" + "제23대 총선 · 개표율 67.2% · LIVE"(적색 dot).
- `Stack [ GoogleMap(선관위 GeoJSON Polygon, fillColor = 개표율 농도 회색 램프 — 당색 금지, 내 지역구 accent 아웃라인 고정, 지도 스타일 무채색 클라우드 스타일링), 결과 패널 ]`.
- 결과 패널: iOS = 지도 위 플로팅 글라스 카드(-22 오버랩) / Android = DraggableScrollableSheet(min 0.35, radius 28, 드래그 핸들). 내용: 지역구명 + 개표 71% + 출처 → 후보 득표 바(박서연 48.2% Ink / 김민준 44.7% Neutral 500 / 이도현 7.1% Neutral 400, TweenAnimationBuilder 증가만) → SegmentedButton(실시간/역대 결과/여론조사 비교).
- 역대: LineChart 연도별. 여론조사: 공인(갤럽·리얼미터) 실선 vs 앱 내 비공식 점선 + "공인 조사 아님" 상시 표기.
- 갱신: 선거일 SSE/30초 폴링(서버 헤더로 주기 제어), Polygon 탭 → 시트 확장 + 카메라 애니메이션, 핀치 줌 → 시도/지역구/읍면동 세분화.

---

## State Management (Riverpod)

```dart
enum AddressStatus { unverified, pending, verified }

final addressProvider  = AsyncNotifierProvider<AddressNotifier, AddressState>(...);
final districtProvider = Provider((ref) => ref.watch(addressProvider).district);
// 화면별: family + 자동 캐시
final legislatorProvider  = FutureProvider.family((ref, districtId) => api.legislator(districtId));
final pledgeStatsProvider = FutureProvider.family(...);
final aiMatchProvider     = StreamProvider.family(...);      // LLM 스트리밍
final liveResultsProvider = StreamProvider.family((ref, id) => sse.watch('/results/$id'));
```

- 주소 인증 변경 → `ref.invalidate(districtProvider)` 한 줄로 전 화면 갱신.
- 작성/제보/채팅 버튼은 전부 단일 `VerifiedGate` 래퍼 위젯으로 게이트(disabled + 인증 유도 sheet).
- 리포지토리 3계층 분리: REST(프로필·공약) / SSE·WS(개표·채팅) / LLM 스트림.
- 모든 응답 모델 `sourceUrl, fetchedAt` 필수. 캐시 표시 시 "○월 ○일 기준" 스탬프.

## Assets
- 인물 사진·지도는 목업에서 플레이스홀더(회색 그라디언트/그리드). 실서비스: 선관위 공보 사진(grayscale 필터 적용), 선관위 지역구 GeoJSON.
- 아이콘: Lucide (flutter_lucide 등).

## Files
- `DEMOCRACY UI Guide.dc.html` — 전체 디자인 레퍼런스(디자인 시스템, 화면별 iOS/Android 목업 나란히 배치, 위젯 트리, 인터랙션, 상태 관리, 플랫폼 분리 설계). 브라우저에서 열어 확인.
- `support.js`, `_ds/` — HTML 프리뷰 런타임/스타일. 구현과 무관, 참조용 HTML을 열기 위해 동봉.
