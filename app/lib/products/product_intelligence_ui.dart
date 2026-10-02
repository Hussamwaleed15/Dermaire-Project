import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ProductIntelligencePanel extends StatefulWidget {
  const ProductIntelligencePanel({
    super.key,
    required this.productId,
    this.load,
  });
  final String productId;
  // Tests may inject responses; production always reads the authenticated API.
  final Future<Map<String, dynamic>> Function()? load;

  @override
  State<ProductIntelligencePanel> createState() =>
      _ProductIntelligencePanelState();
}

class _ProductIntelligencePanelState extends State<ProductIntelligencePanel> {
  late Future<Map<String, dynamic>> _future;
  @override
  void initState() {
    super.initState();
    _reload();
    ApiService.instance.addListener(_sessionChanged);
  }

  void _reload() {
    _future =
        widget.load?.call() ??
        ApiService.instance.getProductIntelligence(widget.productId);
  }

  void _sessionChanged() {
    if (mounted) setState(_reload);
  }

  @override
  void didUpdateWidget(ProductIntelligencePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.load != widget.load) {
      _reload();
    }
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(_sessionChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Text('Loading product intelligence…');
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Product intelligence unavailable.'),
                TextButton(
                  onPressed: () => setState(_reload),
                  child: const Text('Retry intelligence'),
                ),
              ],
            );
          }
          final data = snapshot.data!;
          final facts = data['facts'] as Map;
          final sources = (facts['sources'] as List).cast<Map>();
          final ingredients = (data['ingredients'] as List).cast<Map>();
          final warnings = [
            ...(data['warnings'] as List).cast<Map>(),
            ...(data['routine_warnings'] as List? ?? []).cast<Map>(),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Product intelligence',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (data['state'] == 'unknown')
                const Text('Ingredient intelligence is unknown.'),
              if (data['data_completeness'] == 'incomplete')
                const Text(
                  'Partial data: ingredient information is incomplete.',
                ),
              for (final key in [
                'canonical_name',
                'brand',
                'manufacturer',
                'category',
                'product_type',
                'region',
                'formulation_variant',
                'dosage_form',
                'formulation_text',
              ])
                if (facts[key] != null)
                  Text(
                    '${key.replaceAll('_', ' ')}: ${facts[key]['value']} · source ${facts[key]['source_id']}',
                  ),
              for (final item in ingredients)
                Text(
                  '${item['name']} · ${item['strength'] == null ? 'Strength unknown' : item['strength']['value']} · source ${item['source_id']}'
                  '${item['strength'] == null ? '' : ' · strength source ${item['strength']['source_id']}'}',
                ),
              for (final source in sources)
                Text(
                  '${source['id']}: ${source['type']} · ${source['verification']} · ${source['confidence']} confidence · ${source['reference']}'
                  '${source['last_verified_at'] == null ? '' : ' · verified ${source['last_verified_at']}'}',
                ),
              for (final warning in warnings) ...[
                Text('${warning['severity']}: ${warning['explanation']}'),
                Text(
                  'Evidence confidence: ${warning['confidence']} · ${warning['data_completeness']} data',
                ),
              ],
              if (data['unknowns'] is List &&
                  (data['unknowns'] as List).isNotEmpty)
                Text('Unknown: ${(data['unknowns'] as List).join(', ')}'),
              for (final limitation in (data['limitations'] as List))
                Text(limitation.toString()),
              TextButton(
                onPressed: () => setState(_reload),
                child: const Text('Refresh intelligence'),
              ),
            ],
          );
        },
      ),
    ),
  );
}
