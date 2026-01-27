// Test script for comparing boilerplate removal before/after StructureAnalyzer
// Run with: dart test/epub_comparison_analysis_test.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';

import 'package:audiobook_flutter_v2/utils/text_normalizer.dart';
import 'package:audiobook_flutter_v2/utils/boilerplate_remover.dart';
import 'package:audiobook_flutter_v2/utils/structure_analyzer.dart';

void main() async {
  final epubDir = Directory('local_dev/dev_books/epub');
  final outputDir = Directory('test/epub_analysis_output');

  if (!await epubDir.exists()) {
    print('EPUB directory not found: ${epubDir.path}');
    print('Please ensure you have test EPUBs in: $epubDir');
    return;
  }

  await outputDir.create(recursive: true);

  // Recursively find all EPUB files
  final epubFiles = await epubDir
      .list(recursive: true)
      .where((f) => f.path.endsWith('.epub'))
      .cast<File>()
      .toList();

  if (epubFiles.isEmpty) {
    print('No EPUB files found in ${epubDir.path}');
    return;
  }

  print('Found ${epubFiles.length} EPUB files\n');

  final allResults = <String, dynamic>{};

  for (final epubFile in epubFiles) {
    final fileName = epubFile.path.split('/').last;
    print('Analyzing: $fileName');

    try {
      final result = await analyzeEpubWithComparison(epubFile);
      allResults[fileName] = result;
      print('  ✓ ${result['chapterCount']} chapters analyzed');
      print('    Old pipeline reduction: ${result['summary']['oldPipelineReduction'].toStringAsFixed(1)}%');
      print('    New pipeline reduction: ${result['summary']['newPipelineReduction'].toStringAsFixed(1)}%');
      print('    Additional reduction: ${result['summary']['additionalReduction'].toStringAsFixed(1)}%');
    } catch (e) {
      print('  ✗ Error: $e');
      allResults[fileName] = {'error': e.toString()};
    }
  }

  // Write detailed results
  final detailFile = File('${outputDir.path}/comparison_results_detailed.json');
  await detailFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(allResults),
  );
  print('\nDetailed results: ${detailFile.path}');

  // Generate summary report
  generateSummaryReport(allResults, outputDir);
}

Future<Map<String, dynamic>> analyzeEpubWithComparison(File epubFile) async {
  final bytes = await epubFile.readAsBytes();

  EpubBook epubBook;
  try {
    epubBook = await EpubReader.readBook(bytes);
  } catch (e) {
    return await analyzeEpubFromZipWithComparison(epubFile);
  }

  final chapters = <Map<String, dynamic>>[];
  final flattened = <EpubChapter>[];

  void addChapters(List<EpubChapter>? list) {
    if (list == null) return;
    for (final ch in list) {
      flattened.add(ch);
      addChapters(ch.SubChapters);
    }
  }

  addChapters(epubBook.Chapters);

  for (var i = 0; i < flattened.length; i++) {
    final ch = flattened[i];
    final html = (ch.HtmlContent ?? '').trim();
    if (html.isEmpty) continue;

    final rawText = stripHtmlToText(html);
    if (rawText.isEmpty) continue;

    final normalizedText = TextNormalizer.normalize(rawText);

    // Old pipeline: just boilerplate removal
    final oldPipelineText = BoilerplateRemover.cleanChapter(normalizedText);

    // New pipeline: with StructureAnalyzer
    var newPipelineText = normalizedText;

    // Extract preliminary section
    final preliminary = StructureAnalyzer.extractPreliminarySection(newPipelineText);
    if (preliminary != null) {
      newPipelineText = newPipelineText.replaceFirst(preliminary, '');
    }

    // Clean chapter (existing boilerplate removal)
    newPipelineText = BoilerplateRemover.cleanChapter(newPipelineText);

    chapters.add(analyzeChapterComparison(
      chapterNumber: i + 1,
      title: ch.Title ?? 'Chapter ${i + 1}',
      rawText: rawText,
      normalizedText: normalizedText,
      oldPipelineText: oldPipelineText,
      newPipelineText: newPipelineText,
    ));
  }

  return {
    'title': epubBook.Title ?? 'Unknown',
    'author': epubBook.Author ?? 'Unknown',
    'chapterCount': chapters.length,
    'chapters': chapters,
    'summary': generateSummary(chapters),
  };
}

