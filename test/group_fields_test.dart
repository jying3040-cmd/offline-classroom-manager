import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:classroom_manager/data/db.dart';
import 'package:classroom_manager/data/models.dart';
import 'package:classroom_manager/data/repo.dart';
import 'package:classroom_manager/pages/draw_page.dart';
import 'package:classroom_manager/pages/roster_page.dart';

void main() {
  late Klass klass;

  Future<void> pumpDatabase(WidgetTester tester) async {
    await tester.runAsync<void>(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> waitForFinder(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 20; i++) {
      if (finder.evaluate().isNotEmpty) return;
      await tester.runAsync<void>(() async {
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      await tester.pump();
    }
    fail('Timed out waiting for $finder');
  }

  setUpAll(() async {
    final appData = Platform.environment['APPDATA'];
    // Tests must be launched with a disposable APPDATA; never touch a real
    // user's application data directory.
    expect(appData, isNotNull,
        reason: 'Set APPDATA to a temporary test directory before running tests');
    final safeAppData = appData!;
    expect(p.basename(safeAppData), startsWith('classroom_v4_test_'),
        reason: 'APPDATA must point to a fresh classroom_v4_test_ directory');
    final root = Directory(p.join(safeAppData, 'classroom_manager'));
    expect(root.existsSync(), isFalse,
        reason: 'Use a fresh test directory; existing data is never deleted');
    final data = Directory(p.join(root.path, 'data'))..createSync(recursive: true);
    sqfliteFfiInit();
    final oldDb = await databaseFactoryFfi.openDatabase(
      p.join(data.path, 'classroom.db'),
    );
    await oldDb.execute('''
      CREATE TABLE classes (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        archived INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await oldDb.execute('''
      CREATE TABLE students (
        id TEXT PRIMARY KEY,
        class_id TEXT NOT NULL,
        name TEXT NOT NULL,
        seat_no INTEGER,
        gender TEXT,
        archived INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
    await oldDb.execute('''
      CREATE TABLE flower_logs (
        id TEXT PRIMARY KEY,
        student_id TEXT NOT NULL,
        delta INTEGER NOT NULL,
        reason TEXT,
        ref_log_id TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await oldDb.execute('''
      CREATE TABLE draw_logs (
        id TEXT PRIMARY KEY,
        class_id TEXT NOT NULL,
        student_ids TEXT NOT NULL,
        names TEXT NOT NULL,
        count INTEGER NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');
    await oldDb.insert('classes', {
      'id': 'legacy-class',
      'name': '旧版班级',
      'created_at': 1,
      'archived': 1,
    });
    await oldDb.insert('students', {
      'id': 'legacy-student',
      'class_id': 'legacy-class',
      'name': '旧版学生',
      'seat_no': 7,
      'gender': '女',
      'archived': 0,
      'created_at': 2,
      'updated_at': 2,
    });
    await oldDb.insert('flower_logs', {
      'id': 'legacy-flower',
      'student_id': 'legacy-student',
      'delta': 4,
      'reason': '迁移保留',
      'created_at': 3,
    });
    await oldDb.insert('draw_logs', {
      'id': 'legacy-draw',
      'class_id': 'legacy-class',
      'student_ids': jsonEncode(['legacy-student']),
      'names': jsonEncode(['旧版学生']),
      'count': 1,
      'created_at': 4,
    });
    await oldDb.close();
    await AppDb.init();
    klass = await Repo.addClass('四年级测试班');
  });

  tearDownAll(() async {
    await AppDb.close();
  });

  test('v4 migration adds group columns and is idempotent on reopen', () async {
    final db = await AppDb.db;
    final columns = await db.rawQuery('PRAGMA table_info(students)');
    final names = columns.map((row) => row['name']).toList();
    expect(names.where((name) => name == 'group_name'), hasLength(1));
    expect(names.where((name) => name == 'member_no'), hasLength(1));

    await AppDb.close();
    final reopened = await AppDb.init();
    final reopenedColumns = await reopened.rawQuery('PRAGMA table_info(students)');
    final reopenedNames = reopenedColumns.map((row) => row['name']).toList();
    expect(reopenedNames.where((name) => name == 'group_name'), hasLength(1));
    expect(reopenedNames.where((name) => name == 'member_no'), hasLength(1));

    final legacy = (await Repo.listStudents('legacy-class')).single;
    expect(legacy.name, '旧版学生');
    expect(legacy.groupName, isNull);
    expect((await Repo.flowerTotals('legacy-class'))['legacy-student'], 4);
    final draws = await Repo.listDrawLogs('legacy-class');
    expect(draws.single.names, ['旧版学生']);
  });

  test('Repo add, edit, and clear group fields, and rejects non-positive members', () async {
    await Repo.addStudent(
      classId: klass.id,
      name: '甲',
      gender: '男',
      groupName: '  向阳  ',
      memberNo: 2,
    );
    var students = await Repo.listStudents(klass.id);
    var student = students.singleWhere((s) => s.name == '甲');
    expect(student.groupName, '向阳');
    expect(student.memberNo, 2);
    expect(student.groupLabel, '向阳小组 · 2号组员');

    await Repo.updateStudent(
      existing: student,
      name: '甲改',
      groupName: '  ',
      memberNo: null,
    );
    student = (await Repo.listStudents(klass.id))
        .singleWhere((s) => s.id == student.id);
    expect(student.groupName, isNull);
    expect(student.memberNo, isNull);
    expect(student.groupLabel, isEmpty);

    await expectLater(
      Repo.addStudent(
        classId: klass.id,
        name: '非法',
        memberNo: 0,
      ),
      throwsArgumentError,
    );
    await expectLater(
      Repo.updateStudent(
        existing: student,
        name: student.name,
        memberNo: -1,
      ),
      throwsArgumentError,
    );
  });

  testWidgets('roster dialog saves group and member fields', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: RosterPage())),
    );
    await tester.pump();
    await pumpDatabase(tester);
    await tester.tap(find.text('添加学生').first);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '对话框学生');
    await tester.enterText(fields.at(2), '彩虹');
    await tester.enterText(fields.at(3), '3');
    await tester.tap(find.text('保存'));
    await tester.pump();
    await pumpDatabase(tester);
    await waitForFinder(tester, find.textContaining('彩虹小组 · 3号组员'));

    Student? saved;
    await tester.runAsync(() async {
      saved = (await Repo.listStudents(klass.id))
          .singleWhere((s) => s.name == '对话框学生');
    });
    expect(saved, isNotNull);
    final savedStudent = saved!;
    expect(savedStudent.groupName, '彩虹');
    expect(savedStudent.memberNo, 3);
    expect(find.textContaining('彩虹小组 · 3号组员'), findsOneWidget);
  });

  testWidgets('draw combines gender, group, and member filters and reports empty pool',
      (tester) async {
    await tester.runAsync(() async {
      await Repo.addStudent(
        classId: klass.id,
        name: '男生一号',
        gender: '男',
        groupName: '甲',
        memberNo: 1,
      );
      await Repo.addStudent(
        classId: klass.id,
        name: '男生二号',
        gender: '男',
        groupName: '甲',
        memberNo: 2,
      );
      await Repo.addStudent(
        classId: klass.id,
        name: '女生一号',
        gender: '女',
        groupName: '乙',
        memberNo: 1,
      );
    });
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: DrawPage())));
    await tester.pump();
    await pumpDatabase(tester);
    await waitForFinder(tester, find.text('男生'));

    await tester.tap(find.text('男生'));
    await tester.tap(find.text('小组：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('小组：甲'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组员号：全部'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('组员号：2'));
    await tester.pumpAndSettle();
    expect(find.text('当前范围 1 人 · 本轮剩余 1 人'), findsOneWidget);

    await tester.tap(find.text('开始抽签'));
    await tester.pump();
    await pumpDatabase(tester);
    await tester.pump(const Duration(milliseconds: 2100));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('男生二号'), findsOneWidget);
    expect(find.textContaining('甲小组 · 2号组员'), findsOneWidget);
    await tester.tap(find.text('返回'));
    await tester.pump();
    expect(find.text('当前范围 1 人 · 本轮剩余 0 人'), findsOneWidget);

    await tester.tap(find.text('女生'));
    await tester.pump();
    expect(find.text('当前范围 0 人 · 本轮剩余 0 人'), findsOneWidget);
    await tester.tap(find.text('开始抽签'));
    await tester.pump();
    expect(find.text('当前范围内没有学生'), findsOneWidget);
  });
}
