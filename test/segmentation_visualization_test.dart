import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:core_domain/core_domain.dart';

void main() {
  group('TextSegmenter Visualization Tests', () {
    test('segments realistic book text and outputs to JSON for manual inspection', () {
      // Realistic example text mixing short and long sentences
      const exampleText = '''
The morning was cold and gray. Detective Sarah Chen stood at the edge of the cliff, looking down at the churning waters below. Her partner, Marcus Rodriguez, arrived moments later with two cups of steaming coffee.

"Any signs of the suspect?" he asked, his breath forming clouds in the frigid air.

"Nothing yet," Sarah replied. She turned to face him, accepting the coffee gratefully. "But I found something interesting. There are fresh tire tracks leading to this exact spot, and they match the description of the vehicle we've been tracking for the past three weeks."

Marcus knelt down to examine the tracks more closely, his experienced eyes noting every detail. "These tracks are deep, suggesting a heavy load. The suspect might have been transporting something substantial, possibly the stolen artifacts from the museum heist last month."

"Exactly what I was thinking," Sarah said. She pulled out her phone and began taking photographs of the evidence. "I'll send these to forensics immediately."

The wind picked up, howling through the trees. In the distance, a raven called out, its harsh cry echoing across the landscape. Sarah shivered, though not entirely from the cold. Something about this case felt wrong, like pieces of a puzzle that didn't quite fit together despite appearing to match at first glance.

"We need to get back to the station," Marcus suggested. He stood up, brushing dirt from his knees. "The captain wanted a full briefing by noon, and we're running out of time. Besides, I think a storm is coming."

Sarah nodded in agreement. They walked back to their car, their footsteps crunching on the frozen ground. As they drove away, she couldn't shake the feeling that they were missing something crucial. The answer was there, somewhere in the details, waiting to be discovered. She just needed to look at the evidence from a different angle.
''';

      // Segment the text
      final segments = segmentText(exampleText);

      // Create detailed output for inspection
      final output = {
        'metadata': {
          'total_segments': segments.length,
          'total_characters': exampleText.length,
          'total_words': exampleText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
          'average_segment_length': segments.isEmpty ? 0 : (segments.map((s) => s.text.length).reduce((a, b) => a + b) / segments.length).round(),
        },
        'segments': segments.map((segment) {
          final words = segment.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          return {
            'index': segment.index,
            'text': segment.text,
            'character_count': segment.text.length,
            'word_count': words,
            'estimated_duration_seconds': segment.estimatedDuration.inSeconds,
            'ends_with_sentence': segment.text.endsWith('.') || segment.text.endsWith('!') || segment.text.endsWith('?'),
          };
        }).toList(),
      };

      // Write to JSON file for manual inspection
      final file = File('test/segmentation_output.json');
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(output),
      );

      // Print summary
      final metadata = output['metadata'] as Map<String, dynamic>;
      print('\n=== SEGMENTATION SUMMARY ===');
      print('Total segments: ${metadata['total_segments']}');
      print('Average segment length: ${metadata['average_segment_length']} characters');
      print('Output written to: test/segmentation_output.json');
      print('\nFirst 3 segments:');
      
      for (var i = 0; i < 3 && i < segments.length; i++) {
        final s = segments[i];
        final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        print('  [$i] ($words words, ${s.text.length} chars): ${s.text}');
      }

      // Basic assertions to ensure segmentation is working
      expect(segments, isNotEmpty, reason: 'Should produce segments');
      expect(segments.length, greaterThan(1), reason: 'Should split into multiple segments');
      
      // Verify all segments end with sentence-ending punctuation
      for (final segment in segments) {
        final endsProper = segment.text.endsWith('.') || 
                          segment.text.endsWith('!') || 
                          segment.text.endsWith('?') ||
                          segment.text.endsWith(',') || // For very long sentences split at comma
                          segment.text.endsWith('"');  // Quotes after punctuation
        expect(endsProper, true, 
            reason: 'Segment should end with proper punctuation: "${segment.text}"');
      }
    });

    test('segments various sentence structures', () {
      final testCases = [
        {
          'name': 'Short sentences',
          'text': 'First. Second. Third. Fourth. Fifth.',
        },
        {
          'name': 'Long sentence under 300 chars',
          'text': 'This is a moderately long sentence that contains quite a few words but is still well under the three hundred character limit that would trigger a forced split at commas or other punctuation marks.',
        },
        {
          'name': 'Mix of short and long',
          'text': 'Short. This is much longer sentence. Another short one. And one more sentence that is somewhat longer than the first but shorter than the second.',
        },
        {
          'name': 'Dialogue',
          'text': '"Hello," she said. "How are you doing today?" He smiled. "I\'m doing well, thank you for asking." She nodded and walked away.',
        },
        {
          'name': 'Very long sentence (should split)',
          'text': 'This is an exceptionally long sentence that continues on and on with multiple clauses separated by commas, and it includes several different ideas that could arguably be separate sentences, but for some reason the author chose to combine them all into a single run-on sentence that exceeds the three hundred character threshold, which should trigger our emergency splitting mechanism that breaks the sentence at the most appropriate comma or other punctuation mark to maintain some semblance of readability.',
        },
      ];

      final results = [];

      for (final testCase in testCases) {
        final name = testCase['name'] as String;
        final text = testCase['text'] as String;
        final segments = segmentText(text);

        final caseResult = {
          'test_case': name,
          'input_length': text.length,
          'input_word_count': text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length,
          'segment_count': segments.length,
          'segments': segments.map((s) {
            final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
            return {
              'text': s.text,
              'length': s.text.length,
              'words': words,
            };
          }).toList(),
        };

        results.add(caseResult);

        print('\n=== ${name.toUpperCase()} ===');
        print('Input: $text');
        print('Segments: ${segments.length}');
        for (var i = 0; i < segments.length; i++) {
          final words = segments[i].text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          print('  [$i] $words words: ${segments[i].text}');
        }
      }

      // Write test cases to JSON
      final file = File('test/segmentation_test_cases.json');
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(results),
      );

      print('\n=== Test cases written to: test/segmentation_test_cases.json ===\n');
    });
  });
}
