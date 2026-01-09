// Test script for parsing EPUBs and analyzing text normalization/boilerplate removal
// Run with: dart test/epub_text_analysis_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:epubx/epubx.dart';

import '../lib/utils/text_normalizer.dart';
import '../lib/utils/boilerplate_remover.dart';

void main() async {
  final epubDir = Directory('local_dev/dev_books/epub');
  final outputDir = Directory('test/epub_analysis_output');
  
  if (!await epubDir.exists()) {
    print('EPUB directory not found: ${epubDir.path}');
    return;
  }
  
  await outputDir.create(recursive: true);
  
  // Recursively find all EPUB files including subdirectories
  final epubFiles = await epubDir
      .list(recursive: true)
      .where((f) => f.path.endsWith('.epub'))
      .cast<File>()
      .toList();
  
  print('Found ${epubFiles.length} EPUB files\n');
  
  final allResults = <String, dynamic>{};
  
  for (final epubFile in epubFiles) {
    final fileName = epubFile.path.split('/').last;
    print('Processing: $fileName');
    
    try {
      final result = await analyzeEpub(epubFile);
      allResults[fileName] = result;
      print('  ✓ ${result['chapterCount']} chapters found');
    } catch (e) {
      print('  ✗ Error: $e');
      allResults[fileName] = {'error': e.toString()};
    }
  }
  
  // Write combined results
  final outputFile = File('${outputDir.path}/analysis_results.json');
  await outputFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(allResults),
  );
  print('\n\nResults written to: ${outputFile.path}');
  
  // Print summary of issues found
  printIssueSummary(allResults);
}

Future<Map<String, dynamic>> analyzeEpub(File epubFile) async {
  final bytes = await epubFile.readAsBytes();
  
  EpubBook epubBook;
  try {
    epubBook = await EpubReader.readBook(bytes);
  } catch (e) {
    // Fallback to zip parsing
    return await analyzeEpubFromZip(epubFile);
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
    final cleanedText = BoilerplateRemover.cleanChapter(normalizedText);
    
    chapters.add(analyzeChapter(
      chapterNumber: i + 1,
      title: ch.Title ?? 'Chapter ${i + 1}',
      rawText: rawText,
      normalizedText: normalizedText,
      cleanedText: cleanedText,
    ));
  }
  
  return {
    'title': epubBook.Title ?? 'Unknown',
    'author': epubBook.Author ?? 'Unknown',
    'chapterCount': chapters.length,
    'chapters': chapters,
    'issues': findIssues(chapters),
  };
}

Future<Map<String, dynamic>> analyzeEpubFromZip(File epubFile) async {
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
    final cleanedText = BoilerplateRemover.cleanChapter(normalizedText);
    
    chapters.add(analyzeChapter(
      chapterNumber: i + 1,
      title: entry.name.split('/').last,
      rawText: rawText,
      normalizedText: normalizedText,
      cleanedText: cleanedText,
    ));
  }
  
  final fileName = epubFile.path.split('/').last.replaceAll('.epub', '');
  return {
    'title': fileName,
    'author': 'Unknown (zip fallback)',
    'chapterCount': chapters.length,
    'chapters': chapters,
    'issues': findIssues(chapters),
  };
}

Map<String, dynamic> analyzeChapter({
  required int chapterNumber,
  required String title,
  required String rawText,
  required String normalizedText,
  required String cleanedText,
}) {
  final rawWords = rawText.split(RegExp(r'\s+'));
  final cleanedWords = cleanedText.split(RegExp(r'\s+'));
  
  // Get first 100 and last 100 words
  final first100Raw = rawWords.take(100).join(' ');
  final last100Raw = rawWords.length > 100 
      ? rawWords.skip(rawWords.length - 100).join(' ')
      : rawWords.join(' ');
  
  final first100Cleaned = cleanedWords.take(100).join(' ');
  final last100Cleaned = cleanedWords.length > 100
      ? cleanedWords.skip(cleanedWords.length - 100).join(' ')
      : cleanedWords.join(' ');
  
  // Find special characters that weren't normalized
  final specialChars = findSpecialCharacters(cleanedText);
  
  return {
    'number': chapterNumber,
    'title': title,
    'wordCount': {
      'raw': rawWords.length,
      'cleaned': cleanedWords.length,
    },
    'first100Words': {
      'raw': first100Raw,
      'cleaned': first100Cleaned,
    },
    'last100Words': {
      'raw': last100Raw,
      'cleaned': last100Cleaned,
    },
    'specialCharsRemaining': specialChars,
    'changedByNormalization': rawText != normalizedText,
    'changedByBoilerplateRemoval': normalizedText != cleanedText,
  };
}

