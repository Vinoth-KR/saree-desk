
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/repository.dart';
import '../../widgets/common.dart';

const _kDate = 'last_receipt_date';
const _kBill = 'last_bill_index';
const _kDraftDesc = 'draft_description';
const _kDraftPrice = 'draft_price';
const _kDraftSku = 'draft_sku';

class AddScreen extends ConsumerStatefulWidget {
  const AddScreen({super.key});
  @override
  ConsumerState<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends ConsumerState<AddScreen> with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _bill = TextEditingController();
  final _desc = TextEditingController();
  final _price = TextEditingController();
  final _sku = TextEditingController();
  final _descFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _billFocus = FocusNode();

  DateTime _date = dateOnly(DateTime.now());
  Uint8List? _photo;
  bool _saving = false;
  bool _manualSku = false;
  String _attemptId = const Uuid().v4(); // reused on retry so a lost response can't duplicate
  Saree? _lastSaved;
  String? _lastPhotoNote;
  String? _formError;
  late SharedPreferences _prefs;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    final d = _prefs.getString(_kDate);
    if (d != null) _date = DateTime.tryParse(d) ?? _date;
    _bill.text = _prefs.getString(_kBill) ?? '';
    _desc.text = _prefs.getString(_kDraftDesc) ?? '';
    _price.text = _prefs.getString(_kDraftPrice) ?? '';
    _sku.text = _prefs.getString(_kDraftSku) ?? '';
    _manualSku = _sku.text.isNotEmpty;
    for (final c in [_desc, _price, _sku]) {
      c.addListener(_persistDraft);
    }
    final lost = await PhotoPicker.recoverLost();
    if (lost != null) _photo = lost;
    if (mounted) setState(() => _ready = true);
  }

  void _persistDraft() {
    _prefs.setString(_kDraftDesc, _desc.text);
    _prefs.setString(_kDraftPrice, _price.text);
    _prefs.setString(_kDraftSku, _sku.text);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final c in [_bill, _desc, _price, _sku]) {
      c.dispose();
    }
    for (final f in [_descFocus, _priceFocus, _billFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null) {
      setState(() => _date = dateOnly(d));
      await _prefs.setString(_kDate, isoDate(_date));
    }
  }

  Future<void> _takePhoto(ImageSource src) async {
    try {
      final b = await PhotoPicker.pick(src);
      if (b != null && mounted) setState(() => _photo = b);
    } catch (e) {
      if (mounted) {
        showError(context,
            'Could not open ${src == ImageSource.camera ? 'camera' : 'gallery'}: $e. '
            'You can still save without a photo and add it later.');
      }
    }
  }

  Future<void> _save({required bool andView}) async {
    if (_saving) return;
    setState(() => _formError = null);
    if (!_form.currentState!.validate()) return;
    final membership = ref.read(membershipProvider).asData?.value;
    if (membership == null) return;

    final paise = parseRupeesToPaise(_price.text)!;
    setState(() => _saving = true);
    final repo = ref.read(repoProvider);
    try {
      final saree = await repo.addSaree(
        id: _attemptId,
        receiptDate: _date,
        billIndex: _bill.text.trim(),
        description: _desc.text.trim(),
        markedPaise: paise,
        manualSku: _manualSku ? _sku.text.trim() : null,
      );
      // Text record is durable now. Remember batch values, clear the draft.
      await _prefs.setString(_kDate, isoDate(_date));
      await _prefs.setString(_kBill, _bill.text.trim());

      String? note;
      if (_photo != null) {
        try {
          await repo.uploadPhoto(businessId: membership.businessId, sareeId: saree.id, bytes: _photo!);
          note = 'Photo uploaded';
        } catch (e) {
          await PendingPhotos.add(saree.id, _photo!);
          note = 'Saved, but photo NOT uploaded ($e). Retry from Inventory.';
        }
      } else {
        note = 'Saved without photo';
      }

      for (final k in [_kDraftDesc, _kDraftPrice, _kDraftSku]) {
        await _prefs.remove(k);
      }
      refreshAll(ref);
      if (!mounted) return;
      if (andView) {
        _resetForNext(saree, note, clearBill: false);
        context.push('/saree/${saree.id}');
      } else {
        _resetForNext(saree, note, clearBill: false);
        _descFocus.requestFocus();
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() => _formError = e.message);
        if (e.isDuplicateSku) {
          // keep the same attempt id? No: the failed insert didn't consume it, so it's reusable.
        }
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetForNext(Saree saved, String note, {required bool clearBill}) {
    setState(() {
      _lastSaved = saved;
      _lastPhotoNote = note;
      _attemptId = const Uuid().v4();
      _desc.clear();
      _price.clear();
      _sku.clear();
      _manualSku = false;
      _photo = null;
      if (clearBill) _bill.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const Center(child: CircularProgressIndicator());
    final member = ref.watch(membershipProvider).asData?.value;
    if (member != null && !member.canWrite) return const ReadOnlyScreen(title: 'Add saree');
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Add saree')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            children: [
              if (_lastSaved != null)
                Card(
                  color: cs.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Saved ${_lastSaved!.sku}', style: Theme.of(context).textTheme.titleMedium),
                              Text(_lastPhotoNote ?? '', style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy SKU',
                          icon: const Icon(Icons.copy),
                          onPressed: () async {
                            await Clipboard.setData(ClipboardData(text: _lastSaved!.sku));
                            if (context.mounted) showInfo(context, 'Copied ${_lastSaved!.sku}');
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              if (_formError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_formError!, style: TextStyle(color: cs.error, fontWeight: FontWeight.w600)),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _pickDate,
                      child: InputDecorator(
                        decoration: const InputDecoration(labelText: 'Wholesale receipt date', isDense: true),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [Text(formatDate(_date)), const Icon(Icons.calendar_today, size: 18)],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _bill,
                      focusNode: _billFocus,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Bill index', isDense: true),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                      onFieldSubmitted: (_) => _descFocus.requestFocus(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _desc,
                focusNode: _descFocus,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.next,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'Blue soft-silk floral border',
                  isDense: true,
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Description is required' : null,
                onFieldSubmitted: (_) => _priceFocus.requestFocus(),
              ),
              TextFormField(
                controller: _price,
                focusNode: _priceFocus,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: const InputDecoration(
                  labelText: 'Marked retail price (from tag)',
                  prefixText: '₹ ',
                  isDense: true,
                ),
                validator: (v) =>
                    parseRupeesToPaise(v ?? '') == null ? 'Enter a price greater than zero' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 160,
                      child: _photo == null
                          ? Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: cs.outline),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                  child: Text('No photo yet', style: TextStyle(color: cs.outline))),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(_photo!, fit: BoxFit.cover, width: double.infinity),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      FilledButton.tonalIcon(
                        style: FilledButton.styleFrom(minimumSize: const Size(140, 52)),
                        onPressed: _saving ? null : () => _takePhoto(ImageSource.camera),
                        icon: const Icon(Icons.photo_camera),
                        label: Text(_photo == null ? 'Camera' : 'Retake'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(minimumSize: const Size(140, 52)),
                        onPressed: _saving ? null : () => _takePhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: const Text('Gallery'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Enter SKU manually'),
                subtitle: const Text('Otherwise the next SR-#### is assigned automatically'),
                value: _manualSku,
                onChanged: (v) => setState(() => _manualSku = v),
              ),
              if (_manualSku)
                TextFormField(
                  controller: _sku,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'SKU', isDense: true),
                  validator: (v) =>
                      _manualSku && (v == null || v.trim().isEmpty) ? 'Enter a SKU or turn off manual' : null,
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : () => _save(andView: false),
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_circle_outline),
                label: const Text('Save & add next'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _saving ? null : () => _save(andView: true),
                child: const Text('Save & view'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
