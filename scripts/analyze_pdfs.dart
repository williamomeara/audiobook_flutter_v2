#!/usr/bin/env dart
// ignore_for_file: avoid_print
/// PDF Analysis Script
///
/// Run directly with:
///   dart run scripts/analyze_pdfs.dart
///
/// This script uses pdfrx to analyze PDF files and output results.

import 'dart:convert';
import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

const pdfDir = 'local_dev/dev_books/pdf';
const outputPath = 'test/pdf_analysis_output/pdf_analysis_results.json';

void main() async {
  print('PDF Analysis Script');
  print('==================');
  print('');
  
  final dir = Directory(pdfDir);
  if (!dir.existsSync()) {
    print('PDF directory not found: $pdfDir');
    exit(1);
  }
  
  final pdfFiles = <File>[];
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File && entity.path.toLowerCase().endsWith('.pdf')) {
      pdfFiles.add(entity);
    }
  }
  
  print('Found ${pdfFiles.length} PDF files');
  print('');
  
  final results = <Map<String, dynamic>>[];
  
  for (final file in pdfFiles) {
    final filename = file.path.split('/').last;
    print('Analyzing: $filename');
    
    try {
      final analysis = await analyzePdf(file.path);
      results.add(analysis);
      
      print('  Pages: ${analysis['pageCount']}');
      print('  Outline: ${analysis['outlineCount']} entries');
      print('  Est. chars: ${analysis['estimatedCharacters']}');
      print('');
    } catch (e) {
      print('  ERROR: $e');
      print('');
      results.add({
        'file': filename,
        'error': e.toString(),
      });
    }
  }
  
  // Write results
  final outputFile = File(outputPath);
  await outputFile.parent.create(recursive: true);
  
  final encoder = JsonEncoder.withIndent('  ');
  await outputFile.writeAsString(encoder.convert({
    'analyzedAt': DateTime.now().toIso8601String(),
    'totalFiles': pdfFiles.length,
    'successCount': results.where((r) => !r.containsKey('error')).length,
    'results': results,
  }));
  
  print('Results written to: $outputPath');
}

Future<Map<String, dynamic>> analyzePdf(String path) async {
  final document = await PdfDocument.openFile(path);
  
  try {
    final filename = path.split('/').last;
    final pageCount = document.pages.length;
    
    // Outline
    final outline = await document.loadOutline();
    final flatOutline = flattenOutline(outline);
    
    // Sample pages
    final sampleIndices = [0, 1, pageCount ~/ 2, pageCount - 1]
        .where((i) => i >= 0 && i < pageCount)
        .toSet()
        .toList()
      ..sort();
    
    var totalSampleChars = 0;
    final samples = <Map<String, dynamic>>[];
    
    for (final idx in sampleIndices) {
      final page = document.pages[idx];
      final text = await page.loadText();
      final fullText = text.fullText;
      totalSampleChars += fullText.length;
      
      samples.add({
        'pageNumber': idx + 1,
        'chars': fullText.length,
        'lines': fullText.split('\n').length,
        'preview': fullText.substring(0, fullText.length.clamp(0, 300)),
      });
    }
    
    final avgCharsPerPage = totalSampleChars / sampleIndices.length;
    final estimatedChars = (avgCharsPerPage * pageCount).round();
    
    return {
      'file': filename,
      'pageCount': pageCount,
      'outlineCount': flatOutline.length,
      'hasOutline': flatOutline.isNotEmpty,
      'estimatedCharacters': estimatedChars,
      'estimatedChapters': flatOutline.isNotEmpty 
          ? flatOutline.length 
          : (pageCount / 20).ceil(),
      'outlineEntries': flatOutline.take(15).toList(),
      'samplePages': samples,
    };
  } finally {
    document.dispose();
  }
}

List<Map<String, dynamic>> flattenOutline(List<PdfOutlineNode> nodes, {int depth = 0}) {
  final result = <Map<String, dynamic>>[];
  
  for (final node in nodes) {
    final pageNum = node.dest?.pageNumber;
    if (pageNum != null) {
      result.add({
        'title': node.title,
        'page': pageNum + 1,
        'depth': depth,
      });
    }
    if (node.children.isNotEmpty) {
      result.addAll(flattenOutline(node.children, depth: depth + 1));
    }
  }
  
  return result;
}
