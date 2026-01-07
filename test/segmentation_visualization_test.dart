import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:core_domain/core_domain.dart';

void main() {
  group('TextSegmenter Visualization Tests', () {
    test('segments 1000-word passage and outputs to JSON', () {
      // A realistic 1000-word passage from a fictional novel
      const longText = '''
The city awakened slowly that morning, wrapped in a thick blanket of fog that rolled in from the harbor. Streets that were usually bustling with activity by dawn remained eerily quiet, their emptiness punctuated only by the occasional rumble of a delivery truck or the distant wail of a siren. Sarah Martinez stood at her apartment window, coffee cup warming her hands, watching the world below emerge gradually from the gray mist.

She had been a detective for nearly fifteen years, long enough to develop an instinct for trouble, and something about today felt wrong. Perhaps it was the unusual silence, or maybe the nagging feeling that had kept her awake most of the night. The Stevens case had been gnawing at her for weeks now, a puzzle with pieces that refused to fit together no matter how many times she rearranged them.

The victim, Marcus Stevens, had been a respected businessman with no apparent enemies. His death had been ruled an accident initially—a tragic fall from his office building's roof. But Sarah had never believed in coincidences, and the timing was too convenient. Stevens had been about to testify in a major corruption case, one that could have brought down some powerful people in the city's political establishment.

Her phone buzzed, breaking her reverie. It was her partner, Detective James Chen. "We need to meet," his text read. "New evidence in the Stevens case. Coffee shop on Fifth, thirty minutes." Sarah felt her pulse quicken. James wasn't one for dramatics; if he said the evidence was significant, it meant they were finally getting somewhere.

She dressed quickly, choosing practical clothes that would serve her well through a long day. Black pants, a simple blouse, her worn leather jacket that had seen her through countless investigations. She checked her service weapon out of habit, secured her badge, and grabbed her keys. The morning air was cold when she stepped outside, the fog still clinging to the streets like a living thing.

The coffee shop was a small establishment that catered to early risers and night shift workers transitioning to day. James was already there, sitting in a corner booth with two cups of coffee and a manila folder that looked suspiciously thick. His usually calm demeanor seemed slightly ruffled, and Sarah could see the excitement in his eyes even from across the room.

"You're going to want to sit down for this," James said as she slid into the booth across from him. He pushed one of the coffee cups toward her, then opened the folder with deliberate care. "Remember how we couldn't find any security footage from Stevens' building that night? Someone had conveniently erased it all?"

Sarah nodded, taking a sip of her coffee. It was strong and bitter, exactly what she needed. "Yeah, that's what made me suspicious from the start. Too clean, too convenient."

"Well, we got lucky," James continued, pulling out several photographs. "A tourist was taking pictures of the city skyline that evening from a nearby rooftop restaurant. She didn't realize what she had captured until she got home and went through her photos. Look at this." He spread three photographs across the table.

Sarah leaned forward, studying the images carefully. They showed Stevens' building from across the street, the time stamp indicating they were taken about twenty minutes before the estimated time of death. In the second photo, barely visible in the dying light, two figures could be seen on the roof. The third photo was slightly blurred, as if the camera had moved, but it clearly showed what appeared to be a confrontation.

"Can we enhance these?" Sarah asked, her detective instincts kicking into high gear. "Get facial recognition on the second person?"

"Already sent them to the lab," James replied with a slight smile. "But that's not all. The tourist also had video on her phone. She was recording the sunset, panning across the skyline. You can see the struggle on the roof, clear as day. Stevens didn't jump, Sarah. He was pushed."

The implications hit Sarah like a physical blow. This changed everything. They weren't investigating an accident anymore; this was murder. And if Stevens had been killed to prevent his testimony, it meant the corruption went even deeper than they had suspected. It also meant that whoever was responsible had the power and resources to cover it up—at least until now.

"We need to move carefully," Sarah said, her voice low. "If this gets out before we're ready, evidence could disappear, witnesses could vanish. We need to build an airtight case before we make any moves."

James agreed. "I've already started running background checks on everyone who had access to Stevens' building that day. Building security, cleaning staff, deliveries—everyone. And I'm cross-referencing them with known associates of the people Stevens was planning to testify against."

They spent the next hour going through the evidence, piece by piece, building a timeline and identifying potential suspects. The fog outside had begun to lift, revealing a city that seemed to wake up properly at last. Pedestrians filled the sidewalks, cars honked in traffic, life returned to normal. But for Sarah and James, nothing would be normal until they solved this case.

As they left the coffee shop, Sarah felt a renewed sense of purpose. The pieces were finally starting to come together. Justice for Marcus Stevens was within reach, and she would make sure that whoever was responsible would face the consequences of their actions, no matter how powerful they were. The investigation was far from over, but for the first time in weeks, she felt like they had a real chance of bringing the truth to light.
''';

      // Count words to verify it's around 1000
      final wordCount = longText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      print('\n=== 1000-WORD TEST ===');
      print('Actual word count: $wordCount words');
      print('Character count: ${longText.length} characters');

      // Segment the text
      final segments = segmentText(longText);

      // Create detailed output
      final output = {
        'metadata': {
          'input_word_count': wordCount,
          'input_character_count': longText.length,
          'total_segments': segments.length,
          'average_segment_length_chars': segments.isEmpty ? 0 : (segments.map((s) => s.text.length).reduce((a, b) => a + b) / segments.length).round(),
          'average_segment_length_words': segments.isEmpty ? 0 : (segments.map((s) {
            return s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          }).reduce((a, b) => a + b) / segments.length).round(),
          'shortest_segment_chars': segments.isEmpty ? 0 : segments.map((s) => s.text.length).reduce((a, b) => a < b ? a : b),
          'longest_segment_chars': segments.isEmpty ? 0 : segments.map((s) => s.text.length).reduce((a, b) => a > b ? a : b),
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

      // Write to JSON file
      final file = File('test/segmentation_1000_words.json');
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(output),
      );

      final metadata = output['metadata'] as Map<String, dynamic>;
      print('Total segments: ${metadata['total_segments']}');
      print('Average segment: ${metadata['average_segment_length_words']} words, ${metadata['average_segment_length_chars']} chars');
      print('Range: ${metadata['shortest_segment_chars']}-${metadata['longest_segment_chars']} chars');
      print('\nOutput written to: test/segmentation_1000_words.json');

      // Print first 5 and last 5 segments
      print('\nFirst 5 segments:');
      for (var i = 0; i < 5 && i < segments.length; i++) {
        final s = segments[i];
        final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
        final preview = s.text.length > 100 ? '${s.text.substring(0, 97)}...' : s.text;
        print('  [$i] $words words: $preview');
      }

      if (segments.length > 5) {
        print('\nLast 5 segments:');
        for (var i = segments.length - 5; i < segments.length; i++) {
          final s = segments[i];
          final words = s.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
          final preview = s.text.length > 100 ? '${s.text.substring(0, 97)}...' : s.text;
          print('  [$i] $words words: $preview');
        }
      }

      // Assertions
      expect(segments, isNotEmpty);
      expect(wordCount, greaterThanOrEqualTo(900), reason: 'Should be close to 1000 words');
      expect(wordCount, lessThanOrEqualTo(1100), reason: 'Should be close to 1000 words');
    });

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
