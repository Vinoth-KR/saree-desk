import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/format.dart';
import '../../data/models.dart';

/// Internal, non-tax sales slip. No GST, no GSTIN, no tax breakdown.
Future<Uint8List> buildSlipPdf(Sale s, {String shopName = 'Aadav Saree Desk'}) async {
  final isDraft = s.status == 'draft';
  final title = isDraft
      ? 'Draft Sales Summary - Not a Tax Invoice'
      : 'Sales Record - Not a GST Tax Invoice';
  final doc = pw.Document();
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a5,
      margin: const pw.EdgeInsets.all(24),
      build: (c) => [
        pw.Text(shopName, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
        if (s.status == 'void') pw.Text('VOID: ${s.voidReason ?? ''}', style: const pw.TextStyle(fontSize: 11)),
        pw.SizedBox(height: 8),
        pw.Text('No: ${s.saleNumber ?? '(draft)'}'),
        pw.Text('Date: ${formatDate(s.effectiveDate)}'),
        pw.Text('Customer: ${s.customerName}'),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['SKU', 'Description', 'Marked', 'Agreed', 'Final'],
          data: [
            for (final i in s.items)
              [
                i.sku,
                i.description,
                formatInrPlain(i.markedPaise),
                formatInrPlain(i.negotiatedPaise),
                formatInrPlain(i.finalPaise),
              ]
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellAlignments: {
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
            4: pw.Alignment.centerRight,
          },
        ),
        pw.SizedBox(height: 10),
        _row('Total marked', formatInrPlain(s.totalMarkedPaise)),
        _row('Agreed subtotal', formatInrPlain(s.subtotalNegotiatedPaise)),
        if (s.orderDiscountPaise > 0)
          _row('Collective discount (${formatBp(s.discountBp)})', '- ${formatInrPlain(s.orderDiscountPaise)}'),
        _row('Customer discount vs tag', formatInrPlain(s.totalDiscountVsTag)),
        pw.Divider(),
        _row('Total collected', formatInrPlain(s.totalCollectedPaise), bold: true),
        pw.SizedBox(height: 16),
        pw.Text('Internal record. Not a tax invoice. Contains no GST details.',
            style: const pw.TextStyle(fontSize: 8)),
      ],
    ),
  );
  return doc.save();
}

pw.Widget _row(String k, String v, {bool bold = false}) {
  final st = pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [pw.Text(k, style: st), pw.Text(v, style: st)],
  );
}
