import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../services/google_auth_helper.dart';
import '../capture/capture_controller.dart';
import '../capture/capture_panel.dart';

class TesterEnvironment {
  static const baseUrl = String.fromEnvironment(
    'TESTER_API_BASE_URL',
    defaultValue: 'https://dermaire-api.azurewebsites.net/api/v1',
  );
  static String get label =>
      baseUrl == 'https://dermaire-api.azurewebsites.net/api/v1'
      ? 'TESTER • PRODUCTION'
      : 'TESTER • CUSTOM ENVIRONMENT';
}

class TestSessionSummary {
  final results = <String, String>{
    for (final flow in [
      'Google login',
      'Profile fetch',
      'Profile save',
      'Routine create',
      'Routine view',
      'Check-in',
      'Home / History',
      'Image upload',
      'AI request',
      'Delete account',
    ])
      flow: 'SKIPPED',
  };
  String export() =>
      '${TesterEnvironment.label}\n${results.entries.map((e) => '${e.key}: ${e.value}').join('\n')}';
  void reset() {
    results.updateAll((key, value) => 'SKIPPED');
  }
}

class TesterApp extends StatelessWidget {
  const TesterApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Dermaire Tester',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true),
    home: const TesterDashboard(),
  );
}

class TesterDashboard extends StatefulWidget {
  const TesterDashboard({super.key});
  @override
  State<TesterDashboard> createState() => _TesterDashboardState();
}

