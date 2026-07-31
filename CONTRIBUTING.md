# 기여 안내

## 브랜치 전략

Git Flow를 따른다.

| 브랜치 | 역할 | 분기 원본 | 병합 대상 |
|---|---|---|---|
| `main` | 출시된 상태만 담는다. 항상 태그가 붙어 있다 | — | — |
| `develop` | 통합 브랜치. 기본 브랜치이며 평소 작업은 여기로 모인다 | `main` | `main` (release 경유) |
| `feature/*` | 기능 단위 작업 | `develop` | `develop` |
| `release/*` | 출시 준비. 버전 확정과 마무리 수정만 한다 | `develop` | `main` + `develop` |
| `hotfix/*` | 출시본 긴급 수정 | `main` | `main` + `develop` |

`main`에 직접 push하지 않는다. `develop`도 PR을 거친다. 기본 브랜치는 `develop`이므로 PR은 별도 지정 없이 `develop`을 향한다.

### 브랜치 보호 설정

`main`과 `develop` 모두 다음이 걸려 있다.

- PR 없이는 병합할 수 없다 (승인 필요 수는 0. 1인 작업을 막지 않으면서 흐름은 강제한다)
- `analyze and test` 체크를 통과해야 한다
- base 브랜치가 최신이어야 한다 (strict)
- force push와 브랜치 삭제 금지

`enforce_admins`가 **켜져 있다.** 저장소 소유자에게도 예외가 없다. `main`과 `develop`에 직접 push하면 거부된다.

```
! [remote rejected] develop -> develop (protected branch hook declined)
remote: - Changes must be made through a pull request.
```

이 문서를 포함해 모든 변경은 브랜치를 따고 PR로 들어와야 한다.

### 막혔을 때

CI 자체가 고장 나서 아무것도 병합할 수 없는 상황이라면, 고치는 변경도 PR로 올려야 하지만 그 PR 역시 같은 CI에 막힌다. 이때만 일시적으로 해제한다.

```bash
gh api -X DELETE repos/Seungpyo1007/DEMOCRACY/branches/main/protection/enforce_admins
# 수습 후 곧바로 되돌린다
gh api -X POST repos/Seungpyo1007/DEMOCRACY/branches/main/protection/enforce_admins
```

해제한 채로 두지 않는다. 켜 두는 이유는 규율이 아니라, 검증되지 않은 커밋이 `main`에 닿는 경로를 없애기 위해서다.

### 이름 규칙

```
feature/onboarding-address-search
release/0.2.0
hotfix/0.1.1-source-badge-crash
```

### 기능 작업

```bash
git switch develop && git pull
git switch -c feature/<작업명>
# 작업, 커밋
git push -u origin feature/<작업명>
gh pr create --base develop
```

### 출시

```bash
git switch -c release/0.2.0 develop
# app/pubspec.yaml의 version 갱신, HANDOFF.md 검증 기록 정리
gh pr create --base main
# 병합 후
git tag -a v0.2.0 -m "..." && git push origin v0.2.0
git switch develop && git merge --no-ff main   # 릴리스 커밋을 develop으로 되돌린다
```

`release`와 `hotfix`는 `main`과 `develop` **양쪽**에 반영해야 한다. 한쪽을 빠뜨리면 다음 릴리스에서 되살아난 버그로 나타난다.

## 검증

PR은 `.github/workflows/verify.yml`을 통과해야 한다. 로컬에서 같은 것을 먼저 돌린다.

```bash
cd app && flutter pub get && dart format lib test && flutter analyze && flutter test
```

Windows에서는 다음이 같은 순서를 수행한다.

```powershell
.\tool\bootstrap.ps1 -Organization "com.democracy.kr"
```

CI는 `dart format --set-exit-if-changed`를 쓴다. 로컬 bootstrap은 포맷을 고쳐 주지만 CI는 고쳐 주지 않고 실패시킨다. 커밋 전에 포맷을 맞춰 둔다.

Flutter는 **3.44.8로 고정**돼 있다. bootstrap과 CI 모두 정확히 이 버전을 요구하므로, 올리려면 `app/.fvmrc`, `tool/bootstrap.ps1`, `.github/workflows/verify.yml` 세 곳을 함께 바꿔야 한다.

## 커밋 메시지

- 제목은 명령형 현재형으로 쓰고 마침표를 붙이지 않는다
- 본문에는 무엇을 바꿨는지보다 **왜 그렇게 했는지**를 남긴다. 특히 다른 선택지를 버린 이유
- 도구 생성 표식이나 공동 작성자 트레일러를 넣지 않는다

## 지켜야 할 제품 규칙

`CLAUDE.md`(저장소에 포함되지 않음)와 `design_handoff_democracy_app/README.md`가 원본이다. 코드에서 타입으로 강제되는 것들:

- 외부 수치는 `SourcedValue<T>`로만 표현한다. 출처와 취득 시각 없이는 파싱이 거부한다
- 정당은 `PartyRef`와 `PartyTag`로만 표시한다. 색을 넘길 인자가 없다
- 인물 사진은 `GrayscalePortrait`를 쓴다. 필터가 위젯에 내장돼 있다
- 공약 상태는 `PledgeStatusChip`을 쓴다. 색·아이콘·텍스트가 항상 함께 나간다
- 후보 정렬은 `DistrictProfile.sortedByName`이 담당하고, 화면은 `sortLabel`을 표시한다

이 경계를 우회하는 코드는 리뷰에서 되돌린다.