Future<Map<String, dynamic>> analyzeEpubFromZipWithComparison(File epubFile) async {
  final inputStream = InputFileStream(epubFile.path);
  final archive = ZipDecoder().decodeBuffer(inputStream);

  final chapters = <Map<String, dynamic>>[];

  final xhtmlFiles = archive
      .where((f) => f.isFile &&
             (f.name.endsWith('.xhtml') || f.name.endsWith('.html') || f.name.endsWith('.htm')))
      .toList();
  xhtmlFiles.sort((a, b) => a.name.compareTo(b.name));

  for (var i = 0; i < xhtmlFiles.length; i++) {
    final entry = xhtmlFiles[i];
    final raw = entry.content as List<int>;
    String html;
    try {
      html = utf8.decode(raw);
    } catch (_) {
      html = String.fromCharCodes(raw);
    }

    final rawText = stripHtmlToText(html);
    if (rawText.trim().isEmpty) continue;

    final normalizedText = TextNormalizer.normalize(rawText);

    // Old pipeline
    final oldPipelineText = BoilerplateRemover.cleanChapter(normalizedText);

    // New pipeline
    var newPipelineText = normalizedText;
    final preliminary = StructureAnalyzer.extractPreliminarySection(newPipelineText);
    if (preliminary != null) {
      newPipelineText = newPipelineText.replaceFirst(preliminary, '');
    }
    newPipelineText = BoilerplateRemover.cleanChapter(newPipelineText);

    chapters.add(analyzeChapterComparison(
      chapterNumber: i + 1,
      title: entry.name.split('/').last,
      rawText: rawText,
      normalizedText: normalizedText,
      oldPipelineText: oldPipelineText,
      newPipelineText: newPipelineText,
    ));
  }

  final fileName = epubFile.path.split('/').last.replaceAll('.epub', '');
  return {
    'title': fileName,
    'author': 'Unknown (zip fallback)',
    'chapterCount': chapters.length,
    'chapters': chapters,
    'summary': generateSummary(chapters),
  };
}

Map<String, dynamic> analyzeChapterComparison({
  required int chapterNumber,
  required String title,
  required String rawText,
  required String normalizedText,
  required String oldPipelineText,
  required String newPipelineText,
}) {
  final rawWords = rawText.split(RegExp(r'\s+'));
  final normalizedWords = normalizedText.split(RegExp(r'\s+'));
  final oldPipelineWords = oldPipelineText.split(RegExp(r'\s+'));
  final newPipelineWords = newPipelineText.split(RegExp(r'\s+'));

  final rawCount = rawWords.length;
  final oldCount = oldPipelineWords.length;
  final newCount = newPipelineWords.length;

  // Calculate reduction percentages
  final oldReduction = rawCount > 0 ? ((rawCount - oldCount) / rawCount * 100) : 0.0;
  final newReduction = rawCount > 0 ? ((rawCount - newCount) / rawCount * 100) : 0.0;
  final additionalReduction = oldCount > 0 ? ((oldCount - newCount) / oldCount * 100) : 0.0;

  // Get samples
  final first100Old = oldPipelineWords.take(100).join(' ');
  final first100New = newPipelineWords.take(100).join(' ');
  final last100Old = oldPipelineWords.length > 100
      ? oldPipelineWords.skip(oldPipelineWords.length - 100).join(' ')
      : oldPipelineWords.join(' ');
  final last100New = newPipelineWords.length > 100
      ? newPipelineWords.skip(newPipelineWords.length - 100).join(' ')
      : newPipelineWords.join(' ');

  return {
    'number': chapterNumber,
    'title': title,
    'wordCounts': {
      'raw': rawCount,
      'normalized': normalizedWords.length,
      'oldPipeline': oldCount,
      'newPipeline': newCount,
    },
    'reductions': {
      'oldPipelinePercent': oldReduction,
      'newPipelinePercent': newReduction,
      'additionalPercent': additionalReduction,
      'wordsSavedByNew': oldCount - newCount,
    },
    'contentComparison': {
      'oldPipelineFirst100': first100Old,
      'newPipelineFirst100': first100New,
      'oldPipelineLast100': last100Old,
      'newPipelineLast100': last100New,
    },
    'falsePositiveCheck': {
      'oldUnchangedFromNew': oldPipelineText == newPipelineText,
      'significantAdditionalRemoval': additionalReduction > 20.0,
    },
  };
}

