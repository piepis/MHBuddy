import 'dart:convert';

import 'package:http/http.dart' as http;

import 'client_stub.dart' if (dart.library.html) 'client_web.dart';

class Api {
  Api({http.Client? client}) : client = client ?? createClient();
  final http.Client client;

  Future<http.Response> send(String method, String path, {Object? jsonBody}) {
    return client.sendRequest(method, Uri.parse(path), jsonBody: jsonBody);
  }
}

extension on http.Client {
  Future<http.Response> sendRequest(String method, Uri uri, {Object? jsonBody}) {
    final body = jsonBody == null ? null : jsonEncode(jsonBody);
    final headers = {if (body != null) 'content-type': 'application/json; charset=utf-8'};
    switch (method) {
      case 'POST':
        return post(uri, headers: headers, body: body);
      case 'DELETE':
        return delete(uri, headers: headers, body: body);
      default:
        return get(uri, headers: headers);
    }
  }
}
