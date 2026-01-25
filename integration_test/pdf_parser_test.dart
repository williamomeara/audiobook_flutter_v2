// ignore_for_file: avoid_print
/// PDF Parser Integration Test
///
/// Tests the full PDF parsing pipeline including:
/// - Text extraction
/// - Outline-based chapter detection
/// - Smart text processing
/// - Cover image extraction
///
/// Run on desktop:
///   flutter test integration_test/pdf_parser_test.dart -d linux
///   flutter test integration_test/pdf_parser_test.dart -d macos
///
/// Run on Android device (PDFs must be in /sdcard/Download/):
///   flutter test integration_test/pdf_parser_test.dart -d <device_id>
///
/// This test outputs JSON results for inspection.
/// Output is written to test/pdf_analysis_output/analysis_results.json on desktop,
/// or printed to console on Android (since device can't write to host filesystem).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:audiobook_flutter_v2/app/app_paths.dart';
import 'package:audiobook_flutter_v2/infra/pdf_parser.dart';
import 'package:audiobook_flutter_v2/utils/boilerplate_remover.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  // Use different paths for desktop vs Android
  // Desktop: local_dev/dev_books/pdf (relative to project root)
  // Android: App's external storage (more reliable access)
  const desktopPdfDir = 'local_dev/dev_books/pdf';
  // Note: On Android, we use the app's external files directory which has reliable access
  // Push test PDFs there via: adb push test.pdf /sdcard/Android/data/io.eist.app/files/
  // Or use /data/local/tmp/ for testing
  
  group('PDF Parser Integration', () {
    late AppPaths paths;
    late PdfParser parser;
    late String pdfDir;
    late bool isAndroid;
    
    setUpAll(() async {
      // Initialize paths
      final tempDir = await getTemporaryDirectory();
      final appDir = Directory('${tempDir.path}/pdf_parser_test');
      await appDir.create(recursive: true);
      
      paths = AppPaths(appDir);
      parser = PdfParser(paths);
      
      // Detect platform and set PDF directory
      isAndroid = Platform.isAndroid;
      if (isAndroid) {
        // Use app's external files directory for reliable access
        final extDir = await getExternalStorageDirectory();
        pdfDir = extDir?.path ?? '/data/local/tmp';
        print('App external dir: $pdfDir');
      } else {
        pdfDir = desktopPdfDir;
      }
      print('Running on: ${Platform.operatingSystem}');
      print('Using PDF directory: $pdfDir');
    });
    
    test('parse all sample PDFs and output results', timeout: Timeout(Duration(minutes: 10)), () async {
      final dir = Directory(pdfDir);
      if (!dir.existsSync()) {
        print('PDF directory not found: $pdfDir');
        if (isAndroid) {
          print('On Android, push PDFs to /sdcard/Download/ first:');
          print('  adb shell "cat > /sdcard/Download/book.pdf" < local_book.pdf');
        }
        print('Skipping PDF parser integration test.');
        return;
      }
      
      final pdfFiles = <File>[];
      print('Scanning directory: ${dir.path}');
      await for (final entity in dir.list(recursive: false)) {
        print('  Found: ${entity.path}');
        if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
          // In app's external dir, accept any PDF (no filter needed - controlled location)
          print('    ✓ PDF file found');
          pdfFiles.add(entity);
        }
      }
      
      print('Found ${pdfFiles.length} PDF files to parse');
      print('');
      
      // Use same format as EPUB analysis: Map<filename, result>
      final allResults = <String, dynamic>{};
      
      for (final file in pdfFiles) {
        final filename = file.path.split('/').last;
        print('Processing: $filename');
        
        try {
          final bookId = 'test-${DateTime.now().millisecondsSinceEpoch}';
          final parsed = await parser.parseFromFile(
            pdfPath: file.path,
            bookId: bookId,
          );
          
          print('  ✓ ${parsed.chapters.length} chapters found');
          
          // Analyze chapters in same format as EPUB analysis
          final chapters = <Map<String, dynamic>>[];
          for (final ch in parsed.chapters) {
            final words = ch.content.split(RegExp(r'\s+'));
            final first100 = words.take(100).join(' ');
            final last100 = words.length > 100 
                ? words.skip(words.length - 100).join(' ')
                : words.join(' ');
            
            chapters.add({
              'number': ch.number,
              'title': ch.title,
              'wordCount': {
                'raw': words.length,
                'cleaned': words.length,  // PDF processing happens during parse
              },
              'first100Words': {
                'raw': first100,
                'cleaned': first100,
              },
              'last100Words': {
                'raw': last100,
                'cleaned': last100,
              },
              'specialCharsRemaining': _findSpecialCharacters(ch.content),
              'changedByNormalization': false,  // Already processed
              'changedByBoilerplateRemoval': false,
            });
          }
          
          allResults[filename] = {
            'title': parsed.title,
            'author': parsed.author,
            'hasCover': parsed.coverPath != null,
            'chapterCount': parsed.chapters.length,
            'chapters': chapters,
            'issues': _findIssues(chapters),
          };
          
        } catch (e, st) {
          print('  ✗ Error: $e');
          print('  $st');
          
          allResults[filename] = {'error': e.toString()};
        }
      }
      
      // Write results to JSON (same location/format as EPUB)
      // On Android, we can't write to the host filesystem, so just print results
      final encoder = JsonEncoder.withIndent('  ');
      final jsonOutput = encoder.convert(allResults);
      
      if (isAndroid) {
        print('\n\n=== JSON RESULTS (copy this) ===');
        print(jsonOutput);
        print('=== END JSON RESULTS ===\n');
      } else {
        final outputDir = Directory('test/pdf_analysis_output');
        await outputDir.create(recursive: true);
        
        final outputFile = File('${outputDir.path}/analysis_results.json');
        await outputFile.writeAsString(jsonOutput);
        print('\n\nResults written to: ${outputFile.path}');
      }
      
      // Print summary
      _printIssueSummary(allResults);
      
      // Basic assertions
      expect(allResults, isNotEmpty);
      expect(
        allResults.values.where((r) => r is Map && !r.containsKey('error')).length,
        greaterThan(0),
        reason: 'At least one PDF should parse successfully',
      );
    });
    
    test('parse single PDF with detailed output', timeout: Timeout(Duration(minutes: 5)), () async {
      // Use a specific PDF for detailed testing
      // On Android, use the PDF we copied to app's external dir
      final testPdf = isAndroid 
          ? '$pdfDir/Basic Economics.pdf'
          : '$pdfDir/Programming/The Pragmatic Programmer - 20th Anniversary Edition (David Thomas, Andrew Hunt) (Z-Library).pdf';
      
      final file = File(testPdf);
      if (!file.existsSync()) {
        print('Test PDF not found: $testPdf');
        return;
      }
      
      final bookId = 'detailed-test-${DateTime.now().millisecondsSinceEpoch}';
      final parsed = await parser.parseFromFile(
        pdfPath: testPdf,
        bookId: bookId,
      );
      
      print('Detailed Parse Results:');
      print('=======================');
      print('Title: ${parsed.title}');
      print('Author: ${parsed.author}');
      print('Cover: ${parsed.coverPath ?? "None"}');
      print('Chapters: ${parsed.chapters.length}');
      print('');
      
      for (final chapter in parsed.chapters.take(5)) {
        print('Chapter ${chapter.number}: ${chapter.title}');
        print('  Content length: ${chapter.content.length} chars');
        print('  Preview: ${chapter.content.substring(0, chapter.content.length.clamp(0, 200))}...');
        print('');
      }
      
      // Assertions
      expect(parsed.title, isNotEmpty);
      expect(parsed.chapters, isNotEmpty);
      
      // Check that text processing was applied
      for (final chapter in parsed.chapters) {
        // Should not contain raw ligatures after normalization
        expect(chapter.content.contains('ﬁ'), isFalse, 
            reason: 'fi ligature should be normalized');
        expect(chapter.content.contains('ﬂ'), isFalse,
            reason: 'fl ligature should be normalized');
        
        // Should not have excessive blank lines
        expect(chapter.content.contains('\n\n\n\n'), isFalse,
            reason: 'Should not have 4+ consecutive newlines');
      }
    });
  });
}

