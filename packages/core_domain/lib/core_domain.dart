/// Core domain models and utilities for the audiobook app.
///
/// This package contains pure Dart types and functions with no Flutter
/// dependencies, making it highly testable and reusable.
library core_domain;

// Models
export 'src/models/book.dart';
export 'src/models/chapter.dart';
export 'src/models/segment.dart';
export 'src/models/voice.dart';
export 'src/models/cache_key.dart';

// Utilities
export 'src/utils/text_segmenter.dart';
export 'src/utils/text_normalizer.dart';
export 'src/utils/cache_key_generator.dart';
export 'src/utils/time_estimator.dart';
export 'src/utils/id_generator.dart';
