<p align="center">
  <img src="docs/assets/logo.png" width="160" alt="DEMOCRACY 앱 아이콘">
</p>

<h1 align="center">DEMOCRACY</h1>

<p align="center">
  <a href="https://github.com/Seungpyo1007/DEMOCRACY/actions/workflows/verify.yml?query=branch%3Adevelop"><img src="https://github.com/Seungpyo1007/DEMOCRACY/actions/workflows/verify.yml/badge.svg?branch=develop" alt="verify"></a>
  <a href="https://docs.flutter.dev/release/archive"><img src="https://img.shields.io/badge/Flutter-3.44.8-02569B?logo=flutter&logoColor=white" alt="Flutter 3.44.8"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Seungpyo1007/DEMOCRACY?color=blue" alt="license: AGPL-3.0"></a>
</p>

내 지역구 국회의원이 뭘 약속했고 뭘 했는지, 정당색 말고 기록으로 보는 앱. 주소 하나 넣으면 선거구를 찾고 공약, 법안, 출석, 역대 선거, 개표 결과를 한 곳에 모아 보여 줌. 숫자마다 원문 출처가 붙어 있어서 눌러서 바로 확인할 수 있음.

## 주요 기능

- **내 지역구 찾기**: 도로명 주소나 현재 위치로 선거구를 찾음. 254개 선거구 전부. 주소는 찾는 데만 쓰고 저장 안 함
- **현직 의원**: 출석률, 대표 발의 법안, 표결 기록
- **공약 트래커**: 22대 당선인 공약 전체(선관위 선거공보 기준)와 이행 상태. 판정 전인 건 판정 전이라고 씀
- **역사**: 20~22대 선거 결과, 선거구가 어떻게 합쳐지고 나뉘었는지, 보궐·궐위
- **개표**: 22대 선거구별 최종 결과. 선거 기간 여론조사 공표 제한도 지킴
- **AI 대조**: 내 관심사와 의원 공약·법안을 폰 안에서 대조함 (Apple Foundation Models, Gemini Nano). 서버로 안 보냄
- **커뮤니티**: 지역구별 실시간 채팅과 평가. 읽기는 누구나, 쓰기는 로그인과 주민 인증 후. 글마다 신고하거나 그 주민 글을 숨길 수 있음

정당은 색으로 표시하지 않고, 인물 사진은 흑백, 상태는 색 말고 아이콘과 글자로 같이 보여 줌.

## 대상 사용자

- 우리 동네 의원이 누군지, 뭘 하는지 한 번에 보고 싶은 사람
- 선거 때 뉴스 말고 원문 기록으로 판단하고 싶은 사람
- 이사해서 선거구가 바뀌었는데 어디인지 모르는 사람

## 다운로드

최신 버전은 [릴리스 페이지](https://github.com/Seungpyo1007/DEMOCRACY/releases/latest)에 있음. Google Play, App Store 출시는 심사 준비 중.

[개인정보처리방침](https://seungpyo1007.github.io/DEMOCRACY/privacy/) · [이용약관](https://seungpyo1007.github.io/DEMOCRACY/terms/) · [계정 삭제](https://seungpyo1007.github.io/DEMOCRACY/account-deletion/)

## 사용 기술

| 구분 | 내용 |
|---|---|
| 앱 | Flutter 3.44.8 (고정), Dart 3.12.2, Riverpod, go_router |
| iOS | iOS 26 Liquid Glass 네이티브 탭 바, Apple Foundation Models |
| Android | Material 3 Expressive 플로팅 툴바, Gemini Nano |
| 서버 | Supabase (Postgres, Edge Functions, pg_cron, Realtime), Deno 2.9 |
| 데이터 | 열린국회정보, 중앙선관위(data.go.kr, 선거공보), 국가법령정보센터, 행정안전부 행정동 코드, 도로명주소, VWorld |
| 로그인 | Apple, Google, 카카오, 이메일 코드. 실명·휴대폰 인증 안 함 |

앱 ID는 `com.democracy.kr`. Android는 compileSdk 37 · targetSdk 36 · minSdk 24 (compileSdk 37은 `flutter_secure_storage` 11 때문).

## 시작하기

툴체인 확인하고 기본 검증까지 한 번에 돌림. Flutter 3.44.8이 아니면 파일 건드리기 전에 멈춤.

```bash
./tool/bootstrap.sh                                      # macOS · Linux
```

```powershell
.\tool\bootstrap.ps1 -Organization "com.democracy.kr"    # Windows
```

그냥 `flutter run` 하면 샘플 데이터로 뜸. 실제 서버에 붙이려면:

```bash
cp app/dart_defines.example.json app/dart_defines.json   # 주소랑 anon 키 채움. gitignore라 커밋 안 됨
cd app && flutter run --dart-define-from-file=dart_defines.json
```

폰에 릴리스로 넣을 때도 `flutter build ios --release --dart-define-from-file=dart_defines.json`. 이거 빼면 샘플 데이터로 뜸.

로그인 키(카카오, Google, Android의 Apple)는 따로 넣어야 함. 키 없는 제공자는 버튼이 안 나오고 이메일 로그인만 됨. `app/ios/Flutter/Keys.xcconfig.example`, `server/README.md` 참고.

서버 테스트는 `cd server && deno task ci`.

## 폴더 구성

| 경로 | 내용 |
|---|---|
| `app/` | Flutter 앱. 기능별 `data / domain / application / presentation` |
| `app/assets/fixtures/` | 샘플 데이터. 서버 응답 모양의 기준이기도 함 |
| `server/` | Supabase 마이그레이션, Edge Functions(BFF, 수집), 선거구 매핑표 |
| `design_handoff_democracy_app/` | 처음 제품 명세랑 HTML 디자인 레퍼런스 |
| `docs/` | MVP 계획, 공직선거법 정리, 운영 계획, 답글 설계 |
| `HANDOFF.md` | 지금 상태랑 다음 할 일 |
| `CONTRIBUTING.md` | 브랜치 규칙, 검증 절차 |

## 추후 계획

- **실시간 개표**: 지금은 22대 최종 결과만 있음. 다음 선거 때 선관위 실시간 데이터 붙일 예정
- **답글**: 채팅·평가에 답글 (#54)
- **운영 기능**: 반론·정정 경로, 공약 이행 판정, 푸시 알림 (#57~#59, `docs/OPS_ROADMAP.md`). 신고·숨기기·관리자 처리는 0.2.2에 들어감
- **지도**: Google Maps 키 없어서 지금은 회색 격자. 개표율 색칠이랑 선택은 동작함
- **의원 사진**: 사진은 미리 옮겨 둠. 국회사무처에 사용 허락 확인되면 앱 업데이트 없이 보이기 시작함 (#31)

## 기여

Git Flow. 기본 브랜치는 `develop`, `main`은 출시된 것만. 빌드 배지도 `develop` 기준이라 `main`이 뒤처져 있는 게 정상. 자세한 건 [CONTRIBUTING.md](CONTRIBUTING.md).

## 라이선스

[GNU AGPL-3.0](LICENSE). 고쳐서 네트워크 서비스로 돌려도 소스를 공개해야 함.
