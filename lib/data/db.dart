import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 应用数据库与本地数据目录的统一入口。
///
/// 数据库按“天生可同步”设计：所有表以 UUID 字符串为主键，
/// 记录携带毫秒时间戳，为后续导入导出/多端合并预留空间。
///
/// 不使用 path_provider 插件（规避 Windows symlink/开发人员模式要求），
/// 数据目录定位为 %APPDATA%\classroom_manager\data。
class AppDb {
  AppDb._();

  static Database? _db;
  static String? _dataDir;

  /// 应用数据目录（数据库与后续录音文件都存放在这里）。
  static String get dataDir => _dataDir ?? '';

  static Future<Database> get db async {
    final existing = _db;
    if (existing != null && existing.isOpen) return existing;
    return init();
  }

  /// 关闭数据库（备份/恢复前调用，确保 WAL 全部落盘）。
  /// 之后任何 db 访问都会自动重新打开。
  static Future<void> close() async {
    final existing = _db;
    _db = null;
    await existing?.close();
  }

  static Future<Database> init() async {
    sqfliteFfiInit();
    final appData =
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final dir = Directory(p.join(appData, 'classroom_manager', 'data'));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    _dataDir = dir.path;
    final database =
        await databaseFactoryFfi.openDatabase(p.join(dir.path, 'classroom.db'));
    await _migrate(database);
    _db = database;
    return database;
  }

  static Future<void> _migrate(Database database) async {
    await database.execute('PRAGMA foreign_keys = ON');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS classes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS students (
        id TEXT PRIMARY KEY,
        class_id TEXT NOT NULL,
        name TEXT NOT NULL,
        seat_no INTEGER,
        gender TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes(id)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_students_class ON students(class_id)',
    );
    // 兼容旧名单及旧备份；事务确保新增字段同时完成，重复启动不再迁移。
    await database.transaction((txn) async {
      final columns = await txn.rawQuery('PRAGMA table_info(students)');
      final names = columns.map((column) => column['name']).toSet();
      if (!names.contains('group_name')) {
        await txn.execute('ALTER TABLE students ADD COLUMN group_name TEXT');
      }
      if (!names.contains('member_no')) {
        await txn.execute('ALTER TABLE students ADD COLUMN member_no INTEGER');
      }
    });
    await database.execute('''
      CREATE TABLE IF NOT EXISTS flower_logs (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        delta INTEGER NOT NULL,
        reason TEXT,
        ref_log_id TEXT,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (student_id) REFERENCES students(id)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_flower_student ON flower_logs(student_id)',
    );
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_flower_time ON flower_logs(created_at)',
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS draw_logs (
        id TEXT PRIMARY KEY,
        class_id TEXT NOT NULL,
        student_ids TEXT NOT NULL,
        names TEXT NOT NULL,
        count INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes(id)
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS word_lists (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        subject TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS words (
        id TEXT PRIMARY KEY,
        list_id TEXT NOT NULL,
        text TEXT NOT NULL,
        meaning TEXT,
        audio_file TEXT NOT NULL,
        orig_filename TEXT,
        duration_ms INTEGER,
        sort INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (list_id) REFERENCES word_lists(id)
      )
    ''');
    await database.execute(
      'CREATE INDEX IF NOT EXISTS idx_words_list ON words(list_id)',
    );
  }
}
