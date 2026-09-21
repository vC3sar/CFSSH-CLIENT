import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/connection_profile.dart';

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
      version: 1,
      onCreate: _createDB,
    );
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
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}
