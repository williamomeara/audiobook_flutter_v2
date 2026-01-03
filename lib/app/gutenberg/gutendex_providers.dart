import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infra/gutendex/gutendex_client.dart';

final gutendexClientProvider = Provider<GutendexClient>((ref) {
  return GutendexClient();
});
