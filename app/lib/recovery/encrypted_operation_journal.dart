import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import '../integration/operation_identity.dart';
import 'journal_platform.dart';
import 'operation_journal.dart';

/// SQLCipher adapter. Deliberately absent from main.dart and ApiService factories.
/// No production rollout switch or mutation fallback is provided.
class EncryptedOperationJournal implements OperationJournal {
  EncryptedOperationJournal._(
    this._db,
    this.platform,
    this.namespace,
    this.active,
    this.directory,
  );
  final Database _db;
  final JournalPlatform platform;
  final JournalNamespace namespace;
  final bool Function() active;
  final String directory;
  bool _closed = false;

  static Future<EncryptedOperationJournal> open({
    required JournalPlatform platform,
    required JournalNamespace namespace,
    required bool Function() active,
  }) async {
    Database? db;
    var stage = 'directory';
    try {
      if (!active()) throw RecoverySessionLost();
      final path = await platform.directory(namespace.value);
      if (!active()) throw RecoverySessionLost();
      final dir = Directory(path);
      // Any persistent artifact means this is NOT a new journal. Never rekey.
      final existing = dir.listSync().isNotEmpty;
      stage = 'protected-key';
      final key = await platform.key(namespace.value, create: !existing);
      try {
        if (!active()) throw RecoverySessionLost();
        stage = 'cipher-initialization';
        db = sqlite3.open('$path/operations.db');
        final cipher = db.select('PRAGMA cipher_version');
        if (cipher.isEmpty || (cipher.first.values.first as String).isEmpty) {
          throw const JournalUnavailable();
        }
        final hex = key.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
        db.execute('PRAGMA key = "x\'$hex\'"');
      } finally {
        key.fillRange(0, key.length, 0);
      }
      stage = 'cipher-settings';
      db.execute('PRAGMA cipher_plaintext_header_size=0');
      db.execute('PRAGMA cipher_memory_security=ON');
      db.execute('PRAGMA temp_store=MEMORY');
      db.execute('PRAGMA busy_timeout=3000');
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA synchronous=FULL');
      if (db.select('PRAGMA journal_mode').first.values.first != 'wal' ||
          db.select('PRAGMA synchronous').first.values.first != 2 ||
          db.select('PRAGMA temp_store').first.values.first != 2 ||
          db.select('PRAGMA cipher_plaintext_header_size').first.values.first !=
              '0' ||
          db.select('PRAGMA cipher_memory_security').first.values.first !=
              '1') {
        throw const JournalUnavailable();
      }
      stage = 'schema';
      final version = db.select('PRAGMA user_version').first.values.first;
      if (!existing) {
        if (version != 0) throw const JournalUnavailable();
        db.execute('BEGIN IMMEDIATE');
        try {
          db.execute(
            'CREATE TABLE binding (owner TEXT NOT NULL, role TEXT NOT NULL) STRICT',
          );
          db.execute('INSERT INTO binding VALUES (?, ?)', [
            namespace.owner,
            namespace.role,
          ]);
          db.execute(
            'CREATE TABLE operations (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT',
          );
          db.execute('PRAGMA user_version=1');
          db.execute('COMMIT');
        } catch (_) {
          db.execute('ROLLBACK');
          rethrow;
        }
      } else if (version != 1) {
        throw const JournalUnavailable(); // No destructive automatic migration.
      }
      stage = 'integrity-binding';
      final binding = db.select('SELECT owner, role FROM binding');
      if (binding.length != 1 ||
          binding.first['owner'] != namespace.owner ||
          binding.first['role'] != namespace.role ||
          db.select('PRAGMA integrity_check').single.values.first != 'ok' ||
          db.select('PRAGMA cipher_integrity_check').isNotEmpty) {
        throw const JournalUnavailable();
      }
      stage = 'file-protection';
      await platform.action(namespace.value, 'protectFiles');
      if (!active()) throw RecoverySessionLost();
      return EncryptedOperationJournal._(db, platform, namespace, active, path);
    } catch (_) {
      db?.close();
      throw JournalUnavailable(stage);
    }
  }

  void _guard([OperationIdentity? identity]) {
    if (_closed ||
        !active() ||
        (identity != null && !namespace.owns(identity))) {
      throw RecoverySessionLost();
    }
  }

  T _transaction<T>(T Function() action) {
    _guard();
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _guard();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  JournalEntry? _read(OperationIdentity i) {
    final rows = _db.select('SELECT value FROM operations WHERE key=?', [
      i.key,
    ]);
    if (rows.isEmpty) return null;
    final entry = JournalEntry.decode(rows.single['value'] as String);
    if (jsonEncode(entry.identity.toJson()) != jsonEncode(i.toJson())) {
      throw const JournalUnavailable();
    }
    return entry;
  }

  @override
  Future<JournalEntry?> read(OperationIdentity identity) async {
    _guard(identity);
    try {
      return _read(identity);
    } catch (_) {
      throw const JournalUnavailable();
    }
  }

  /// Reauthentication and safety/grant validation belong to active()/reader.
  /// No payload is restored and no mutation is resent by this method.
  Future<List<JournalEntry>> pending() async {
    _guard();
    try {
      final rows = _db.select(
        'SELECT value FROM operations ORDER BY key LIMIT 1001',
      );
      if (rows.length > 1000) throw const JournalUnavailable();
      final entries = rows
          .map((r) => JournalEntry.decode(r['value'] as String))
          .toList();
      if (entries.any((e) => !namespace.owns(e.identity))) {
        throw const JournalUnavailable();
      }
      return List.unmodifiable(entries);
    } catch (_) {
      throw const JournalUnavailable();
    }
  }

  @override
  Future<void> insertDurably(JournalEntry entry) async {
    _guard(entry.identity);
    try {
      _transaction(() {
        if (entry.phase != JournalPhase.prepared ||
            _db.select('SELECT count(*) AS n FROM operations').single['n']
                    as int >=
                1000) {
          throw const JournalUnavailable();
        }
        // Decode enforces serialized bounds before any record can be written.
        final encoded = JournalEntry.decode(entry.encode()).encode();
        _db.execute('INSERT INTO operations VALUES (?, ?)', [
          entry.identity.key,
          encoded,
        ]);
      });
      await platform.action(namespace.value, 'protectFiles');
      _guard(entry.identity);
    } catch (_) {
      throw const JournalUnavailable();
    }
  }

  @override
  Future<void> replaceDurably(JournalEntry entry, JournalPhase expected) async {
    _guard(entry.identity);
    try {
      _transaction(() {
        final old = _read(entry.identity);
        if (old == null ||
            old.phase != expected ||
            entry.phase == JournalPhase.prepared ||
            old.createdAt != entry.createdAt ||
            old.reviewAt != entry.reviewAt) {
          throw const JournalUnavailable();
        }
        final value = JournalEntry.decode(entry.encode()).encode();
        _db.execute('UPDATE operations SET value=? WHERE key=?', [
          value,
          entry.identity.key,
        ]);
      });
      await platform.action(namespace.value, 'protectFiles');
      _guard(entry.identity);
    } catch (_) {
      throw const JournalUnavailable();
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }

  /// Caller hides private views synchronously first. Interrupted cleanup leaves
  /// the persistent native fence. Retry cleanup without opening the journal.
  Future<void> erase() async {
    close();
    await eraseNamespace(platform, namespace);
  }

  static Future<void> eraseNamespace(
    JournalPlatform platform,
    JournalNamespace ns,
  ) async {
    await platform.action(ns.value, 'fence');
    await platform.action(ns.value, 'destroyKey');
    await platform.action(ns.value, 'eraseFiles');
  }
}
