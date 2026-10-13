import '../clinical/clinical_models.dart' show timestamp;

enum ProductCategory {
  cleanser,
  toner,
  serum,
  moisturizer,
  treatment,
  sunscreen,
  other,
}

enum ProductStatus { active, inactive, archived }

enum UsageTime { morning, evening, both, asNeeded }

enum ProductSort { recentlyUpdated, name, newest, rating }

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.createdAt,
    required this.updatedAt,
    this.serverUpdatedAt,
    this.owner,
    this.brand,
    this.productType,
    this.activeIngredients = const [],
    this.skinConcerns = const [],
    this.usageInstructions = '',
    this.frequencyPerWeek = 1,
    this.timeOfUse = UsageTime.evening,
    this.startDate,
    this.endDate,
    this.status = ProductStatus.active,
    this.notes,
    this.imagePath,
    this.tags = const [],
    this.rating,
    this.inRoutine = true,
    this.inExperiment = false,
  });

  final DateTime? serverUpdatedAt;
  final String? owner;
  final String id;
  final String name;
  final String? brand;
  final ProductCategory category;
  final String? productType;
  final List<String> activeIngredients;
  final List<String> skinConcerns;
  final String usageInstructions;
  final int frequencyPerWeek;
  final UsageTime timeOfUse;
  final DateTime? startDate;
  final DateTime? endDate;
  final ProductStatus status;
  final String? notes;
  final String? imagePath;
  final List<String> tags;
  final double? rating;
  final bool inRoutine;
  final bool inExperiment;
  final DateTime createdAt;
  final DateTime updatedAt;

  Product copyWith({
    String? id,
    String? name,
    String? brand,
    bool clearBrand = false,
    ProductCategory? category,
    String? productType,
    List<String>? activeIngredients,
    List<String>? skinConcerns,
    String? usageInstructions,
    int? frequencyPerWeek,
    UsageTime? timeOfUse,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    ProductStatus? status,
    String? notes,
    bool clearNotes = false,
    String? imagePath,
    List<String>? tags,
    double? rating,
    bool? inRoutine,
    bool? inExperiment,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Product(
    serverUpdatedAt: serverUpdatedAt,
    owner: owner,
    id: id ?? this.id,
    name: name ?? this.name,
    brand: clearBrand ? null : brand ?? this.brand,
    category: category ?? this.category,
    productType: productType ?? this.productType,
    activeIngredients: activeIngredients ?? this.activeIngredients,
    skinConcerns: skinConcerns ?? this.skinConcerns,
    usageInstructions: usageInstructions ?? this.usageInstructions,
    frequencyPerWeek: frequencyPerWeek ?? this.frequencyPerWeek,
    timeOfUse: timeOfUse ?? this.timeOfUse,
    startDate: startDate ?? this.startDate,
    endDate: clearEndDate ? null : endDate ?? this.endDate,
    status: status ?? this.status,
    notes: clearNotes ? null : notes ?? this.notes,
    imagePath: imagePath ?? this.imagePath,
    tags: tags ?? this.tags,
    rating: rating ?? this.rating,
    inRoutine: inRoutine ?? this.inRoutine,
    inExperiment: inExperiment ?? this.inExperiment,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'brand': brand,
    'category': category.name,
    'productType': productType,
    'activeIngredients': activeIngredients,
    'skinConcerns': skinConcerns,
    'usageInstructions': usageInstructions,
    'frequencyPerWeek': frequencyPerWeek,
    'timeOfUse': timeOfUse.name,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'status': status.name,
    'notes': notes,
    'imagePath': imagePath,
    'tags': tags,
    'rating': rating,
    'inRoutine': inRoutine,
    'inExperiment': inExperiment,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static const _apiKeys = {
    'productType': 'product_type',
    'activeIngredients': 'active_ingredients',
    'skinConcerns': 'skin_concerns',
    'usageInstructions': 'usage_instructions',
    'frequencyPerWeek': 'frequency_per_week',
    'timeOfUse': 'time_of_use',
    'startDate': 'start_date',
    'endDate': 'end_date',
    'imagePath': 'image_url',
    'inRoutine': 'in_routine',
    'inExperiment': 'in_experiment',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  };

  factory Product.fromApi(Map<String, Object?> json) {
    if (json['created_at'] is! String ||
        json['updated_at'] is! String ||
        json['id'] is! String ||
        (json['id'] as String).isEmpty ||
        json['name'] is! String ||
        (json['name'] as String).trim().isEmpty ||
        json['user_id'] is! String ||
        (json['user_id'] as String).isEmpty ||
        !ProductCategory.values.any((v) => v.name == json['category']) ||
        !ProductStatus.values.any((v) => v.name == json['status']) ||
        !UsageTime.values.any((v) => v.name == json['time_of_use']) ||
        json['in_routine'] is! bool ||
        json['in_experiment'] is! bool ||
        json['frequency_per_week'] is! int ||
        (json['frequency_per_week'] as int) < 1 ||
        (json['frequency_per_week'] as int) > 14 ||
        ['active_ingredients', 'skin_concerns', 'tags'].any(
          (k) => json[k] is! List || (json[k] as List).any((v) => v is! String),
        )) {
      throw const FormatException('Unsupported product contract');
    }
    final parsed = Product.fromJson({
      for (final entry in json.entries)
        (_apiKeys.entries
                    .where((key) => key.value == entry.key)
                    .firstOrNull
                    ?.key ??
                entry.key):
            entry.value,
    });
    final updated = timestamp(json['updated_at'], naiveUtc: true);
    return parsed
        .copyWith(
          createdAt: timestamp(json['created_at'], naiveUtc: true),
          updatedAt: updated,
        )
        .withServerIdentity(json['user_id'] as String, updated);
  }
  Product withServerIdentity(String owner, DateTime version) => Product(
    id: id,
    name: name,
    category: category,
    createdAt: createdAt,
    updatedAt: updatedAt,
    serverUpdatedAt: version,
    owner: owner,
    brand: brand,
    productType: productType,
    activeIngredients: List.unmodifiable(activeIngredients),
    skinConcerns: List.unmodifiable(skinConcerns),
    usageInstructions: usageInstructions,
    frequencyPerWeek: frequencyPerWeek,
    timeOfUse: timeOfUse,
    startDate: startDate,
    endDate: endDate,
    status: status,
    notes: notes,
    imagePath: imagePath,
    tags: List.unmodifiable(tags),
    rating: rating,
    inRoutine: inRoutine,
    inExperiment: inExperiment,
  );

  Map<String, dynamic> toApi({bool create = false}) => {
    for (final entry in toJson().entries)
      if (!['id', 'createdAt', 'updatedAt', 'imagePath'].contains(entry.key) &&
          !(create && ['status', 'rating', 'endDate'].contains(entry.key)))
        (_apiKeys[entry.key] ?? entry.key): entry.value,
  };

  factory Product.fromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.where((value) => value.name == name).firstOrNull ?? fallback;
    List<String> strings(String key) =>
        (json[key] as List<Object?>? ?? []).whereType<String>().toList();
    return Product(
      id: json['id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      category: enumValue(
        ProductCategory.values,
        json['category'] as String?,
        ProductCategory.other,
      ),
      productType: json['productType'] as String?,
      activeIngredients: strings('activeIngredients'),
      skinConcerns: strings('skinConcerns'),
      usageInstructions: json['usageInstructions'] as String? ?? '',
      frequencyPerWeek: json['frequencyPerWeek'] as int? ?? 1,
      timeOfUse: enumValue(
        UsageTime.values,
        json['timeOfUse'] as String?,
        UsageTime.evening,
      ),
      startDate: DateTime.tryParse(json['startDate'] as String? ?? ''),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      status: enumValue(
        ProductStatus.values,
        json['status'] as String?,
        ProductStatus.active,
      ),
      notes: json['notes'] as String?,
      imagePath: json['imagePath'] as String?,
      tags: strings('tags'),
      rating: (json['rating'] as num?)?.toDouble(),
      inRoutine: json['inRoutine'] as bool? ?? true,
      inExperiment: json['inExperiment'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}

extension ProductCategoryLabel on ProductCategory {
  String get label => switch (this) {
    ProductCategory.cleanser => 'Cleanser',
    ProductCategory.toner => 'Toner',
    ProductCategory.serum => 'Serum',
    ProductCategory.moisturizer => 'Moisturizer',
    ProductCategory.treatment => 'Treatment',
    ProductCategory.sunscreen => 'Sunscreen',
    ProductCategory.other => 'Other',
  };

  String get icon => switch (this) {
    ProductCategory.cleanser => '🧼',
    ProductCategory.toner => '💦',
    ProductCategory.serum => '🧪',
    ProductCategory.moisturizer => '💧',
    ProductCategory.treatment => '🧴',
    ProductCategory.sunscreen => '☀️',
    ProductCategory.other => '🌿',
  };
}

extension UsageTimeLabel on UsageTime {
  String get label => switch (this) {
    UsageTime.morning => 'Morning',
    UsageTime.evening => 'Evening',
    UsageTime.both => 'Morning & evening',
    UsageTime.asNeeded => 'As needed',
  };
}
