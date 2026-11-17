import 'package:e_labay/core/utils/ranking.dart';
import 'package:e_labay/models/office_model.dart';
import 'package:flutter_test/flutter_test.dart';

Office office(String name, int points) =>
    Office(officeId: name, officeName: name, building: 'Main', totalPoints: points);

void main() {
  test('ranks by points, highest first', () {
    final ranked = rankOffices([office('A', 10), office('B', 30), office('C', 20)]);
    expect(ranked.map((r) => r.office.officeName), ['B', 'C', 'A']);
    expect(ranked.map((r) => r.rank), [1, 2, 3]);
  });

  test('ties share a rank (1-2-2-4) and are listed alphabetically', () {
    final ranked = rankOffices([
      office('Zeta', 20),
      office('Alpha', 20),
      office('Top', 50),
      office('Low', 5),
    ]);
    expect(ranked.map((r) => r.office.officeName), ['Top', 'Alpha', 'Zeta', 'Low']);
    expect(ranked.map((r) => r.rank), [1, 2, 2, 4]);
  });

  test('all zero points share first place', () {
    final ranked = rankOffices([office('B', 0), office('A', 0)]);
    expect(ranked.map((r) => r.rank), [1, 1]);
    expect(ranked.first.office.officeName, 'A');
  });

  test('empty input', () {
    expect(rankOffices(const []), isEmpty);
  });
}
