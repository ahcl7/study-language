import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

// ─── Table definitions ───

class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text().withLength(min: 1, max: 50)();
  TextColumn get passwordHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Classes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get language => text().withDefault(const Constant('en'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get classId => integer().references(Classes, #id)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WordTypes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
}

class Words extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 200)();
  TextColumn get meaning => text()();
  TextColumn get example => text().withDefault(const Constant(''))();
  TextColumn get imagePath => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WordGroupLinks extends Table {
  IntColumn get wordId => integer().references(Words, #id)();
  IntColumn get groupId => integer().references(Groups, #id)();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {wordId, groupId};
}

class WordTypeLinks extends Table {
  IntColumn get wordId => integer().references(Words, #id)();
  IntColumn get typeId => integer().references(WordTypes, #id)();

  @override
  Set<Column> get primaryKey => {wordId, typeId};
}

class Paragraphs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get classId => integer().references(Classes, #id)();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// ─── Database ───

@DriftDatabase(tables: [
  Users,
  Classes,
  Groups,
  WordTypes,
  Words,
  WordGroupLinks,
  WordTypeLinks,
  Paragraphs,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.addColumn(words, words.isActive);
          }
          if (from < 3) {
            await m.addColumn(wordGroupLinks, wordGroupLinks.sortOrder);
          }
          if (from < 4) {
            await m.addColumn(groups, groups.sortOrder);
          }
          if (from < 5) {
            await m.addColumn(classes, classes.sortOrder);
          }
          if (from < 6) {
            await _normalizeSortOrders();
          }
        },
        onCreate: (Migrator m) async {
          await m.createAll();
          // Seed default word types
          await into(wordTypes).insert(WordTypesCompanion.insert(name: 'Noun'));
          await into(wordTypes).insert(WordTypesCompanion.insert(name: 'Verb'));
          await into(wordTypes)
              .insert(WordTypesCompanion.insert(name: 'Adjective'));
          await into(wordTypes)
              .insert(WordTypesCompanion.insert(name: 'Adverb'));
          await into(wordTypes)
              .insert(WordTypesCompanion.insert(name: 'Preposition'));
          await into(wordTypes)
              .insert(WordTypesCompanion.insert(name: 'Conjunction'));
          await into(wordTypes)
              .insert(WordTypesCompanion.insert(name: 'Pronoun'));
          await into(wordTypes)
              .insert(WordTypesCompanion.insert(name: 'Interjection'));
        },
      );

  // ─── User queries ───

  Future<List<User>> getAllUsers() => select(users).get();

  Future<User?> getUserByUsername(String username) =>
      (select(users)..where((u) => u.username.equals(username)))
          .getSingleOrNull();

  Future<int> insertUser(UsersCompanion user) => into(users).insert(user);

  Future<bool> updateUser(User user) => update(users).replace(user);

  // ─── Class queries ───

  Future<List<ClassesData>> getAllClasses() =>
      (select(classes)..orderBy([(c) => OrderingTerm.asc(c.sortOrder)])).get();

  Stream<List<ClassesData>> watchAllClasses() =>
      (select(classes)..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
          .watch();

  Future<int> insertClass(ClassesCompanion c) async {
    final existing = await getAllClasses();
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    return into(classes).insert(c.copyWith(sortOrder: Value(nextOrder)));
  }

  Future<bool> updateClass(ClassesData c) => update(classes).replace(c);

  Future<int> deleteClass(ClassesData c) => delete(classes).delete(c);

  Future<void> updateClassSortOrder(int classId, int sortOrder) async {
    await (update(classes)..where((c) => c.id.equals(classId)))
        .write(ClassesCompanion(sortOrder: Value(sortOrder)));
  }

  Future<void> swapClassSortOrders(int classIdA, int classIdB) async {
    final rows = await (select(classes)
          ..where((c) => c.id.equals(classIdA) | c.id.equals(classIdB)))
        .get();
    if (rows.length != 2) return;
    final orderA = rows.firstWhere((r) => r.id == classIdA).sortOrder;
    final orderB = rows.firstWhere((r) => r.id == classIdB).sortOrder;
    await updateClassSortOrder(classIdA, orderB);
    await updateClassSortOrder(classIdB, orderA);
  }

  /// Normalize sortOrder for all classes, groups, and word-group links so that
  /// within each parent there are no duplicates. Relative order is preserved
  /// by sorting on (current sort_order, id).
  Future<void> _normalizeSortOrders() async {
    // ── Classes ──
    final classRows = await customSelect(
      'SELECT id FROM classes ORDER BY sort_order, id',
    ).get();
    for (int i = 0; i < classRows.length; i++) {
      await customUpdate(
        'UPDATE classes SET sort_order = ? WHERE id = ?',
        variables: [Variable(i), Variable(classRows[i].read<int>('id'))],
        updates: {classes},
      );
    }

    // ── Groups (per class) ──
    final groupRows = await customSelect(
      'SELECT id, class_id FROM groups ORDER BY class_id, sort_order, id',
    ).get();
    final Map<int, int> classCounter = {};
    for (final row in groupRows) {
      final gId = row.read<int>('id');
      final cId = row.read<int>('class_id');
      final order = classCounter[cId] ?? 0;
      await customUpdate(
        'UPDATE groups SET sort_order = ? WHERE id = ?',
        variables: [Variable(order), Variable(gId)],
        updates: {groups},
      );
      classCounter[cId] = order + 1;
    }

    // ── Word-group links (per group) ──
    final linkRows = await customSelect(
      'SELECT word_id, group_id FROM word_group_links ORDER BY group_id, sort_order, word_id',
    ).get();
    final Map<int, int> groupCounter = {};
    for (final row in linkRows) {
      final wId = row.read<int>('word_id');
      final gId = row.read<int>('group_id');
      final order = groupCounter[gId] ?? 0;
      await customUpdate(
        'UPDATE word_group_links SET sort_order = ? WHERE word_id = ? AND group_id = ?',
        variables: [Variable(order), Variable(wId), Variable(gId)],
        updates: {wordGroupLinks},
      );
      groupCounter[gId] = order + 1;
    }
  }

  // ─── Group queries ───

  Future<List<Group>> getGroupsByClass(int classId) => (select(groups)
        ..where((g) => g.classId.equals(classId))
        ..orderBy([(g) => OrderingTerm.asc(g.sortOrder)]))
      .get();

  Stream<List<Group>> watchGroupsByClass(int classId) => (select(groups)
        ..where((g) => g.classId.equals(classId))
        ..orderBy([(g) => OrderingTerm.asc(g.sortOrder)]))
      .watch();

  Future<List<Group>> getAllGroups() => select(groups).get();

  Future<int> insertGroup(GroupsCompanion g) async {
    final existing = await getGroupsByClass((g.classId as Value<int>).value);
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    return into(groups).insert(g.copyWith(sortOrder: Value(nextOrder)));
  }

  Future<bool> updateGroup(Group g) => update(groups).replace(g);

  Future<int> deleteGroup(Group g) => delete(groups).delete(g);

  Future<void> updateGroupSortOrder(int groupId, int sortOrder) async {
    await (update(groups)..where((g) => g.id.equals(groupId)))
        .write(GroupsCompanion(sortOrder: Value(sortOrder)));
  }

  Future<void> swapGroupSortOrders(int groupIdA, int groupIdB) async {
    final rows = await (select(groups)
          ..where((g) => g.id.equals(groupIdA) | g.id.equals(groupIdB)))
        .get();
    if (rows.length != 2) return;
    final orderA = rows.firstWhere((r) => r.id == groupIdA).sortOrder;
    final orderB = rows.firstWhere((r) => r.id == groupIdB).sortOrder;
    await updateGroupSortOrder(groupIdA, orderB);
    await updateGroupSortOrder(groupIdB, orderA);
  }

  // ─── WordType queries ───

  Future<List<WordType>> getAllWordTypes() => select(wordTypes).get();

  Stream<List<WordType>> watchAllWordTypes() => select(wordTypes).watch();

  Future<int> insertWordType(WordTypesCompanion wt) =>
      into(wordTypes).insert(wt);

  Future<int> deleteWordType(WordType wt) => delete(wordTypes).delete(wt);

  // ─── Word queries ───

  Future<List<Word>> getAllWords() => select(words).get();

  Stream<List<Word>> watchAllWords() => select(words).watch();

  Future<int> insertWord(WordsCompanion w) => into(words).insert(w);

  Future<bool> updateWord(Word w) => update(words).replace(w);

  Future<int> deleteWord(Word w) => delete(words).delete(w);

  Future<void> setWordActive(int wordId, {required bool isActive}) =>
      (update(words)..where((w) => w.id.equals(wordId)))
          .write(WordsCompanion(isActive: Value(isActive)));

  // ─── Word-Group link queries ───

  Future<void> linkWordToGroup(int wordId, int groupId) async {
    // Assign next sort order within the group
    final existing = await (select(wordGroupLinks)
          ..where((l) => l.groupId.equals(groupId)))
        .get();
    final nextOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
    await into(wordGroupLinks).insert(
      WordGroupLinksCompanion.insert(
        wordId: wordId,
        groupId: groupId,
        sortOrder: Value(nextOrder),
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  Future<void> updateWordSortOrderInGroup(
      int wordId, int groupId, int sortOrder) async {
    await (update(wordGroupLinks)
          ..where((l) => l.wordId.equals(wordId) & l.groupId.equals(groupId)))
        .write(WordGroupLinksCompanion(sortOrder: Value(sortOrder)));
  }

  /// Swap sort orders of two words inside a group.
  Future<void> swapWordSortOrders(int wordIdA, int wordIdB, int groupId) async {
    final rows = await (select(wordGroupLinks)
          ..where((l) =>
              l.groupId.equals(groupId) &
              (l.wordId.equals(wordIdA) | l.wordId.equals(wordIdB))))
        .get();
    if (rows.length != 2) return;
    final orderA = rows.firstWhere((r) => r.wordId == wordIdA).sortOrder;
    final orderB = rows.firstWhere((r) => r.wordId == wordIdB).sortOrder;
    await updateWordSortOrderInGroup(wordIdA, groupId, orderB);
    await updateWordSortOrderInGroup(wordIdB, groupId, orderA);
  }

  /// Move [wordId] to position after [afterWordId] in the group.
  /// Pass [afterWordId] = null to move to first position.
  ///
  /// Cost: usually **1 UPDATE** (midpoint between neighbors).
  /// Falls back to renormalize (n+1 updates) only when the integer gap is
  /// exhausted — which is very rare with a gap seed of 1 000.
  Future<void> moveWordToPositionInGroup(
      int wordId, int groupId, {required int? afterWordId}) async {
    // All links ordered by sortOrder, excluding the word being moved
    final allRows = await (select(wordGroupLinks)
          ..where((l) => l.groupId.equals(groupId))
          ..orderBy([(l) => OrderingTerm.asc(l.sortOrder)]))
        .get();
    final others = allRows.where((r) => r.wordId != wordId).toList();
    if (others.isEmpty) return;

    int newOrder;
    if (afterWordId == null) {
      // Move before the first word
      newOrder = others.first.sortOrder - 1;
    } else {
      final idx = others.indexWhere((r) => r.wordId == afterWordId);
      if (idx == -1) return;
      if (idx == others.length - 1) {
        // Move after the last word
        newOrder = others.last.sortOrder + 1;
      } else {
        final a = others[idx].sortOrder;
        final b = others[idx + 1].sortOrder;
        if (b - a > 1) {
          // Gap available — 1 UPDATE only
          newOrder = (a + b) ~/ 2;
        } else {
          // Gap exhausted: renormalize entire group with gap=1000000, then midpoint
          for (int i = 0; i < others.length; i++) {
            await updateWordSortOrderInGroup(others[i].wordId, groupId, i * 1000000);
          }
          newOrder = idx * 1000000 + 500000; // sits exactly between idx and idx+1
        }
      }
    }
    await updateWordSortOrderInGroup(wordId, groupId, newOrder);
  }

  /// Move a word to the bottom (highest sortOrder + 1) in every group it belongs to.
  Future<void> moveWordToBottomOfAllGroups(int wordId) async {
    final links = await (select(wordGroupLinks)
          ..where((l) => l.wordId.equals(wordId)))
        .get();
    for (final link in links) {
      final groupLinks = await (select(wordGroupLinks)
            ..where((l) => l.groupId.equals(link.groupId)))
          .get();
      final maxOrder = groupLinks.isEmpty
          ? 0
          : groupLinks.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b);
      await updateWordSortOrderInGroup(wordId, link.groupId, maxOrder + 1);
    }
  }

  /// Re-sort a group so all active words come before inactive ones,
  /// preserving relative order within each category.
  Future<void> _renormalizeGroupOrder(int groupId) async {
    // Fetch all (wordId, sortOrder, isActive) for the group
    final rows = await (select(wordGroupLinks).join([
      innerJoin(words, words.id.equalsExp(wordGroupLinks.wordId)),
    ])
          ..where(wordGroupLinks.groupId.equals(groupId))
          ..orderBy([OrderingTerm.asc(wordGroupLinks.sortOrder)]))
        .get();

    final active = rows.where((r) => r.readTable(words).isActive).toList();
    final inactive = rows.where((r) => !r.readTable(words).isActive).toList();
    final ordered = [...active, ...inactive];

    for (int i = 0; i < ordered.length; i++) {
      final wId = ordered[i].readTable(wordGroupLinks).wordId;
      await updateWordSortOrderInGroup(wId, groupId, i);
    }
  }

  /// When a word is re-activated, place it just before all inactive words
  /// in every group it belongs to (preserving relative order of others).
  Future<void> moveWordAboveInactiveInAllGroups(int wordId) async {
    final links = await (select(wordGroupLinks)
          ..where((l) => l.wordId.equals(wordId)))
        .get();
    for (final link in links) {
      await _renormalizeGroupOrder(link.groupId);
    }
  }

  Future<void> unlinkWordFromGroup(int wordId, int groupId) =>
      (delete(wordGroupLinks)
            ..where((l) => l.wordId.equals(wordId) & l.groupId.equals(groupId)))
          .go();

  Future<void> deleteWordGroupLinksByWord(int wordId) =>
      (delete(wordGroupLinks)..where((l) => l.wordId.equals(wordId))).go();

  Future<List<Word>> getWordsByGroup(int groupId) {
    final query = select(words).join([
      innerJoin(wordGroupLinks, wordGroupLinks.wordId.equalsExp(words.id)),
    ])
      ..where(wordGroupLinks.groupId.equals(groupId))
      ..orderBy([OrderingTerm.asc(wordGroupLinks.sortOrder)]);
    return query.map((row) => row.readTable(words)).get();
  }

  Future<List<Word>> getActiveWordsByGroup(int groupId) {
    final query = select(words).join([
      innerJoin(wordGroupLinks, wordGroupLinks.wordId.equalsExp(words.id)),
    ])
      ..where(
          wordGroupLinks.groupId.equals(groupId) & words.isActive.equals(true));
    return query.map((row) => row.readTable(words)).get();
  }

  Future<List<Word>> getWordsByClass(int classId) {
    final query = select(words).join([
      innerJoin(wordGroupLinks, wordGroupLinks.wordId.equalsExp(words.id)),
      innerJoin(groups, groups.id.equalsExp(wordGroupLinks.groupId)),
    ])
      ..where(groups.classId.equals(classId));
    return query.map((row) => row.readTable(words)).get();
  }

  Future<List<Word>> getActiveWordsByClass(int classId) {
    final query = select(words).join([
      innerJoin(wordGroupLinks, wordGroupLinks.wordId.equalsExp(words.id)),
      innerJoin(groups, groups.id.equalsExp(wordGroupLinks.groupId)),
    ])
      ..where(groups.classId.equals(classId) & words.isActive.equals(true));
    return query.map((row) => row.readTable(words)).get();
  }

  // ─── Word-Type link queries ───

  Future<void> linkWordToType(int wordId, int typeId) =>
      into(wordTypeLinks).insert(
        WordTypeLinksCompanion.insert(wordId: wordId, typeId: typeId),
        mode: InsertMode.insertOrIgnore,
      );

  Future<void> unlinkWordFromType(int wordId, int typeId) =>
      (delete(wordTypeLinks)
            ..where((l) => l.wordId.equals(wordId) & l.typeId.equals(typeId)))
          .go();

  Future<void> deleteWordTypeLinksByWord(int wordId) =>
      (delete(wordTypeLinks)..where((l) => l.wordId.equals(wordId))).go();

  Future<List<WordType>> getTypesForWord(int wordId) {
    final query = select(wordTypes).join([
      innerJoin(wordTypeLinks, wordTypeLinks.typeId.equalsExp(wordTypes.id)),
    ])
      ..where(wordTypeLinks.wordId.equals(wordId));
    return query.map((row) => row.readTable(wordTypes)).get();
  }

  Future<List<Word>> getWordsByType(int typeId) {
    final query = select(words).join([
      innerJoin(wordTypeLinks, wordTypeLinks.wordId.equalsExp(words.id)),
    ])
      ..where(wordTypeLinks.typeId.equals(typeId));
    return query.map((row) => row.readTable(words)).get();
  }

  Future<List<Word>> getActiveWordsByType(int typeId) {
    final query = select(words).join([
      innerJoin(wordTypeLinks, wordTypeLinks.wordId.equalsExp(words.id)),
    ])
      ..where(
          wordTypeLinks.typeId.equals(typeId) & words.isActive.equals(true));
    return query.map((row) => row.readTable(words)).get();
  }

  Future<List<int>> getGroupIdsForWord(int wordId) async {
    final query = select(wordGroupLinks)..where((l) => l.wordId.equals(wordId));
    final rows = await query.get();
    return rows.map((r) => r.groupId).toList();
  }

  Future<List<int>> getTypeIdsForWord(int wordId) async {
    final query = select(wordTypeLinks)..where((l) => l.wordId.equals(wordId));
    final rows = await query.get();
    return rows.map((r) => r.typeId).toList();
  }

  // ─── Paragraph queries ───

  Future<List<Paragraph>> getParagraphsByClass(int classId) =>
      (select(paragraphs)..where((p) => p.classId.equals(classId))).get();

  Stream<List<Paragraph>> watchParagraphsByClass(int classId) =>
      (select(paragraphs)..where((p) => p.classId.equals(classId))).watch();

  Future<List<Paragraph>> getAllParagraphs() => select(paragraphs).get();

  Future<int> insertParagraph(ParagraphsCompanion p) =>
      into(paragraphs).insert(p);

  Future<bool> updateParagraph(Paragraph p) => update(paragraphs).replace(p);

  Future<int> deleteParagraph(Paragraph p) => delete(paragraphs).delete(p);

  // ─── Backup / Restore helpers ───

  Future<Map<String, dynamic>> exportAll() async {
    return {
      'users': (await getAllUsers())
          .map((u) => {
                'id': u.id,
                'username': u.username,
                'passwordHash': u.passwordHash,
                'createdAt': u.createdAt.toIso8601String(),
              })
          .toList(),
      'classes': (await getAllClasses())
          .map((c) => {
                'id': c.id,
                'name': c.name,
                'language': c.language,
                'sortOrder': c.sortOrder,
                'createdAt': c.createdAt.toIso8601String(),
              })
          .toList(),
      'groups': (await getAllGroups())
          .map((g) => {
                'id': g.id,
                'classId': g.classId,
                'name': g.name,
                'sortOrder': g.sortOrder,
                'createdAt': g.createdAt.toIso8601String(),
              })
          .toList(),
      'wordTypes': (await getAllWordTypes())
          .map((wt) => {'id': wt.id, 'name': wt.name})
          .toList(),
      'words': (await getAllWords())
          .map((w) => {
                'id': w.id,
                'name': w.name,
                'meaning': w.meaning,
                'example': w.example,
                'imagePath': w.imagePath,
                'isActive': w.isActive,
                'createdAt': w.createdAt.toIso8601String(),
              })
          .toList(),
      'wordGroupLinks': (await select(wordGroupLinks).get())
          .map((l) => {
                'wordId': l.wordId,
                'groupId': l.groupId,
                'sortOrder': l.sortOrder
              })
          .toList(),
      'wordTypeLinks': (await select(wordTypeLinks).get())
          .map((l) => {'wordId': l.wordId, 'typeId': l.typeId})
          .toList(),
      'paragraphs': (await getAllParagraphs())
          .map((p) => {
                'id': p.id,
                'classId': p.classId,
                'title': p.title,
                'content': p.content,
                'createdAt': p.createdAt.toIso8601String(),
              })
          .toList(),
    };
  }

  Future<void> importAll(Map<String, dynamic> data) async {
    await transaction(() async {
      // Clear all tables
      await delete(wordGroupLinks).go();
      await delete(wordTypeLinks).go();
      await delete(words).go();
      await delete(paragraphs).go();
      await delete(groups).go();
      await delete(classes).go();
      await delete(wordTypes).go();
      await delete(users).go();

      // Reset auto-increment counters
      await customStatement(
        'DELETE FROM sqlite_sequence WHERE name IN '
        "('users','classes','groups','word_types','words','paragraphs')",
      );

      // Import users
      for (final u in (data['users'] as List? ?? [])) {
        await into(users).insert(UsersCompanion.insert(
          username: u['username'] as String,
          passwordHash: u['passwordHash'] as String,
        ));
      }

      // Import classes
      for (final c in (data['classes'] as List? ?? [])) {
        await into(classes).insert(ClassesCompanion.insert(
          name: c['name'] as String,
          language: Value(c['language'] as String? ?? 'en'),
          sortOrder: Value(c['sortOrder'] as int? ?? 0),
        ));
      }

      // Import groups
      for (final g in (data['groups'] as List? ?? [])) {
        await into(groups).insert(GroupsCompanion.insert(
          classId: g['classId'] as int,
          name: g['name'] as String,
          sortOrder: Value(g['sortOrder'] as int? ?? 0),
        ));
      }

      // Import word types
      for (final wt in (data['wordTypes'] as List? ?? [])) {
        await into(wordTypes).insert(WordTypesCompanion.insert(
          name: wt['name'] as String,
        ));
      }

      // Import words
      for (final w in (data['words'] as List? ?? [])) {
        await into(words).insert(WordsCompanion.insert(
          name: w['name'] as String,
          meaning: w['meaning'] as String,
          example: Value(w['example'] as String? ?? ''),
          imagePath: Value(w['imagePath'] as String?),
          isActive: Value(w['isActive'] as bool? ?? true),
        ));
      }

      // Import word-group links
      for (final l in (data['wordGroupLinks'] as List? ?? [])) {
        await into(wordGroupLinks).insert(
          WordGroupLinksCompanion.insert(
            wordId: l['wordId'] as int,
            groupId: l['groupId'] as int,
            sortOrder: Value(l['sortOrder'] as int? ?? 0),
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }

      // Import word-type links
      for (final l in (data['wordTypeLinks'] as List? ?? [])) {
        await into(wordTypeLinks).insert(
          WordTypeLinksCompanion.insert(
            wordId: l['wordId'] as int,
            typeId: (l['typeId'] ?? l['wordTypeId']) as int,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      }

      // Import paragraphs
      for (final p in (data['paragraphs'] as List? ?? [])) {
        await into(paragraphs).insert(ParagraphsCompanion.insert(
          classId: p['classId'] as int,
          title: p['title'] as String,
          content: p['content'] as String,
        ));
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'study_language.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
