-- SAMPLE SEED (generated from server/testdata by scripts; see testdata/README.md).
-- NOT VERIFIED against 공직선거법 [별표2]. Enough for 마포구 갑/을 + 종로구 to resolve.
-- Real data: run scripts/import_district_areas.ts on the full 별표2 CSV instead.
-- District ids: nec-313502f4 = 서울 마포구 갑, nec-24863648 = 서울 마포구 을, nec-0bd970c0 = 서울 종로구

insert into public.districts (id, sg_id, sg_typecode, sgg_code, sd_name, wiw_name, sgg_name, display_name, name_key, sgg_jungsu, s_order, source_url, publisher, fetched_at) values
  ('nec-313502f4', '20240410', 2, '313502f4', '서울특별시', '마포구', '마포구갑', '서울 마포구 갑', '서울마포구갑', 1, null, 'https://www.data.go.kr/data/15000897/openapi.do', '중앙선거관리위원회', '2026-09-24T00:00:00.000Z'),
  ('nec-24863648', '20240410', 2, '24863648', '서울특별시', '마포구', '마포구을', '서울 마포구 을', '서울마포구을', 1, null, 'https://www.data.go.kr/data/15000897/openapi.do', '중앙선거관리위원회', '2026-09-24T00:00:00.000Z'),
  ('nec-0bd970c0', '20240410', 2, '0bd970c0', '서울특별시', '종로구', '종로구', '서울 종로구', '서울종로구', 1, null, 'https://www.data.go.kr/data/15000897/openapi.do', '중앙선거관리위원회', '2026-09-24T00:00:00.000Z')
on conflict (id) do update set sg_id = excluded.sg_id, sg_typecode = excluded.sg_typecode, sgg_code = excluded.sgg_code, sd_name = excluded.sd_name, wiw_name = excluded.wiw_name, sgg_name = excluded.sgg_name, display_name = excluded.display_name, name_key = excluded.name_key, sgg_jungsu = excluded.sgg_jungsu, s_order = excluded.s_order, source_url = excluded.source_url, publisher = excluded.publisher, fetched_at = excluded.fetched_at;

insert into public.district_areas (election_sg_id, hdong_code, sgg_code, hdong_name, sigungu_code, source_url, fetched_at) values
  ('20240410', '1144055500', '313502f4', '아현동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144056500', '313502f4', '공덕동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144058500', '313502f4', '도화동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144059000', '313502f4', '용강동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144060000', '313502f4', '대흥동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144061000', '313502f4', '염리동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144063000', '313502f4', '신수동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144065500', '24863648', '서강동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144066000', '24863648', '서교동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144068000', '24863648', '합정동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144069000', '24863648', '망원1동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144070000', '24863648', '망원2동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144071000', '24863648', '연남동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144072000', '24863648', '성산1동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144073000', '24863648', '성산2동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '1144074000', '24863648', '상암동', '11440', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z'),
  ('20240410', '11110', '0bd970c0', null, '11110', 'https://www.law.go.kr/법령/공직선거법', '2026-09-24T00:00:00.000Z')
on conflict (election_sg_id, hdong_code) do update set sgg_code = excluded.sgg_code, hdong_name = excluded.hdong_name, sigungu_code = excluded.sigungu_code, source_url = excluded.source_url, fetched_at = excluded.fetched_at;

insert into public.bjdong_hdong (bjd_code, hdong_code, hdong_name, source_url, fetched_at) values
  ('1144010100', '1144056500', '공덕동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010200', '1144056500', '공덕동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010300', '1144056500', '공덕동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010100', '1144055500', '아현동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010200', '1144055500', '아현동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010900', '1144055500', '아현동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010400', '1144058500', '도화동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010700', '1144058500', '도화동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010400', '1144059000', '용강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010500', '1144059000', '용강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010600', '1144059000', '용강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010700', '1144059000', '용강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010800', '1144059000', '용강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010900', '1144059000', '용강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010800', '1144060000', '대흥동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011000', '1144060000', '대흥동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011100', '1144060000', '대흥동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010900', '1144061000', '염리동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010200', '1144061000', '염리동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144010800', '1144063000', '신수동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011100', '1144063000', '신수동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011200', '1144063000', '신수동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011300', '1144063000', '신수동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011700', '1144063000', '신수동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011400', '1144065500', '서강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011500', '1144065500', '서강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011600', '1144065500', '서강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011700', '1144065500', '서강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011800', '1144065500', '서강동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012000', '1144066000', '서교동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012100', '1144066000', '서교동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144011000', '1144066000', '서교동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012200', '1144068000', '합정동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012300', '1144069000', '망원1동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012300', '1144070000', '망원2동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012400', '1144071000', '연남동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012500', '1144072000', '성산1동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012500', '1144073000', '성산2동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012600', '1144073000', '성산2동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z'),
  ('1144012700', '1144074000', '상암동', 'https://www.mapo.go.kr/site/main/content/mapo04010104', '2026-09-24T00:00:00.000Z')
on conflict (bjd_code, hdong_code) do update set hdong_name = excluded.hdong_name, source_url = excluded.source_url, fetched_at = excluded.fetched_at;

