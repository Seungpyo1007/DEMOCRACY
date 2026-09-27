# DEMOCRACY

[![verify](https://github.com/Seungpyo1007/DEMOCRACY/actions/workflows/verify.yml/badge.svg?branch=develop)](https://github.com/Seungpyo1007/DEMOCRACY/actions/workflows/verify.yml?query=branch%3Adevelop)
[![Flutter 3.44.8](https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white)](https://docs.flutter.dev/release/archive)
[![license: AGPL-3.0](https://img.shields.io/github/license/Seungpyo1007/DEMOCRACY?color=blue)](LICENSE)

정당색이나 감정 말고 확인 가능한 정치 데이터로 판단하게 돕는 앱. Flutter 앱 + Supabase 백엔드.

빌드 배지는 통합 브랜치 `develop` 기준. `main`은 마지막 릴리스(`v0.1.0`)라 보통 뒤처져 있고 그게 정상.

## 구성

- `app/`: Flutter 앱. 기능별 `{data,domain,application,presentation}` 계층 + Android/iOS 프로젝트
- `app/assets/fixtures/`: 샘플 데이터. 실데이터 아님. BFF 응답 모양의 기준(계약)이기도 함
- `server/`: Supabase(Postgres, Edge Functions, pg_cron). 공공 API 수집 + 앱이 읽는 BFF + 계정. 자세한 건 `server/README.md`
- `design_handoff_democracy_app/`: 원래 제품 명세랑 HTML 디자인 레퍼런스. 앱 코드로 복사하지 않음
- `docs/INITIAL_PLAN.md`: MVP 범위, 순서, 완료 조건
- `docs/ELECTION_LAW.md`: 공직선거법 조문이랑 코드에서 막는 지점, BFF가 할 일, 넣으면 안 되는 것
- `HANDOFF.md`: 지금 상태랑 다음 사람한테 넘길 것
- `CONTRIBUTING.md`: 브랜치 규칙, 검증 절차
- `tool/bootstrap.sh`, `tool/bootstrap.ps1`: 툴체인 버전 확인 + 기본 검증. macOS면 iOS 빌드까지

## 요구 사항

| 항목 | 값 |
|---|---|
| Flutter | 3.44.8 (고정) |
| Dart | 3.12.2 |
| Application ID / Bundle ID | `com.democracy.kr` |
| Android | compileSdk 37 · targetSdk 36 · minSdk 24 |
| 서버 | Deno 2.9, Supabase CLI |

compileSdk만 37인 건 `flutter_secure_storage` 11 때문. bootstrap 스크립트는 Flutter 3.44.8이 아니면 파일 건드리기 전에 멈춤.

## 시작

```bash
./tool/bootstrap.sh          # macOS·Linux
```

```powershell
.\tool\bootstrap.ps1 -Organization "com.democracy.kr"   # Windows
```

몇 번 돌려도 같음. 네이티브 프로젝트는 이미 커밋돼 있어서 `pub get → format → analyze → test`만 돎.

그냥 `flutter run` 하면 전부 샘플 데이터로 뜸. 실제 서버에 붙이려면:

```bash
cp app/dart_defines.example.json app/dart_defines.json   # 주소랑 anon 키 채움. gitignore라 커밋 안 됨
cd app && flutter run --dart-define-from-file=dart_defines.json
```

폰에 릴리스로 넣을 때도 `flutter build ios --release --dart-define-from-file=dart_defines.json`. 이거 빼고 빌드하면 전부 샘플 데이터로 뜸

로그인 제공자 키(카카오, Google, Android에서 Apple)는 따로 넣어야 함. 키 없는 제공자는 버튼이 안 나오고 이메일 로그인만 됨. 넣는 곳은 `app/ios/Flutter/Keys.xcconfig.example`, `server/README.md` 참고.

서버 테스트:

```bash
cd server && deno task ci
```

## 상태

- 명세의 6화면(온보딩, 지역구 홈, 공약 트래커, AI, 커뮤니티, 개표) + 역사 탭 전부 있음
- 읽기는 계정 없이 됨. 글쓰기(리뷰, 채팅, 이행 제보)는 로그인 + 주민 인증 필요
  - 로그인: Apple, 카카오, Google, 이메일 코드. 실명·휴대폰 인증은 안 함 (`docs/ELECTION_LAW.md`)
  - 주민 인증: 서버가 주소로 선거구 확인하고 토큰 발급. 자기 신고라 실거주 증명은 아님. 주소는 안 남김
- 서버는 Supabase에 배포돼 있고 국회·선관위 실데이터 들어가 있음 (지역구 254, 의원 299, 20~22대 당선인, 법안·표결)
- 주소 → 선거구: 공직선거법 [별표 1] 구역표를 지금 행정동 코드로 옮긴 매핑표(`server/data/`)로 찾음. 한 건물이 선거구 두 개에 걸치면 결과에서 뺌
- 개표 탭은 서버 모드에서 22대 최종 결과를 보여 줌 (254개 선거구, 선관위 투·개표 정보, `mode=counts` 적재 후). 실시간 개표는 아직 없음
- 실데이터 없는 기능(AI, 평가, 채팅)은 서버 모드에서 「준비 중」. 샘플로 채우지 않음
- 모든 외부 수치는 원문 주소랑 가져온 시각이 있어야만 화면에 나옴. 출처 배지 누르면 원문 열림
- 지도 타일은 Google Maps 키가 없어서 회색 격자. 개표율 색칠, 선택, 내 지역구 테두리는 동작함

Android는 디버그 빌드랑 에뮬레이터, iOS는 실기기랑 시뮬레이터에서 봄. 390dp Android/iOS 골든으로 화면 고정. 자세한 건 `HANDOFF.md`.

## 기여

Git Flow. 기본 브랜치는 `develop`, `main`은 출시된 것만. 규칙이랑 검증 절차는 [CONTRIBUTING.md](CONTRIBUTING.md).

## 라이선스

[GNU AGPL-3.0](LICENSE). 고쳐서 네트워크 서비스로 돌려도 소스 공개해야 함.
