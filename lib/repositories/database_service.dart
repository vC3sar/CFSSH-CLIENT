import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/connection_profile.dart';
import '../models/connection_history.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('cfssh.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      const idType = 'TEXT PRIMARY KEY';
      const textType = 'TEXT NOT NULL';
      
      await db.execute('''
      CREATE TABLE connection_history (
        id $idType,
        profileId $textType,
        timestamp $textType
      )
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';
    const textNullableType = 'TEXT';

    await db.execute('''
CREATE TABLE profiles (
  id $idType,
  name $textType,
  host $textType,
  port $intType,
  username $textType,
  authMethod $textType,
  privateKeyId $textNullableType,
  timeout $intType,
  keepalive $intType,
  createdAt $textType,
  lastConnected $textType
)
''');

    await db.execute('''
CREATE TABLE connection_history (
  id $idType,
  profileId $textType,
  timestamp $textType
)
''');
  }

  Future<void> insertProfile(ConnectionProfile profile) async {
    final db = await instance.database;
    await db.insert(
      'profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ConnectionProfile>> getAllProfiles() async {
    final db = await instance.database;
    final result = await db.query('profiles', orderBy: 'lastConnected DESC');
    return result.map((json) => ConnectionProfile.fromMap(json)).toList();
  }

  Future<void> updateProfile(ConnectionProfile profile) async {
    final db = await instance.database;
    await db.update(
      'profiles',
      profile.toMap(),
      where: 'id = ?',
      whereArgs: [profile.id],
    );
  }

  Future<void> deleteProfile(String id) async {
    final db = await instance.database;
    await db.delete(
      'profiles',
      where: 'id = ?',
      whereArgs: [id],
    );
    // Also delete history
    await db.delete(
      'connection_history',
      where: 'profileId = ?',
      whereArgs: [id],
    );
  }

  // History Methods
  Future<void> insertHistory(ConnectionHistory history) async {
    final db = await instance.database;
    await db.insert(
      'connection_history',
      history.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ConnectionHistory>> getRecentHistory({int limit = 10}) async {
    final db = await instance.database;
    final result = await db.query(
      'connection_history',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
    return result.map((json) => ConnectionHistory.fromMap(json)).toList();
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
