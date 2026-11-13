import 'package:intl/intl.dart';

/// All money is integer paise. No floating point is used for parsing or math.
final _inr = NumberFormat.decimalPattern('en_IN');

String formatInr(int paise) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final rem = abs % 100;
  final body = rem == 0
      ? _inr.format(rupees)
      : '${_inr.format(rupees)}.${rem.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}₹$body';
}

/// Paise -> editable rupee text ("2499" or "2499.50"), for form fields.
String paiseToRupeeText(int paise) =>
    paise % 100 == 0 ? '${paise ~/ 100}' : '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';

/// PDF-safe variant (default PDF fonts lack the rupee glyph).
String formatInrPlain(int paise) => formatInr(paise).replaceFirst('₹', 'INR ');

/// "2,499" / "2499.50" -> paise. Returns null when invalid or not > 0 (when [allowZero] false).
int? parseRupeesToPaise(String input, {bool allowZero = false}) {
  final s = input.replaceAll(',', '').replaceAll('₹', '').trim();
  final m = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final rupees = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final paise = rupees * 100 + int.parse(frac.isEmpty ? '0' : frac);
  if (paise == 0 && !allowZero) return null;
  if (paise > 2000000000) return null;
  return paise;
}

/// "10" / "7.5" -> basis points (1000 / 750). Null if invalid or outside 0..100%.
int? parsePercentToBp(String input) {
  final s = input.trim();
  if (s.isEmpty) return 0;
  final m = RegExp(r'^(\d{1,3})(?:\.(\d{1,2}))?$').firstMatch(s);
  if (m == null) return null;
  final whole = int.parse(m.group(1)!);
  final frac = (m.group(2) ?? '').padRight(2, '0');
  final bp = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  return bp > 10000 ? null : bp;
}

String formatBp(int bp) {
  final whole = bp ~/ 100;
  final frac = bp % 100;
  return frac == 0
      ? '$whole%'
      : '$whole.${frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}%';
}

/// Basis points -> editable percent text for a form field ("10", "7.5"), no % sign.
String bpToText(int bp) {
  if (bp == 0) return '';
  final frac = bp % 100;
  if (frac == 0) return '${bp ~/ 100}';
  return '${bp ~/ 100}.${frac.toString().padLeft(2, '0').replaceFirst(RegExp(r'0$'), '')}';
}

final _dateFmt = DateFormat('dd MMM yyyy');
String formatDate(DateTime d) => _dateFmt.format(d.toLocal());
String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Inventory age in days, driven by wholesale receipt date (not created_at).
int ageInDays(DateTime receiptDate, {DateTime? now}) =>
    dateOnly(now ?? DateTime.now()).difference(dateOnly(receiptDate)).inDays;
