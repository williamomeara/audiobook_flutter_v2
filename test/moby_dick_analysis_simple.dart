// Simple analysis of Moby Dick without database dependency
// Run with: dart test/moby_dick_analysis_simple.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';

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

  print('');
  print('=' * 90);
  print('MOBY DICK DETAILED ANALYSIS: Identifying Excessive Pre-Chapter Segments');
  print('=' * 90);
  print('');

  // Parse EPUB
  final bytes = await mobyFile.readAsBytes();
  EpubBook epubBook;

  try {
    epubBook = await EpubReader.readBook(bytes);
  } catch (e) {
    print('Failed to parse EPUB: $e');
    return;
  }

  // Flatten chapters
  final flattened = <EpubChapter>[];
  void addChapters(List<EpubChapter>? list) {
    if (list == null) return;
    for (final ch in list) {
      flattened.add(ch);
      addChapters(ch.SubChapters);
    }
  }
  addChapters(epubBook.Chapters);

  print('Found ${flattened.length} total sections in EPUB\n');

  // Process chapters
  final chapters = <ChapterAnalysis>[];
  var processedCount = 0;

  print('Processing chapters (this may take a moment)...\n');

  for (var i = 0; i < flattened.length; i++) {
    final ch = flattened[i];
    final html = (ch.HtmlContent ?? '').trim();

    if (html.isEmpty) continue;

    final rawText = stripHtmlToText(html);
    if (rawText.isEmpty) continue;

    processedCount++;

    // Apply pipeline
    final normalizedText = TextNormalizer.normalize(rawText);
    final oldPipelineText = BoilerplateRemover.cleanChapter(normalizedText);

    // New pipeline with StructureAnalyzer
    var newPipelineText = normalizedText;
    final preliminary = StructureAnalyzer.extractPreliminarySection(newPipelineText);
    if (preliminary != null) {
      newPipelineText = newPipelineText.replaceFirst(preliminary, '');
    }
    newPipelineText = BoilerplateRemover.cleanChapter(newPipelineText);

    final rawWords = rawText.split(RegExp(r'\s+')).length;
    final cleanedWords = newPipelineText.split(RegExp(r'\s+')).length;

    // Get first 500 characters to analyze pre-chapter content
    final first500 = rawText.length > 500 ? rawText.substring(0, 500) : rawText;

    chapters.add(ChapterAnalysis(
      number: processedCount,
      title: ch.Title ?? 'Chapter $processedCount',
      rawWords: rawWords,
      cleanedWords: cleanedWords,
      first500Chars: first500,
      oldPipelineWords: oldPipelineText.split(RegExp(r'\s+')).length,
      newPipelineWords: cleanedWords,
    ));

    if (processedCount % 20 == 0) {
      print('  Processed $processedCount chapters...');
    }
  }

  print('  ✓ Processed $processedCount chapters\n');

  // Analysis
  print('=' * 90);
  print('CHAPTER STATISTICS');
  print('=' * 90);
  print('');

  double totalRaw = 0;
  double totalOld = 0;
  double totalNew = 0;
  int maxWordRemoval = 0;
  int maxWordRemovalChapter = 0;

  final shortChapters = <ChapterAnalysis>[];

  for (final ch in chapters) {
    totalRaw += ch.rawWords;
    totalOld += ch.oldPipelineWords;
    totalNew += ch.newPipelineWords;

    final removed = ch.oldPipelineWords - ch.newPipelineWords;
    if (removed > maxWordRemoval) {
      maxWordRemoval = removed;
      maxWordRemovalChapter = ch.number;
    }

    // Mark if chapter is suspiciously short
    if (ch.rawWords < 1000 && ch.rawWords > 0) {
      shortChapters.add(ch);
    }
  }

  final totalReductionOld = totalRaw > 0 ? ((totalRaw - totalOld) / totalRaw * 100) : 0;
  final totalReductionNew = totalRaw > 0 ? ((totalRaw - totalNew) / totalRaw * 100) : 0;
  final additionalReduction = totalOld > 0 ? ((totalOld - totalNew) / totalOld * 100) : 0;

  print('OVERALL METRICS:');
  print('  Total chapters analyzed: ${chapters.length}');
  print('  Total raw words: ${totalRaw.toInt()}');
  print('  ');
  print('  Old pipeline (existing boilerplate removal):');
  print('    → Words removed: ${(totalRaw - totalOld).toInt()}');
  print('    → Reduction: ${totalReductionOld.toStringAsFixed(2)}%');
  print('    → Words remaining: ${totalOld.toInt()}');
  print('  ');
  print('  New pipeline (with StructureAnalyzer):');
  print('    → Words removed: ${(totalRaw - totalNew).toInt()}');
  print('    → Reduction: ${totalReductionNew.toStringAsFixed(2)}%');
  print('    → Words remaining: ${totalNew.toInt()}');
  print('  ');
  print('  Additional improvement from StructureAnalyzer:');
  print('    → Words removed: ${(totalOld - totalNew).toInt()}');
  print('    → Additional reduction: ${additionalReduction.toStringAsFixed(2)}%');
  print('');

  // Find average chapter length
  final avgRawWords = (totalRaw / chapters.length).toInt();
  print('  Average chapter size: $avgRawWords words');
  print('');

  // Identify pre-chapter boilerplate patterns
  print('=' * 90);
  print('PRE-CHAPTER BOILERPLATE ANALYSIS');
  print('=' * 90);
  print('');

  _analyzePrechapterPatterns(chapters);

  // Show first few chapters in detail
  print('');
  print('=' * 90);
  print('FIRST 10 CHAPTERS (DETAILED)');
  print('=' * 90);
  print('');

  for (int i = 0; i < (chapters.length > 10 ? 10 : chapters.length); i++) {
    final ch = chapters[i];
    final oldReduction = ch.rawWords > 0
        ? ((ch.rawWords - ch.oldPipelineWords) / ch.rawWords * 100)
        : 0;
    final newReduction = ch.rawWords > 0
        ? ((ch.rawWords - ch.newPipelineWords) / ch.rawWords * 100)
        : 0;
    final additionalRed = ch.oldPipelineWords > 0
        ? ((ch.oldPipelineWords - ch.newPipelineWords) / ch.oldPipelineWords * 100)
        : 0;

    print('CHAPTER ${ch.number}: ${ch.title}');
    print('  Raw words: ${ch.rawWords}');
    print('  After old pipeline: ${ch.oldPipelineWords} (${oldReduction.toStringAsFixed(1)}% removed)');
    print('  After new pipeline: ${ch.newPipelineWords} (additional ${additionalRed.toStringAsFixed(1)}% removed)');
    print('  First 200 characters:');
    print('    "${ch.first500Chars.replaceAll('\n', ' ').substring(0, 200)}..."');
    print('');
  }

  // Identify problem chapters
  print('');
  print('=' * 90);
  print('PROBLEM CHAPTERS (likely excessive pre-chapter boilerplate)');
  print('=' * 90);
  print('');

  final problemChapters = chapters.where((ch) {
    final oldReduction = ch.rawWords > 0
        ? ((ch.rawWords - ch.oldPipelineWords) / ch.rawWords * 100)
        : 0;
    return oldReduction > 20; // Chapters losing >20% to boilerplate
  }).toList();

  if (problemChapters.isEmpty) {
    print('✓ No chapters with excessive boilerplate (>20% reduction)');
  } else {
    print('Found ${problemChapters.length} chapters with >20% reduction:');
    print('');
    for (final ch in problemChapters.take(10)) {
      final oldReduction = ch.rawWords > 0
          ? ((ch.rawWords - ch.oldPipelineWords) / ch.rawWords * 100)
          : 0;
      print('  Chapter ${ch.number} (${ch.title}): ${oldReduction.toStringAsFixed(1)}% removed');
      print('    First 150 chars: "${ch.first500Chars.substring(0, ch.first500Chars.length > 150 ? 150 : ch.first500Chars.length).replaceAll('\n', ' ')}..."');
    }
  }

  print('');
  print('=' * 90);
  print('RECOMMENDATIONS FOR SEGMENT REDUCTION');
  print('=' * 90);
  print('');

  if (additionalReduction < 1) {
    print('⚠ StructureAnalyzer is providing minimal improvement (${additionalReduction.toStringAsFixed(2)}%)');
    print('');
    print('This suggests:');
    print('1. Boilerplate patterns are already caught by existing BoilerplateRemover');
    print('2. The "excessive segments" issue is likely NOT boilerplate-related');
    print('3. Segments are probably from content structure (many short paragraphs)');
    print('');
    print('NEXT STEP: Check segmentation logic, not boilerplate removal');
  } else {
    print('✓ StructureAnalyzer provides ${additionalReduction.toStringAsFixed(2)}% additional improvement');
    print('');
    if (problemChapters.isNotEmpty) {
      print('Problem chapters found with excessive boilerplate.');
      print('Recommendation: Review first 500 characters of these chapters');
      print('and add new patterns if they match common boilerplate.');
    }
  }

  print('');

  // Save detailed report
  final reportData = {
    'title': 'Moby Dick Analysis',
    'chapters': chapters.map((ch) => {
      'number': ch.number,
      'title': ch.title,
      'rawWords': ch.rawWords,
      'oldPipelineWords': ch.oldPipelineWords,
      'newPipelineWords': ch.newPipelineWords,
      'first500Chars': ch.first500Chars,
    }).toList(),
    'summary': {
      'totalChapters': chapters.length,
      'totalRawWords': totalRaw.toInt(),
      'totalOldPipelineWords': totalOld.toInt(),
      'totalNewPipelineWords': totalNew.toInt(),
      'oldPipelineReductionPercent': totalReductionOld,
      'newPipelineReductionPercent': totalReductionNew,
      'additionalReductionPercent': additionalReduction,
    },
  };

  final outputDir = Directory('test/epub_analysis_output');
  await outputDir.create(recursive: true);

  final reportFile = File('${outputDir.path}/moby_dick_analysis.json');
  await reportFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(reportData),
  );

  print('Detailed analysis saved: ${reportFile.path}');
}

