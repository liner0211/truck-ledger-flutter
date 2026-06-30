import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client? _client;

void initApiHttpClient() {
  if (_client != null) return;

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux)) {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..idleTimeout = const Duration(seconds: 15);
    _client = IOClient(httpClient);
    return;
  }

  _client = http.Client();
}

http.Client get apiHttpClient {
  initApiHttpClient();
  return _client!;
}
