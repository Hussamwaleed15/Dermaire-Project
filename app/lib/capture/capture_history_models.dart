import 'dart:typed_data';
import 'guided_capture_models.dart';

// Stored images are re-encoded PNG by the server, so the upload's 8 MiB
// limit is not a valid download bound. Refuse larger downloads honestly.
const maxPrivateImageBytes = 64 * 1024 * 1024;
const maxPrivateSourcePixels = 16000000;
const maxPrivateDecodedPixels = 12000000;
const privateThumbnailEdge = 256;
const privateViewerEdge = 1600;

class PrivateImageBytes {
  const PrivateImageBytes(this.bytes, this.mime);
  final Uint8List bytes;
  final String mime;
}

class PrivateCaptureException implements Exception {
  const PrivateCaptureException(this.status);
  final int status;
}

List<GuidedCaptureRecord> parseCaptureHistory(Object? data, String owner) {
  if (data is! List || data.length > 100) {
    throw const FormatException('Unsupported capture history');
  }
  final ids = <String>{};
  final records = data.map((row) {
    final record = GuidedCaptureRecord.fromApi(
      row as Map<String, dynamic>,
      owner: owner,
      readback: true,
    );
    if (!ids.add(record.id)) {
      throw const FormatException('Duplicate capture identity');
    }
    return record;
  }).toList();
  records.sort((a, b) {
    final time = b.receivedAt.compareTo(a.receivedAt);
    return time != 0 ? time : b.id.compareTo(a.id);
  });
  return List.unmodifiable(records);
}

String captureDate(DateTime time) =>
    time.toUtc().toIso8601String().substring(0, 10);
String captureTime(DateTime time) =>
    '${time.toUtc().toIso8601String()} (server receipt, UTC)';

String captureReadError(Object error, {bool image = false}) {
  if (error is PrivateCaptureException) {
    if (error.status == 404) {
      return image
          ? 'Image unavailable. Metadata does not guarantee stored bytes are still available.'
          : 'Capture information is unavailable.';
    }
    if (error.status == 403) {
      return 'Access was denied. Retry after checking your account.';
    }
    if (error.status == 401) return 'Session expired. Sign in again.';
    if (error.status >= 500) {
      return 'Server temporarily unavailable. Please retry.';
    }
  }
  if (error is FormatException || error is TypeError) {
    return image
        ? 'Image is unsupported, unreadable or exceeds the memory limit.'
        : 'The server returned unsupported capture information. Please retry.';
  }
  return 'Could not read ${image ? 'the private image' : 'capture information'}. Check your connection and retry.';
}
