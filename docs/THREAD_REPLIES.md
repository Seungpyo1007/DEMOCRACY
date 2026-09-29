# 정책 토론 답글 설계

지금 토론 스레드는 목록만 보임. 현직 의원 대표발의 법안마다 `sync_bill_threads()`가 스레드를 열고, 앱은 제목·출처·답글 수(항상 0)만 그림. 열어서 읽고 답글 다는 경로가 없음. `thread_replies` 테이블은 이미 있고 비어 있음. 탈퇴 시 삭제/유지, `/me/export`도 이 테이블을 이미 포함함.

## 범위

- 스레드 하나 열기: 원래 법안 정보 + 답글 목록
- 답글 쓰기, 내 답글 지우기
- 답글에 답글(대댓글)은 안 함. 한 단계만. 지역 토론에서 트리 구조는 읽기 어렵고, 1단계 목록으로도 인용은 됨
- 좋아요·추천 안 함. 정렬이 인기순이 되면 판단형 신호가 됨 (제품 규칙 N-계열)

## 규칙

채팅·평가랑 같은 규칙을 그대로 씀. 새 규칙 안 만듦.

- 읽기: 로그인 없이 됨
- 쓰기: 로그인 + 동의 + 그 스레드가 속한 지역구 주민 인증(만료 전). `community_write_check(user, thread.district_id)` 재사용
- 속도 제한: 평가·채팅·답글 합쳐서 1분에 5개 (이미 `community_write_check`에 답글도 들어가 있음)
- 길이: 1–500자 (테이블 check 이미 있음)
- 혐오 표현: 서버에서 422 `content_rejected`, 허위정보 류는 앱 경고만 (채팅이랑 같음)
- 작성자 표시: 활동명 / 「익명 주민」 / 「탈퇴한 주민」. 익명이 기본
- 지우기: 본인 것만. 지우면 행 삭제 (채팅이랑 같음). 남의 답글 지우기는 신고·관리자 기능(운영 계획 5번) 때 따로

## DB

새 테이블 없음. 추가하는 것만:

```sql
-- 스레드 하나 + 답글 수. 목록 화면과 상세 화면이 같은 숫자를 봄
create or replace function public.bff_thread(p_thread_id text)
returns table (id text, district_id text, title text, origin text, bill_id text,
               source_url text, opened_at timestamptz, replies int)
language sql stable set search_path = '' as $$ … $$;

-- 답글 쓰기. 스레드의 지역구로 권한 확인
create or replace function public.post_thread_reply(
  p_user_id uuid, p_thread_id text, p_body text, p_anonymous boolean
) returns setof public.thread_replies
language plpgsql set search_path = '' as $$
declare d text;
begin
  select t.district_id into d from public.community_threads t where t.id = p_thread_id;
  if d is null then raise exception 'not_found'; end if;
  perform public.community_write_check(p_user_id, d);
  return query insert into public.thread_replies
    (thread_id, author_id, body, anonymous, verified_resident)
    values (p_thread_id, p_user_id, p_body, p_anonymous, true)
    returning *;
end $$;
```

- `bff_district_threads`의 `replies`를 실제 count로 바꿈 (지금 0 고정)
- 둘 다 `revoke execute … from public, anon, authenticated`, BFF만 service role로 부름
- 법안이 철회·폐기돼도 스레드는 닫지 않음. 상태는 법안 쪽 정보로 보여줌 (아래 `bill.stage`)

## API (BFF)

| 경로 | 설명 |
|---|---|
| `GET /threads/{id}?before=<cursor>&limit=30` | 스레드 + 답글 한 페이지. 로그인 안 해도 됨. 로그인하면 `mine` 표시 때문에 캐시 안 함 (채팅이랑 같음), 비로그인 15초 캐시 |
| `POST /threads/{id}/replies` | `{body, anonymous?}` → `{reply}` |
| `DELETE /replies/{id}` | → `{deleted:true}`. 본인 것만, 아니면 403 |

`GET /threads/{id}` 응답:

```json
{
  "thread": {
    "id": "bill-PRC_…",
    "districtId": "nec-…",
    "title": "…법률 일부개정법률안",
    "origin": "법안 발의로 자동 생성",
    "openedAt": "2026-07-21T00:00:00Z",
    "replies": 12,
    "source": {"sourceUrl": "https://likms.assembly.go.kr/bill/billDetail.do?billId=…", "fetchedAt": "…"},
    "bill": {"proposer": "…", "committee": "…", "stage": "위원회 심사", "proposedAt": "2026-07-21"}
  },
  "replies": [
    {"id": "…", "author": "솔숲 42", "body": "…", "verifiedResident": true, "mine": false, "createdAt": "…"}
  ],
  "nextCursor": "2026-09-01T10:00:00Z|<uuid>"
}
```

- 정렬은 오래된 순. 토론은 위에서 아래로 읽힘. 페이지는 `(created_at, id)` 커서, offset 안 씀 (중간에 글 들어와도 안 밀림)
- `bill` 블록은 `bills` 테이블에서 바로 가져옴. 법안 원문 링크가 스레드의 출처
- 오류 코드는 기존 것만: `not_found` 404, `unauthorized` 401, `consent_required`/`residency_required` 403, `content_rejected` 422, `rate_limited` 429, `forbidden` 403

## 실시간

채팅 실시간(`district-chat:<districtId>` 브로드캐스트)이랑 같은 방식으로 `thread:<threadId>` 토픽에 새 답글·삭제를 보냄. 스레드 화면이 열려 있을 때만 구독. 채팅 실시간이 들어간 뒤에 같은 트리거 패턴으로 붙임.

## 앱

- `DiscussionThread`에 `open` 경로 추가: 토론 목록 → `/community/threads/:id` 상세 화면
- 상세 화면: 맨 위 법안 카드(제목, 발의자, 소관 위원회, 단계, 원문 링크 = 출처 배지), 아래 답글 목록, 맨 아래 작성창
- 작성 게이트는 기존 `runWriteGated` 그대로 (로그인 → 주민 인증 → 작성)
- 빈 상태: 「아직 답글이 없습니다.」
- 실패 문구는 채팅이랑 같은 것 재사용

## 테스트

- SQL: 다른 지역구 주민이 쓰면 `residency_required`, 없는 스레드면 `not_found`, 1분 5개 합산 제한에 답글 포함
- BFF: 계약 검사(contract.ts), 커서 페이지 경계, 비로그인 캐시 헤더, 본인 아닌 삭제 403, `/me/export`와 `DELETE /me?posts=delete`에 답글 포함 (이미 됨, 회귀 테스트만)
- 앱: 상세 파서, 게이트 흐름, 빈 상태, 골든 1장씩(iOS/Android)

## 순서

1. 마이그레이션 (`post_thread_reply`, `bff_thread`, 답글 수 실제 값)
2. BFF 라우트 3개 + contract.ts + 테스트
3. 앱 상세 화면 + 원격 저장소
4. 채팅 실시간 머지 후 `thread:` 토픽 붙이기