Map<String, dynamic> generateSummary(List<Map<String, dynamic>> chapters) {
  if (chapters.isEmpty) {
    return {
      'oldPipelineReduction': 0.0,
      'newPipelineReduction': 0.0,
      'additionalReduction': 0.0,
      'totalWordsRemoved': 0,
      'chaptersAnalyzed': 0,
    };
  }

  double totalRawWords = 0;
  double totalOldWords = 0;
  double totalNewWords = 0;
  int chaptersWithAdditionalRemoval = 0;

  for (final ch in chapters) {
    final wordCounts = ch['wordCounts'] as Map;
    final reductions = ch['reductions'] as Map;

    totalRawWords += (wordCounts['raw'] as int).toDouble();
    totalOldWords += (wordCounts['oldPipeline'] as int).toDouble();
    totalNewWords += (wordCounts['newPipeline'] as int).toDouble();

    if ((reductions['additionalPercent'] as double) > 0.1) {
      chaptersWithAdditionalRemoval++;
    }
  }

  final oldReduction = totalRawWords > 0 ? ((totalRawWords - totalOldWords) / totalRawWords * 100) : 0.0;
  final newReduction = totalRawWords > 0 ? ((totalRawWords - totalNewWords) / totalRawWords * 100) : 0.0;
  final additionalReduction = totalOldWords > 0 ? ((totalOldWords - totalNewWords) / totalOldWords * 100) : 0.0;

  return {
    'chaptersAnalyzed': chapters.length,
    'totalRawWords': totalRawWords.toInt(),
    'oldPipelineReduction': oldReduction,
    'newPipelineReduction': newReduction,
    'additionalReduction': additionalReduction,
    'totalWordsRemovedByNew': (totalOldWords - totalNewWords).toInt(),
    'chaptersWithAdditionalRemoval': chaptersWithAdditionalRemoval,
    'averageAdditionalRemovalPerChapter': chapters.isEmpty ? 0.0 : (totalOldWords - totalNewWords) / chapters.length,
  };
}

void generateSummaryReport(Map<String, dynamic> allResults, Directory outputDir) {
  print('\n${'=' * 80}');
  print('BOILERPLATE REMOVAL COMPARISON SUMMARY');
  print('=' * 80);

  var totalBooksAnalyzed = 0;
  var totalChapters = 0;
  double totalOldReduction = 0;
  double totalNewReduction = 0;
  double totalAdditional = 0;
  int booksWithImprovement = 0;

  final reportLines = <String>[
    '# Boilerplate Removal Comparison Report\n',
    '## Executive Summary\n',
  ];

  for (final entry in allResults.entries) {
    if (entry.value is! Map || entry.value['error'] != null) continue;

    final bookData = entry.value as Map;
    final summary = bookData['summary'] as Map;

    totalBooksAnalyzed++;
    totalChapters += bookData['chapterCount'] as int;
    final oldRed = (summary['oldPipelineReduction'] as num).toDouble();
    final newRed = (summary['newPipelineReduction'] as num).toDouble();
    final addRed = (summary['additionalReduction'] as num).toDouble();

    totalOldReduction += oldRed;
    totalNewReduction += newRed;
    totalAdditional += addRed;

    if (addRed > 0.1) booksWithImprovement++;
  }

  print('Books analyzed: $totalBooksAnalyzed');
  print('Total chapters: $totalChapters');
  print('Average old pipeline reduction: ${(totalOldReduction / totalBooksAnalyzed).toStringAsFixed(2)}%');
  print('Average new pipeline reduction: ${(totalNewReduction / totalBooksAnalyzed).toStringAsFixed(2)}%');
  print('Average additional reduction: ${(totalAdditional / totalBooksAnalyzed).toStringAsFixed(2)}%');
  print('Books with improvement: $booksWithImprovement');

  reportLines.addAll([
    'Books analyzed: $totalBooksAnalyzed\n',
    'Total chapters: $totalChapters\n',
    'Average old pipeline reduction: ${(totalOldReduction / totalBooksAnalyzed).toStringAsFixed(2)}%\n',
    'Average new pipeline reduction: ${(totalNewReduction / totalBooksAnalyzed).toStringAsFixed(2)}%\n',
    'Average additional reduction: ${(totalAdditional / totalBooksAnalyzed).toStringAsFixed(2)}%\n',
    'Books showing improvement: $booksWithImprovement\n\n',
    '## Per-Book Results\n\n',
  ]);

  for (final entry in allResults.entries) {
    if (entry.value is! Map || entry.value['error'] != null) continue;

    final bookData = entry.value as Map;
    final summary = bookData['summary'] as Map;

    reportLines.add('### ${entry.key}\n');
    reportLines.add('- Title: ${bookData['title']}\n');
    reportLines.add('- Author: ${bookData['author']}\n');
    reportLines.add('- Chapters: ${bookData['chapterCount']}\n');
    reportLines.add('- Old pipeline reduction: ${(summary['oldPipelineReduction'] as num).toStringAsFixed(2)}%\n');
    reportLines.add('- New pipeline reduction: ${(summary['newPipelineReduction'] as num).toStringAsFixed(2)}%\n');
    reportLines.add('- Additional reduction: ${(summary['additionalReduction'] as num).toStringAsFixed(2)}%\n');
    reportLines.add('- Words removed by new pipeline: ${summary['totalWordsRemovedByNew']}\n\n');
  }

  final reportFile = File('${outputDir.path}/comparison_report.md');
  reportFile.writeAsStringSync(reportLines.join(''));
  print('Summary report: ${reportFile.path}');
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
