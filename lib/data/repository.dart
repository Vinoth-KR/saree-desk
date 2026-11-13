import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';

class AppException implements Exception {
  AppException(this.message, {this.isDuplicateSku = false, this.isConflict = false});
  final String message;
  final bool isDuplicateSku;
  final bool isConflict;
  @override
  String toString() => message;
}

AppException friendlyError(Object e) {
  if (e is AppException) return e;
  if (e is PostgrestException) {
    final m = e.message;
    if (e.code == '23505' && m.contains('already exists')) {
      return AppException(m, isDuplicateSku: true);
    }
    if (e.code == '23505' && m.contains('sarees_business_sku_key')) {
      return AppException('That SKU already exists.', isDuplicateSku: true);
    }
    if (e.code == '40001' || m.startsWith('Already sold')) {
      return AppException(m, isConflict: true);
    }
    if (e.code == '42501') {
      return AppException(m.isEmpty || m.toLowerCase().startsWith('not authorized')
          ? 'Not authorized for this shop.'
          : m);
    }
    return AppException(m);
  }
  if (e is SocketException || e is HttpException || e.toString().contains('ClientException')) {
    return AppException('No connection. Check your internet and try again.');
  }
  return AppException(e.toString());
}

class Repository {
  Repository(this._c);
  final SupabaseClient _c;

  static const bucket = 'saree-photos';

  String? get userId => _c.auth.currentUser?.id;

  // ------------------------------------------------------------ membership
  Future<Membership?> fetchMembership() async {
    final uid = userId;
    if (uid == null) return null;
    final rows = await _c
        .from('business_members')
        .select('business_id, role, businesses(name)')
        .eq('user_id', uid)
        .limit(1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return Membership(
      businessId: r['business_id'] as String,
      role: r['role'] as String,
      businessName: ((r['businesses'] as Map?)?['name'] as String?) ?? 'Shop',
    );
  }

  // ------------------------------------------------------------ sarees
  Future<List<Saree>> fetchSarees() async {
    final rows = await _c.from('sarees').select().order('indexed_at', ascending: false).limit(5000);
    return rows.map((e) => Saree.fromJson(e)).toList();
  }

  Future<Saree> fetchSaree(String id) async =>
      Saree.fromJson(await _c.from('sarees').select().eq('id', id).single());

  Future<Saree> addSaree({
    required String id,
    required DateTime receiptDate,
    required String billIndex,
    required String description,
    required int markedPaise,
    String? manualSku,
  }) async {
    try {
      final res = await _c.rpc('add_saree', params: {
        'p_receipt_date':
            '${receiptDate.year.toString().padLeft(4, '0')}-${receiptDate.month.toString().padLeft(2, '0')}-${receiptDate.day.toString().padLeft(2, '0')}',
        'p_bill_index': billIndex,
        'p_description': description,
        'p_marked_price_paise': markedPaise,
        'p_sku': (manualSku == null || manualSku.trim().isEmpty) ? null : manualSku.trim(),
        'p_id': id,
      });
      return Saree.fromJson(Map<String, dynamic>.from(res as Map));
    } on PostgrestException catch (e) {
      // A retry after a lost response: the row already exists under our client id.
      if (e.code == '23505' && e.message.contains('sarees_pkey')) {
        return fetchSaree(id);
      }
      throw friendlyError(e);
    } catch (e) {
      throw friendlyError(e);
    }
  }

  Future<Saree> editSaree({
    required String id,
    required DateTime receiptDate,
    required String billIndex,
    required String description,
    required int markedPaise,
  }) async {
    try {
      final res = await _c.rpc('edit_saree_details', params: {
        'p_id': id,
        'p_receipt_date':
            '${receiptDate.year.toString().padLeft(4, '0')}-${receiptDate.month.toString().padLeft(2, '0')}-${receiptDate.day.toString().padLeft(2, '0')}',
        'p_bill_index': billIndex,
        'p_description': description,
        'p_marked_price_paise': markedPaise,
      });
      return Saree.fromJson(Map<String, dynamic>.from(res as Map));
    } catch (e) {
      throw friendlyError(e);
    }
  }

  // ------------------------------------------------------------ photos
  /// Uploads, then records the path. Only after the storage object exists is the DB updated.
  Future<void> uploadPhoto({
    required String businessId,
    required String sareeId,
    required Uint8List bytes,
  }) async {
    final path = '$businessId/$sareeId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    try {
      await _c.storage.from(bucket).uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: false),
          );
      await _c.rpc('set_saree_image', params: {'p_id': sareeId, 'p_image_path': path});
    } catch (e) {
      throw friendlyError(e);
    }
  }

  final Map<String, ({String url, DateTime expires})> _urlCache = {};

  Future<String> signedUrl(String path) async {
    final hit = _urlCache[path];
    if (hit != null && hit.expires.isAfter(DateTime.now())) return hit.url;
    final url = await _c.storage.from(bucket).createSignedUrl(path, 3600);
    _urlCache[path] = (url: url, expires: DateTime.now().add(const Duration(minutes: 50)));
    return url;
  }

  // ------------------------------------------------------------ sales
  Future<List<Sale>> fetchSales() async {
    final rows = await _c
        .from('sales')
        .select('*, sale_items(*)')
        .order('created_at', ascending: false)
        .limit(5000);
    return rows.map((e) => Sale.fromJson(e)).toList();
  }

  Future<Sale> submitSale({
    required List<({String sareeId, int negotiatedPaise})> items,
    required String customerName,
    required int discountBp,
    required String idempotencyKey,
    required bool confirm,
    String? draftId,
  }) async {
    try {
      final res = await _c.rpc('confirm_sale', params: {
        'p_items': [
          for (final i in items)
            {'saree_id': i.sareeId, 'negotiated_price_paise': i.negotiatedPaise}
        ],
        'p_customer_name': customerName,
        'p_discount_bp': discountBp,
        'p_idempotency_key': idempotencyKey,
        'p_confirm': confirm,
        'p_draft_id': draftId,
      });
      final id = (res as Map)['id'] as String;
      return await fetchSale(id);
    } catch (e) {
      throw friendlyError(e);
    }
  }

  Future<Sale> confirmDraft(String draftId, String idempotencyKey) async {
    try {
      final res = await _c.rpc('confirm_draft',
          params: {'p_draft_id': draftId, 'p_idempotency_key': idempotencyKey});
      return await fetchSale((res as Map)['id'] as String);
    } catch (e) {
      throw friendlyError(e);
    }
  }

  Future<Sale> fetchSale(String id) async => Sale.fromJson(
      await _c.from('sales').select('*, sale_items(*)').eq('id', id).single());

  Future<void> voidSale(String saleId, String reason) async {
    try {
      await _c.rpc('void_sale', params: {'p_sale_id': saleId, 'p_reason': reason});
    } catch (e) {
      throw friendlyError(e);
    }
  }

  /// Deletes a stock entry that has never been part of any sale. The server enforces this and keeps an
  /// audit event; it rejects sarees with sales history or in a draft with an explanatory message.
  Future<void> deleteSaree(String sareeId) async {
    try {
      await _c.rpc('delete_saree', params: {'p_id': sareeId});
    } catch (e) {
      throw friendlyError(e);
    }
  }

  /// Removes an unconfirmed draft. Drafts never touched stock; the server keeps an audit event.
  Future<void> discardDraft(String saleId) async {
    try {
      await _c.rpc('discard_draft', params: {'p_sale_id': saleId});
    } catch (e) {
      throw friendlyError(e);
    }
  }

  // ------------------------------------------------------------ team (owner only, enforced server-side)
  Future<List<TeamMember>> listMembers() async {
    try {
      final rows = await _c.rpc('list_members') as List;
      return rows.map((e) => TeamMember.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      throw friendlyError(e);
    }
  }

  Future<void> addMember(String email, String role) async {
    try {
      await _c.rpc('add_member', params: {'p_email': email, 'p_role': role});
    } catch (e) {
      throw friendlyError(e);
    }
  }

  Future<void> setMemberRole(String userId, String role) async {
    try {
      await _c.rpc('set_member_role', params: {'p_user': userId, 'p_role': role});
    } catch (e) {
      throw friendlyError(e);
    }
  }

  Future<void> removeMember(String userId) async {
    try {
      await _c.rpc('remove_member', params: {'p_user': userId});
    } catch (e) {
      throw friendlyError(e);
    }
  }
}