List<Map<String, dynamic>> findSpecialCharacters(String text) {
  final specials = <Map<String, dynamic>>[];
  
  // Check for remaining special characters that should have been normalized
  final patterns = {
    'curly single quotes': RegExp(r'[\u2018\u2019\u201A\u201B]'),
    'curly double quotes': RegExp(r'[\u201C\u201D\u201E\u201F]'),
    'guillemets': RegExp(r'[\u00AB\u00BB]'),
    'em-dash': RegExp(r'\u2014'),
    'en-dash': RegExp(r'\u2013'),
    'ellipsis': RegExp(r'\u2026'),
    'ligatures': RegExp(r'[\uFB00-\uFB06]'),
    'special spaces': RegExp(r'[\u00A0\u202F\u2009\u200A\u2002\u2003\u2007]'),
    'zero-width chars': RegExp(r'[\u200B\u200C\u200D\uFEFF]'),
  };
  
  for (final entry in patterns.entries) {
    final matches = entry.value.allMatches(text);
    if (matches.isNotEmpty) {
      specials.add({
        'type': entry.key,
        'count': matches.length,
        'examples': matches.take(3).map((m) => m.group(0)).toList(),
      });
    }
  }
  
  return specials;
}

Map<String, dynamic> findIssues(List<Map<String, dynamic>> chapters) {
  final issues = <String, dynamic>{};
  
  // Count chapters with remaining special characters
  var specialCharChapters = 0;
  for (final ch in chapters) {
    final specials = ch['specialCharsRemaining'] as List;
    if (specials.isNotEmpty) {
      specialCharChapters++;
    }
  }
  
  if (specialCharChapters > 0) {
    issues['chaptersWithSpecialChars'] = specialCharChapters;
  }
  
  // Check for potential front matter (short chapters at start)
  if (chapters.isNotEmpty) {
    final firstChapter = chapters.first;
    final wordCount = (firstChapter['wordCount'] as Map)['cleaned'] as int;
    final first100 = (firstChapter['first100Words'] as Map)['cleaned'] as String;
    
    // Check for front matter indicators
    final frontMatterKeywords = [
      'copyright', 'isbn', 'published', 'all rights reserved',
      'table of contents', 'contents', 'dedication', 'acknowledgment',
    ];
    final lowerFirst = first100.toLowerCase();
    for (final keyword in frontMatterKeywords) {
      if (lowerFirst.contains(keyword)) {
        issues['possibleFrontMatter'] = {
          'chapter': 1,
          'keyword': keyword,
          'excerpt': first100.substring(0, first100.length.clamp(0, 200)),
        };
        break;
      }
    }
  }
  
  // Check for potential back matter (short chapters at end)
  if (chapters.length > 1) {
    final lastChapter = chapters.last;
    final last100 = (lastChapter['last100Words'] as Map)['cleaned'] as String;
    
    final backMatterKeywords = [
      'about the author', 'acknowledgment', 'bibliography',
      'also by', 'further reading',
    ];
    final lowerLast = last100.toLowerCase();
    for (final keyword in backMatterKeywords) {
      if (lowerLast.contains(keyword)) {
        issues['possibleBackMatter'] = {
          'chapter': chapters.length,
          'keyword': keyword,
          'excerpt': last100.substring(0, last100.length.clamp(0, 200)),
        };
        break;
      }
    }
  }
  
  // Check for boilerplate in first chapter
  if (chapters.isNotEmpty) {
    final first100 = (chapters.first['first100Words'] as Map)['cleaned'] as String;
    if (BoilerplateRemover.hasProjectGutenbergBoilerplate(first100)) {
      issues['projectGutenbergBoilerplate'] = true;
    }
  }
  
  // Check for repeated prefixes across chapters (like PG headers)
  if (chapters.length >= 5) {
    final chapterTexts = chapters.map((ch) {
      final first = (ch['first100Words'] as Map)['cleaned'] as String;
      return first;
    }).toList();
    
    final repeatedPrefix = BoilerplateRemover.detectRepeatedPrefix(chapterTexts);
    if (repeatedPrefix != null) {
      issues['repeatedPrefix'] = repeatedPrefix.length > 50 
          ? '${repeatedPrefix.substring(0, 50)}...' 
          : repeatedPrefix;
    }
    
    final chapterLastTexts = chapters.map((ch) {
      final last = (ch['last100Words'] as Map)['cleaned'] as String;
      return last;
    }).toList();
    
    final repeatedSuffix = BoilerplateRemover.detectRepeatedSuffix(chapterLastTexts);
    if (repeatedSuffix != null) {
      issues['repeatedSuffix'] = repeatedSuffix.length > 50 
          ? '${repeatedSuffix.substring(0, 50)}...' 
          : repeatedSuffix;
    }
  }
  
  return issues;
}

