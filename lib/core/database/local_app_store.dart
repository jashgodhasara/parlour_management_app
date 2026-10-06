import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalAppStore {
  static const _databaseName = 'parlour_local_store.db';
  static const _databaseVersion = 1;
  static const _stateTable = 'app_state';
  static const _stateKey = 'current';

  Database? _database;

  Future<String?> loadStateJson() async {
    final db = await _openDatabase();
    final rows = await db.query(
      _stateTable,
      columns: ['payload'],
      where: 'id = ?',
      whereArgs: [_stateKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['payload'] as String?;
  }

  Future<void> saveStateJson(String json) async {
    final db = await _openDatabase();
    await db.insert(
      _stateTable,
      {
        'id': _stateKey,
        'payload': json,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Database> _openDatabase() async {
    final existing = _database;
    if (existing != null) return existing;

    final databasesPath = await getDatabasesPath();
    final databasePath = p.join(databasesPath, _databaseName);
    _database = await openDatabase(
      databasePath,
      version: _databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_stateTable (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            updated_at TEXT NOT NULL
          )
        ''');
      },
    );
    return _database!;
  }
}