/// Photos whose upload failed. Stored on disk so the user can retry later
/// (including after an app restart). Never reported as saved until uploaded.
class PendingPhotos {
  static const _key = 'pending_photos_v1';

  static Future<Map<String, String>> all() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return {};
    return Map<String, String>.from(jsonDecode(raw) as Map);
  }

  static Future<void> add(String sareeId, Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/pending_$sareeId.jpg');
    await f.writeAsBytes(bytes, flush: true);
    final m = await all();
    m[sareeId] = f.path;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(m));
  }

  static Future<void> remove(String sareeId) async {
    final m = await all();
    final path = m.remove(sareeId);
    if (path != null) {
      final f = File(path);
      if (await f.exists()) await f.delete();
    }
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(m));
  }

  static Future<Uint8List?> bytes(String sareeId) async {
    final path = (await all())[sareeId];
    if (path == null) return null;
    final f = File(path);
    return await f.exists() ? f.readAsBytes() : null;
  }
}

/// Camera / gallery. image_picker resizes (long edge <= 1200) and JPEG-compresses at 70,
/// which keeps files well under the ~500KB target for typical saree photos.
class PhotoPicker {
  static final _picker = ImagePicker();

  static Future<Uint8List?> pick(ImageSource source) async {
    final x = await _picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 70,
      requestFullMetadata: false,
    );
    return x == null ? null : await x.readAsBytes();
  }

  /// Android may kill the activity while the camera is open; recover the result.
  static Future<Uint8List?> recoverLost() async {
    final r = await _picker.retrieveLostData();
    if (r.isEmpty || r.file == null) return null;
    return r.file!.readAsBytes();
  }
}
