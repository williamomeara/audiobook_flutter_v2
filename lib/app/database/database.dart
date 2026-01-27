/// SQLite database infrastructure for Eist audiobook app.
///
/// This library provides:
/// - [AppDatabase]: Singleton database instance with WAL mode optimization
/// - Data Access Objects (DAOs) for each table
///
/// Usage:
/// ```dart
/// import 'package:audiobook_flutter_v2/app/database/database.dart';
///
/// final db = await AppDatabase.instance;
/// final bookDao = BookDao(db);
/// final books = await bookDao.getAllBooks();
/// ```
library;

export 'app_database.dart';
export 'daos/book_dao.dart';
export 'daos/cache_dao.dart';
export 'daos/chapter_dao.dart';
export 'daos/completed_chapters_dao.dart';
export 'daos/downloaded_voices_dao.dart';
export 'daos/model_metrics_dao.dart';
export 'daos/progress_dao.dart';
export 'daos/segment_dao.dart';
export 'daos/segment_progress_dao.dart';
export 'daos/settings_dao.dart';
export 'migrations/cache_migration_service.dart';
export 'migrations/json_migration_service.dart';
export 'repositories/library_repository.dart';
export 'sqlite_cache_metadata_storage.dart';
