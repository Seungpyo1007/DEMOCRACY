# DEMOCRACY

정당색이나 감정 대신 검증 가능한 정치 데이터로 판단하도록 돕는 Flutter 앱의 초기 작업공간이다.

현재는 구현을 시작하기 위한 최소 골격만 포함한다.

- `design_handoff_democracy_app/`: 원본 제품 명세와 HTML 디자인 레퍼런스. 앱 코드로 복사하지 않는다.
- `app/`: Flutter SDK 생성 전에도 검토 가능한 앱 골격.
- `docs/INITIAL_PLAN.md`: MVP 범위, 순서, 완료 조건.
- `HANDOFF.md`: 현재 상태와 다음 실행자용 체크리스트.
- `CLAUDE.md`: Claude Code가 우선 읽을 작업 규칙.
- `tool/bootstrap.ps1`: Flutter 네이티브 프로젝트 생성과 기본 검증을 재현하는 스크립트.

## 시작

Flutter 3.44.8을 준비한 뒤, 확정된 조직 도메인을 전달해 실행한다.

```powershell
.\tool\bootstrap.ps1 -Organization "kr.example"
```

`kr.example`은 예시일 뿐이다. 실제 Bundle ID/Application ID 소유 주체가 확정되기 전에는 실행하지 않는다.

현재 머신에는 Flutter/Dart SDK가 없어 `flutter analyze`와 `flutter test`는 아직 실행되지 않았다. 자세한 상태는 `HANDOFF.md`에 기록되어 있다.

