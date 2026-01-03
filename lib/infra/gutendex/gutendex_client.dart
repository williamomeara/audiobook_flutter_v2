import 'dart:convert';

import 'package:http/http.dart' as http;

import 'gutendex_models.dart';

class GutendexClient {
  GutendexClient({
    http.Client? httpClient,
    this.baseUrl = 'https://gutendex.com',
  }) : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String baseUrl;

  static const epubMimeType = 'application/epub+zip';

  Future<GutendexPage> fetchTopEpubBooksPage({int page = 1}) async {
    final uri = Uri.parse('$baseUrl/books').replace(
      queryParameters: {
        'sort': 'popular',
        'mime_type': epubMimeType,
        'copyright': 'false',
        if (page > 1) 'page': '$page',
      },
    );
    return _getPage(uri);
  }

  Future<GutendexPage> searchEpubBooks({
    required String query,
    int page = 1,
  }) async {
    final q = query.trim();
    if (q.isEmpty) {
      return const GutendexPage(
        count: 0,
        next: null,
        previous: null,
        results: <GutendexBook>[],
      );
    }

    final uri = Uri.parse('$baseUrl/books').replace(
      queryParameters: {
        'search': q,
        'mime_type': epubMimeType,
        'copyright': 'false',
        if (page > 1) 'page': '$page',
      },
    );
    return _getPage(uri);
  }

  Future<GutendexPage> fetchByUrl(String url) async {
    return _getPage(Uri.parse(url));
  }

  Future<GutendexPage> _getPage(Uri uri) async {
    final resp = await _http.get(
      uri,
      headers: const {'accept': 'application/json'},
    );

    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw Exception('Gutendex HTTP ${resp.statusCode}');
    }

    final json = jsonDecode(resp.body);
    if (json is! Map<String, dynamic>) {
      throw Exception('Gutendex returned unexpected JSON');
    }

    return GutendexPage.fromJson(json);
  }
}
