# DEMOCRACY

정당색이나 감정 대신 검증 가능한 정치 데이터로 판단하도록 돕는 Flutter 앱의 초기 작업공간이다.

현재는 구현을 시작하기 위한 최소 골격만 포함한다.

- `design_handoff_democracy_app/`: 원본 제품 명세와 HTML 디자인 레퍼런스. 앱 코드로 복사하지 않는다.
- `app/`: Flutter 앱. 골격과 생성된 Android/iOS 프로젝트.
- `docs/INITIAL_PLAN.md`: MVP 범위, 순서, 완료 조건.
- `HANDOFF.md`: 현재 상태와 다음 실행자용 체크리스트.
- `tool/bootstrap.ps1`: Flutter 네이티브 프로젝트 생성과 기본 검증을 재현하는 스크립트.

## 요구 사항

| 항목 | 값 |
|---|---|
| Flutter | 3.44.8 (고정) |
| Dart | 3.12.2 |
| Application ID / Bundle ID | `com.democracy.kr` |
| Android | compileSdk 36 · targetSdk 36 · minSdk 24 |

`bootstrap.ps1`은 정확히 Flutter 3.44.8을 요구하며, 버전이 다르면 파일을 변경하기 전에 중단한다.

## 시작

```powershell
.\tool\bootstrap.ps1 -Organization "com.democracy.kr"
```

이 스크립트는 멱등하다. `app/android`와 `app/ios`가 이미 있으면 생성을 건너뛰고 `pub get → format → analyze → test`만 수행한다.

개별 실행:

```powershell
cd app; flutter analyze; flutter test
```

## 상태

MVP 1차의 기반 골격까지 구현돼 있다. 온보딩 외부 라우트, 상태 보존 5탭 셸, 디자인 토큰, 플랫폼 폴백, 주소 인증 게이트, 출처 메타데이터 런타임 검증이 동작하며 `flutter analyze`와 `flutter test`가 통과한다.

트래커, AI 분석, 커뮤니티, 개표는 라우트와 명시적 placeholder만 존재한다. 실제 API, 지도, LLM, 실시간 채널은 아직 구현하지 않았다. 자세한 내용은 `HANDOFF.md`를 참고한다.

## 라이선스

[GNU AGPL-3.0](LICENSE). 이 프로그램을 수정해 네트워크 서비스로 제공하는 경우에도 해당 소스를 공개해야 한다.

