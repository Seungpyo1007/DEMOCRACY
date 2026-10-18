/// Every interest a reader can pick: 분야 > 세부 주제.
///
/// One const tree, so the list reviewed in a pull request is the list the app
/// ships. Labels are written the way pledges and bills are titled (전월세, not
/// "rental housing market"), and each one is unique across the whole tree,
/// because the on-device match names its axes by label and checks the
/// model's answer against them.
///
/// Ids are what is stored on the device. They never change once shipped; a
/// label can be reworded freely.
///
/// [InterestTopic.keywords] are the other words a reader might type and the
/// words a pledge or bill title on the subject tends to use. They serve both
/// the search (`searchInterests`) and the match (`interestTermsFor`): a
/// reader who picked 전월세 is also shown pledges titled 전세 사기 예방.
library;

class InterestArea {
  const InterestArea({
    required this.id,
    required this.label,
    required this.keywords,
    required this.topics,
  });

  final String id;
  final String label;
  final List<String> keywords;
  final List<InterestTopic> topics;
}

class InterestTopic {
  const InterestTopic({
    required this.id,
    required this.label,
    required this.keywords,
  });

  final String id;
  final String label;
  final List<String> keywords;
}

const interestAreas = <InterestArea>[
  InterestArea(
    id: 'transport',
    label: '교통',
    keywords: ['교통', '대중교통', '교통망'],
    topics: [
      InterestTopic(
        id: 'transport.rail',
        label: '지하철·광역철도',
        keywords: ['전철', '도시철도', '호선', 'GTX', '경전철', '트램', '역 신설'],
      ),
      InterestTopic(
        id: 'transport.bus',
        label: '버스',
        keywords: ['버스 노선', '마을버스', '광역버스', '심야버스', '정류장', '정류소'],
      ),
      InterestTopic(
        id: 'transport.road',
        label: '도로·주차',
        keywords: ['주차장', '주차난', '고속도로', '교차로', '나들목', '교통체증', '도로 확장'],
      ),
      InterestTopic(
        id: 'transport.underground',
        label: '철도·도로 지하화',
        keywords: ['지하화', '선로', '폐철도', '상부 공원'],
      ),
      InterestTopic(
        id: 'transport.walk',
        label: '보행·자전거',
        keywords: ['보행자', '인도', '횡단보도', '자전거 도로', '킥보드'],
      ),
      InterestTopic(
        id: 'transport.fare',
        label: '교통비·환승',
        keywords: ['교통비', '환승', '대중교통 요금', '정기권', 'K-패스', '기후동행카드'],
      ),
    ],
  ),
  InterestArea(
    id: 'housing',
    label: '주거',
    keywords: ['주거', '주택', '집'],
    topics: [
      InterestTopic(
        id: 'housing.rent',
        label: '전월세',
        keywords: ['전세', '월세', '임대차', '전세 사기', '보증금', '세입자'],
      ),
      InterestTopic(
        id: 'housing.redevelop',
        label: '재건축·재개발',
        keywords: ['정비사업', '뉴타운', '리모델링', '이주 대책', '모아타운'],
      ),
      InterestTopic(
        id: 'housing.public',
        label: '공공주택',
        keywords: ['임대주택', '공공임대', '행복주택', '공공분양', '청약'],
      ),
      InterestTopic(
        id: 'housing.market',
        label: '부동산',
        keywords: ['집값', '주택 가격', '종부세', '종합부동산세', '양도세', '공시가격'],
      ),
      InterestTopic(
        id: 'housing.aging',
        label: '노후 주택·주거환경',
        keywords: ['노후 주택', '단열', '층간소음', '빈집', '집수리', '반지하'],
      ),
      InterestTopic(
        id: 'housing.urban',
        label: '도시개발·신도시',
        keywords: ['도시개발', '신도시', '택지', '지구단위', '그린벨트', '개발제한구역', '역세권'],
      ),
    ],
  ),
  InterestArea(
    id: 'education',
    label: '교육',
    keywords: ['교육', '학교', '학생'],
    topics: [
      InterestTopic(
        id: 'education.childcare',
        label: '보육·유치원',
        keywords: ['어린이집', '유보통합', '영유아', '보육료'],
      ),
      InterestTopic(
        id: 'education.school',
        label: '초중고',
        keywords: ['초등학교', '중학교', '고등학교', '학교 급식', '교원', '교권', '학교 신설'],
      ),
      InterestTopic(
        id: 'education.university',
        label: '대학·등록금',
        keywords: ['대학교', '등록금', '학자금', '장학금', '캠퍼스'],
      ),
      InterestTopic(
        id: 'education.afterschool',
        label: '돌봄교실·방과후',
        keywords: ['늘봄', '방과후', '초등돌봄', '학원비', '사교육'],
      ),
      InterestTopic(
        id: 'education.lifelong',
        label: '평생교육',
        keywords: ['평생학습', '평생학습관', '성인 교육', '학력 보완'],
      ),
    ],
  ),
  InterestArea(
    id: 'jobs',
    label: '일자리',
    keywords: ['일자리', '고용', '노동'],
    topics: [
      InterestTopic(
        id: 'jobs.employment',
        label: '취업 지원',
        keywords: ['취업', '구직', '채용', '고용센터', '취업지원센터'],
      ),
      InterestTopic(
        id: 'jobs.labor',
        label: '노동권·근로조건',
        keywords: ['근로', '노동시간', '주4일', '노조', '비정규직', '근로기준법'],
      ),
      InterestTopic(
        id: 'jobs.wage',
        label: '임금·최저임금',
        keywords: ['임금', '최저임금', '임금체불', '퇴직금'],
      ),
      InterestTopic(
        id: 'jobs.public',
        label: '공공일자리',
        keywords: ['공공일자리', '사회적 일자리', '공공근로', '사회적경제'],
      ),
      InterestTopic(
        id: 'jobs.training',
        label: '직업훈련',
        keywords: ['직업교육', '재교육', '기술교육', '폴리텍', '마이스터'],
      ),
      InterestTopic(
        id: 'jobs.platform',
        label: '플랫폼·프리랜서 노동',
        keywords: ['플랫폼 노동', '배달 노동', '프리랜서', '특수고용', '대리운전'],
      ),
    ],
  ),
  InterestArea(
    id: 'economy',
    label: '경제·소상공인',
    keywords: ['경제', '지역경제', '경기 활성화'],
    topics: [
      InterestTopic(
        id: 'economy.smallbiz',
        label: '소상공인·자영업',
        keywords: ['소상공인', '자영업자', '임대료', '카드 수수료', '폐업'],
      ),
      InterestTopic(
        id: 'economy.market',
        label: '전통시장·골목상권',
        keywords: ['전통시장', '골목상권', '상점가', '상권 활성화', '구도심 상권'],
      ),
      InterestTopic(
        id: 'economy.prices',
        label: '물가·생활비',
        keywords: ['물가', '생활비', '공공요금', '장바구니', '난방비'],
      ),
      InterestTopic(
        id: 'economy.tax',
        label: '세금',
        keywords: ['세제', '감세', '증세', '소득세', '상속세', '부가세', '세무서'],
      ),
      InterestTopic(
        id: 'economy.industry',
        label: '기업 유치·산업단지',
        keywords: ['기업 유치', '산업단지', '산단', '투자 유치', '규제 완화', '특구', '공장'],
      ),
      InterestTopic(
        id: 'economy.local_currency',
        label: '지역화폐',
        keywords: ['지역사랑상품권', '상품권', '온누리', '지역화폐'],
      ),
      InterestTopic(
        id: 'economy.debt',
        label: '가계부채·금융',
        keywords: ['가계부채', '대출', '금리', '서민금융', '신용', '금융'],
      ),
    ],
  ),
  InterestArea(
    id: 'welfare',
    label: '복지',
    keywords: ['복지', '사회보장', '취약계층'],
    topics: [
      InterestTopic(
        id: 'welfare.basic',
        label: '기초생활보장',
        keywords: ['기초생활', '생계급여', '수급자', '차상위', '빈곤'],
      ),
      InterestTopic(
        id: 'welfare.care',
        label: '돌봄 서비스',
        keywords: ['돌봄', '통합돌봄', '방문 돌봄', '돌봄센터'],
      ),
      InterestTopic(
        id: 'welfare.income',
        label: '수당·기본소득',
        keywords: ['기본소득', '수당', '지원금', '바우처'],
      ),
      InterestTopic(
        id: 'welfare.facility',
        label: '복지관·복지시설',
        keywords: ['복지관', '복지시설', '사회복지사', '종사자 처우'],
      ),
      InterestTopic(
        id: 'welfare.single',
        label: '1인 가구 지원',
        keywords: ['1인 가구', '1인가구', '고독사', '사회적 고립'],
      ),
    ],
  ),
  InterestArea(
    id: 'health',
    label: '의료·건강',
    keywords: ['의료', '건강', '병원', '보건'],
    topics: [
      InterestTopic(
        id: 'health.public',
        label: '지역 병원·공공의료',
        keywords: ['공공의료', '공공병원', '의료원', '대학병원', '의료 인프라', '의료취약'],
      ),
      InterestTopic(
        id: 'health.emergency',
        label: '응급·소아의료',
        keywords: ['응급실', '응급의료', '소아과', '어린이병원', '심야약국'],
      ),
      InterestTopic(
        id: 'health.cost',
        label: '의료비·건강보험',
        keywords: ['의료비', '건강보험', '본인부담', '급여화', '실손'],
      ),
      InterestTopic(
        id: 'health.mental',
        label: '정신건강',
        keywords: ['마음건강', '우울', '자살 예방', '심리상담'],
      ),
      InterestTopic(
        id: 'health.longterm',
        label: '간병·요양',
        keywords: ['간병', '간병비', '요양병원', '요양원', '장기요양', '재택의료'],
      ),
      InterestTopic(
        id: 'health.workforce',
        label: '의료 인력·의대',
        keywords: ['의대', '의대 정원', '의사', '간호사', '의료인력', '전공의'],
      ),
    ],
  ),
  InterestArea(
    id: 'environment',
    label: '환경·기후',
    keywords: ['환경', '기후', '생태', '친환경'],
    topics: [
      InterestTopic(
        id: 'environment.climate',
        label: '탄소중립·기후위기',
        keywords: ['탄소중립', '기후위기', '기후변화', '온실가스', 'RE100'],
      ),
      InterestTopic(
        id: 'environment.air',
        label: '미세먼지·대기',
        keywords: ['미세먼지', '대기오염', '공기질', '악취'],
      ),
      InterestTopic(
        id: 'environment.waste',
        label: '쓰레기·재활용',
        keywords: ['쓰레기', '재활용', '소각장', '매립지', '폐기물', '일회용'],
      ),
      InterestTopic(
        id: 'environment.park',
        label: '공원·녹지',
        keywords: ['공원', '녹지', '숲', '둘레길', '산책로', '정원'],
      ),
      InterestTopic(
        id: 'environment.water',
        label: '하천·상하수도',
        keywords: ['하천', '상수도', '하수도', '하수처리', '수질'],
      ),
      InterestTopic(
        id: 'environment.energy',
        label: '에너지·전기요금',
        keywords: ['에너지', '전기요금', '태양광', '재생에너지', '원전', '신재생'],
      ),
    ],
  ),
  InterestArea(
    id: 'safety',
    label: '안전·치안',
    keywords: ['안전', '치안'],
    topics: [
      InterestTopic(
        id: 'safety.crime',
        label: '범죄 예방·CCTV',
        keywords: ['범죄', 'CCTV', '방범', '순찰', '스토킹', '마약'],
      ),
      InterestTopic(
        id: 'safety.disaster',
        label: '재난·재해',
        keywords: ['재난', '재해', '침수', '산사태', '풍수해', '지진', '폭염'],
      ),
      InterestTopic(
        id: 'safety.traffic',
        label: '교통안전·스쿨존',
        keywords: ['교통안전', '스쿨존', '어린이보호구역', '통학로', '음주운전'],
      ),
      InterestTopic(
        id: 'safety.fire',
        label: '화재·소방',
        keywords: ['화재', '소방', '소방서', '119', '구급'],
      ),
      InterestTopic(
        id: 'safety.industrial',
        label: '산업 안전',
        keywords: ['산업재해', '산재', '중대재해', '안전관리'],
      ),
    ],
  ),
  InterestArea(
    id: 'culture',
    label: '문화·체육',
    keywords: ['문화', '체육', '여가'],
    topics: [
      InterestTopic(
        id: 'culture.facility',
        label: '문화시설·도서관',
        keywords: ['도서관', '문화센터', '복합문화', '공연장', '미술관', '박물관'],
      ),
      InterestTopic(
        id: 'culture.arts',
        label: '예술·공연',
        keywords: ['문화예술', '예술인', '공연', '전시'],
      ),
      InterestTopic(
        id: 'culture.sports',
        label: '체육시설·생활체육',
        keywords: ['체육관', '체육시설', '수영장', '운동장', '생활체육', '파크골프'],
      ),
      InterestTopic(
        id: 'culture.tourism',
        label: '관광·축제',
        keywords: ['관광', '축제', '관광지', '테마파크', '관광객'],
      ),
      InterestTopic(
        id: 'culture.heritage',
        label: '문화유산',
        keywords: ['문화재', '국가유산', '유적', '역사문화'],
      ),
    ],
  ),
  InterestArea(
    id: 'youth',
    label: '청년',
    keywords: ['청년', '청년층', '2030'],
    topics: [
      InterestTopic(
        id: 'youth.housing',
        label: '청년 주거',
        keywords: ['청년 주택', '청년 임대', '청년 월세', '기숙사'],
      ),
      InterestTopic(
        id: 'youth.jobs',
        label: '청년 일자리·창업',
        keywords: ['청년 일자리', '청년 창업', '청년 취업', '창업 지원', '스타트업'],
      ),
      InterestTopic(
        id: 'youth.assets',
        label: '청년 자산 형성',
        keywords: ['청년도약계좌', '청년 적금', '자산 형성', '청년 금융'],
      ),
      InterestTopic(
        id: 'youth.mind',
        label: '청년 마음건강',
        keywords: ['고립 청년', '은둔 청년', '청년 상담', '청년 마음'],
      ),
    ],
  ),
  InterestArea(
    id: 'senior',
    label: '노인',
    keywords: ['노인', '어르신', '고령', '시니어'],
    topics: [
      InterestTopic(
        id: 'senior.jobs',
        label: '노인 일자리',
        keywords: ['어르신 일자리', '시니어 일자리', '정년'],
      ),
      InterestTopic(
        id: 'senior.pension',
        label: '연금·기초연금',
        keywords: ['연금', '기초연금', '국민연금', '연금개혁'],
      ),
      InterestTopic(
        id: 'senior.center',
        label: '경로당·노인복지관',
        keywords: ['경로당', '노인복지관', '노인회관', '실버'],
      ),
      InterestTopic(
        id: 'senior.dementia',
        label: '치매·노인 돌봄',
        keywords: ['치매', '치매안심센터', '독거노인', '어르신 급식'],
      ),
    ],
  ),
  InterestArea(
    id: 'family',
    label: '여성·가족',
    keywords: ['가족', '여성', '아동'],
    topics: [
      InterestTopic(
        id: 'family.birth',
        label: '저출생·출산 지원',
        keywords: ['저출생', '저출산', '출산', '임신', '난임'],
      ),
      InterestTopic(
        id: 'family.parenting',
        label: '육아·아이돌봄',
        keywords: ['육아', '아이돌봄', '공동육아', '아동수당'],
      ),
      InterestTopic(
        id: 'family.leave',
        label: '육아휴직·일가정 양립',
        keywords: ['육아휴직', '출산휴가', '일가정', '유연근무', '경력단절'],
      ),
      InterestTopic(
        id: 'family.diverse',
        label: '한부모·다문화 가족',
        keywords: ['한부모', '다문화', '조손', '미혼모'],
      ),
      InterestTopic(
        id: 'family.equality',
        label: '성평등·폭력 예방',
        keywords: ['성평등', '성폭력', '가정폭력', '디지털 성범죄', '여성 안전'],
      ),
    ],
  ),
  InterestArea(
    id: 'disability',
    label: '장애인',
    keywords: ['장애인', '장애'],
    topics: [
      InterestTopic(
        id: 'disability.mobility',
        label: '장애인 이동권',
        keywords: ['이동권', '장애인 이동', '저상버스', '특별교통수단', '승강기', '엘리베이터'],
      ),
      InterestTopic(
        id: 'disability.jobs',
        label: '장애인 고용',
        keywords: ['장애인 일자리', '장애인 고용', '보호작업장'],
      ),
      InterestTopic(
        id: 'disability.care',
        label: '활동지원·발달장애',
        keywords: ['활동지원', '발달장애', '장애인 돌봄', '주간보호'],
      ),
      InterestTopic(
        id: 'disability.access',
        label: '특수교육·배리어프리',
        keywords: ['특수학교', '특수교육', '무장애', '배리어프리'],
      ),
    ],
  ),
  InterestArea(
    id: 'rural',
    label: '농어촌',
    keywords: ['농어촌', '농촌', '어촌'],
    topics: [
      InterestTopic(
        id: 'rural.farming',
        label: '농업·농가 소득',
        keywords: ['농업', '농가', '농민', '쌀값', '직불금', '농작물'],
      ),
      InterestTopic(
        id: 'rural.fishery',
        label: '어업·수산',
        keywords: ['어업', '어민', '수산', '어항', '항구'],
      ),
      InterestTopic(
        id: 'rural.smartfarm',
        label: '스마트팜·미래농업',
        keywords: ['스마트팜', '스마트 팜', '첨단농업', '귀농'],
      ),
      InterestTopic(
        id: 'rural.distribution',
        label: '농산물 유통·가격',
        keywords: ['농산물', '직거래', '로컬푸드', '산지 유통'],
      ),
      InterestTopic(
        id: 'rural.living',
        label: '인구 감소·농어촌 정주',
        keywords: ['인구소멸', '지방소멸', '인구감소', '정주', '귀촌'],
      ),
    ],
  ),
  InterestArea(
    id: 'defense',
    label: '국방·보훈',
    keywords: ['국방', '안보', '군'],
    topics: [
      InterestTopic(
        id: 'defense.service',
        label: '군 복무·병사 처우',
        keywords: ['병사', '군 복무', '군 급식', '군인', '병역'],
      ),
      InterestTopic(
        id: 'defense.base',
        label: '군사시설·주변 규제',
        keywords: ['군부대', '군사시설', '군사보호구역', '비행장', '사격장', '군공항'],
      ),
      InterestTopic(
        id: 'defense.veterans',
        label: '보훈·국가유공자',
        keywords: ['보훈', '국가유공자', '참전', '유공자', '보훈병원'],
      ),
    ],
  ),
  InterestArea(
    id: 'diplomacy',
    label: '외교·통일',
    keywords: ['외교', '통일', '북한'],
    topics: [
      InterestTopic(
        id: 'diplomacy.korea',
        label: '남북관계·통일',
        keywords: ['남북', '북한', '평화', '접경지역'],
      ),
      InterestTopic(
        id: 'diplomacy.trade',
        label: '외교·통상',
        keywords: ['통상', '수출', '무역', 'FTA'],
      ),
      InterestTopic(
        id: 'diplomacy.overseas',
        label: '재외동포·이주민',
        keywords: ['재외동포', '외국인', '이주민', '이민', '외국인 노동자'],
      ),
    ],
  ),
  InterestArea(
    id: 'digital',
    label: '디지털·과학기술',
    keywords: ['디지털', '과학', '기술', 'IT'],
    topics: [
      InterestTopic(
        id: 'digital.ai',
        label: 'AI·디지털 산업',
        keywords: ['인공지능', 'AI', '반도체', '데이터센터', '소프트웨어'],
      ),
      InterestTopic(
        id: 'digital.science',
        label: '과학기술·R&D',
        keywords: ['R&D', '연구개발', '과학기술', '연구단지', '연구소'],
      ),
      InterestTopic(
        id: 'digital.divide',
        label: '통신·디지털 격차',
        keywords: ['통신', '와이파이', '5G', '디지털 격차', '키오스크', '통신비'],
      ),
      InterestTopic(
        id: 'digital.privacy',
        label: '개인정보·플랫폼 규제',
        keywords: ['개인정보', '플랫폼', '해킹', '정보보호'],
      ),
    ],
  ),
  InterestArea(
    id: 'admin',
    label: '행정·지방자치',
    keywords: ['행정', '지방자치', '지자체'],
    topics: [
      InterestTopic(
        id: 'admin.decentral',
        label: '지방분권·자치',
        keywords: ['지방분권', '자치분권', '특별자치', '주민자치'],
      ),
      InterestTopic(
        id: 'admin.boundary',
        label: '행정구역 개편',
        keywords: ['행정구역', '행정통합', '편입', '분구', '명칭 변경'],
      ),
      InterestTopic(
        id: 'admin.balance',
        label: '균형발전·공공기관 이전',
        keywords: ['균형발전', '공공기관 이전', '혁신도시', '수도권 집중'],
      ),
      InterestTopic(
        id: 'admin.budget',
        label: '예산·재정',
        keywords: ['예산', '재정', '국비', '교부세', '재원'],
      ),
      InterestTopic(
        id: 'admin.service',
        label: '민원·행정서비스',
        keywords: ['민원', '행정서비스', '주민센터', '행정복지센터', '청사'],
      ),
    ],
  ),
  InterestArea(
    id: 'politics',
    label: '정치·사법',
    keywords: ['정치', '국회', '사법'],
    topics: [
      InterestTopic(
        id: 'politics.reform',
        label: '정치개혁·선거제도',
        keywords: ['정치개혁', '선거제도', '선거', '국회의원 특권', '정당'],
      ),
      InterestTopic(
        id: 'politics.justice',
        label: '검찰·사법 개혁',
        keywords: ['검찰', '법원', '공수처', '수사권'],
      ),
      InterestTopic(
        id: 'politics.integrity',
        label: '부패 방지·공직윤리',
        keywords: ['부패', '청렴', '공직', '이해충돌'],
      ),
    ],
  ),
  InterestArea(
    id: 'pets',
    label: '반려동물',
    keywords: ['반려동물', '반려견', '반려묘', '동물'],
    topics: [
      InterestTopic(
        id: 'pets.facility',
        label: '반려동물 시설',
        keywords: ['반려견 놀이터', '반려동물 놀이터', '반려동물 문화센터', '산책'],
      ),
      InterestTopic(
        id: 'pets.welfare',
        label: '동물복지·유기동물',
        keywords: ['동물복지', '유기동물', '유기견', '길고양이', '동물학대', '보호소'],
      ),
      InterestTopic(
        id: 'pets.cost',
        label: '반려동물 의료비',
        keywords: ['동물병원', '진료비', '펫보험', '반려동물 보험'],
      ),
    ],
  ),
];
