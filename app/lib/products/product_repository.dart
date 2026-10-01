import '../services/api_service.dart';
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
  @override
  Future<List<Product>> fetchProducts() async =>
      (await ApiService.instance.getProducts()).map(Product.fromApi).toList();
  @override
  Future<Product> create(Product product) async => Product.fromApi(
    await ApiService.instance.createProduct(product.toApi(create: true)),
  );
  @override
  Future<Product> update(Product product) async => Product.fromApi(
    await ApiService.instance.updateProduct(product.id, product.toApi()),
  );
  @override
  Future<void> delete(String id) => ApiService.instance.deleteProduct(id);
}
