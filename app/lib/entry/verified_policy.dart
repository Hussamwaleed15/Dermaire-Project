import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class VerifiedPolicy {
  VerifiedPolicy(this.version, this.document);
  final String version, document;
}

class PolicyMetadata {
  PolicyMetadata(Map<String, dynamic> value) {
    if (value['schema_version'] != 1 ||
        value['required_version'] is! String ||
        !RegExp(r'^[0-9]+\.[0-9]+$').hasMatch(value['required_version']) ||
        (value['required_version'] as String).length > 20 ||
        value['enforcement_enabled'] is! bool ||
        value['acceptance_ready'] is! bool ||
        !['approved', 'unavailable'].contains(value['document_status'])) {
      throw const FormatException('Unsupported safety policy');
    }
    version = value['required_version'];
    ready = value['acceptance_ready'];
    if (!ready) {
      if (value['document_status'] != 'unavailable' ||
          value['document'] != null) {
        throw const FormatException('Inconsistent safety policy');
      }
      return;
    }
    final document = value['document'];
    if (value['document_status'] != 'approved' ||
        document is! Map ||
        document['url'] is! String ||
        document['sha256'] is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(document['sha256'])) {
      throw const FormatException('Unverified policy reference');
    }
    url = Uri.parse(document['url']);
    if (url!.scheme != 'https' ||
        url!.host.isEmpty ||
        url!.userInfo.isNotEmpty ||
        url!.hasFragment) {
      throw const FormatException('Unsafe policy reference');
    }
    if (url!.host == 'localhost' ||
        url!.host.endsWith('.localhost') ||
        RegExp(r'^[0-9.]+$').hasMatch(url!.host) ||
        url!.host.contains(':')) {
      throw const FormatException('Unsupported policy host');
    }
    digest = (document['sha256'] as String).toLowerCase();
  }
  late final String version;
  late final bool ready;
  Uri? url;
  String? digest;

  Future<VerifiedPolicy> download(http.Client client) async {
    if (!ready || url == null) throw StateError('Approved policy unavailable');
    final response = await client
        .send(http.Request('GET', url!)..followRedirects = false)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200 ||
        response.headers['content-type']?.split(';').first != 'text/plain' ||
        (response.contentLength ?? 0) > 262144) {
      throw const FormatException('Policy document unavailable or unsupported');
    }
    final bytes = BytesBuilder();
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 15),
    )) {
      if (bytes.length + chunk.length > 262144) {
        throw const FormatException('Policy document exceeds limit');
      }
      bytes.add(chunk);
    }
    final raw = bytes.takeBytes();
    if (sha256.convert(raw).toString() != digest) {
      throw const FormatException('Policy document verification failed');
    }
    final text = utf8.decode(raw);
    if (text.trim().isEmpty || text.contains('\u0000')) {
      throw const FormatException('Unsupported policy text');
    }
    return VerifiedPolicy(version, text);
  }
}
