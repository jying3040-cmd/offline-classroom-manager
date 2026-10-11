import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'db.dart';
import 'models.dart';

const Uuid _uuid = Uuid();

class Repo {
  // ---------- 班级 ----------

  static Future<List<Klass>> listClasses() async {
    final db = await AppDb.db;
    final rows = await db.query(
      'classes',
      where: 'archived = 0',
      orderBy: 'created_at',
    );
    return rows.map(Klass.fromMap).toList();
  }

  static Future<Klass> addClass(String name) async {
    final db = await AppDb.db;
    final klass = Klass(
      id: _uuid.v4(),
      name: name.trim(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await db.insert('classes', klass.toMap());
    return klass;
  }

  // ---------- 学生 ----------

  static Future<List<Student>> listStudents(String classId) async {
    final db = await AppDb.db;
    final rows = await db.query(
      'students',
      where: 'class_id = ? AND archived = 0',
      whereArgs: [classId],
      orderBy: 'seat_no IS NULL, seat_no, created_at',
    );
    return rows.map(Student.fromMap).toList();
  }

  static Future<void> addStudent({
    required String classId,
    required String name,
    int? seatNo,
    String? gender,
    String? groupName,
    int? memberNo,
  }) async {
    final db = await AppDb.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'students',
      Student(
        id: _uuid.v4(),
        classId: classId,
        name: name.trim(),
        seatNo: seatNo,
        gender: gender,
        groupName: _normalizeGroup(groupName),
        memberNo: _validateMemberNo(memberNo),
        createdAt: now,
        updatedAt: now,
      ).toMap(),
    );
  }

  /// 批量导入：一行一个名字，自动去重。
  static Future<int> addStudentsByName({
    required String classId,
    required List<String> names,
  }) async {
    if (names.isEmpty) return 0;
    final db = await AppDb.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (final name in names) {
      batch.insert(
        'students',
        Student(
          id: _uuid.v4(),
          classId: classId,
          name: name,
          createdAt: now,
          updatedAt: now,
        ).toMap(),
      );
    }
    await batch.commit(noResult: true);
    return names.length;
  }

  static Future<void> updateStudent({
    required Student existing,
    required String name,
    int? seatNo,
    String? gender,
    String? groupName,
    int? memberNo,
  }) async {
    final db = await AppDb.db;
    final updated = Student(
      id: existing.id,
      classId: existing.classId,
      name: name.trim(),
      seatNo: seatNo,
      gender: gender,
      groupName: _normalizeGroup(groupName),
      memberNo: _validateMemberNo(memberNo),
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await db.update(
      'students',
      updated.toMap(),
      where: 'id = ?',
      whereArgs: [existing.id],
    );
  }

  static Future<void> deleteStudent(String id) async {
    final db = await AppDb.db;
    await db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  static String? _normalizeGroup(String? value) {
    final name = value?.trim() ?? '';
    return name.isEmpty ? null : name;
  }

  static int? _validateMemberNo(int? value) {
    if (value != null && value <= 0) {
      throw ArgumentError('组员号必须为正整数');
    }
    return value;
  }

  // ---------- 小红花 ----------

  /// 班级内每个学生的红花合计。
  static Future<Map<String, int>> flowerTotals(String classId) async {
    final db = await AppDb.db;
    final rows = await db.rawQuery('''
      SELECT l.student_id AS sid, SUM(l.delta) AS total
      FROM flower_logs l
      JOIN students s ON s.id = l.student_id
      WHERE s.class_id = ? AND s.archived = 0
      GROUP BY l.student_id
    ''', [classId]);
    return {
      for (final r in rows) r['sid'] as String: (r['total'] as int?) ?? 0,
    };
  }

  static Future<void> awardFlower({
    required String studentId,
    required int delta,
    String? reason,
    String? refLogId,
  }) async {
    final db = await AppDb.db;
    await db.insert(
      'flower_logs',
      FlowerLog(
        id: _uuid.v4(),
        studentId: studentId,
        delta: delta,
        reason: reason,
        refLogId: refLogId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ).toMap(),
    );
  }

  /// 榜单：时间段内有正向得分的学生，按合计降序。
  static Future<List<LeaderRow>> flowerLeaderboard(
    String classId, {
    required int sinceMs,
  }) async {
    final db = await AppDb.db;
    final rows = await db.rawQuery('''
      SELECT s.id AS sid, s.name AS name, COALESCE(SUM(l.delta), 0) AS total
      FROM students s
      LEFT JOIN flower_logs l
        ON l.student_id = s.id AND l.created_at >= ?
      WHERE s.class_id = ? AND s.archived = 0
      GROUP BY s.id, s.name
      HAVING COALESCE(SUM(l.delta), 0) > 0
      ORDER BY total DESC, s.name
    ''', [sinceMs, classId]);
    return [
      for (final r in rows)
        LeaderRow(
          studentId: r['sid'] as String,
          name: r['name'] as String,
          total: (r['total'] as int?) ?? 0,
        ),
    ];
  }

  /// 班级流水时间线（今日页）。
  static Future<List<FlowerEntry>> classLogsSince(
    String classId, {
    required int sinceMs,
    int limit = 300,
  }) async {
    final db = await AppDb.db;
    final rows = await db.rawQuery('''
      SELECT l.*, s.name AS sname
      FROM flower_logs l
      JOIN students s ON s.id = l.student_id
      WHERE s.class_id = ? AND l.created_at >= ?
      ORDER BY l.created_at DESC, l.rowid DESC
      LIMIT ?
    ''', [classId, sinceMs, limit]);
    return [
      for (final r in rows)
        FlowerEntry(
          log: FlowerLog.fromMap(r),
          studentName: r['sname'] as String,
        ),
    ];
  }

  /// 单个学生的红花明细。
  static Future<List<FlowerEntry>> studentLogs(
    String studentId, {
    int limit = 100,
  }) async {
    final db = await AppDb.db;
    final rows = await db.rawQuery('''
      SELECT l.*, s.name AS sname
      FROM flower_logs l
      JOIN students s ON s.id = l.student_id
      WHERE l.student_id = ?
      ORDER BY l.created_at DESC, l.rowid DESC
      LIMIT ?
    ''', [studentId, limit]);
    return [
      for (final r in rows)
        FlowerEntry(
          log: FlowerLog.fromMap(r),
          studentName: r['sname'] as String,
        ),
    ];
  }

  // ---------- 抽签 ----------

  static Future<void> addDrawLog({
    required String classId,
    required List<Student> winners,
  }) async {
    final db = await AppDb.db;
    await db.insert('draw_logs', {
      'id': _uuid.v4(),
      'class_id': classId,
      'student_ids': jsonEncode(winners.map((s) => s.id).toList()),
      'names': jsonEncode(winners.map((s) => s.name).toList()),
      'count': winners.length,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  static Future<List<DrawRecord>> listDrawLogs(
    String classId, {
    int limit = 50,
  }) async {
    final db = await AppDb.db;
    final rows = await db.query(
      'draw_logs',
      where: 'class_id = ?',
      whereArgs: [classId],
      orderBy: 'created_at DESC, rowid DESC',
      limit: limit,
    );
    return rows.map(DrawRecord.fromMap).toList();
  }

  // ---------- 设置 ----------

  static Future<String?> getSetting(String key) async {
    final db = await AppDb.db;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  static Future<void> setSetting(String key, String value) async {
    final db = await AppDb.db;
    await db.execute(
      'INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  // ---------- 听写词表 ----------

  static Future<List<WordList>> listWordLists() async {
    final db = await AppDb.db;
    final rows = await db.rawQuery('''
      SELECT wl.*, COUNT(w.id) AS word_count
      FROM word_lists wl
      LEFT JOIN words w ON w.list_id = wl.id
      GROUP BY wl.id
      ORDER BY wl.created_at DESC, wl.rowid DESC
    ''');
    return rows.map(WordList.fromMap).toList();
  }

  static Future<WordList> createWordList(String title,
      {String? subject}) async {
    final db = await AppDb.db;
    final now = DateTime.now().millisecondsSinceEpoch;
    final list = WordList(
      id: _uuid.v4(),
      title: title.trim(),
      subject:
          (subject == null || subject.trim().isEmpty) ? null : subject.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('word_lists', list.toMap());
    return list;
  }

  static Future<void> deleteWordList(String id) async {
    final db = await AppDb.db;
    final words = await listWords(id);
    for (final w in words) {
      try {
        final f = File(w.audioFile);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {
        // 删除音频失败不阻塞，残留文件可下次清理。
      }
    }
    await db.delete('words', where: 'list_id = ?', whereArgs: [id]);
    await db.delete('word_lists', where: 'id = ?', whereArgs: [id]);
  }

  static Future<List<Word>> listWords(String listId) async {
    final db = await AppDb.db;
    final rows = await db.query(
      'words',
      where: 'list_id = ?',
      whereArgs: [listId],
      orderBy: 'sort, created_at, rowid',
    );
    return rows.map(Word.fromMap).toList();
  }

  /// 导入词条：先把音频复制进应用数据目录（UUID 命名），再写库。
  /// 先复制后写库，中途断电最多留一个孤儿文件，库不会脏。
  static Future<int> importWords({
    required String listId,
    required List<WordImportItem> items,
  }) async {
    if (items.isEmpty) return 0;
    final db = await AppDb.db;
    final dir = Directory(p.join(AppDb.dataDir, 'audio', listId));
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final now = DateTime.now().millisecondsSinceEpoch;
    final batch = db.batch();
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final newId = _uuid.v4();
      final target = p.join(dir.path, '$newId${item.ext}');
      File(item.sourcePath).copySync(target);
      batch.insert('words', {
        'id': newId,
        'list_id': listId,
        'text': item.word,
        'meaning': item.meaning,
        'audio_file': target,
        'orig_filename': item.origFilename,
        'duration_ms': item.durationMs,
        'sort': i,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
    await db.update(
      'word_lists',
      {'updated_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [listId],
    );
    return items.length;
  }

  static Future<void> deleteWord(Word w) async {
    final db = await AppDb.db;
    try {
      final f = File(w.audioFile);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // 同上：不阻塞。
    }
    await db.delete('words', where: 'id = ?', whereArgs: [w.id]);
  }

  // ---------- 红花记录删除 ----------

  /// 删除单条红花流水（明细页纠错用）。
  static Future<void> deleteFlowerLog(String logId) async {
    final db = await AppDb.db;
    await db.delete('flower_logs', where: 'id = ?', whereArgs: [logId]);
  }
}
