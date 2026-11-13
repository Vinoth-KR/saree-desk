class Saree {
  Saree({
    required this.id,
    required this.businessId,
    required this.sku,
    required this.receiptDate,
    required this.billIndex,
    required this.description,
    required this.imagePath,
    required this.markedPricePaise,
    required this.status,
    required this.indexedAt,
    required this.soldAt,
  });

  final String id;
  final String businessId;
  final String sku;
  final DateTime receiptDate;
  final String billIndex;
  final String description;
  final String? imagePath;
  final int markedPricePaise;
  final String status;
  final DateTime indexedAt;
  final DateTime? soldAt;

  bool get isAvailable => status == 'available';

  factory Saree.fromJson(Map<String, dynamic> j) => Saree(
        id: j['id'] as String,
        businessId: j['business_id'] as String,
        sku: j['sku'] as String,
        receiptDate: DateTime.parse(j['wholesale_receipt_date'] as String),
        billIndex: j['wholesale_bill_index'] as String,
        description: j['description'] as String,
        imagePath: j['image_path'] as String?,
        markedPricePaise: (j['marked_price_paise'] as num).toInt(),
        status: j['status'] as String,
        indexedAt: DateTime.parse(j['indexed_at'] as String),
        soldAt: j['sold_at'] == null ? null : DateTime.parse(j['sold_at'] as String),
      );
}

class SaleItem {
  SaleItem({
    required this.sareeId,
    required this.sku,
    required this.description,
    required this.imagePath,
    required this.markedPaise,
    required this.negotiatedPaise,
    required this.allocatedDiscountPaise,
    required this.finalPaise,
  });

  final String sareeId;
  final String sku;
  final String description;
  final String? imagePath;
  final int markedPaise;
  final int negotiatedPaise;
  final int allocatedDiscountPaise;
  final int finalPaise;

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        sareeId: j['saree_id'] as String,
        sku: j['sku_at_sale'] as String,
        description: j['description_at_sale'] as String,
        imagePath: j['image_path_at_sale'] as String?,
        markedPaise: (j['marked_price_at_sale_paise'] as num).toInt(),
        negotiatedPaise: (j['negotiated_price_paise'] as num).toInt(),
        allocatedDiscountPaise: (j['allocated_order_discount_paise'] as num).toInt(),
        finalPaise: (j['final_sold_price_paise'] as num).toInt(),
      );
}

class Sale {
  Sale({
    required this.id,
    required this.saleNumber,
    required this.customerName,
    required this.status,
    required this.createdAt,
    required this.confirmedAt,
    required this.totalMarkedPaise,
    required this.subtotalNegotiatedPaise,
    required this.discountBp,
    required this.orderDiscountPaise,
    required this.totalCollectedPaise,
    required this.voidReason,
    required this.voidedAt,
    required this.items,
  });

  final String id;
  final String? saleNumber;
  final String customerName;
  final String status; // draft | confirmed | void
  final DateTime createdAt;
  final DateTime? confirmedAt;
  final int totalMarkedPaise;
  final int subtotalNegotiatedPaise;
  final int discountBp;
  final int orderDiscountPaise;
  final int totalCollectedPaise;
  final String? voidReason;
  final DateTime? voidedAt;
  final List<SaleItem> items;

  int get totalDiscountVsTag => totalMarkedPaise - totalCollectedPaise;
  DateTime get effectiveDate => confirmedAt ?? createdAt;

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: j['id'] as String,
        saleNumber: j['sale_number'] as String?,
        customerName: j['customer_name'] as String,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
        confirmedAt: j['confirmed_at'] == null ? null : DateTime.parse(j['confirmed_at'] as String),
        totalMarkedPaise: (j['total_marked_paise'] as num).toInt(),
        subtotalNegotiatedPaise: (j['subtotal_negotiated_paise'] as num).toInt(),
        discountBp: (j['discount_percent_bp'] as num).toInt(),
        orderDiscountPaise: (j['order_discount_paise'] as num).toInt(),
        totalCollectedPaise: (j['total_collected_paise'] as num).toInt(),
        voidReason: j['void_reason'] as String?,
        voidedAt: j['voided_at'] == null ? null : DateTime.parse(j['voided_at'] as String),
        items: ((j['sale_items'] as List?) ?? const [])
            .map((e) => SaleItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

class Membership {
  Membership({required this.businessId, required this.role, required this.businessName});
  final String businessId;
  final String role; // owner | editor | viewer
  final String businessName;

  bool get isOwner => role == 'owner';

  /// Owners and editors can change data; viewers are read-only (also enforced by the database).
  bool get canWrite => role == 'owner' || role == 'editor';
}

class TeamMember {
  TeamMember({required this.userId, required this.email, required this.role});
  final String userId;
  final String email;
  final String role;

  factory TeamMember.fromJson(Map<String, dynamic> j) => TeamMember(
        userId: j['user_id'] as String,
        email: (j['email'] as String?) ?? '(no email)',
        role: j['role'] as String,
      );
}

const memberRoles = ['owner', 'editor', 'viewer'];

String roleDescription(String role) => switch (role) {
      'owner' => 'Everything, including managing team members',
      'editor' => 'Add and edit stock, sell, void sales',
      'viewer' => 'View only',
      _ => role,
    };
