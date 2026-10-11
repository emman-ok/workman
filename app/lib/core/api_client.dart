// Owned by AppWand.
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_controller.dart';
import 'auth/token_store.dart';
import 'config.dart';
import 'i18n.dart';
import 'plugins.g.dart' show appPlugins;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode, this.fieldErrors = const {}, this.offline = false});
  final String message;
  final int? statusCode;

  /// A 400 from the API's validation: one message per field, keyed by the
  /// JSON field name. Empty for every other error.
  final Map<String, String> fieldErrors;

  /// The server could not be reached (no connection, or it is down).
  final bool offline;

  @override
  String toString() => message;
}

/// One request through ApiClient, as an ApiLayer sees it.
class ApiCall {
  const ApiCall(this.method, this.path, {this.query, this.data});

  /// GET, POST, PUT, PATCH or DELETE.
  final String method;

  /// Relative to /api, e.g. '/orders/5'.
  final String path;
  final Map<String, dynamic>? query;
  final Object? data;

  bool get isWrite => method != 'GET';

  /// The method, path and sorted query: what an answer is kept under.
  String get key {
    final q = query ?? const {};
    final pairs = [for (final k in q.keys.toList()..sort()) '$k=${q[k]}'];
    return '$method $path${pairs.isEmpty ? '' : '?${pairs.join('&')}'}';
  }

  Map<String, dynamic> toJson() => {'method': method, 'path': path, 'query': query, 'data': data};

  factory ApiCall.fromJson(Map<String, dynamic> json) => ApiCall(
        '${json['method']}',
        '${json['path']}',
        query: json['query'] is Map ? Map<String, dynamic>.from(json['query'] as Map) : null,
        data: json['data'],
      );
}

/// Sits between ApiClient and the network, added by a plugin (AppPlugin.apiLayer):
/// it answers a call itself (a copy saved on the device) or passes it on with [send].
abstract class ApiLayer {
  const ApiLayer();

  Future<dynamic> handle(ApiCall call, ApiClient client, Future<dynamic> Function() send);
}

/// A file fetched with ApiClient.download: its bytes and the response's
/// headers (names in lower case).
class ApiDownload {
  const ApiDownload(this.bytes, this.headers);
  final Uint8List bytes;
  final Map<String, String> headers;
}

/// Readable text for any error, e.g. the `Object` in `.when(error: (e, _) => ...)`.
String errorMessage(Object error) =>
    error is ApiException ? error.message : error.toString();

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    onUnauthorized: () => ref.read(authProvider.notifier).expire(),
    onChanged: () => ref.read(dataVersionProvider.notifier).bump(),
  );
});

/// Goes up after every successful write (POST, PUT, PATCH, DELETE) through the
/// API. A provider that shows numbers or rows other pages change (a dashboard's
/// totals) watches it, so it reloads when a record is saved anywhere in the app.
final dataVersionProvider = NotifierProvider<DataVersion, int>(DataVersion.new);

class DataVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

/// JSON client for the app's API. Paths are relative to /api.
class ApiClient {
  ApiClient({this.onUnauthorized, this.onChanged})
      : _dio = Dio(BaseOptions(
          baseUrl: apiBaseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
          contentType: Headers.jsonContentType,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final token = TokenStore.token;
      if (token != null && token.isNotEmpty) options.headers['Authorization'] = 'Bearer $token';
      handler.next(options);
    }));
  }

  final Dio _dio;
  final void Function()? onUnauthorized;

  /// Called after a write succeeds (not after a file upload, which changes no record).
  final void Function()? onChanged;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _call(ApiCall('GET', path, query: _clean(query)));

  Future<dynamic> post(String path, {Object? data}) => _write(ApiCall('POST', path, data: data));

  Future<dynamic> put(String path, {Object? data}) => _write(ApiCall('PUT', path, data: data));

  Future<dynamic> patch(String path, {Object? data}) => _write(ApiCall('PATCH', path, data: data));

  Future<dynamic> delete(String path) => _write(ApiCall('DELETE', path));

  /// Whether a write's answer is a change kept on the device while offline
  /// (the offline plugin): the data that was sent, with no new id yet.
  static bool isQueued(dynamic result) => result is Map && result['_queued'] == true;

  Future<dynamic> _write(ApiCall call) async {
    final data = await _call(call);
    if (!isQueued(data)) onChanged?.call();
    return data;
  }

  static final List<ApiLayer> _layers = [
    for (final plugin in appPlugins)
      if (plugin.apiLayer != null) plugin.apiLayer!,
  ];

  /// [call] through the plugins' layers, then the network.
  Future<dynamic> _call(ApiCall call) {
    Future<dynamic> Function() next = () => send(call);
    for (final layer in _layers.reversed) {
      final inner = next;
      next = () => layer.handle(call, this, inner);
    }
    return next();
  }

  /// Sends [call] to the API, past every layer: for a layer's own requests
  /// (replaying a queued write). Throws ApiException.
  Future<dynamic> send(ApiCall call) => _send(
        () => _dio.request(call.path, data: call.data, queryParameters: call.query, options: Options(method: call.method)),
      );

  /// Sends one file as multipart/form-data, in the field "file" (an upload,
  /// or a list's import, which may take a while to answer).
  Future<dynamic> upload(String path, {required List<int> bytes, required String filename, Map<String, dynamic>? query}) => _send(
        () => _dio.post(
          path,
          queryParameters: _clean(query),
          data: FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: filename)}),
          options: Options(receiveTimeout: const Duration(minutes: 5)),
        ),
      );

  /// Fetches a file (a list's export) as bytes, past the plugins' layers:
  /// it is never answered from a copy on the device. Throws ApiException.
  Future<ApiDownload> download(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: _clean(query),
        options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(minutes: 5)),
      );
      return ApiDownload(
        Uint8List.fromList(response.data ?? const <int>[]),
        {for (final entry in response.headers.map.entries) entry.key.toLowerCase(): entry.value.join(', ')},
      );
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    return {
      for (final entry in query.entries)
        if (entry.value != null && '${entry.value}'.isNotEmpty) entry.key: entry.value,
    };
  }

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      return response.data;
    } on DioException catch (e) {
      throw _failure(e);
    }
  }

  /// The API's { message, errors } answer, or what went wrong on the way, as an ApiException.
  ApiException _failure(DioException e) {
    final status = e.response?.statusCode;
    var body = e.response?.data;
    // The API's messages are English; tr() gives the ones with a translation.
    // A download's error still arrives as bytes.
    if (body is List<int>) {
      try {
        body = jsonDecode(utf8.decode(body));
      } catch (error) {
        body = null;
      }
    }
    final message = body is Map && body['message'] is String
        ? tr(body['message'] as String)
        : switch (e.type) {
            DioExceptionType.connectionError ||
            DioExceptionType.connectionTimeout =>
              tr('Cannot reach the server. Is the API running?'),
            DioExceptionType.receiveTimeout => tr('The server took too long to answer.'),
            _ => status == null ? tr('Request failed.') : tr('Request failed ({status}).', {'status': status}),
          };
    if (status == 401 && !e.requestOptions.path.startsWith('/auth/')) onUnauthorized?.call();
    final errors = body is Map && body['errors'] is Map
        ? {for (final entry in (body['errors'] as Map).entries) '${entry.key}': tr('${entry.value}')}
        : const <String, String>{};
    final offline = e.response == null &&
        const {DioExceptionType.connectionError, DioExceptionType.connectionTimeout, DioExceptionType.sendTimeout}.contains(e.type);
    return ApiException(message, statusCode: status, fieldErrors: errors, offline: offline);
  }
}