String stripHtmlToText(String html) {
  // Remove script and style tags with content
  var text = html.replaceAll(RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false), '');
  
  // Replace br and p tags with newlines
  text = text.replaceAll(RegExp(r'<br\s*/?>'), '\n');
  text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
  
  // Remove all remaining HTML tags
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  
  // Decode HTML entities
  text = decodeHtmlEntities(text);
  
  // Normalize whitespace
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  
  return text;
}

String decodeHtmlEntities(String text) {
  // Use the improved TextNormalizer.decodeHtmlEntities method
  return TextNormalizer.decodeHtmlEntities(text);
}

void printIssueSummary(Map<String, dynamic> allResults) {
  print('\n${'=' * 60}');
  print('ISSUE SUMMARY');
  print('=' * 60);
  
  var booksWithSpecialChars = 0;
  var booksWithFrontMatter = 0;
  var booksWithBackMatter = 0;
  var booksWithGutenberg = 0;
  var booksWithRepeatedPrefix = 0;
  var booksWithRepeatedSuffix = 0;
  
  for (final entry in allResults.entries) {
    if (entry.value is! Map || entry.value['error'] != null) continue;
    
    final issues = entry.value['issues'] as Map? ?? {};
    
    if (issues['chaptersWithSpecialChars'] != null) booksWithSpecialChars++;
    if (issues['possibleFrontMatter'] != null) booksWithFrontMatter++;
    if (issues['possibleBackMatter'] != null) booksWithBackMatter++;
    if (issues['projectGutenbergBoilerplate'] == true) booksWithGutenberg++;
    if (issues['repeatedPrefix'] != null) booksWithRepeatedPrefix++;
    if (issues['repeatedSuffix'] != null) booksWithRepeatedSuffix++;
  }
  
  print('Books with remaining special characters: $booksWithSpecialChars');
  print('Books with possible front matter: $booksWithFrontMatter');
  print('Books with possible back matter: $booksWithBackMatter');
  print('Books with Project Gutenberg boilerplate: $booksWithGutenberg');
  print('Books with repeated prefix headers: $booksWithRepeatedPrefix');
  print('Books with repeated suffix footers: $booksWithRepeatedSuffix');
  
  // Print detailed issues
  print('\n--- DETAILED ISSUES ---\n');
  
  for (final entry in allResults.entries) {
    if (entry.value is! Map || entry.value['error'] != null) continue;
    
    final issues = entry.value['issues'] as Map? ?? {};
    if (issues.isNotEmpty) {
      print('${entry.key}:');
      for (final issue in issues.entries) {
        print('  - ${issue.key}: ${_formatIssue(issue.value)}');
      }
      print('');
    }
  }
}

String _formatIssue(dynamic value) {
  if (value is Map) {
    if (value.containsKey('keyword')) {
      return 'found "${value['keyword']}"';
    }
    return value.toString();
  }
  return value.toString();
}
