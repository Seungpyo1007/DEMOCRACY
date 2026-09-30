# 운영 기능 계획 (후순위)

지금 급한 건 아님. 사용자가 늘거나 판정을 시작하기 전에 필요한 것들. 전부 Supabase 안에서 됨, 별도 서버 없음.

순서는 의존 관계 기준:

| 순서 | 항목 | 왜 이 순서 |
|---|---|---|
| 1 | 신고·삭제 (5) | 글쓰기가 이미 열려 있음. 문제 글이 올라오면 지금은 지울 방법이 DB 직접 수정뿐 |
| 2 | 반론·정정 경로 (7) | 공약 판정(6)을 하나라도 넣기 전에 있어야 함. 판정이 먼저 나가면 반론 경로 없는 공개 판정이 됨 |
| 3 | 공약 판정 입력 (6) | 1·2 뒤에. 판정 = 실명 정치인에 대한 공개 평가라 법적 부담이 제일 큼 |
| 4 | 푸시 알림 (8) | 있으면 좋은 것. 동의(`notify`)는 이미 받고 있음 |

관리자 기능(1·2·3)은 공통으로 **관리자 역할**이 필요함. 이걸 먼저 한 번 만들고 셋이 같이 씀.

## 0. 관리자 역할 (공통)

- `public.staff (user_id pk → auth.users, role in ('moderator','editor'), added_by, added_at)`. 사람이 SQL로 직접 넣음. 앱에서 스스로 관리자 되는 경로 없음
- BFF에 `requireStaff(role)` 헬퍼. 관리자 라우트는 `/staff/...` 아래로 모음
- 관리자 화면은 앱 안에 안 넣음. 공개 앱에 관리 화면이 섞이면 권한 버그 하나가 바로 사고라서. 처음엔 Supabase 대시보드 + 간단한 관리용 웹페이지(정적 HTML + BFF 호출)로 충분
- 모든 관리 행위는 `staff_actions (id, staff_id, action, target, reason, at)`에 남김. 지운 것도 이유랑 같이 남음

## 1. 신고·삭제 (5)

사용자:
- 글(평가·채팅·답글)마다 「신고」. 사유 고르기: 혐오·욕설 / 개인정보 노출 / 허위사실 / 도배·광고 / 기타(짧은 설명)
- `POST /reports {targetType, targetId, reason, note?}` 로그인 필요, 주민 인증은 불필요. 같은 사람이 같은 글 두 번 신고 못 함
- 신고 3건 이상 쌓이거나 `개인정보 노출`이면 자동으로 가림(`hidden_at`) → 목록에서 「신고로 가려진 글입니다」. 삭제는 사람이 확인 후

관리자:
- `GET /staff/reports?status=open` 목록, `POST /staff/reports/{id}/resolve {action: keep|hide|delete, reason}`
- 삭제된 글 작성자에게 이유 표시 (푸시 붙은 뒤엔 알림)

DB: `reports (id, target_type, target_id, reporter_id, reason, note, status, created_at, resolved_by, resolved_at)`, 각 글 테이블에 `hidden_at`, `hidden_reason`

법·운영 메모:
- 개인정보 노출은 가장 빨리 가려야 함 (자동 가림 대상)
- 「허위사실」 신고로 자동 가림은 안 함. 참/거짓 판단을 기계적으로 하면 앱이 발언을 검열하는 게 됨. 사람이 봄

## 2. 반론·정정 경로 (7)

`docs/ELECTION_LAW.md` 「아직 다루지 않은 것」의 첫 항목. 판정받은 정치인(또는 대리인)이 이의를 낼 수 있어야 함.

- 공약·판정 화면마다 「이의 제기」 링크 → 공개 양식 (로그인 불필요, 연락처 필수, 소속·관계 기재)
- `POST /corrections {pledgeId, claim, evidenceUrl?, contact, relation}` → 접수번호. 연락처는 관리자만 봄, 공개 안 함
- 처리: 접수 → 검토 중 → 반영(판정 수정) / 기각(이유 공개)
- 판정이 바뀌면 **정정 이력**을 남기고 화면에 보임: 「2026-10-02 판정 변경: 미이행 → 추진 중 (이의 제기 반영)」. 조용히 바꾸지 않음
- 이의 제기 중인 판정엔 「이의 제기 검토 중」 표시

DB: `corrections (…, status, decision, decided_by, decided_at)`, `pledge_revisions (pledge_id, from_status, to_status, reason, correction_id, at)`

## 3. 공약 판정 입력 (6)

지금 5,323개 전부 「판정 전」. 판정을 넣으려면 근거가 같이 있어야 하고, 입력 경로가 필요함.

- 판정 단위: 공약 하나 = 상태(이행/추진 중/미이행/번복) + 근거 링크 1개 이상 + 판정 근거 요약 + 판정한 사람(편집자) + 판정일
- 스키마는 이미 있음: `pledges.status`, `evidence_url`, `judgement` jsonb, `bill_ids`. 「번복」은 근거 필수 (check 있음)
- 입력: 관리용 웹페이지에서 공약 검색 → 판정 폼 → `POST /staff/pledges/{id}/judgement`. 편집자(editor) 역할만
- 두 사람 확인: 편집자 A가 입력 → 편집자 B가 승인해야 공개 (`judgement.approvedBy`). 한 사람 실수로 실명 판정이 나가지 않게
- 판정 가능한 근거 출처를 정해 둠: 국회 의안정보(법안 통과), 지자체·부처 공식 발표, 예산서, 공사 착공·준공 공고. 언론 보도는 보조로만
- 판정 바뀔 때마다 `pledge_revisions`에 남음 (2번과 같은 테이블)
- 이행률(`공약 이행`) 통계는 판정된 것만으로 계산 (이미 그렇게 됨)

## 4. 푸시 알림 (8)

- FCM (Android) + APNs (FCM이 iOS도 중계). Firebase 프로젝트 `democracy-kr` 이미 있음 → Cloud Messaging만 켜면 됨. 앱에 `firebase_messaging` 추가 (지금 Firebase SDK 없음, 이때 처음 들어감)
- 토큰 등록: `POST /me/devices {token, platform}` → `devices (user_id, token, platform, updated_at)`. 로그아웃·탈퇴 시 삭제
- 보내는 건 Edge Function `notify` 하나. 서버 키(FCM 서비스 계정)는 Supabase secret
- 무엇을 보내나 (전부 `notify` 동의한 사람만, 지역구 기준):
  - 내 지역구 의원 새 대표발의 법안 (법안 수집 크론 뒤에 묶어서 하루 1번)
  - 내 글에 답글 (답글 기능 뒤)
  - 내 글이 신고로 가려짐/삭제됨 (1번 뒤)
- 선거 관련 알림은 안 함 (선거운동으로 보일 수 있음). 선거 기간엔 알림 전체를 다시 검토

## 이슈로 나눌 단위

1. 관리자 역할 + 행위 로그
2. 신고 API + 자동 가림 + 관리자 처리
3. 이의 제기 접수 + 정정 이력 표시
4. 판정 입력 + 2인 승인
5. 기기 토큰 등록 + notify 함수 + 첫 알림(새 법안)
