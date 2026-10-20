import '../integration/operation_identity.dart';
import '../services/api_service.dart';
import 'operation_journal.dart';
import 'product_receipt_reader.dart';
import 'configuration_receipt_reader.dart';
import 'clinical_receipt_reader.dart';
import 'adherence_receipt_reader.dart';
import 'message_receipt_reader.dart';
import 'plan_receipt_reader.dart';
import 'grant_receipt_reader.dart';

/// Read-only domain selection shared by memory review and explicitly injected
/// isolated journal qualification. Never constructs storage or mutation transport.
/// Unsupported contracts remain unsupported; this is not a universal receipt.
class RecoveryReaderCatalog {
  RecoveryReaderCatalog(this.api, this.generation)
    : owner = api.authenticatedOwner,
      role = api.authenticatedRole;
  final ApiService api;
  final int generation;
  final String? owner, role;
  bool get authorized =>
      owner != null &&
      api.isCurrentSession(generation) &&
      api.authenticatedOwner == owner &&
      api.authenticatedRole == role &&
      (role == 'doctor'
          ? api.canReadDoctorWorkspace
          : role == 'patient' && api.canReadPatientClinicalStatus);

  JournalReceiptReader? readerFor(OperationIdentity i) {
    if (!authorized || i.owner != owner || i.role != role) return null;
    try {
      if (i.path == 'doctor/claim' ||
          i.path == 'doctor/generate-qr' ||
          i.path.startsWith('doctor/access/') ||
          i.path.startsWith('doctor/revoke/')) {
        final reader = GrantReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (i.path.startsWith('messaging/threads/')) {
        final reader = MessageReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (i.path == 'clinical-plans' || i.path.startsWith('clinical-plans/')) {
        final reader = PlanReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (role == 'doctor') {
        final reader = ClinicalReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (role != 'patient') return null;
      if (i.path == 'routine/adherence') {
        final reader = AdherenceReceiptReader(api, generation);
        reader.contract(i);
        return reader;
      }
      if (i.path == 'products' || i.path.startsWith('products/')) {
        final reader = ProductReceiptReader(api, generation);
        reader.kind(i);
        return reader;
      }
      final reader = ConfigurationReceiptReader(api, generation);
      reader.contract(i);
      return reader;
    } on FormatException {
      return null;
    }
  }
}
