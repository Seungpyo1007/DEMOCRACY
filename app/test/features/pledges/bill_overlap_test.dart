import 'package:democracy/src/features/district/domain/legislator_record.dart';
import 'package:democracy/src/features/pledges/domain/bill_overlap.dart';
import 'package:flutter_test/flutter_test.dart';

BillEntry _bill(String id, String title) =>
    BillEntry(id: id, title: title, stage: '발의', stamp: '7월 9일');

void main() {
  final bills = [
    _bill('b1', '도시공원 보전 및 이용에 관한 법률 일부개정법률안'),
    _bill('b2', '역세권 청년주택 공급 촉진법 일부개정법률안'),
    _bill('b3', '청년기본법 일부개정법률안'),
    _bill('b4', '소상공인 지원법 일부개정법률안'),
  ];

  test('keeps a pledge title\'s subject words and drops the generic ones', () {
    expect(pledgeKeywords('청년 임대주택 공급 확대'), ['청년', '임대주택', '공급']);
    expect(pledgeKeywords('GTX-B 노선 조기 착공'), ['GTX', '노선']);
    expect(pledgeKeywords('지원 확대 및 개선'), isEmpty);
  });

  test('matches inside run-together words, most shared words first', () {
    final matches = billsSharingKeywords('청년 주택 공급', bills);

    expect([for (final m in matches) m.bill.id], ['b2', 'b3']);
    expect(matches.first.keywords, ['청년', '주택', '공급']);
    expect(matches.last.keywords, ['청년']);
  });

  test('does not pair bills on a generic word alone', () {
    expect(billsSharingKeywords('소상공인 지원', bills).single.bill.id, 'b4');
    expect(billsSharingKeywords('전통시장 지원 확대', bills), isEmpty);
  });

  test('caps the list', () {
    final many = [for (var i = 0; i < 9; i++) _bill('c$i', '청년 법안 $i')];
    expect(billsSharingKeywords('청년', many, limit: 5), hasLength(5));
  });
}
