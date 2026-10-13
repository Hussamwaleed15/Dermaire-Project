import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'routine_controller.dart';
import '../products/product_repository.dart';
import '../products/products_ui.dart';
import '../dermaire_state.dart';
import '../clinical/clinical_ui.dart';
import '../experiments/experiment_ui.dart';
import '../psm/psm_screen.dart';
import '../entry/entry_motion.dart';

class RoutineScreen extends StatefulWidget {
  const RoutineScreen({
    super.key,
    this.repository,
    this.stopEntryId,
    this.state,
    this.productId,
  });
  final DermaireState? state;
  final String? productId;
  final RoutineRepository? repository;
  // Passed from a server-confirmed active stop experiment; the API verifies it.
  final String? stopEntryId;
  @override
  State<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends State<RoutineScreen> {
  late final RoutineController controller;
  late final int generation;
  late String reportDay;
  bool get current =>
      widget.repository != null ||
      ApiService.instance.isCurrentSession(generation) &&
          ApiService.instance.canReadPatientClinicalStatus;
  @override
  void initState() {
    super.initState();
    generation = ApiService.instance.sessionGeneration;
    reportDay = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    controller = RoutineController(
      widget.repository ?? RemoteRoutineRepository(),
    );
    ApiService.instance.addListener(_sessionChanged);
    controller.refresh();
  }

  void _sessionChanged() {
    if (!current) controller.clear();
  }

  @override
  void dispose() {
    ApiService.instance.removeListener(_sessionChanged);
    controller.dispose();
    super.dispose();
  }

  String get day => reportDay;
  Future<void> _save(
    String resource,
    Map<String, dynamic> payload, {
    String method = 'POST',
  }) async {
    if (!current) return;
    final entry = controller.entries
        ?.where((e) => e['id'] == resource.split('/').last)
        .firstOrNull;
    final success = await controller.write(
      resource,
      payload,
      method: method,
      expectedUpdatedAt: entry?['updated_at'] as String?,
    );
    if (success && current) {
      await widget.state?.refreshRoutineContext(generation: generation);
    }
    if (mounted && current && success) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved on server')));
    }
  }

