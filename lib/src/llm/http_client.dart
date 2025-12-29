/// HTTP client wrapper for LLM API calls.
/// Provides a unified interface for web and native platforms.

import 'dart:convert';
import 'package:http/http.dart' as http;

/// HTTP client for making API calls.
class ApiClient {
  final http.Client _client;

  ApiClient() : _client = http.Client();

  /// Make a POST request to an API endpoint.
  Future<ApiResponse> post({
    required Uri uri,
    required Map<String, String> headers,
    required Map<String, dynamic> body,
  }) async {
    try {
      final response = await _client.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(body),
      );

      return ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        isSuccess: response.statusCode >= 200 && response.statusCode < 300,
      );
    } catch (e) {
      return ApiResponse(
        statusCode: 0,
        body: e.toString(),
        isSuccess: false,
        error: e.toString(),
      );
    }
  }

  /// Close the client and release resources.
  void dispose() {
    _client.close();
  }
}

/// Response from an API call.
class ApiResponse {
  final int statusCode;
  final String body;
  final bool isSuccess;
  final String? error;

  ApiResponse({
    required this.statusCode,
    required this.body,
    required this.isSuccess,
    this.error,
  });

  /// Parse the body as JSON.
  Map<String, dynamic>? get json {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