class _TesterDashboardState extends State<TesterDashboard> {
  final api = ApiService.instance;
  final summary = TestSessionSummary();
  late final capture = CaptureController(api.submitCapture);
  final goal = TextEditingController();
  final product = TextEditingController(text: 'Tester moisturizer');
  final question = TextEditingController(
    text: 'What should I track about my routine?',
  );
  String skin = 'normal', change = 'same', schedule = 'AM';
  String status = 'Use a disposable Google account and non-sensitive images.';
  List<String> routineRows = [], historyRows = [];
  String? busy;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    api.addListener(sessionChanged);
    capture.addListener(captureChanged);
  }

  void sessionChanged() {
    if (!api.isAuthenticated) {
      generation++;
      routineRows = [];
      historyRows = [];
      goal.clear();
      product.text = 'Tester moisturizer';
      question.text = 'What should I track about my routine?';
      status = 'Session ended. Sign in again.';
      skin = 'normal';
      capture.retake();
    }
    if (mounted) setState(() {});
  }

  void captureChanged() {
    if (capture.phase == CapturePhase.accepted ||
        capture.phase == CapturePhase.rejected) {
      summary.results['Image upload'] = 'PASS (${capture.phase.name})';
    } else if (capture.phase == CapturePhase.failure) {
      summary.results['Image upload'] = 'FAIL';
    }
    if (mounted) setState(() {});
  }

  Future<void> run(String flow, Future<String> Function() action) async {
    if (busy != null) return;
    final started = generation;
    setState(() {
      busy = flow;
      status = '$flow in progress…';
    });
    try {
      final message = await action().timeout(const Duration(seconds: 70));
      if (!mounted) return;
      if (started != generation &&
          flow != 'Delete account' &&
          flow != 'Logout') {
        summary.results[flow] = 'FAIL';
        status = 'Session ended. Sign in again and refresh before retrying.';
      } else {
        if (summary.results.containsKey(flow)) {
          summary.results[flow] = message.startsWith('SKIPPED:')
              ? 'SKIPPED'
              : 'PASS';
        }
        status = message;
      }
    } catch (_) {
      if (!mounted) return;
      if (summary.results.containsKey(flow)) summary.results[flow] = 'FAIL';
      status = api.isAuthenticated
          ? '$flow unconfirmed. Check connection and refresh before retrying. The server may have saved the request.'
          : '$flow failed or session expired. Sign in again. For Google, check OAuth package and signing certificate setup.';
    } finally {
      if (mounted) setState(() => busy = null);
    }
  }

  Future<String> fetchProfile() async {
    final row = await api.getCurrentUser();
    if (row == null) throw const FormatException();
    skin =
        [
          'normal',
          'dry',
          'oily',
          'combination',
          'sensitive',
        ].contains(row['skin_type'])
        ? row['skin_type'] as String
        : 'normal';
    goal.text = row['selected_goal'] as String? ?? '';
    return 'Profile loaded. Only skin type and goal are shown.';
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete test account?'),
        content: const Text(
          'This permanently deletes the signed-in tester account and its backend data, including images. This cannot be undone. Only continue with a disposable account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Permanently delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await run('Delete account', () async {
      if (!await api.deleteAccount()) throw const FormatException();
      try {
        await GoogleAuthHelper.signOut();
      } catch (_) {
        /* Backend session already cleared. */
      }
      return 'Test account deleted. Local session cleared.';
    });
  }

  @override
  void dispose() {
    api.removeListener(sessionChanged);
    capture.removeListener(captureChanged);
    capture.dispose();
    goal.dispose();
    product.dispose();
    question.dispose();
    super.dispose();
  }

  Widget button(String label, String flow, Future<String> Function() action) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: FilledButton(
          onPressed: busy != null ? null : () => run(flow, action),
          child: Text(label),
        ),
      );
  Widget choice(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> change,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: options
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList(),
    onChanged: busy != null ? null : (v) => setState(() => change(v!)),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(TesterEnvironment.label)),
    body: AbsorbPointer(
      absorbing: busy != null,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(TesterEnvironment.baseUrl),
          const Text(
            'Functional backend test harness. Use disposable accounts only.',
          ),
          if (busy != null) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(status),
          ),
          if (!api.isAuthenticated)
            button('Sign in with Google', 'Google login', () async {
              final token = await GoogleAuthHelper.signInAndGetIdToken();
              if (token == null) return 'SKIPPED: Google sign-in cancelled.';
              summary.reset();
              await api.loginWithGoogle(idToken: token);
              return 'Google login confirmed by backend. Fetch profile next.';
            }),
          if (api.isAuthenticated) ...[
            const Divider(),
            const Text('1. Profile / onboarding'),
            button('Fetch profile', 'Profile fetch', fetchProfile),
            choice('Skin type', skin, [
              'normal',
              'dry',
              'oily',
              'combination',
              'sensitive',
            ], (v) => skin = v),
            TextField(
              controller: goal,
              maxLength: 100,
              decoration: const InputDecoration(labelText: 'Tracking goal'),
            ),
            button('Save profile', 'Profile save', () async {
              await api.updateSkinProfile(
                skinType: skin,
                selectedGoal: goal.text.trim(),
              );
              return 'Profile saved. Fetch again to confirm persistence.';
            }),
            const Divider(),
            const Text(
              '2. Routine (creates a tester product and daily routine entry)',
            ),
            TextField(
              controller: product,
              maxLength: 150,
              decoration: const InputDecoration(labelText: 'Product name'),
            ),
            choice('Schedule', schedule, [
              'AM',
              'PM',
              'BOTH',
            ], (v) => schedule = v),
            button('Create routine', 'Routine create', () async {
              if (product.text.trim().length < 2) throw const FormatException();
              final p = await api.createProduct({
                'name': product.text.trim(),
                'category': 'moisturizer',
                'in_routine': false,
              });
              await api.routineRequest(
                'entries',
                method: 'POST',
                payload: {
                  'product_id': p['id'],
                  'schedule': schedule,
                  'frequency': 'daily',
                  'start_date': DateTime.now().toIso8601String().substring(
                    0,
                    10,
                  ),
                },
              );
              return 'Routine created. View routine to confirm persistence.';
            }),
            button('View routine', 'Routine view', () async {
              final rows = await api.routineRequest('entries') as List;
              routineRows = rows
                  .map(
                    (r) =>
                        '${r['product_name']} • ${r['schedule']} • ${r['active'] == true ? 'active' : 'ended'}',
                  )
                  .toList();
              return '${rows.length} routine entries loaded.';
            }),
            ...routineRows.map(Text.new),
            const Divider(),
            const Text('3. Check-in (self-reported, no invented measurements)'),
            choice('Overall change', change, [
              'better',
              'same',
              'worse',
            ], (v) => change = v),
            button('Create check-in', 'Check-in', () async {
              await api.submitCheckIn(
                timeOfDay: 'Morning',
                report: {
                  'overall_change': change,
                  'symptoms': <String>[],
                  'routine_status': 'not_applicable',
                },
              );
              return 'Check-in confirmed. Refresh history next.';
            }),
            button('Refresh Home / History', 'Home / History', () async {
              await api.getHome();
              final checks = await api.getCheckIns();
              final images = await api.getCaptureHistory();
              historyRows = [
                ...checks.map(
                  (r) =>
                      'Check-in • ${r['created_at']} • ${r['observation']?['user_reported']?['overall_change'] ?? 'measured'}',
                ),
                ...images.map(
                  (r) => 'Image • ${r['received_at']} • ${r['state']}',
                ),
              ];
              return 'Home loaded. ${checks.length} check-ins and ${images.length} captures persisted.';
            }),
            ...historyRows.map(Text.new),
            const Divider(),
            const Text('4. Upload image • real guided quality gate'),
            CapturePanel(controller: capture),
            const Divider(),
            const Text(
              '5. Contextual AI • current server provider configuration',
            ),
            TextField(
              controller: question,
              maxLength: 1000,
              decoration: const InputDecoration(labelText: 'Question'),
            ),
            button('Ask assistance', 'AI request', () async {
              final response = await api.requestAssistance(
                question.text.trim(),
              );
              final metadata = response['metadata'] as Map;
              final availability = metadata['availability'];
              if (availability != 'available') {
                summary.results['AI request'] = 'SKIPPED';
              }
              return '${availability == 'available' ? '' : 'SKIPPED: '}Assistance endpoint responded. Provider: $availability; mode: ${metadata['mode']}.\n${response['message']}';
            }),
            button('Logout', 'Logout', () async {
              await api.logout();
              try {
                await GoogleAuthHelper.signOut();
              } catch (_) {
                /* Local API session is cleared. */
              }
              return 'Signed out.';
            }),
            const Divider(),
            const Text('Danger • disposable accounts only'),
            TextButton(
              onPressed: busy == null ? delete : null,
              child: const Text(
                'Delete Test Account',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
          const Divider(),
          const Text('Test Session Summary • local only'),
          Text(summary.export()),
          TextButton(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: summary.export())),
            child: const Text('Copy safe summary'),
          ),
        ],
      ),
    ),
  );
}
