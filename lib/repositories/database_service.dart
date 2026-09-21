import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/connection_profile.dart';
import '../models/connection_history.dart';
import '../models/ssh_key_model.dart';

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
      version: 3,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    const idType = 'TEXT PRIMARY KEY';
    const textType = 'TEXT NOT NULL';

    if (oldVersion < 2) {
      await db.execute('''
      CREATE TABLE connection_history (
        id $idType,
        profileId $textType,
        timestamp $textType
      )
      ''');
    }

    if (oldVersion < 3) {
      await db.execute('''
      CREATE TABLE ssh_keys (
        id $idType,
        name $textType,
        keyType $textType,
        publicKey $textType,
        fingerprint $textType,
        createdAt $textType
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

    await db.execute('''
CREATE TABLE ssh_keys (
  id $idType,
  name $textType,
  keyType $textType,
  publicKey $textType,
  fingerprint $textType,
  createdAt $textType
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
    // Remove previous entries for the same profileId to avoid duplicates
    await db.delete(
      'connection_history',
      where: 'profileId = ?',
      whereArgs: [history.profileId],
    );
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

  // SSH Key Methods
  Future<void> insertSshKey(SshKeyModel key) async {
    final db = await instance.database;
    await db.insert(
      'ssh_keys',
      key.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<SshKeyModel>> getAllSshKeys() async {
    final db = await instance.database;
    final result = await db.query('ssh_keys', orderBy: 'createdAt DESC');
    return result.map((json) => SshKeyModel.fromMap(json)).toList();
  }

  Future<SshKeyModel?> getSshKeyById(String id) async {
    final db = await instance.database;
    final result = await db.query(
      'ssh_keys',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (result.isNotEmpty) {
      return SshKeyModel.fromMap(result.first);
    }
    return null;
  }

  Future<void> deleteSshKey(String id) async {
    final db = await instance.database;
    await db.delete(
      'ssh_keys',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}

