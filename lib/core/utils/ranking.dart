import '../../models/office_model.dart';

class RankedOffice {
  const RankedOffice({required this.rank, required this.office});

  final int rank;
  final Office office;
}

/// Ranks offices by accumulated points (highest first).
///
/// Tie rule: offices with equal points share the same rank ("1-2-2-4"
/// competition ranking) and are listed alphabetically by office name.
List<RankedOffice> rankOffices(Iterable<Office> offices) {
  final sorted = offices.toList()
    ..sort((a, b) {
      final byPoints = b.totalPoints.compareTo(a.totalPoints);
      if (byPoints != 0) return byPoints;
      return a.officeName.toLowerCase().compareTo(b.officeName.toLowerCase());
    });

  final ranked = <RankedOffice>[];
  for (var i = 0; i < sorted.length; i++) {
    final rank = i > 0 && sorted[i].totalPoints == sorted[i - 1].totalPoints
        ? ranked[i - 1].rank
        : i + 1;
    ranked.add(RankedOffice(rank: rank, office: sorted[i]));
  }
  return ranked;
}
