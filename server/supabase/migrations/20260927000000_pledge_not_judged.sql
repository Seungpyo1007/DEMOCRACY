-- 「판정 전」: a pledge listed from the winner's 선거공보 with no fulfilment call made.
--
-- Pilot boards list real 22대 pledges before anyone has judged them. A verdict on a named
-- politician without evidence is a defamation risk (docs/ELECTION_LAW.md), so such a row
-- must not be able to carry any of a verdict's parts: no evidence link, no judgement
-- record, no bills cited as evidence. The BFF also leaves notJudged rows out of 공약 이행.

alter table public.pledges drop constraint pledges_status_check;

alter table public.pledges add constraint pledges_status_check
  check (status in ('notJudged', 'fulfilled', 'inProgress', 'unfulfilled', 'reversed'));

alter table public.pledges add constraint pledges_not_judged_has_no_verdict
  check (
    status <> 'notJudged'
    or (evidence_url is null and judgement is null and bill_ids = '{}')
  );
