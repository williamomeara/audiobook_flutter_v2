// Analyzes Moby Dick import to identify segment distribution issues
// Run with: dart test/moby_dick_import_analysis.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:audiobook_flutter_v2/utils/text_normalizer.dart';
import 'package:audiobook_flutter_v2/utils/boilerplate_remover.dart';
import 'package:audiobook_flutter_v2/utils/structure_analyzer.dart';

void main() async {
  final mobyDickPath = 'local_dev/dev_books/epub/project_gutenberg/pg2701_moby_dick.epub';
  final mobyFile = File(mobyDickPath);

  if (!await mobyFile.exists()) {
    print('Moby Dick EPUB not found at: $mobyDickPath');
    return;
  }

  print('=' * 80);
  print('MOBY DICK IMPORT & SEGMENT ANALYSIS');
  print('=' * 80);
  print('');

  // Create test database
  final fixturesDir = Directory('test/fixtures');
  await fixturesDir.create(recursive: true);
  final dbPath = '${fixturesDir.path}/moby_dick_test.db';

  final existingDb = File(dbPath);
  if (await existingDb.exists()) {
    await existingDb.delete();
  }

  final db = sqlite3.open(dbPath);
  print('Database: $dbPath\n');

  try {
    // Create schema
    _createSchema(db);

    // Import and analyze Moby Dick
    final analysis = await importAndAnalyzeMobyDick(mobyFile, db);

    // Detailed analysis
    await analyzeSegmentDistribution(analysis, db);

  } finally {
    db.dispose();
  }
}