void _analyzePrechapterPatterns(List<ChapterAnalysis> chapters) {
  // Look for repeated patterns at chapter starts
  final firstLines = <String, int>{};
  final firstParagraphs = <String, int>{};

  for (final ch in chapters) {
    // Get first line
    final lines = ch.first500Chars.split('\n');
    if (lines.isNotEmpty) {
      final firstLine = lines.first.trim();
      if (firstLine.isNotEmpty && firstLine.length > 3) {
        firstLines[firstLine] = (firstLines[firstLine] ?? 0) + 1;
      }
    }

    // Get first paragraph
    final paragraphs = ch.first500Chars.split(RegExp(r'\n\s*\n'));
    if (paragraphs.isNotEmpty) {
      final firstPara = paragraphs.first.trim();
      if (firstPara.isNotEmpty && firstPara.length > 20) {
        firstParagraphs[firstPara] = (firstParagraphs[firstPara] ?? 0) + 1;
      }
    }
  }

  // Find patterns appearing in 5+ chapters
  final repeatedLines = firstLines.entries
      .where((e) => e.value >= 5)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  print('Patterns appearing at chapter starts (5+ chapters):');
  print('');

  if (repeatedLines.isEmpty) {
    print('  ✓ No repeated first lines (good!)');
  } else {
    for (final entry in repeatedLines.take(10)) {
      print('  • "${entry.key}" (${entry.value} chapters)');
    }
  }

  print('');
  print('Analysis:');
  if (repeatedLines.isEmpty) {
    print('  ✓ No obvious boilerplate headers before chapters');
    print('  → The segment issue is likely content-driven');
  } else if (repeatedLines.every((e) => e.value < chapters.length * 0.8)) {
    print('  ✓ Repeated patterns are below 80% threshold');
    print('  → detectChapterSpanningBoilerplate() might not catch them');
    print('  → Consider lowering threshold or adding specific patterns');
  } else {
    print('  ✗ Found high-frequency boilerplate patterns');
    print('  → These should be detected and removed');
    print('  → Review patterns for accuracy');
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

class ChapterAnalysis {
  final int number;
  final String title;
  final int rawWords;
  final int cleanedWords;
  final int oldPipelineWords;
  final int newPipelineWords;
  final String first500Chars;

  ChapterAnalysis({
    required this.number,
    required this.title,
    required this.rawWords,
    required this.cleanedWords,
    required this.oldPipelineWords,
    required this.newPipelineWords,
    required this.first500Chars,
  });
}
