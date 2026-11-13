import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/age.dart';
import '../../core/format.dart';
import 'inventory_filter.dart';

/// Bottom sheet for the extra inventory filters: age bucket, receipt date range,
/// wholesale bill index and marked price range. Status and sort stay on the main screen.
class FilterSheet extends ConsumerStatefulWidget {
  const FilterSheet({super.key, required this.billIndexes});
  final List<String> billIndexes;

  @override
  ConsumerState<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<FilterSheet> {
  late final InventoryFilter _start = ref.read(inventoryFilterProvider);
  late AgeBucket? _age = _start.age;
  late DateTime? _from = _start.receiptFrom;
  late DateTime? _to = _start.receiptTo;
  late String? _bill = _start.billIndex;
  late final _min = TextEditingController(text: _start.minPaise == null ? '' : paiseToRupeeText(_start.minPaise!));
  late final _max = TextEditingController(text: _start.maxPaise == null ? '' : paiseToRupeeText(_start.maxPaise!));
  String? _error;

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _pick(bool isFrom) async {
    final initial = (isFrom ? _from : _to) ?? DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) setState(() => isFrom ? _from = dateOnly(d) : _to = dateOnly(d));
  }

  void _apply() {
    int? min, max;
    if (_min.text.trim().isNotEmpty) {
      min = parseRupeesToPaise(_min.text);
      if (min == null) return setState(() => _error = 'Enter a valid minimum price');
    }
    if (_max.text.trim().isNotEmpty) {
      max = parseRupeesToPaise(_max.text);
      if (max == null) return setState(() => _error = 'Enter a valid maximum price');
    }
    if (min != null && max != null && min > max) return setState(() => _error = 'Minimum price is above maximum');
    if (_from != null && _to != null && _from!.isAfter(_to!)) {
      return setState(() => _error = '"From" date is after "To" date');
    }
    ref.read(inventoryFilterProvider.notifier).set(InventoryFilter(
          status: _start.status,
          sort: _start.sort,
          age: _age,
          receiptFrom: _from,
          receiptTo: _to,
          billIndex: _bill,
          minPaise: min,
          maxPaise: max,
        ));
    Navigator.pop(context);
  }

  void _reset() => setState(() {
        _age = null;
        _from = null;
        _to = null;
        _bill = null;
        _min.clear();
        _max.clear();
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final bills = {...widget.billIndexes, ?_bill}.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filters', style: t.titleLarge),
            const SizedBox(height: 12),
            Text('Stock age (from receipt date)', style: t.titleSmall),
            const SizedBox(height: 4),
            Wrap(spacing: 8, children: [
              ChoiceChip(label: const Text('Any'), selected: _age == null, onSelected: (_) => setState(() => _age = null)),
              for (final b in ageBuckets)
                ChoiceChip(label: Text(b.shortLabel), selected: _age == b, onSelected: (_) => setState(() => _age = b)),
            ]),
            const SizedBox(height: 16),
            Text('Receipt date range', style: t.titleSmall),
            const SizedBox(height: 4),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_from == null ? 'From' : formatDate(_from!)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.calendar_today, size: 18),
                  label: Text(_to == null ? 'To' : formatDate(_to!)),
                ),
              ),
              if (_from != null || _to != null)
                IconButton(
                  tooltip: 'Clear dates',
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _from = null;
                    _to = null;
                  }),
                ),
            ]),
            const SizedBox(height: 16),
            DropdownButtonFormField<String?>(
              initialValue: _bill,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Wholesale bill index', isDense: true),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('Any')),
                for (final b in bills) DropdownMenuItem<String?>(value: b, child: Text(b)),
              ],
              onChanged: (v) => setState(() => _bill = v),
            ),
            const SizedBox(height: 16),
            Text('Marked price (₹)', style: t.titleSmall),
            const SizedBox(height: 4),
            Row(children: [
              for (final (i, c) in [_min, _max].indexed) ...[
                if (i == 1) const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: InputDecoration(labelText: i == 0 ? 'Min' : 'Max', prefixText: '₹ ', isDense: true),
                  ),
                ),
              ],
            ]),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: _reset, child: const Text('Reset'))),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: FilledButton(onPressed: _apply, child: const Text('Apply filters'))),
            ]),
          ],
        ),
      ),
    );
  }
}
