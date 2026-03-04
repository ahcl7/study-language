# Flutter Language Study App — Implementation Plan

A comprehensive Flutter desktop/mobile app for learning English and Japanese vocabulary,
featuring flashcards, quizzes, and two unique typing-practice modes.
Primary target: **Windows 11**. Designed to port easily to Android/iOS.

---

## Tech Stack

| Concern | Package |
|---|---|
| State management | `flutter_riverpod` |
| Navigation | `go_router` |
| Database | `drift` (SQLite wrapper) + `drift_dev`, `sqlite3_flutter_libs` |
| Auth (local PIN/password) | custom (stored in SQLite, hashed) |
| JSON backup | `dart:convert` + `file_picker` |
| Image pick | `image_picker` |
| Settings persistence | `shared_preferences` |
| Fonts | Google Fonts via `google_fonts` |

---

## Architecture — Clean Architecture

```
lib/
├── core/
│   ├── database/          # Drift DB definition + DAOs
│   ├── router/            # go_router config
│   ├── theme/             # ThemeData, ThemeNotifier
│   └── utils/
├── features/
│   ├── auth/              # login / logout
│   ├── classes/           # Class CRUD
│   ├── groups/            # Group CRUD
│   ├── words/             # Word CRUD + types
│   ├── flashcard/         # Flashcard study mode
│   ├── practice/          # Quiz + fill-in-the-blank
│   ├── type_to_learn/     # Typing modes (mode1 + mode2)
│   ├── paragraphs/        # Paragraph management (for mode2)
│   └── settings/          # Theme, font, color settings
│   └── backup/            # JSON backup / restore
```

Each feature follows: `data/` → `domain/` → `presentation/`.

---

## Database Schema

### Tables
- **users** — id, username, password_hash
- **classes** — id, name, language (en/ja), created_at
- **groups** — id, class_id, name, created_at
- **word_types** — id, name (noun, verb, adj…)
- **words** — id, name, meaning, example, image_path, created_at
- **word_group_links** — word_id, group_id (many-to-many)
- **word_type_links** — word_id, type_id (many-to-many)
- **paragraphs** — id, class_id, title, content, created_at

---

## Proposed Changes / New Files

### Core Setup

#### [NEW] `pubspec.yaml` — Flutter project manifest with all dependencies
#### [NEW] `lib/main.dart` — App entry point, Riverpod ProviderScope, GoRouter
#### [NEW] `lib/core/database/app_database.dart` — Drift DB + all table definitions + DAOs
#### [NEW] `lib/core/router/app_router.dart` — All named routes via go_router
#### [NEW] `lib/core/theme/app_theme.dart` — Light + Dark ThemeData factories
#### [NEW] `lib/core/theme/theme_notifier.dart` — Riverpod notifier for theme/font/color

---

### Feature: Auth

#### [NEW] `lib/features/auth/presentation/login_screen.dart`
- Username + password fields
- Login button → validates against DB hash
- On success → navigate to Home

#### [NEW] `lib/features/auth/presentation/register_screen.dart`
- First-run setup: create master user

---

### Feature: Classes

#### [NEW] `lib/features/classes/presentation/class_list_screen.dart`
- List all classes, add/edit/delete
- Tap → navigate to class detail (groups inside)

#### [NEW] `lib/features/classes/presentation/class_form_screen.dart`
- Name + language selector

---

### Feature: Groups

#### [NEW] `lib/features/groups/presentation/group_list_screen.dart`
- Groups within a class
- Tap → word list for that group

#### [NEW] `lib/features/groups/presentation/group_form_screen.dart`

---

### Feature: Words

#### [NEW] `lib/features/words/presentation/word_list_screen.dart`
- Filterable by class / group / word type

#### [NEW] `lib/features/words/presentation/word_form_screen.dart`
- Fields: name, word types (multi-select chip), meaning, example, image picker

---

### Feature: Flashcard

#### [NEW] `lib/features/flashcard/presentation/flashcard_screen.dart`
- Filter by class / group / word type
- Animated flip card (front: word, back: meaning + example)
- Previous / Next / Shuffle

---

### Feature: Practice

#### [NEW] `lib/features/practice/presentation/practice_config_screen.dart`
- Choose filter, mode (MCQ or fill-blank)

#### [NEW] `lib/features/practice/presentation/mcq_screen.dart`
- Multiple choice with 4 options

#### [NEW] `lib/features/practice/presentation/fill_blank_screen.dart`
- Type the answer, check correctness

---

### Feature: Type-to-Learn

#### [NEW] `lib/features/type_to_learn/presentation/mode1_screen.dart`
- Words float right→left like clouds using `AnimationController`
- Text field to type; correct word disappears
- Configurable filter (class / group / word type)

#### [NEW] `lib/features/type_to_learn/presentation/mode2_screen.dart`
- Paragraph display, user must type each word in order
- Typing errors highlighted red, correct word turns green before advancing

---

### Feature: Paragraph Management

#### [NEW] `lib/features/paragraphs/presentation/paragraph_list_screen.dart`
#### [NEW] `lib/features/paragraphs/presentation/paragraph_form_screen.dart`
- Assign to a class, write paragraph text

---

### Feature: Settings

#### [NEW] `lib/features/settings/presentation/settings_screen.dart`
- Font size slider
- Font family dropdown (Google Fonts)
- Primary color picker
- Theme toggle (light / dark)
- Change password

---

### Feature: Backup

#### [NEW] `lib/features/backup/presentation/backup_screen.dart`
- Export all data → JSON file (file_picker for save location)
- Import from JSON file (restore & merge)

---

## Verification Plan

### Automated Tests
No existing test suite. After implementation:
```
flutter test
```
Basic widget tests will be added for:
- Login form validation
- Word form validation
- Flashcard flip behavior

### Manual Verification (Run on Windows 11)
```
flutter run -d windows
```

1. **Auth** — Register user → Logout → Login with wrong password (should fail) → Login correctly (should succeed)
2. **Class/Group/Word CRUD** — Create class → create group inside → add word with all fields + image
3. **Flashcard** — Open flashcard by class → flip cards → shuffle
4. **Practice** — Run MCQ and fill-blank for a group
5. **Type-to-Learn Mode 1** — Select words, watch them float, type to dismiss
6. **Type-to-Learn Mode 2** — Create paragraph, start mode 2, type words in order
7. **Settings** — Toggle dark mode, change font size → verify UI updates live
8. **Backup** — Export JSON → delete a word → restore JSON → verify word is back
