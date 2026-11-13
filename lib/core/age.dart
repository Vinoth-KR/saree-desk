/// Inventory age buckets, driven by wholesale receipt date (never created_at).
/// Shared by the dashboard counts and the inventory filter so they can never disagree.
class AgeBucket {
  const AgeBucket(this.label, this.shortLabel, this.minDays, this.maxDays);
  final String label;
  final String shortLabel;
  final int minDays;

  /// null = no upper bound.
  final int? maxDays;

  bool contains(int days) => days >= minDays && (maxDays == null || days <= maxDays!);
}

const ageBuckets = <AgeBucket>[
  AgeBucket('0–30 days', '0–30d', 0, 30),
  AgeBucket('31–60 days', '31–60d', 31, 60),
  AgeBucket('61–90 days', '61–90d', 61, 90),
  AgeBucket('Over 90 days', '90+d', 91, null),
];

/// Index into [ageBuckets] for an age in days (negative ages, e.g. a future receipt date, count as 0–30).
int ageBucketIndex(int days) {
  final i = ageBuckets.indexWhere((b) => b.contains(days < 0 ? 0 : days));
  return i < 0 ? ageBuckets.length - 1 : i;
}
