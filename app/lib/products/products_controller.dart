import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/request_failure.dart';
import 'product.dart';
import 'product_repository.dart';
import 'product_validation.dart';

class ProductOperationResult {
  const ProductOperationResult._(this.success, this.message);
  const ProductOperationResult.success(String message) : this._(true, message);
  const ProductOperationResult.failure(String message) : this._(false, message);
  final bool success;
  final String message;
}

class ProductsController extends ChangeNotifier {
  ProductsController(this._repository, {this.onConfirmed}) {
    if (requiresServerSession) {
      _session = ApiService.instance.sessionGeneration;
      ApiService.instance.addListener(_sessionChanged);
    }
  }
  int _session = 0;
  void _sessionChanged() {
    if (!_disposed &&
        (_session != ApiService.instance.sessionGeneration ||
            !ApiService.instance.canReadPatientClinicalStatus)) {
      _session = ApiService.instance.sessionGeneration;
      clear();
    }
  }

  final ProductRepository _repository;
  final Future<void> Function(int generation)? onConfirmed;

  bool _disposed = false;
  bool get requiresServerSession => _repository is RemoteProductRepository;
  List<Product> _products = [];
  int _generation = 0;
  bool createUncertain = false;
  bool isStale = false;
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  RequestFailure? readFailure;
  DateTime? lastConfirmedAt;
  bool _reading = false;
  String query = '';
  ProductCategory? categoryFilter;
  ProductStatus? statusFilter;
  ProductSort sort = ProductSort.recentlyUpdated;

  List<Product> get all => List.unmodifiable(_products);
  List<Product> get active => _products
      .where((product) => product.status == ProductStatus.active)
      .toList();
  List<Product> get archived => _products
      .where((product) => product.status == ProductStatus.archived)
      .toList();

  List<Product> get visibleProducts {
    final normalized = query.trim().toLowerCase();
    final result = _products.where((product) {
      if (statusFilter != null && product.status != statusFilter) return false;
      if (statusFilter == null && product.status == ProductStatus.archived) {
        return false;
      }
      if (categoryFilter != null && product.category != categoryFilter) {
        return false;
      }
      if (normalized.isEmpty) return true;
      final searchable = [
        product.name,
        product.brand ?? '',
        product.category.label,
        ...product.activeIngredients,
        ...product.tags,
      ].join(' ').toLowerCase();
      return searchable.contains(normalized);
    }).toList();
    switch (sort) {
      case ProductSort.recentlyUpdated:
        result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      case ProductSort.name:
        result.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
      case ProductSort.newest:
        result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case ProductSort.rating:
        result.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
    }
    return result;
  }