void _createSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS books (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      author TEXT,
      cover_path TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    )
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS chapters (
      id TEXT PRIMARY KEY,
      book_id TEXT NOT NULL,
      number INTEGER NOT NULL,
      title TEXT,
      content TEXT NOT NULL,
      word_count_raw INTEGER,
      word_count_cleaned INTEGER,
      word_count_with_structure INTEGER,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (book_id) REFERENCES books(id)
    )
  ''');

  db.execute('CREATE INDEX idx_chapters_book_id ON chapters(book_id)');
  db.execute('CREATE INDEX idx_chapters_number ON chapters(number)');
}

Future<Map<String, dynamic>> importAndAnalyzeMobyDick(File epubFile, Database db) async {
  print('Parsing Moby Dick EPUB...');

  final bytes = await epubFile.readAsBytes();
  EpubBook epubBook;

  try {
    epubBook = await EpubReader.readBook(bytes);
  } catch (e) {
    print('Failed to parse with EpubReader: $e');
    return {};
  }

  final title = epubBook.Title ?? 'Moby Dick';
  final author = epubBook.Author ?? 'Herman Melville';

  print('  Title: $title');
  print('  Author: $author\n');

  // Flatten chapter hierarchy
  final flattened = <EpubChapter>[];
  void addChapters(List<EpubChapter>? list) {
    if (list == null) return;
    for (final ch in list) {
      flattened.add(ch);
      addChapters(ch.SubChapters);
    }
  }
  addChapters(epubBook.Chapters);

  print('Found ${flattened.length} chapters/sections\n');

  // Insert book
  final now = DateTime.now().millisecondsSinceEpoch;
  final bookId = 'moby_dick_${now}';

  db.execute(
    'INSERT INTO books (id, title, author, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
    [bookId, title, author, now, now],
  );

  // Process each chapter
  final analysisData = <String, dynamic>{
    'bookId': bookId,
    'title': title,
    'author': author,
    'chapters': <Map<String, dynamic>>[],
    'totalChapters': 0,
  };

  var chapterCount = 0;
  var processedCount = 0;

  print('Processing chapters...\n');

  for (var i = 0; i < flattened.length; i++) {
    final ch = flattened[i];
    final html = (ch.HtmlContent ?? '').trim();

    if (html.isEmpty) continue;

    chapterCount++;
    final rawText = stripHtmlToText(html);
    if (rawText.isEmpty) continue;

    processedCount++;

    // Apply pipeline
    final normalizedText = TextNormalizer.normalize(rawText);

    // Old pipeline (just boilerplate)
    final oldPipelineText = BoilerplateRemover.cleanChapter(normalizedText);

    // New pipeline (with StructureAnalyzer)
    var newPipelineText = normalizedText;
    final preliminary = StructureAnalyzer.extractPreliminarySection(newPipelineText);
    if (preliminary != null) {
      newPipelineText = newPipelineText.replaceFirst(preliminary, '');
    }
    newPipelineText = BoilerplateRemover.cleanChapter(newPipelineText);

    final rawWords = rawText.split(RegExp(r'\s+')).length;
    final cleanedWords = newPipelineText.split(RegExp(r'\s+')).length;

    // Get first 200 chars to see what's at the start
    final first200raw = rawText.length > 200 ? rawText.substring(0, 200) : rawText;
    final first200cleaned = newPipelineText.length > 200
        ? newPipelineText.substring(0, 200)
        : newPipelineText;

    final chapterData = {
      'number': processedCount,
      'title': ch.Title ?? 'Chapter $processedCount',
      'wordCount': {
        'raw': rawWords,
        'cleaned': cleanedWords,
      },
      'reduction': {
        'words': rawWords - cleanedWords,
        'percent': rawWords > 0 ? ((rawWords - cleanedWords) / rawWords * 100) : 0,
      },
      'content': {
        'first200raw': first200raw,
        'first200cleaned': first200cleaned,
      },
    };

    analysisData['chapters'].add(chapterData);

    // Insert into database
    final chapterId = 'ch_moby_${processedCount}_${DateTime.now().millisecondsSinceEpoch}';
    db.execute(
      '''INSERT INTO chapters
         (id, book_id, number, title, content, word_count_raw, word_count_cleaned, word_count_with_structure, created_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)''',
      [
        chapterId,
        bookId,
        processedCount,
        ch.Title ?? 'Chapter $processedCount',
        newPipelineText,
        rawWords,
        cleanedWords,
        cleanedWords, // Using new pipeline as the "with structure"
        now,
      ],
    );

    if (processedCount % 10 == 0) {
      print('  Processed $processedCount chapters...');
    }
  }

  analysisData['totalChapters'] = processedCount;
  print('  ✓ Processed $processedCount chapters\n');

  return analysisData;
}

Future<void> analyzeSegmentDistribution(Map<String, dynamic> analysis, Database db) async {
  if ((analysis['chapters'] as List).isEmpty) {
    print('No chapters to analyze');
    return;
  }

  final chapters = analysis['chapters'] as List<Map<String, dynamic>>;

  print('=' * 80);
  print('CHAPTER ANALYSIS');
  print('=' * 80);
  print('');

  // Statistics
  double totalRawWords = 0;
  double totalCleanedWords = 0;
  int maxReductionChapter = 0;
  double maxReduction = 0;
  int minReductionChapter = 0;
  double minReduction = 100;

  for (int i = 0; i < chapters.length; i++) {
    final ch = chapters[i];
    final wordCount = ch['wordCount'] as Map;
    final reduction = ch['reduction'] as Map;

    final raw = (wordCount['raw'] as int).toDouble();
    final cleaned = (wordCount['cleaned'] as int).toDouble();
    final reductionPercent = (reduction['percent'] as num).toDouble();

    totalRawWords += raw;
    totalCleanedWords += cleaned;

    if (reductionPercent > maxReduction) {
      maxReduction = reductionPercent;
      maxReductionChapter = i + 1;
    }
    if (reductionPercent < minReduction) {
      minReduction = reductionPercent;
      minReductionChapter = i + 1;
    }
  }

  final totalReduction = totalRawWords > 0
      ? ((totalRawWords - totalCleanedWords) / totalRawWords * 100)
      : 0;

  print('OVERALL STATISTICS:');
  print('  Total raw words: ${totalRawWords.toInt()}');
  print('  Total cleaned words: ${totalCleanedWords.toInt()}');
  print('  Total reduction: ${totalReduction.toStringAsFixed(2)}%');
  print('  Words removed: ${(totalRawWords - totalCleanedWords).toInt()}');
  print('  Average words per chapter: ${(totalRawWords / chapters.length).toStringAsFixed(0)}');
  print('');

  print('REDUCTION PATTERNS:');
  print('  Highest reduction: Chapter $maxReductionChapter (${maxReduction.toStringAsFixed(2)}%)');
  print('  Lowest reduction: Chapter $minReductionChapter (${minReduction.toStringAsFixed(2)}%)');
  print('');

  // Analyze first 5 chapters in detail
  print('FIRST 5 CHAPTERS (DETAILED):');
  print('');

  for (int i = 0; i < (chapters.length > 5 ? 5 : chapters.length); i++) {
    final ch = chapters[i];
    final number = ch['number'] as int;
    final title = ch['title'] as String;
    final wordCount = ch['wordCount'] as Map;
    final reduction = ch['reduction'] as Map;
    final content = ch['content'] as Map;

    final raw = wordCount['raw'] as int;
    final cleaned = wordCount['cleaned'] as int;
    final reductionPercent = (reduction['percent'] as num).toStringAsFixed(2);
    final first200raw = content['first200raw'] as String;
    final first200cleaned = content['first200cleaned'] as String;

    print('CHAPTER $number: $title');
    print('  Words: $raw → $cleaned (${reduction['words']} removed, $reductionPercent%)');
    print('  First 200 chars (raw):');
    print('    ${first200raw.replaceAll('\n', ' ').substring(0, 150)}...');
    print('  First 200 chars (cleaned):');
    print('    ${first200cleaned.replaceAll('\n', ' ').substring(0, 150)}...');
    print('');
  }

  // Check for excessive boilerplate at chapter starts
  print('CHECKING FOR PRE-CHAPTER BOILERPLATE PATTERNS:');
  print('');

  _analyzePreChapterPatterns(chapters);

  // Save detailed report
  final outputDir = Directory('test/epub_analysis_output');
  await outputDir.create(recursive: true);

  final reportFile = File('${outputDir.path}/moby_dick_analysis.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(analysis),
  );

  print('');
  print('Detailed report saved to: ${reportFile.path}');
}

void _analyzePreChapterPatterns(List<Map<String, dynamic>> chapters) {
  // Look at first 500 characters of each chapter to find patterns
  final startPatterns = <String, int>{};

  for (int i = 0; i < chapters.length; i++) {
    final ch = chapters[i];
    final content = ch['content'] as Map;
    final first200raw = content['first200raw'] as String;

    // Extract first "line" or sentence
    final lines = first200raw.split('\n');
    if (lines.isNotEmpty) {
      final firstLine = lines.first.trim();
      if (firstLine.isNotEmpty && firstLine.length > 5) {
        startPatterns[firstLine] = (startPatterns[firstLine] ?? 0) + 1;
      }
    }
  }

  // Find patterns appearing in 5+ chapters
  final repeatedStarts = startPatterns.entries
      .where((e) => e.value >= 5)
      .toList();

  if (repeatedStarts.isEmpty) {
    print('  No repeated start patterns found (good!)');
  } else {
    print('  Found ${repeatedStarts.length} patterns appearing in 5+ chapters:');
    for (final entry in repeatedStarts) {
      print('    • "${entry.key.substring(0, entry.key.length > 60 ? 60 : entry.key.length)}..." (${entry.value} chapters)');
    }
  }

  print('');
  print('RECOMMENDATIONS:');
  if (repeatedStarts.isEmpty) {
    print('  ✓ No obvious repeated boilerplate before chapters');
    print('  → The excessive segments might be content-driven (many short paragraphs)');
    print('  → Consider reviewing paragraph segmentation logic');
  } else {
    print('  ✗ Found repeated patterns at chapter starts');
    print('  → These should be filtered by detectChapterSpanningBoilerplate()');
    print('  → Check if patterns match the 80% threshold rule');
  }
}

String stripHtmlToText(String html) {
  var text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
  text = text.replaceAll(
    RegExp(r'<section[^>]*class="[^"]*pg-boilerplate[^"]*"[^>]*>[\s\S]*?</section>', caseSensitive: false),
    ''
  );
  text = text.replaceAll(
    RegExp(r'<div[^>]*class="[^"]*pg-boilerplate[^"]*"[^>]*>[\s\S]*?</div>', caseSensitive: false),
    ''
  );
  text = text.replaceAll(
    RegExp(r'<[^>]*id="pg-header"[^>]*>[\s\S]*?</[^>]+>', caseSensitive: false),
    ''
  );
  text = text.replaceAll(
    RegExp(r'<[^>]*id="pg-footer"[^>]*>[\s\S]*?</[^>]+>', caseSensitive: false),
    ''
  );
  text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = TextNormalizer.decodeHtmlEntities(text);
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();

  return text;
}
