import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import '../integration/operation_identity.dart';

/// No runtime production composition uses this bridge. Never logs platform data.
abstract interface class JournalPlatform {
  Future<Uint8List> epoch();
  Future<String> directory(String namespace);
  Future<Uint8List> key(String namespace, {required bool create});
  Future<void> action(String namespace, String action);
}

class JournalUnavailable implements Exception {
  const JournalUnavailable([this.stage = 'unavailable']);
  final String stage;
  @override
  String toString() => 'Protected operation recovery unavailable';
}

class NativeJournalPlatform implements JournalPlatform {
  static const _channel = MethodChannel('dermaire/journal-keys-v1');
  Future<T> _call<T>(String method, String namespace) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(namespace)) {
      throw const JournalUnavailable();
    }
    try {
      final value = await _channel.invokeMethod<T>(method, {
        'namespace': namespace,
      });
      if (value == null) throw const JournalUnavailable();
      return value;
    } catch (_) {
      throw const JournalUnavailable();
    }
  }

  @override
  Future<Uint8List> epoch() async {
    final bytes = await _call<Uint8List>('epoch', '0' * 64);
    if (bytes.length != 32) throw const JournalUnavailable();
    return Uint8List.fromList(bytes);
  }

  @override
  Future<String> directory(String namespace) =>
      _call<String>('directory', namespace);
  @override
  Future<Uint8List> key(String namespace, {required bool create}) async {
    final bytes = await _call<Uint8List>(
      create ? 'createKey' : 'loadKey',
      namespace,
    );
    if (bytes.length != 32) throw const JournalUnavailable();
    return Uint8List.fromList(bytes);
  }

  @override
  Future<void> action(String namespace, String action) async {
    if (![
          'fence',
          'destroyKey',
          'eraseFiles',
          'protectFiles',
        ].contains(action) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(namespace)) {
      throw const JournalUnavailable();
    }
    try {
      await _channel.invokeMethod<void>(action, {'namespace': namespace});
    } on PlatformException catch (e) {
      final details = e.details;
      final reason = details is Map ? details['reason'] : null;
      final safe =
          reason is String &&
          RegExp(
            r'^(unavailable|syncOpen|syncCommit|fileProtectionMismatch|filesystem--?[0-9]{1,6})$',
          ).hasMatch(reason);
      throw JournalUnavailable(safe ? reason : 'native-action');
    } catch (_) {
      throw const JournalUnavailable();
    }
  }
}

/// Owner and role are encrypted inside the DB; filenames use an installation
/// random epoch and account digest. A fenced namespace is never reused.
class JournalNamespace {
  JournalNamespace._(this.owner, this.role, this.value);
  final String owner, role, value;
  static Future<JournalNamespace> resolve(
    JournalPlatform platform, {
    required String owner,
    required String role,
  }) async {
    // Reuse the same bounded account/role validation as existing identities.
    OperationIdentity(
      owner: owner,
      role: role,
      path: 'products',
      receiptPath: 'products/attempts',
      key: '0' * 48,
      fingerprint: '0' * 64,
    );
    final epoch = await platform.epoch();
    if (epoch.length != 32) throw const JournalUnavailable();
    return JournalNamespace._(
      owner,
      role,
      sha256.convert([
        ...epoch,
        ...utf8.encode(jsonEncode([owner, role])),
      ]).toString(),
    );
  }

  bool owns(OperationIdentity identity) =>
      identity.owner == owner && identity.role == role;
}
