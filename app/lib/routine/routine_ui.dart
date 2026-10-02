import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'routine_controller.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({super.key, this.repository});
  final RoutineRepository? repository;
  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  late final RoutineController controller;
  @override
  void initState() {
    super.initState();
    controller = RoutineController(
      widget.repository ?? RemoteRoutineRepository(),
    );
    ApiService.instance.addListener(_sessionChanged);
    controller.refresh();
  }

  void _sessionChanged() => controller.clear();
  @override
  void dispose() {
    ApiService.instance.removeListener(_sessionChanged);
    controller.dispose();
    super.dispose();
  }

  String get day => DateTime.now().toUtc().toIso8601String().substring(0, 10);
  Future<void> _save(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    final success = await controller.write(resource, payload, method: method);
    if (mounted && success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved on server')));
    }
  }

  Future<void> _editor([Map<String, dynamic>? entry]) async {
    List<Map<String, dynamic>> products = [];
    if (entry == null) {
      try {
        products = (await ApiService.instance.getProducts())
            .where((p) => p['status'] == 'active')
            .toList();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Products unavailable')));
        }
        return;
      }
      if (!mounted) return;
      if (products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save an active product first')),
        );
        return;
      }
    }
    if (!mounted) return;
    final note = TextEditingController(
      text: entry?['instructions'] as String? ?? '',
    );
    final start = TextEditingController(text: day);
    final order = TextEditingController(text: '${entry?['am_order'] ?? 0}');
    final pmOrder = TextEditingController(text: '${entry?['pm_order'] ?? 0}');
    var productId =
        entry?['product_id'] as String? ?? products.first['id'] as String;
    var schedule = entry?['schedule'] as String? ?? 'AM';
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            entry == null ? 'Configure daily routine' : 'Edit routine',
          ),
          content: SingleChildScrollView(
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry == null)
                    DropdownButtonFormField<String>(
                      initialValue: productId,
                      decoration: const InputDecoration(
                        labelText: 'Saved product',
                      ),
                      items: products
                          .map(
                            (p) => DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(p['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => productId = v!),
                    ),
                  DropdownButtonFormField<String>(
                    initialValue: schedule,
                    decoration: const InputDecoration(
                      labelText: 'Daily schedule',
                    ),
                    items: ['AM', 'PM', 'BOTH']
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => schedule = v!),
                  ),
                  if (entry == null)
                    TextFormField(
                      controller: start,
                      decoration: const InputDecoration(
                        labelText: 'Start date (YYYY-MM-DD, UTC)',
                      ),
                      validator: (v) =>
                          v != null &&
                              RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) &&
                              DateTime.tryParse(v) != null
                          ? null
                          : 'Enter a valid date',
                    ),
                  TextFormField(
                    controller: order,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'AM sequence (0–100)',
                    ),
                    validator: _orderValidator,
                  ),
                  TextFormField(
                    controller: pmOrder,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'PM sequence (0–100)',
                    ),
                    validator: _orderValidator,
                  ),
                  TextFormField(
                    controller: note,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                      labelText: 'Your instructions / notes',
                    ),
                  ),
                  const Text(
                    'Configuration does not confirm use. Record completed or skipped separately.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: controller.saving
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      final payload = <String, dynamic>{
                        'schedule': schedule,
                        'frequency': 'daily',
                        'instructions': note.text,
                        'am_order': int.parse(order.text),
                        'pm_order': int.parse(pmOrder.text),
                      };
                      if (entry == null) {
                        payload['product_id'] = productId;
                        payload['start_date'] = start.text;
                      }
                      setState(() {});
                      final success = await controller.write(
                        entry == null ? 'entries' : 'entries/${entry['id']}',
                        payload,
                        method: entry == null ? 'POST' : 'PATCH',
                      );
                      if (!dialogContext.mounted) return;
                      if (success) {
                        Navigator.pop(dialogContext);
                        if (mounted) {
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            const SnackBar(content: Text('Saved on server')),
                          );
                        }
                      } else {
                        setState(() {});
                        ScaffoldMessenger.of(dialogContext).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Save unconfirmed. Your draft is still here.',
                            ),
                          ),
                        );
                      }
                    },
              child: const Text('Save on server'),
            ),
          ],
        ),
      ),
    );
    // Controllers belong to the dialog; dispose after the route animation ends.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    note.dispose();
    start.dispose();
    order.dispose();
    pmOrder.dispose();
  }

  String? _orderValidator(String? v) {
    final n = int.tryParse(v ?? '');
    return n != null && n >= 0 && n <= 100 ? null : 'Enter 0–100';
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('My routine'),
        actions: [
          IconButton(
            onPressed: controller.loading || controller.saving
                ? null
                : controller.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: controller.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Daily user-configured routine. Days and reports use UTC. Missing reports mean unknown adherence.',
                ),
                if (controller.error != null) ...[
                  Text(controller.error!),
                  TextButton(
                    onPressed: controller.refresh,
                    child: const Text('Retry'),
                  ),
                ],
                if (controller.entries != null) ...[
                  if (controller.entries!.isEmpty)
                    const Text('No routine configured'),
                  FilledButton(
                    onPressed: controller.saving ? null : () => _editor(),
                    child: const Text('Configure routine'),
                  ),
                  for (final entry in controller.entries!)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${entry['product_name']} · ${entry['schedule']} · daily',
                            ),
                            Text(
                              '${entry['active'] == true ? 'Active' : 'Stopped'} · Start ${entry['start_date']}',
                            ),
                            if (entry['instructions'] != null)
                              Text(entry['instructions'] as String),
                            if (entry['active'] == true) ...[
                              Wrap(
                                children: [
                                  TextButton(
                                    onPressed: controller.saving
                                        ? null
                                        : () => _editor(entry),
                                    child: const Text('Edit'),
                                  ),
                                  TextButton(
                                    onPressed: controller.saving
                                        ? null
                                        : () => _save(
                                            'entries/${entry['id']}',
                                            {'active': false},
                                            method: 'PATCH',
                                          ),
                                    child: const Text('Stop'),
                                  ),
                                ],
                              ),
                              for (final slot
                                  in entry['schedule'] == 'BOTH'
                                      ? ['AM', 'PM']
                                      : [entry['schedule'] as String])
                                Wrap(
                                  children: [
                                    for (final status in [
                                      'completed',
                                      'skipped',
                                    ])
                                      TextButton(
                                        onPressed:
                                            controller.saving ||
                                                controller.history!.any(
                                                  (h) =>
                                                      h['routine_entry_id'] ==
                                                          entry['id'] &&
                                                      h['date'] == day &&
                                                      h['slot'] == slot,
                                                )
                                            ? null
                                            : () => _save('adherence', {
                                                'routine_entry_id': entry['id'],
                                                'date': day,
                                                'slot': slot,
                                                'status': status,
                                              }),
                                        child: Text('$slot $status today'),
                                      ),
                                  ],
                                ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  const Text(
                    'Recent reports (latest 100; full history available through the API)',
                  ),
                  if (controller.history!.isEmpty)
                    const Text('No adherence reported'),
                  for (final row in controller.history!)
                    ListTile(
                      title: Text(
                        '${row['date']} ${row['slot']} · ${row['status']}',
                      ),
                      subtitle: Text(
                        '${(row['configuration_snapshot'] as Map)['product_name']} · user reported',
                      ),
                    ),
                ],
              ],
            ),
    ),
  );
}
