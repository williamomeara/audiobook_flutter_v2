import 'package:core_domain/core_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SegmentTypeDetector', () {
    const detector = SegmentTypeDetector();
    
    group('code detection', () {
      test('detects Python code', () {
        const pythonCode = '''
def calculate_total(items):
    return sum(i.price for i in items)
''';
        final result = detector.detect(pythonCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.metadata?['language'], equals('python'));
      });
      
      test('detects JavaScript code', () {
        const jsCode = '''
const fetchData = async () => {
    const response = await fetch('/api/data');
    return response.json();
};
''';
        final result = detector.detect(jsCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.metadata?['language'], equals('javascript'));
      });
      
      test('detects Dart code', () {
        const dartCode = '''
@override
Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container();
}
''';
        final result = detector.detect(dartCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.metadata?['language'], equals('dart'));
      });
      
      test('detects Django template code', () {
        const djangoCode = '''
{% for item in items %}
<p>{{ item.name }}: {{ item.price }}</p>
{% endfor %}
''';
        final result = detector.detect(djangoCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.metadata?['language'], equals('django'));
      });
      
      test('detects shell commands', () {
        const shellCode = '''
flutter pub get
dart run build_runner build
npm install
''';
        final result = detector.detect(shellCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.metadata?['language'], equals('bash'));
      });
      
      test('detects explicit [CODE] markers', () {
        const markedCode = '[CODE]print("Hello, World!")[/CODE]';
        final result = detector.detect(markedCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.confidence, equals(1.0));
        expect(result.metadata?['marked'], equals(true));
      });
      
      test('detects SQL queries', () {
        const sqlCode = 'SELECT * FROM books WHERE author = "Orwell" ORDER BY title;';
        final result = detector.detect(sqlCode);
        expect(result.type, equals(SegmentType.code));
        expect(result.metadata?['language'], equals('sql'));
      });
    });
    
    group('figure detection', () {
      test('detects [Figure:] markers', () {
        const figureText = '[Figure: Architecture diagram showing component relationships]';
        final result = detector.detect(figureText);
        expect(result.type, equals(SegmentType.figure));
        expect(result.confidence, equals(1.0));
        expect(result.metadata?['caption'], equals('Architecture diagram showing component relationships'));
      });
      
      test('detects empty figure markers', () {
        const figureText = '[Figure: ]';
        final result = detector.detect(figureText);
        expect(result.type, equals(SegmentType.figure));
      });
    });
    
    group('regular text detection', () {
      test('detects normal prose', () {
        const prose = '''
Call me Ishmael. Some years ago—never mind how long precisely—having 
little or no money in my purse, and nothing particular to interest me 
on shore, I thought I would sail about a little and see the watery part 
of the world.
''';
        final result = detector.detect(prose);
        expect(result.type, equals(SegmentType.text));
        expect(result.confidence, equals(1.0));
      });
      
      test('does not misidentify dialog as code', () {
        const dialog = '"Hello," she said. "How are you today?"';
        final result = detector.detect(dialog);
        expect(result.type, equals(SegmentType.text));
      });
      
      test('does not misidentify short sentences as code', () {
        const shortText = 'Be content.';
        final result = detector.detect(shortText);
        expect(result.type, equals(SegmentType.text));
      });
    });
    
    group('table detection', () {
      test('detects markdown table', () {
        const markdownTable = '''
| Name | Price | Quantity |
|------|-------|----------|
| Apples | \$1.50 | 10 |
| Oranges | \$2.00 | 5 |
''';
        final result = detector.detect(markdownTable);
        expect(result.type, equals(SegmentType.table));
      });
    });
    
    group('edge cases', () {
      test('handles empty string', () {
        final result = detector.detect('');
        expect(result.type, equals(SegmentType.text));
      });
      
      test('handles whitespace-only string', () {
        final result = detector.detect('   \n\t  ');
        expect(result.type, equals(SegmentType.text));
      });
      
      test('code-like content in prose may trigger code detection', () {
        // This is intentional - we prefer false positives over missing code blocks
        // in technical books. The sentence has a function call pattern.
        const mixedText = 'The function calculate_total() takes a list of items and returns the sum.';
        final result = detector.detect(mixedText);
        // May be code or text - both are acceptable for this edge case
        expect(result.type == SegmentType.text || result.type == SegmentType.code, isTrue);
      });
    });
  });
}
