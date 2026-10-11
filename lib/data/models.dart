import 'dart:convert';

/// 班级。`class` 是 Dart 保留字，故命名为 Klass。
class Klass {
  Klass({
    required this.id,
    required this.name,
    required this.createdAt,
    this.archived = 0,
  });

  final String id;
  final String name;
  final int createdAt;
  final int archived;

  factory Klass.fromMap(Map<String, Object?> map) => Klass(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: map['created_at'] as int,
        archived: (map['archived'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt,
        'archived': archived,
      };
}

class Student {
  Student({
    required this.id,
    required this.classId,
    required this.name,
    this.seatNo,
    this.gender,
    this.groupName,
    this.memberNo,
    this.archived = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String classId;
  final String name;
  final int? seatNo;
  final String? gender;
  final String? groupName;
  final int? memberNo;

  String get groupLabel => [
        if (groupName != null && groupName!.isNotEmpty)
          groupName!.endsWith('小组') ? groupName! : '${groupName!}小组',
        if (memberNo != null) '$memberNo号组员',
      ].join(' · ');
  final int archived;
  final int createdAt;
  final int updatedAt;

  factory Student.fromMap(Map<String, Object?> map) => Student(
        id: map['id'] as String,
        classId: map['class_id'] as String,
        name: map['name'] as String,
        seatNo: map['seat_no'] as int?,
        gender: map['gender'] as String?,
        groupName: map['group_name'] as String?,
        memberNo: map['member_no'] as int?,
        archived: (map['archived'] as int?) ?? 0,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'class_id': classId,
        'name': name,
        'seat_no': seatNo,
        'gender': gender,
        'group_name': groupName,
        'member_no': memberNo,
        'archived': archived,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// 红花流水。只增不改：撤销=插入反向记录（ref_log_id 指向原记录），
/// 这样多端数据合并时只需取并集，无需冲突处理。
class FlowerLog {
  FlowerLog({
    required this.id,
    required this.studentId,
    required this.delta,
    this.reason,
    this.refLogId,
    required this.createdAt,
  });

  final String id;
  final String studentId;

  /// 正数=奖励，负数=扣减/撤销。
  final int delta;
  final String? reason;
  final String? refLogId;
  final int createdAt;

  factory FlowerLog.fromMap(Map<String, Object?> map) => FlowerLog(
        id: map['id'] as String,
        studentId: map['student_id'] as String,
        delta: map['delta'] as int,
        reason: map['reason'] as String?,
        refLogId: map['ref_log_id'] as String?,
        createdAt: map['created_at'] as int,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'student_id': studentId,
        'delta': delta,
        'reason': reason,
        'ref_log_id': refLogId,
        'created_at': createdAt,
      };
}

/// 榜单聚合行。
class LeaderRow {
  LeaderRow({required this.studentId, required this.name, required this.total});

  final String studentId;
  final String name;
  final int total;
}

/// 流水 + 学生姓名的联表行（时间线/明细用）。
class FlowerEntry {
  FlowerEntry({required this.log, required this.studentName});

  final FlowerLog log;
  final String studentName;
}

/// 抽签历史记录。名字冗余存储，学生改名/删除后历史仍可读。
class DrawRecord {
  DrawRecord({
    required this.id,
    required this.classId,
    required this.studentIds,
    required this.names,
    required this.count,
    required this.createdAt,
  });

  final String id;
  final String classId;
  final List<String> studentIds;
  final List<String> names;
  final int count;
  final int createdAt;

  factory DrawRecord.fromMap(Map<String, Object?> map) => DrawRecord(
        id: map['id'] as String,
        classId: map['class_id'] as String,
        studentIds: (jsonDecode(map['student_ids'] as String) as List<dynamic>)
            .cast<String>(),
        names: (jsonDecode(map['names'] as String) as List<dynamic>)
            .cast<String>(),
        count: map['count'] as int,
        createdAt: map['created_at'] as int,
      );
}

/// 听写词表。
class WordList {
  WordList({
    required this.id,
    required this.title,
    this.subject,
    required this.createdAt,
    required this.updatedAt,
    this.wordCount = 0,
  });

  final String id;
  final String title;
  final String? subject;
  final int createdAt;
  final int updatedAt;

  /// 列表页展示用（联表统计），详情内无意义。
  final int wordCount;

  factory WordList.fromMap(Map<String, Object?> map) => WordList(
        id: map['id'] as String,
        title: map['title'] as String,
        subject: map['subject'] as String?,
        createdAt: map['created_at'] as int,
        updatedAt: map['updated_at'] as int,
        wordCount: (map['word_count'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'subject': subject,
        'created_at': createdAt,
        'updated_at': updatedAt,
      };
}

/// 单个听写词条。音频文件已复制进应用数据目录（UUID 命名）。
class Word {
  Word({
    required this.id,
    required this.listId,
    required this.text,
    this.meaning,
    required this.audioFile,
    this.origFilename,
    this.durationMs,
    required this.sort,
    required this.createdAt,
  });

  final String id;
  final String listId;
  final String text;
  final String? meaning;
  final String audioFile;
  final String? origFilename;
  final int? durationMs;
  final int sort;
  final int createdAt;

  factory Word.fromMap(Map<String, Object?> map) => Word(
        id: map['id'] as String,
        listId: map['list_id'] as String,
        text: map['text'] as String,
        meaning: map['meaning'] as String?,
        audioFile: map['audio_file'] as String,
        origFilename: map['orig_filename'] as String?,
        durationMs: map['duration_ms'] as int?,
        sort: (map['sort'] as int?) ?? 0,
        createdAt: map['created_at'] as int,
      );
}

/// 导入向导里一条待入库词条（音频尚在微信目录，未复制）。
class WordImportItem {
  WordImportItem({
    required this.sourcePath,
    required this.ext,
    required this.word,
    this.meaning,
    required this.durationMs,
    required this.origFilename,
  });

  final String sourcePath;

  /// 含点，如 '.m4a'。
  final String ext;
  final String word;
  final String? meaning;
  final int durationMs;
  final String origFilename;
}
