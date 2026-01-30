import 'dart:isolate';
import 'dart:math';

import 'package:core_domain/core_domain.dart';

import 'text_normalizer.dart' as tts_normalizer;
import 'boilerplate_remover.dart';
import 'content_classifier.dart';
import 'structure_analyzer.dart';

/// Serializable chapter data for isolate communication.
class ChapterProcessData {
  const ChapterProcessData({
    required this.id,
    required this.number,
    required this.title,
    required this.content,
  });

  final String id;
  final int number;
  final String title;
  final String content;

  /// Convert to Chapter model.
  Chapter toChapter() => Chapter(
    id: id,
    number: number,
    title: title,
    content: content,
  );

  /// Create from Chapter model.
  factory ChapterProcessData.fromChapter(Chapter ch) => ChapterProcessData(
    id: ch.id,
    number: ch.number,
    title: ch.title,
    content: ch.content,
  );
}

/// Payload for isolate communication including book metadata.
class _IsolatePayload {
  final List<ChapterProcessData> chapters;
  final String? bookTitle;
  
  _IsolatePayload(this.chapters, this.bookTitle);
}

/// Run chapter processing pipeline in a background isolate.
/// 
/// This moves CPU-intensive text processing (boilerplate removal, 
/// normalization, classification) off the main UI thread.
/// 
/// [bookTitle] - Optional book title to help detect repeated title prefixes.
Future<List<Chapter>> processChaptersInBackground(
  List<Chapter> rawChapters, {
  String? bookTitle,
}) async {
  if (rawChapters.isEmpty) return rawChapters;

  final chapterData = rawChapters.map(ChapterProcessData.fromChapter).toList();
  final payload = _IsolatePayload(chapterData, bookTitle);
  
  final resultData = await Isolate.run(() => _processChaptersIsolate(payload));
  
  return resultData.map((d) => d.toChapter()).toList();
}

/// Internal isolate function for chapter processing.
List<ChapterProcessData> _processChaptersIsolate(_IsolatePayload payload) {
  final rawChapters = payload.chapters;
  final bookTitle = payload.bookTitle;
  
  if (rawChapters.isEmpty) return rawChapters;

  // Build ChapterInfo for classification
  final chapterInfos = rawChapters.map((ch) {
    final snippetLength = min(500, ch.content.length);
    return ChapterInfo(
      filename: ch.id,
      title: ch.title,
      contentSnippet: ch.content.substring(0, snippetLength),
    );
  }).toList();

  // Find body matter range (skip front/back matter)
  final (startIdx, endIdx) = ContentClassifier.findBodyMatterRange(chapterInfos);

  // Filter to body matter only
  var bodyChapters = rawChapters.sublist(startIdx, endIdx);

  // Detect repeated prefixes and suffixes across chapters
  final chapterContents = bodyChapters.map((ch) => ch.content).toList();
  final repeatedPrefix = BoilerplateRemover.detectRepeatedPrefix(chapterContents, bookTitle: bookTitle);
  final repeatedSuffix = BoilerplateRemover.detectRepeatedSuffix(chapterContents);

  // Detect chapter-spanning boilerplate patterns
  final spanningBoilerplate = StructureAnalyzer.detectChapterSpanningBoilerplate(chapterContents);

  // Clean and normalize each chapter
  bodyChapters = bodyChapters.map((chapter) {
    var content = chapter.content;

    // Remove book title prefix from chapter content (e.g., "A Conjuring of Light Chapter 1...")
    if (bookTitle != null) {
      content = BoilerplateRemover.removeRepeatedTitleFromContent(
        content, 
        bookTitle, 
        chapter.title,
      );
    }

    // Remove detected repeated prefix
    if (repeatedPrefix != null) {
      content = BoilerplateRemover.removePrefix(content, repeatedPrefix);
    }

    // Remove detected repeated suffix
    if (repeatedSuffix != null) {
      content = BoilerplateRemover.removeSuffix(content, repeatedSuffix);
    }

    // Remove preliminary sections (transcriber notes, editor notes, etc.)
    final preliminary = StructureAnalyzer.extractPreliminarySection(content);
    if (preliminary != null) {
      content = content.replaceFirst(preliminary, '');
    }

    // Filter chapter-spanning boilerplate lines
    if (spanningBoilerplate.isNotEmpty) {
      content = content
          .split('\n')
          .where((line) => !spanningBoilerplate.contains(line.trim()))
          .join('\n');
    }

    // Remove per-chapter boilerplate (page numbers, scanner notes, etc.)
    content = BoilerplateRemover.cleanChapter(content);

    // Normalize text (quotes, dashes, ligatures, special chars)
    content = tts_normalizer.TextNormalizer.normalize(content);

    return ChapterProcessData(
      id: chapter.id,
      number: chapter.number,
      title: chapter.title,
      content: content,
    );
  }).toList();

  // Renumber chapters starting from 1
  final renumbered = bodyChapters.asMap().entries.map((e) => ChapterProcessData(
    id: e.value.id,
    number: e.key + 1,
    title: e.value.title,
    content: e.value.content,
  )).toList();

  return renumbered;
}