  void clear() {
    _generation++;
    isSaving = false;
    createUncertain = false;
    _reading = false;
    readFailure = null;
    lastConfirmedAt = null;
    isLoading = true;
    isStale = false;
    _products = [];
    query = '';
    categoryFilter = null;
    statusFilter = null;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> load() async {
    if (_disposed || isSaving || _reading) return;
    final generation = ++_generation;
    _reading = true;
    isLoading = true;
    isStale = _products.isNotEmpty;
    readFailure = null;
    errorMessage = null;
    notifyListeners();
    try {
      final products = await _repository.fetchProducts();
      if (_disposed || generation != _generation) return;
      lastConfirmedAt = DateTime.now().toUtc();
      _products = products;
      isStale = false;
    } on Object catch (failure) {
      if (_disposed || generation != _generation) return;
      isStale = true;
      readFailure = RequestFailure.from(failure);
      errorMessage =
          'Could not refresh products. ${readFailure!.message} Displayed data may be stale.';
    } finally {
      if (!_disposed && generation == _generation) {
        _reading = false;
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void setQuery(String value) {
    query = value.trim();
    notifyListeners();
  }

  void setCategory(ProductCategory? value) {
    categoryFilter = value;
    notifyListeners();
  }

  void setStatus(ProductStatus? value) {
    statusFilter = value;
    notifyListeners();
  }

  void setSort(ProductSort value) {
    sort = value;
    notifyListeners();
  }

  Product? byId(String id) =>
      _products.where((item) => item.id == id).firstOrNull;

  Future<ProductOperationResult> add(Product product) async {
    // No request was sent when the current read is stale/loading. Do not invent
    // an uncertain creation receipt just because this local guard rejected it.
    if (_disposed || isStale || isLoading) {
      return const ProductOperationResult.failure(
        'Refresh products online before making changes.',
      );
    }
    if (createUncertain) {
      return const ProductOperationResult.failure(
        'Previous creation is unconfirmed. Inspect refreshed records; do not submit it again.',
      );
    }
    if (ProductValidation.duplicate(product, _products)) {
      return const ProductOperationResult.failure(
        'This product is already in your library.',
      );
    }
    final result = await _commit(() async {
      final saved = await _repository.create(product);
      return [..._products, saved];
    }, 'Product saved to your library.');
    if (!result.success && requiresServerSession && isStale) {
      createUncertain = true;
    }
    return result;
  }

  Future<ProductOperationResult> update(Product product) async {
    if (ProductValidation.duplicate(
      product,
      _products,
      excludingId: product.id,
    )) {
      return const ProductOperationResult.failure(
        'This product is already in your library.',
      );
    }
    return _commit(() async {
      final saved = await _repository.update(product);
      return _products
          .map((item) => item.id == product.id ? saved : item)
          .toList();
    }, 'Product updated.');
  }

  Future<ProductOperationResult> archive(String id) async {
    final product = byId(id);
    if (product == null) {
      return const ProductOperationResult.failure('Product not found.');
    }
    if (product.inExperiment) {
      return const ProductOperationResult.failure(
        'End the active experiment before archiving this product.',
      );
    }
    return update(
      product.copyWith(
        status: ProductStatus.archived,
        inRoutine: false,
        endDate: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<ProductOperationResult> restore(String id) async {
    final product = byId(id);
    if (product == null) {
      return const ProductOperationResult.failure('Product not found.');
    }
    return update(
      product.copyWith(
        status: ProductStatus.active,
        inRoutine: true,
        clearEndDate: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<ProductOperationResult> delete(
    String id, {
    bool endExperiment = false,
  }) async {
    final product = byId(id);
    if (product == null) {
      return const ProductOperationResult.failure('Product not found.');
    }
    if (product.inExperiment) {
      return const ProductOperationResult.failure(
        'This product is used in an active experiment.',
      );
    }
    return _commit(() async {
      await _repository.delete(id);
      return _products.where((item) => item.id != id).toList();
    }, 'Product removed.');
  }

  Future<ProductOperationResult> setRoutine(String id, bool value) async {
    final product = byId(id);
    if (product == null) {
      return const ProductOperationResult.failure('Product not found.');
    }
    return update(
      product.copyWith(inRoutine: value, updatedAt: DateTime.now()),
    );
  }

  Future<ProductOperationResult> setExperiment(String id, bool value) async {
    final product = byId(id);
    if (product == null) {
      return const ProductOperationResult.failure('Product not found.');
    }
    if (value && _products.any((item) => item.inExperiment && item.id != id)) {
      return const ProductOperationResult.failure(
        'Finish the current experiment before starting another.',
      );
    }
    return update(
      product.copyWith(
        inExperiment: value,
        inRoutine: true,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<ProductOperationResult> _commit(
    Future<List<Product>> Function() operation,
    String success,
  ) async {
    if (_disposed || isStale || isLoading) {
      return const ProductOperationResult.failure(
        'Refresh products online before making changes.',
      );
    }
    if (isSaving) {
      return const ProductOperationResult.failure(
        'Please wait for the current change to finish.',
      );
    }
    final generation = _generation;
    final session = ApiService.instance.sessionGeneration;
    isSaving = true;
    errorMessage = null;
    notifyListeners();
    try {
      final next = await operation();
      if (_disposed || generation != _generation) {
        return const ProductOperationResult.failure(
          'Session or product data changed. Refresh and retry.',
        );
      }
      _products = next;
      await onConfirmed?.call(session);
      if (_disposed || generation != _generation) {
        return const ProductOperationResult.failure(
          'Session changed. Reopen products.',
        );
      }
      return ProductOperationResult.success(success);
    } on Object {
      if (_disposed || generation != _generation) {
        return const ProductOperationResult.failure(
          'Session changed. Please sign in again.',
        );
      }
      isStale = true;
      errorMessage = 'Change not confirmed. Refresh online before retrying.';
      return ProductOperationResult.failure(errorMessage!);
    } finally {
      if (!_disposed && generation == _generation) {
        isSaving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (requiresServerSession) {
      ApiService.instance.removeListener(_sessionChanged);
    }
    _disposed = true;
    _generation++;
    _products = [];
    super.dispose();
  }
}
