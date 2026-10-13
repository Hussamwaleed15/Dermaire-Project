import '../services/api_service.dart';
import 'dart:convert';
import 'product.dart';

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
    final generation = api.sessionGeneration, owner = api.observationOwner;
    final receipt = parse(
      await api.patientResource(
        'products',
        generation,
        method: 'POST',
        payload: product.toApi(create: true),
      ),
      owner!,
    );
    final verified = await read(receipt.id, generation, owner);
    if (jsonEncode(receipt.toApi()) != jsonEncode(verified.toApi())) {
      throw const FormatException('Product readback changed');
    }
    return verified;
  }

  @override
  Future<Product> update(Product product) async {
    final generation = api.sessionGeneration, owner = api.observationOwner!;
    final latest = await read(product.id, generation, owner);
    if (product.serverUpdatedAt != latest.serverUpdatedAt) {
      throw const FormatException('Product changed. Reopen the editor.');
    }
    final desired = product.toApi(), existing = latest.toApi();
    final patch = {
      for (final e in desired.entries)
        if (jsonEncode(e.value) != jsonEncode(existing[e.key])) e.key: e.value,
    };
    if (patch.isEmpty) return latest;
    final receipt = parse(
      await api.patientResource(
        'products/${product.id}',
        generation,
        method: 'PATCH',
        payload: patch,
      ),
      owner,
    );
    final verified = await read(product.id, generation, owner);
    if (receipt.id != product.id ||
        jsonEncode(receipt.toApi()) != jsonEncode(verified.toApi())) {
      throw const FormatException('Unconfirmed product update');
    }
    return verified;
  }

  @override
  Future<void> delete(String id) async {
    final generation = api.sessionGeneration;
    await api.patientResource('products/$id', generation, method: 'DELETE');
    try {
      await api.patientResource('products/$id', generation);
    } on PatientResourceMissing {
      return;
    }
    throw const FormatException('Deletion not confirmed by readback');
  }
}
