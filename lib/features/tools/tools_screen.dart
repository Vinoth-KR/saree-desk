import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/csv.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../widgets/common.dart';

String stockCsv(List<Saree> list) => toCsv(
      ['sku', 'description', 'marked_price', 'status', 'receipt_date', 'bill_index'],
      [
        for (final s in list)
          [s.sku, s.description, paiseToDecimal(s.markedPricePaise), s.status, isoDate(s.receiptDate), s.billIndex]
      ],
    );

String labelsCsv(List<Saree> list) => toCsv(
      ['qr_value', 'description', 'marked_price'],
      [
        for (final s in list)
          [s.sku, s.description.length > 40 ? s.description.substring(0, 40) : s.description, paiseToDecimal(s.markedPricePaise)]
      ],
    );

String salesCsv(List<Sale> list) => toCsv(
      [
        'sale_number', 'sale_date', 'status', 'customer_name', 'sku', 'tagged_price',
        'agreed_price', 'final_allocated_price', 'discount_vs_tag', 'void_reason'
      ],
      [
        for (final s in list)
          for (final i in s.items)
            [
              s.saleNumber ?? '',
              isoDate(s.effectiveDate.toLocal()),
              s.status,
              s.customerName,
              i.sku,
              paiseToDecimal(i.markedPaise),
              paiseToDecimal(i.negotiatedPaise),
              paiseToDecimal(i.finalPaise),
              paiseToDecimal(i.markedPaise - i.finalPaise),
              s.voidReason ?? '',
            ]
      ],
    );

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  Future<void> _export(BuildContext context, String name, String csv) async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File('${dir.path}/$name');
      // UTF-8 with BOM so spreadsheets read it correctly.
      await f.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(csv)], flush: true);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: 'text/csv')], subject: name));
    } catch (e) {
      if (context.mounted) showError(context, 'Export failed: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<List<Saree>> sarees() => ref.read(sareesProvider.future);
    Future<List<Sale>> sales() => ref.read(salesProvider.future);
    final stamp = isoDate(DateTime.now());
    final user = ref.watch(supabaseProvider).auth.currentUser;
    final member = ref.watch(membershipProvider).asData?.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(children: [
        ListTile(
          title: Text('Signed in as ${user?.email ?? ''}'),
          subtitle: Text('Role: ${member?.role ?? 'unknown'}'),
        ),
        if (member?.isOwner ?? false)
          _t(Icons.group_outlined, 'Team and roles', () async => context.push('/team')),
        ListTile(
          leading: const Icon(Icons.brightness_6_outlined),
          title: const Text('Appearance'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.phone_android), label: Text('System')),
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Light')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Dark')),
              ],
              selected: {ref.watch(themeModeProvider)},
              onSelectionChanged: (s) => ref.read(themeModeProvider.notifier).set(s.first),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: const Text('Accent color'),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (final a in accentOptions)
                  _AccentDot(
                    option: a,
                    selected: a.id == ref.watch(accentProvider).id,
                    onTap: () => ref.read(accentProvider.notifier).set(a),
                  ),
              ],
            ),
          ),
        ),
        const Divider(),
        _t(Icons.inventory_2_outlined, 'Export available inventory (CSV)', () async {
          final l = (await sarees()).where((s) => s.isAvailable).toList();
          if (context.mounted) await _export(context, 'available-stock-$stamp.csv', stockCsv(l));
        }),
        _t(Icons.inventory, 'Export full inventory (CSV)', () async {
          final l = await sarees();
          if (context.mounted) await _export(context, 'full-stock-$stamp.csv', stockCsv(l));
        }),
        _t(Icons.receipt_long, 'Export sales (CSV)', () async {
          final l = await sales();
          if (context.mounted) await _export(context, 'sales-$stamp.csv', salesCsv(l));
        }),
        _t(Icons.qr_code_2, 'Export QR label data (CSV)', () async {
          final l = (await sarees()).where((s) => s.isAvailable).toList().reversed.toList();
          if (context.mounted) await _export(context, 'labels-$stamp.csv', labelsCsv(l));
        }),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.backup_outlined),
          title: Text('Backups'),
          subtitle: Text(
            'CSV backs up text records only, not photos. In the Supabase dashboard open Storage > saree-photos '
            'and download the bucket periodically. Free-tier projects pause after a week of inactivity and have '
            'no automatic backups.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Sales slips'),
          subtitle: Text('Internal records only. Not GST tax invoices. Confirm obligations with your CA.'),
        ),
        const Divider(),
        _t(Icons.logout, 'Sign out', () async {
          await ref.read(supabaseProvider).auth.signOut();
        }),
      ]),
    );
  }

  Widget _t(IconData i, String t, Future<void> Function() f) =>
      ListTile(leading: Icon(i), title: Text(t), onTap: f);
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({required this.option, required this.selected, required this.onTap});
  final AccentOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: '${option.name} accent',
        child: Tooltip(
          message: option.name,
          child: InkResponse(
            onTap: onTap,
            radius: 28,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: option.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                  width: 3,
                ),
              ),
              child: selected ? const Icon(Icons.check, color: Colors.white) : null,
            ),
          ),
        ),
      );
}
