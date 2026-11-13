import '../data/models.dart';

const _months = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// Receipt date written the ways people type it: 2026-10-12, 12-10-2026, 12/10/2026,
/// "12 oct 2026", and the full month name ("october").
List<String> receiptDateForms(DateTime d) {
  final mon = _months[d.month - 1];
  return [
    '${d.year}-${_two(d.month)}-${_two(d.day)}',
    '${_two(d.day)}-${_two(d.month)}-${d.year}',
    '${_two(d.day)}/${_two(d.month)}/${d.year}',
    '${_two(d.day)} ${mon.substring(0, 3)} ${d.year}',
    mon,
  ];
}

/// Lower-cased text fields a saree can be found by.
List<String> _fields(Saree s) => [
      s.sku.toLowerCase(),
      s.description.toLowerCase(),
      s.billIndex.toLowerCase(),
      ...receiptDateForms(s.receiptDate),
    ];

/// Inventory search across SKU, description, wholesale bill index and receipt date.
///  - "SR-0012" / "0012": SKU
///  - "blue silk": every word must appear somewhere (description, bill index, date, SKU)
///  - "B-77": bill index
///  - "12 oct", "oct 2026", "2026-10-12", "12/10/2026": receipt date
///  - "2499": exact marked price in rupees (also matches any text field containing it)
///  - "1000-2500" or "1000..2500": marked price range in rupees
bool matchesQuery(Saree s, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final fields = _fields(s);
  bool anyContains(String needle) => fields.any((f) => f.contains(needle));

  final range = RegExp(r'^(\d+)\s*(?:-|\.\.|to)\s*(\d+)$').firstMatch(q);
  if (range != null) {
    final lo = int.parse(range.group(1)!) * 100;
    final hi = int.parse(range.group(2)!) * 100;
    final (a, b) = lo <= hi ? (lo, hi) : (hi, lo);
    // "12-10" could also be a partial date, so text matches still count.
    return (s.markedPricePaise >= a && s.markedPricePaise <= b) || anyContains(q);
  }

  if (RegExp(r'^\d+$').hasMatch(q) && s.markedPricePaise == int.parse(q) * 100) return true;

  if (anyContains(q)) return true;
  final words = q.split(RegExp(r'\s+'));
  return words.length > 1 && words.every(anyContains);
}
