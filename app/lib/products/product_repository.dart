import '../services/api_service.dart';
import 'dart:convert';
import 'product.dart';
import 'product_operation.dart';
import '../integration/contract.dart';

abstract interface class ProductRepository {
  Future<List<Product>> fetchProducts();
  Future<Product> create(Product product);
  Future<Product> update(Product product);
  Future<void> delete(String id);
}

// Explicitly injected by tests only; production always uses the API.
class MemoryProductRepository implements ProductRepository {
  MemoryProductRepository([List<Product>? initial])
    : _products = List.of(initial ?? []);
  List<Product> _products;
  bool failNextOperation = false;
  void _check() {
    if (!failNextOperation) return;
    failNextOperation = false;
    throw StateError('Simulated repository failure');
  }

  @override
  Future<List<Product>> fetchProducts() async {
    _check();
    return List.of(_products);
  }

  @override
  Future<Product> create(Product product) async {
    _check();
    _products.add(product);
    return product;
  }

  @override
  Future<Product> update(Product product) async {
    _check();
    _products = _products.map((p) => p.id == product.id ? product : p).toList();
    return product;
  }

  @override
  Future<void> delete(String id) async {
    _check();
    _products.removeWhere((p) => p.id == id);
  }
}

class RemoteProductRepository implements ProductRepository {
  final api = ApiService.instance;
  static const intentId = 'products:write';
  ProductPendingOperation? get pending =>
      api.integrationIntents[intentId] is ProductPendingOperation
      ? api.integrationIntents[intentId] as ProductPendingOperation
      : null;
  void guard(ProductPendingOperation op) {
    if (!api.isCurrentSession(op.generation) ||
        api.observationOwner != op.owner ||
        !api.canReadPatientClinicalStatus ||
        !identical(pending, op)) {
      throw const FormatException('Product operation session changed');
    }
  }

  ProductPendingOperation begin(
    String kind,
    Map<String, dynamic> body, {
    String? resource,
    int? revision,
  }) {
    if (pending != null) {
      throw const FormatException('Resolve original product request first');
    }
    final op = ProductPendingOperation(
      kind: kind,
      payload: body,
      resource: resource,
      expectedRevision: revision,
      owner: api.observationOwner!,
      generation: api.sessionGeneration,
    );
    api.integrationIntents[intentId] = op;
    return op;
  }

  Future<Product?> dispatch(ProductPendingOperation op) async {
    guard(op);
    final wasUncertain = op.uncertain;
    try {
      final data = await api.patientResource(
        op.path,
        op.generation,
        method: op.method,
        payload: op.kind == 'delete' ? null : op.body,
        expectedRevision: op.expectedRevision,
        idempotencyKey: op.key,
      );
      guard(op);
      if (op.kind == 'delete') {
        try {
          await read(op.resource!, op.generation, op.owner);
        } on PatientResourceMissing {
          guard(op);
          api.integrationIntents.remove(intentId);
          return null;
        }
        throw const FormatException('Deletion current state unconfirmed');
      }
      final original = parse(data, op.owner);
      if (op.resource != null && original.id != op.resource) {
        throw const FormatException('Wrong original product');
      }
      final current = await read(original.id, op.generation, op.owner);
      if (jsonEncode(original.toApi()) != jsonEncode(current.toApi())) {
        throw const FormatException(
          'Current product differs from original response',
        );
      }
      guard(op);
      api.integrationIntents.remove(intentId);
      return current;
    } catch (failure) {
      if (identical(pending, op)) {
        // A first definitive HTTP rejection has no uncertain earlier submission.
        // Once uncertain, even a conflict cannot manufacture a safe new request.
        if (!wasUncertain &&
            failure is IntegrationFailure &&
            [400, 403, 404, 409, 410, 412, 422, 428].contains(failure.status)) {
          api.integrationIntents.remove(intentId);
        } else {
          op.uncertain = true;
        }
      }
      rethrow;
    }
  }

  Future<bool> reconcile({
    bool retryOriginal = false,
    bool finishUnavailableReview = false,
  }) async {
    final op = pending;
    if (op == null) return true;
    guard(op);
    final value = await api.patientResource(
      '${op.attemptPath}/${op.key}',
      op.generation,
    );
    guard(op);
    final receipt = ProductOperationReceipt.parse(value, op);
    op.lookupStatus = receipt.status;
    op.availability = receipt.availability;
    if (receipt.status == 'unknown') {
      op.uncertain = true;
      if (!retryOriginal) return false;
      await dispatch(op);
      return true;
    }
    // Read actual current state, never restore a historical snapshot into a list.
    try {
      await read(receipt.resource!, op.generation, op.owner);
    } on PatientResourceMissing {
      /* Actual current absence, not attempt proof. */
    }
    guard(op);
    if ((receipt.status == 'expired' || receipt.availability == 'erased') &&
        !finishUnavailableReview) {
      return false;
    }
    api.integrationIntents.remove(intentId);
    return true;
  }

  Product parse(Object? data, String owner) {
    final result = Product.fromApi(data as Map<String, dynamic>);
    if (result.owner != owner) {
      throw const FormatException('Wrong product owner');
    }
    return result;
  }

  Future<Product> read(String id, int generation, String owner) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid product ID');
    }
    final product = parse(
      await api.patientResource('products/$id', generation),
      owner,
    );
    if (product.id != id) throw const FormatException('Wrong product identity');
    return product;
  }

  @override
  Future<List<Product>> fetchProducts() async {
    final generation = api.sessionGeneration, owner = api.observationOwner;
    final rows = await api.patientResource('products', generation) as List;
    if (owner == null) throw const FormatException('Missing owner');
    final products = rows.map((r) => parse(r, owner)).toList();
    if (products.map((p) => p.id).toSet().length != products.length) {
      throw const FormatException('Duplicate products');
    }
    return products;
  }

  @override
  Future<Product> create(Product product) async {
    final op = begin('create', product.toApi(create: true));
    return (await dispatch(op))!;
  }

  @override
  Future<Product> update(Product product) async {
    final generation = api.sessionGeneration, owner = api.observationOwner!;
    final latest = await read(product.id, generation, owner);
    if (product.owner != owner ||
        product.serverRevision != latest.serverRevision ||
        product.revisionProtected != latest.revisionProtected ||
        product.serverUpdatedAt != latest.serverUpdatedAt) {
      throw const FormatException('Product changed. Reopen the editor.');
    }
    final desired = product.toApi(), existing = latest.toApi();
    final patch = {
      for (final e in desired.entries)
        if (jsonEncode(e.value) != jsonEncode(existing[e.key])) e.key: e.value,
    };
    if (patch.isEmpty) return latest;
    final op = begin(
      'patch',
      patch,
      resource: product.id,
      revision: product.serverRevision,
    );
    return (await dispatch(op))!;
  }

  @override
  Future<void> delete(String id) async {
    final generation = api.sessionGeneration, owner = api.observationOwner!;
    await deleteChecked(await read(id, generation, owner));
  }

  // The controller supplies the exact server snapshot the patient reviewed.
  Future<void> deleteChecked(Product product) async {
    final generation = api.sessionGeneration, owner = api.observationOwner!;
    final id = product.id;
    final latest = await read(id, generation, owner);
    if (product.owner != owner ||
        product.serverRevision != latest.serverRevision ||
        product.revisionProtected != latest.revisionProtected ||
        product.serverUpdatedAt != latest.serverUpdatedAt) {
      throw const FormatException('Product changed. Reopen the editor.');
    }
    final op = begin(
      'delete',
      {},
      resource: id,
      revision: product.serverRevision,
    );
    await dispatch(op);
  }
}
