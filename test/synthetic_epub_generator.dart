// Generates synthetic Project Gutenberg-style EPUBs for testing
// Run with: dart run test/synthetic_epub_generator.dart

import 'dart:io';
import 'package:archive/archive.dart';

void main() async {
  final outputDir = Directory('test/fixtures/synthetic_epubs');
  await outputDir.create(recursive: true);

  print('Generating synthetic test EPUBs...\n');

  // Generate different test books
  await generateTestBook(
    outputDir: outputDir,
    filename: 'heavy_boilerplate.epub',
    title: 'Heavy Boilerplate Test Book',
    author: 'Test Author',
    chapterCount: 5,
    boilerplateIntensity: 'heavy',
  );

  await generateTestBook(
    outputDir: outputDir,
    filename: 'light_boilerplate.epub',
    title: 'Light Boilerplate Test Book',
    author: 'Test Author',
    chapterCount: 5,
    boilerplateIntensity: 'light',
  );

  await generateTestBook(
    outputDir: outputDir,
    filename: 'edge_cases.epub',
    title: 'Edge Cases Test Book',
    author: 'Test Author',
    chapterCount: 3,
    boilerplateIntensity: 'edge',
  );

  print('\nSynthetic EPUBs generated in: ${outputDir.path}');
}

Future<void> generateTestBook({
  required Directory outputDir,
  required String filename,
  required String title,
  required String author,
  required int chapterCount,
  required String boilerplateIntensity,
}) async {
  print('Creating: $filename ($boilerplateIntensity boilerplate)');

  final archive = Archive();

  // Add mimetype (uncompressed, first file)
  archive.addFile(ArchiveFile(
    'mimetype',
    9,
    'application/epub+zip'.codeUnits,
  ));

  // Add META-INF/container.xml
  archive.addFile(ArchiveFile(
    'META-INF/container.xml',
    _containerXml.length,
    _containerXml.codeUnits,
  ));

  // Add OEBPS/package.opf
  final packageOpf = _generatePackageOpf(title, author, chapterCount);
  archive.addFile(ArchiveFile(
    'OEBPS/package.opf',
    packageOpf.length,
    packageOpf.codeUnits,
  ));

  // Add OEBPS/toc.ncx
  final tocNcx = _generateTocNcx(title, chapterCount);
  archive.addFile(ArchiveFile(
    'OEBPS/toc.ncx',
    tocNcx.length,
    tocNcx.codeUnits,
  ));

  // Add OEBPS/nav.xhtml
  final navXhtml = _generateNavXhtml(chapterCount);
  archive.addFile(ArchiveFile(
    'OEBPS/nav.xhtml',
    navXhtml.length,
    navXhtml.codeUnits,
  ));

  // Add title page
  final titlePage = _generateTitlePageXhtml(title, author);
  archive.addFile(ArchiveFile(
    'OEBPS/ch001_title.xhtml',
    titlePage.length,
    titlePage.codeUnits,
  ));

  // Add chapters with boilerplate
  for (int i = 1; i <= chapterCount; i++) {
    final chapterXhtml = _generateChapterXhtml(
      chapterNumber: i,
      boilerplateIntensity: boilerplateIntensity,
    );
    archive.addFile(ArchiveFile(
      'OEBPS/ch${(i + 1).toString().padLeft(3, '0')}_chapter.xhtml',
      chapterXhtml.length,
      chapterXhtml.codeUnits,
    ));
  }

  // Create EPUB file
  final outputFile = File('${outputDir.path}/$filename');
  final encoded = ZipEncoder().encode(archive);
  await outputFile.writeAsBytes(encoded!);

  print('  ✓ Written to: ${outputFile.path}');
}

