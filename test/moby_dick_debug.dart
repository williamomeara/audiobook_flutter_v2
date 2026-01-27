// Debug what's happening to Moby Dick chapters
// Run with: dart test/moby_dick_debug.dart
// ignore_for_file: avoid_print

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
    print('Moby Dick EPUB not found');
    return;
  }

  final bytes = await mobyFile.readAsBytes();
  EpubBook epubBook;

  try {
    epubBook = await EpubReader.readBook(bytes);
  } catch (e) {
    print('Failed to parse: $e');
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

  print('Debugging first 5 chapters...\n');

  // Process first 5 chapters
  for (int i = 0; i < 5 && i < flattened.length; i++) {
    final ch = flattened[i];
    final html = (ch.HtmlContent ?? '').trim();

    if (html.isEmpty) {
      print('Chapter $i: Empty HTML');
      continue;
    }

    final rawText = stripHtmlToText(html);
    final normalized = TextNormalizer.normalize(rawText);

    print('=' * 80);
    print('CHAPTER ${i + 1}: ${ch.Title}');
    print('=' * 80);
    print('Raw text length: ${rawText.length}');
    print('Normalized length: ${normalized.length}');
    print('');

    // Check for preliminary section
    final preliminary = StructureAnalyzer.extractPreliminarySection(normalized);

    if (preliminary != null) {
      print('⚠ PRELIMINARY SECTION DETECTED:');
      print('  Length: ${preliminary.length}');
      print('  First 300 chars:');
      print('  "${preliminary.substring(0, preliminary.length > 300 ? 300 : preliminary.length)}"');
      print('');

      final afterRemoval = normalized.replaceFirst(preliminary, '');
      print('After removal:');
      print('  Length: ${afterRemoval.length}');
      print('  Content: "${afterRemoval.substring(0, afterRemoval.length > 300 ? 300 : afterRemoval.length)}"');
      print('');
    } else {
      print('✓ No preliminary section detected');
    }

    // Then cleanChapter
    final cleaned = BoilerplateRemover.cleanChapter(normalized);
    print('After BoilerplateRemover.cleanChapter:');
    print('  Length: ${cleaned.length}');
    print('  Content: "${cleaned.substring(0, cleaned.length > 300 ? 300 : cleaned.length)}"');
    print('');
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
