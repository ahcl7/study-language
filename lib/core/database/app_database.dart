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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class Groups extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get classId => integer().references(Classes, #id)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
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
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class WordGroupLinks extends Table {
  IntColumn get wordId => integer().references(Words, #id)();
  IntColumn get groupId => integer().references(Groups, #id)();

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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
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

  Future<List<ClassesData>> getAllClasses() => select(classes).get();

  Stream<List<ClassesData>> watchAllClasses() => select(classes).watch();

  Future<int> insertClass(ClassesCompanion c) => into(classes).insert(c);

  Future<bool> updateClass(ClassesData c) => update(classes).replace(c);

  Future<int> deleteClass(ClassesData c) => delete(classes).delete(c);

  // ─── Group queries ───

  Future<List<Group>> getGroupsByClass(int classId) =>
      (select(groups)..where((g) => g.classId.equals(classId))).get();

  Stream<List<Group>> watchGroupsByClass(int classId) =>
      (select(groups)..where((g) => g.classId.equals(classId))).watch();

  Future<List<Group>> getAllGroups() => select(groups).get();

  Future<int> insertGroup(GroupsCompanion g) => into(groups).insert(g);

  Future<bool> updateGroup(Group g) => update(groups).replace(g);

  Future<int> deleteGroup(Group g) => delete(groups).delete(g);

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

  // ─── Word-Group link queries ───

  Future<void> linkWordToGroup(int wordId, int groupId) =>
      into(wordGroupLinks).insert(
        WordGroupLinksCompanion.insert(wordId: wordId, groupId: groupId),
        mode: InsertMode.insertOrIgnore,
      );

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
      ..where(wordGroupLinks.groupId.equals(groupId));
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
                'createdAt': c.createdAt.toIso8601String(),
              })
          .toList(),
      'groups': (await getAllGroups())
          .map((g) => {
                'id': g.id,
                'classId': g.classId,
                'name': g.name,
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
                'createdAt': w.createdAt.toIso8601String(),
              })
          .toList(),
      'wordGroupLinks': (await select(wordGroupLinks).get())
          .map((l) => {'wordId': l.wordId, 'groupId': l.groupId})
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
        ));
      }

      // Import groups
      for (final g in (data['groups'] as List? ?? [])) {
        await into(groups).insert(GroupsCompanion.insert(
          classId: g['classId'] as int,
          name: g['name'] as String,
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
        ));
      }

      // Import word-group links
      for (final l in (data['wordGroupLinks'] as List? ?? [])) {
        await into(wordGroupLinks).insert(
          WordGroupLinksCompanion.insert(
            wordId: l['wordId'] as int,
            groupId: l['groupId'] as int,
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
