import 'package:flutter/material.dart';
import 'doctor_connection.dart';

/// Contextual routes never inherit authority from a formerly selected patient.
/// Losing/changing the original grant removes the child subtree and separates
/// raw uncertain drafts from minimum original identities before disposal.
class DoctorContextPage extends StatefulWidget {
  const DoctorContextPage({
    super.key,
    required this.connection,
    required this.child,
  });
  final DoctorConnectionController connection;
  final Widget child;
  @override
  State<DoctorContextPage> createState() => _DoctorContextPageState();
}

class _DoctorContextPageState extends State<DoctorContextPage> {
  String? originalGrant;
  @override
  void initState() {
    super.initState();
    originalGrant = widget.connection.grant?.id;
    widget.connection.addListener(changed);
  }

  void quarantine(DoctorConnectionController c) {
    final grant = originalGrant;
    if (grant != null) {
      c.parent.api.quarantineGrantOperations(grant, c.parent.generation);
    }
  }

  void changed() {
    final next = widget.connection.grant?.id;
    if (originalGrant != null &&
        (!widget.connection.confirmed || next != originalGrant)) {
      quarantine(widget.connection);
    }
    if (widget.connection.confirmed) originalGrant ??= next;
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant DoctorContextPage old) {
    super.didUpdateWidget(old);
    if (old.connection != widget.connection) {
      quarantine(old.connection);
      old.connection.removeListener(changed);
      originalGrant = widget.connection.grant?.id;
      widget.connection.addListener(changed);
    }
  }

  @override
  void dispose() {
    widget.connection.removeListener(changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.connection;
    if (!c.confirmed || c.grant?.id != originalGrant) {
      return Scaffold(
        appBar: AppBar(),
        body: const SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Patient context changed or access is unavailable. Return and select a currently authorized patient.',
              ),
            ),
          ),
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey(
        'doctor-context:${c.parent.generation}:${c.patientId}:${c.grant!.id}',
      ),
      child: widget.child,
    );
  }
}
