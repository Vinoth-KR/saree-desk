/// Minimal RFC 4180 CSV writer. Output is prefixed with a UTF-8 BOM by the caller
/// so Excel opens it with the right encoding.
String csvEscape(String v) {
  if (v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r')) {
    return '"${v.replaceAll('"', '""')}"';
  }
  return v;
}

String toCsv(List<String> header, List<List<String>> rows) {
  final b = StringBuffer()..write(header.map(csvEscape).join(','))..write('\r\n');
  for (final r in rows) {
    b..write(r.map(csvEscape).join(','))..write('\r\n');
  }
  return b.toString();
}

/// Paise -> "2499.00" (plain decimal, no currency symbol, spreadsheet friendly).
String paiseToDecimal(int paise) =>
    '${paise ~/ 100}.${(paise % 100).toString().padLeft(2, '0')}';