String _generateChapterXhtml({
  required int chapterNumber,
  required String boilerplateIntensity,
}) {
  final boilerplate = _generateBoilerplate(boilerplateIntensity, chapterNumber);

  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Chapter $chapterNumber</title>
</head>
<body>
$boilerplate
<h1>Chapter $chapterNumber</h1>
<p>This is the beginning of chapter $chapterNumber. The story continues with meaningful content that should be preserved during boilerplate removal.</p>
<p>Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</p>
<p>Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>
<p>The chapter concludes here with important plot information and character development. This content is essential to the narrative.</p>
$boilerplate
</body>
</html>''';
}

String _generateBoilerplate(String intensity, int chapterNumber) {
  if (intensity == 'heavy') {
    return '''
<div class="pg-boilerplate">
<p>*** CHAPTER $chapterNumber ***</p>
<p>e-text prepared by Project Gutenberg volunteers</p>
<p>HTML version created 2024</p>
<p>UTF-8 encoded</p>
<p>Transcribed by volunteers</p>
<p>Distributed under Creative Commons License</p>
<p>This work is in the public domain</p>
<p>Original pagination preserved</p>
<p>[Footnote: Additional editorial notes from transcriber]</p>
<p>Processed by LibGen conversion tool</p>
</div>
''';
  } else if (intensity == 'light') {
    return '''
<div class="pg-boilerplate">
<p>Produced by Project Gutenberg volunteers</p>
<p>HTML version</p>
</div>
''';
  } else if (intensity == 'edge') {
    // Edge case: repeated headers/footers at specific positions
    if (chapterNumber == 1) {
      return '<p>CHAPTER HEADER\n\n';
    } else {
      return '''
<p>SHARED HEADER APPEARS HERE</p>
<p>[Note by editor: This chapter has been reformatted]</p>
<p>Character encoding: UTF-8</p>
''';
    }
  }

  return '';
}

String _generateTitlePageXhtml(String title, String author) {
  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>Title Page</title>
</head>
<body>
<h1>$title</h1>
<p>by $author</p>
<p>Project Gutenberg</p>
</body>
</html>''';
}

String _generateNavXhtml(int chapterCount) {
  final chapters = StringBuffer();
  chapters.write('  <li><a href="ch001_title.xhtml">Title Page</a></li>\n');
  for (int i = 1; i <= chapterCount; i++) {
    final chNum = (i + 1).toString().padLeft(3, '0');
    chapters.write('  <li><a href="ch${chNum}_chapter.xhtml">Chapter $i</a></li>\n');
  }

  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head>
<title>Table of Contents</title>
</head>
<body epub:type="frontmatter toc">
<h1>Table of Contents</h1>
<ol>
$chapters</ol>
</body>
</html>''';
}

String _generatePackageOpf(String title, String author, int chapterCount) {
  final manifest = StringBuffer();
  manifest.write('    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n');
  manifest.write('    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>\n');
  manifest.write('    <item id="ch001" href="ch001_title.xhtml" media-type="application/xhtml+xml"/>\n');
  for (int i = 1; i <= chapterCount; i++) {
    final chNum = (i + 1).toString().padLeft(3, '0');
    manifest.write('    <item id="ch$chNum" href="ch${chNum}_chapter.xhtml" media-type="application/xhtml+xml"/>\n');
  }

  final spine = StringBuffer();
  spine.write('    <itemref idref="ch001"/>\n');
  for (int i = 1; i <= chapterCount; i++) {
    final chNum = (i + 1).toString().padLeft(3, '0');
    spine.write('    <itemref idref="ch$chNum"/>\n');
  }

  return '''<?xml version="1.0" encoding="UTF-8"?>
<package version="3.0" unique-identifier="uuid" xmlns="http://www.idpf.org/2007/opf">
<metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>$title</dc:title>
<dc:creator>$author</dc:creator>
<dc:identifier id="uuid">test-epub-${DateTime.now().millisecondsSinceEpoch}</dc:identifier>
<dc:language>en</dc:language>
</metadata>
<manifest>
$manifest</manifest>
<spine>
$spine</spine>
</package>''';
}

String _generateTocNcx(String title, int chapterCount) {
  final navPoints = StringBuffer();
  navPoints.write('''    <navPoint id="navPoint1" playOrder="1">
      <navLabel><text>Title Page</text></navLabel>
      <content src="ch001_title.xhtml"/>
    </navPoint>
''');

  for (int i = 1; i <= chapterCount; i++) {
    final chNum = (i + 1).toString().padLeft(3, '0');
    navPoints.write('''    <navPoint id="navPoint${i + 1}" playOrder="${i + 1}">
      <navLabel><text>Chapter $i</text></navLabel>
      <content src="ch${chNum}_chapter.xhtml"/>
    </navPoint>
''');
  }

  return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN"
"http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
<ncx version="2005-1" xmlns="http://www.daisy.org/z3986/2005/ncx/">
<head>
<meta name="dtb:uid" content="test-epub"/>
<meta name="dtb:depth" content="1"/>
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>$title</text></docTitle>
<navMap>
$navPoints</navMap>
</ncx>''';
}

const String _containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles>
<rootfile full-path="OEBPS/package.opf" media-type="application/oebps-package+xml"/>
</rootfiles>
</container>''';