/// Find special characters that should have been normalized
List<Map<String, dynamic>> _findSpecialCharacters(String text) {
  final specials = <Map<String, dynamic>>[];
  
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

/// Find issues in parsed chapters (same as EPUB analysis)
Map<String, dynamic> _findIssues(List<Map<String, dynamic>> chapters) {
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
    final first100 = (firstChapter['first100Words'] as Map)['cleaned'] as String;
    
    final frontMatterKeywords = [
      'copyright', 'isbn', 'published', 'all rights reserved',
      'table of contents', 'contents', 'dedication', 'acknowledgment',
    ];
    final lowerFirst = first100.toLowerCase();
    for (final keyword in frontMatterKeywords) {
      if (lowerFirst.contains(keyword)) {
        issues['possibleFrontMatter'] = 'found "$keyword"';
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
        issues['possibleBackMatter'] = 'found "$keyword"';
        break;
      }
    }
  }
  
  // Check for repeated prefixes across chapters
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
  }
  
  return issues;
}

/// Print summary of issues found
void _printIssueSummary(Map<String, dynamic> allResults) {
  print('\n${'=' * 60}');
  print('ISSUE SUMMARY');
  print('=' * 60);
  
  var booksWithSpecialChars = 0;
  var booksWithFrontMatter = 0;
  var booksWithBackMatter = 0;
  var booksWithRepeatedPrefix = 0;
  
  for (final entry in allResults.entries) {
    if (entry.value is! Map || entry.value['error'] != null) continue;
    
    final issues = entry.value['issues'] as Map? ?? {};
    
    if (issues['chaptersWithSpecialChars'] != null) booksWithSpecialChars++;
    if (issues['possibleFrontMatter'] != null) booksWithFrontMatter++;
    if (issues['possibleBackMatter'] != null) booksWithBackMatter++;
    if (issues['repeatedPrefix'] != null) booksWithRepeatedPrefix++;
  }
  
  print('PDFs with remaining special characters: $booksWithSpecialChars');
  print('PDFs with possible front matter: $booksWithFrontMatter');
  print('PDFs with possible back matter: $booksWithBackMatter');
  print('PDFs with repeated prefix headers: $booksWithRepeatedPrefix');
  
  // Print detailed issues
  print('\n--- DETAILED ISSUES ---\n');
  
  for (final entry in allResults.entries) {
    if (entry.value is! Map || entry.value['error'] != null) continue;
    
    final issues = entry.value['issues'] as Map? ?? {};
    if (issues.isNotEmpty) {
      print('${entry.key}:');
      for (final issue in issues.entries) {
        print('  - ${issue.key}: ${issue.value}');
      }
      print('');
    }
  }
}