  Future<void> _editor([Map<String, dynamic>? entry]) async {
    if (!current || controller.stale || controller.saving) return;
    List<Map<String, dynamic>> products = [];
    if (entry == null) {
      try {
        products = (await RemoteProductRepository().fetchProducts())
            .where((p) => p.status.name == 'active')
            .map((p) => {'id': p.id, 'name': p.name})
            .toList();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Products unavailable')));
        }
        return;
      }
      if (!mounted || !current) return;
      if (products.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Save an active product first')),
        );
        return;
      }
    }
    if (!mounted || !current) return;
    final note = TextEditingController(
      text: entry?['instructions'] as String? ?? '',
    );
    final start = TextEditingController(text: day);
    final order = TextEditingController(text: '${entry?['am_order'] ?? 0}');
    final pmOrder = TextEditingController(text: '${entry?['pm_order'] ?? 0}');
    var productId =
        entry?['product_id'] as String? ?? products.first['id'] as String;
    var schedule = entry?['schedule'] as String? ?? 'AM';
    var pending = false;
    final form = GlobalKey<FormState>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: ApiService.instance,
        builder: (context, _) {
          if (!current) {
            note.clear();
            start.clear();
            order.clear();
            pmOrder.clear();
            return AlertDialog(
              title: const Text('Session ended'),
              content: const Text(
                'Draft cleared. Reopen from your current account.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Close'),
                ),
              ],
            );
          }
          return StatefulBuilder(
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
                          isExpanded: true,
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
                        isExpanded: true,
                        initialValue: schedule,
                        decoration: const InputDecoration(
                          labelText: 'Daily schedule',
                        ),
                        items: ['AM', 'PM', 'BOTH']
                            .map(
                              (s) => DropdownMenuItem(value: s, child: Text(s)),
                            )
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
                  onPressed: pending || controller.saving || controller.stale
                      ? null
                      : () async {
                          if (!current ||
                              pending ||
                              !form.currentState!.validate()) {
                            return;
                          }
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
                          setState(() {
                            pending = true;
                          });
                          final success = await controller.write(
                            entry == null
                                ? 'entries'
                                : 'entries/${entry['id']}',
                            payload,
                            method: entry == null ? 'POST' : 'PATCH',
                            expectedUpdatedAt: entry?['updated_at'] as String?,
                          );
                          if (!dialogContext.mounted || !current) return;
                          pending = false;
                          if (success) {
                            await widget.state?.refreshRoutineContext(
                              generation: generation,
                            );
                            if (!dialogContext.mounted || !current) return;
                            Navigator.pop(dialogContext);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(
                                const SnackBar(
                                  content: Text('Saved on server'),
                                ),
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
          );
        },
      ),
    );
    // Controllers belong to the dialog; dispose after the route animation ends.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    note.dispose();
    start.dispose();
    order.dispose();
    pmOrder.dispose();
  }

  Future<void> _product(Map<String, dynamic> entry) async {
    if (!current || widget.state == null) return;
    final state = widget.state!;
    await state.productController.load();
    if (!mounted || !current) return;
    if (state.productController.byId(entry['product_id'] as String) == null ||
        state.productController.isStale) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Associated product unavailable. Refresh and retry.'),
        ),
      );
      return;
    }
    await openEntry(
      context,
      ProductFeatureDetailScreen(
        state: state,
        productId: entry['product_id'] as String,
      ),
    );
    if (mounted && current) await controller.refresh();
  }

  Future<void> _experiments(Map<String, dynamic> entry) async {
    if (!current || widget.state == null) return;
    final state = widget.state!;
    await state.experiments.refresh();
    if (!mounted || !current) return;
    await openEntry(
      context,
      Scaffold(
        appBar: AppBar(title: const Text('Related experiments')),
        body: ExperimentsView(
          controller: state.experiments,
          state: state,
          routineEntryId: entry['id'] as String,
        ),
      ),
    );
    if (mounted && current) await controller.refresh();
  }

  Future<void> _chooseReportDay() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(day),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().toUtc(),
    );
    if (selected != null && mounted && current) {
      setState(() => reportDay = selected.toIso8601String().substring(0, 10));
    }
  }

  Iterable<Map<String, dynamic>> _group(String slot) {
    final rows = controller.entries!
        .where(
          (e) =>
              widget.productId == null || e['product_id'] == widget.productId,
        )
        .where(
          (e) => slot == 'Stopped'
              ? e['active'] == false
              : e['active'] == true &&
                    (e['schedule'] == slot || e['schedule'] == 'BOTH'),
        )
        .toList();
    rows.sort(
      (a, b) => (a[slot == 'PM' ? 'pm_order' : 'am_order'] as int).compareTo(
        b[slot == 'PM' ? 'pm_order' : 'am_order'] as int,
      ),
    );
    return rows;
  }

  Future<void> _stop(Map<String, dynamic> entry) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Stop this step?'),
        content: const Text(
          'History remains. Resume requires a new step; this does not schedule a comparison.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep step'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Stop step'),
          ),
        ],
      ),
    );
    if (yes == true && mounted && current) {
      await _save('entries/${entry['id']}', {'active': false}, method: 'PATCH');
    }
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
            tooltip: 'Refresh routine',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: !current
          ? const Center(child: Text('Session ended. Reopen your routine.'))
          : controller.loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (widget.state != null)
                  ClinicalHomePanel(controller: widget.state!.clinical),
                const Text(
                  'Cosmetic preferences, not clinician-directed treatment. Daily user-configured routine. Days and reports use UTC. Missing reports mean unknown adherence.',
                ),
                if (controller.error != null) ...[
                  Text(controller.error!),
                  TextButton(
                    onPressed: controller.refresh,
                    child: const Text('Retry'),
                  ),
                ],
                if (controller.entries != null) ...[
                  OutlinedButton(
                    onPressed: controller.saving ? null : _chooseReportDay,
                    child: Text('Report date: $day (UTC)'),
                  ),
                  const Text(
                    'Date is selected on this device; the server validates reporting eligibility. This is not a treatment deadline.',
                  ),
                  if (controller.saving)
                    const LinearProgressIndicator(
                      semanticsLabel: 'Waiting for server confirmation',
                    ),
                  if (widget.productId != null &&
                      !controller.entries!.any(
                        (e) => e['product_id'] == widget.productId,
                      ))
                    const Text('No linked routine steps for this product.'),
                  if (controller.entries!.isEmpty)
                    const Text('No routine configured'),
                  FilledButton(
                    onPressed:
                        controller.saving ||
                            controller.stale ||
                            controller.uncertain.contains('entries')
                        ? null
                        : () => _editor(),
                    child: const Text('Configure routine'),
                  ),
                  if (controller.stale)
                    const Text(
                      'Previously confirmed data may be stale. Changes are unavailable until refresh.',
                    ),
                  for (final group in ['AM', 'PM', 'Stopped']) ...[
                    Text(
                      group == 'AM'
                          ? 'Morning'
                          : group == 'PM'
                          ? 'Evening'
                          : 'Stopped steps',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final entry in _group(group))
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
                              if (widget.state != null)
                                Wrap(
                                  children: [
                                    TextButton(
                                      onPressed: () => _product(entry),
                                      child: const Text(
                                        'View associated product',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () => _experiments(entry),
                                      child: const Text('Related experiments'),
                                    ),
                                  ],
                                ),
                              if (entry['instructions'] != null)
                                Text(entry['instructions'] as String),
                              if (entry['active'] == true ||
                                  entry['id'] == widget.stopEntryId) ...[
                                if (entry['active'] == true)
                                  Wrap(
                                    children: [
                                      TextButton(
                                        onPressed:
                                            controller.saving ||
                                                controller.stale ||
                                                controller.stale ||
                                                controller.uncertain.contains(
                                                  "entries/${entry['id']}",
                                                )
                                            ? null
                                            : () => _editor(entry),
                                        child: const Text('Edit'),
                                      ),
                                      TextButton(
                                        onPressed:
                                            controller.saving ||
                                                controller.stale ||
                                                controller.stale ||
                                                controller.uncertain.contains(
                                                  "entries/${entry['id']}",
                                                )
                                            ? null
                                            : () => _stop(entry),
                                        child: const Text('Stop'),
                                      ),
                                    ],
                                  ),
                                for (final report in controller.history!.where(
                                  (h) =>
                                      h['routine_entry_id'] == entry['id'] &&
                                      h['date'] == day &&
                                      (group == 'Stopped' ||
                                          h['slot'] == group),
                                ))
                                  Text(
                                    '${report['slot']} · Server-confirmed ${report['status']} report · ${report['date']} UTC',
                                  ),
                                for (final slot
                                    in group == 'Stopped'
                                        ? (entry['schedule'] == 'BOTH'
                                              ? ['AM', 'PM']
                                              : [entry['schedule'] as String])
                                        : [group])
                                  Wrap(
                                    children: [
                                      for (final status
                                          in entry['active'] == true
                                              ? ['completed', 'skipped']
                                              : ['skipped'])
                                        TextButton(
                                          onPressed:
                                              controller.saving ||
                                                  controller.stale ||
                                                  controller.uncertain.contains(
                                                    'adherence:${entry['id']}:$day:$slot',
                                                  ) ||
                                                  controller.history!.any(
                                                    (h) =>
                                                        h['routine_entry_id'] ==
                                                            entry['id'] &&
                                                        h['date'] == day &&
                                                        h['slot'] == slot,
                                                  )
                                              ? null
                                              : () => _save('adherence', {
                                                  'routine_entry_id':
                                                      entry['id'],
                                                  'date': day,
                                                  'slot': slot,
                                                  'status': status,
                                                }),
                                          child: Text(
                                            '$slot $status ${day == DateTime.now().toUtc().toIso8601String().substring(0, 10) ? 'today' : day}',
                                          ),
                                        ),
                                    ],
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (widget.state != null)
                    PersonalSkinModelEntry(state: widget.state!),
                  Text(
                    'Reported history · ${controller.history!.length} loaded records (UTC). No overall adherence or clinical progress inferred.',
                  ),
                  if (controller.history!.isEmpty)
                    const Text('No adherence reported'),
                  if (controller.historyHasMore)
                    TextButton(
                      onPressed: controller.loadingMore || controller.stale
                          ? null
                          : controller.loadMoreHistory,
                      child: Text(
                        controller.loadingMore
                            ? 'Loading reports…'
                            : 'Load older reports',
                      ),
                    ),
                  for (final row in controller.history!)
                    ListTile(
                      title: Text(
                        '${row['date']} ${row['slot']} · ${row['status']}',
                      ),
                      subtitle: Text(
                        '${(row['configuration_snapshot'] as Map)['product_name']} · user reported\nRecorded ${row['created_at']} · Snapshot schedule ${(row['configuration_snapshot'] as Map)['schedule']}${row['note'] == null ? '' : '\nNote: ${row['note']}'}',
                      ),
                    ),
                ],
              ],
            ),
    ),
  );
}
