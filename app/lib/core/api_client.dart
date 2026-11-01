import 'package:dio/dio.dart';

/// Errore leggibile restituito dal backend: {"detail": {"code": "...", "message": "..."}}
class ApiException implements Exception {
  ApiException(this.code, this.message, [this.status]);
  final String code;
  final String message;
  final int? status;

  bool get isPremiumRequired => code == 'premium_required';
  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(String baseUrl)
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 30),
        ));

  final Dio _dio;

  String get baseUrl => _dio.options.baseUrl;
  set baseUrl(String url) => _dio.options.baseUrl = url;
  String? _token;

  set token(String? t) => _token = t;
  bool get hasToken => _token != null;

  Options _opts() => Options(headers: {if (_token != null) 'Authorization': 'Bearer $_token'});

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _wrap(() => _dio.get(path, queryParameters: query, options: _opts()));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _wrap(() => _dio.post(path, data: body, queryParameters: query, options: _opts()));

  Future<dynamic> patch(String path, {Object? body}) =>
      _wrap(() => _dio.patch(path, data: body, options: _opts()));

  Future<dynamic> put(String path, {Object? body}) =>
      _wrap(() => _dio.put(path, data: body, options: _opts()));

  Future<dynamic> delete(String path) => _wrap(() => _dio.delete(path, options: _opts()));

  Future<dynamic> upload(String path, List<int> bytes, String filename, {Map<String, dynamic>? fields}) {
    final form = FormData.fromMap({
      ...?fields,
      'image': MultipartFile.fromBytes(bytes, filename: filename),
    });
    return _wrap(() => _dio.post(path, data: form, options: _opts()));
  }

  Future<dynamic> _wrap(Future<Response<dynamic>> Function() call) async {
    try {
      final r = await call();
      return r.data;
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['detail'] is Map) {
        final d = data['detail'] as Map;
        throw ApiException('${d['code'] ?? 'error'}', '${d['message'] ?? 'Errore'}', e.response?.statusCode);
      }
      if (e.response == null) {
        throw ApiException('network', 'Server non raggiungibile ($baseUrl). Controlla che il backend sia avviato.');
      }
      throw ApiException('http_${e.response?.statusCode}', 'Errore del server (${e.response?.statusCode})',
          e.response?.statusCode);
    }
  }
}
