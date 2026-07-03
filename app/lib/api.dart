// api.dart — عميل HTTP لـ API السيرفر (نفس النقاط في scripts/api.py).
//
// عدّل عنوان السيرفر إمّا هنا في kDefaultBaseUrl، أو عند البناء عبر:
//   flutter build apk --dart-define=API_BASE=https://your-server.com
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kDefaultBaseUrl =
    String.fromEnvironment('API_BASE', defaultValue: 'https://your-server.com');

class ApiResult {
  final bool ok;
  final int status;
  final Map<String, dynamic> data;
  final Uint8List? bytes; // للملفات (zip)
  ApiResult(this.ok, this.status, this.data, {this.bytes});
}

class Api {
  String baseUrl;
  String? token;

  Api({String? baseUrl}) : baseUrl = baseUrl ?? kDefaultBaseUrl;

  Map<String, String> get _authHeaders =>
      token == null ? {} : {'Authorization': 'Bearer $token'};

  // ----- إدارة التوكن (حفظ محلي) -----
  Future<void> loadToken() async {
    final p = await SharedPreferences.getInstance();
    token = p.getString('token');
    // عنوان السيرفر مدمج وقت البناء (API_BASE) ولا يُسترجع من التخزين.
  }

  Future<void> _saveToken(String? t) async {
    token = t;
    final p = await SharedPreferences.getInstance();
    if (t == null) {
      await p.remove('token');
    } else {
      await p.setString('token', t);
    }
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url;
    final p = await SharedPreferences.getInstance();
    await p.setString('base_url', url);
  }

  // ----- الحساب -----
  Future<ApiResult> register(String email, String password) =>
      _postJson('/api/register', {'email': email, 'password': password});

  Future<ApiResult> login(String email, String password) async {
    final r = await _postJson('/api/login', {'email': email, 'password': password});
    if (r.ok && r.data['ok'] == true && r.data['token'] != null) {
      await _saveToken(r.data['token'] as String);
    }
    return r;
  }

  Future<void> logout() async {
    try {
      await http.post(Uri.parse('$baseUrl/api/logout'), headers: _authHeaders);
    } catch (_) {}
    await _saveToken(null);
  }

  Future<ApiResult> requestReset(String email) =>
      _postJson('/api/password/request-reset', {'email': email});

  Future<ApiResult> resetPassword(String email, String code, String password) =>
      _postJson('/api/password/reset',
          {'email': email, 'code': code, 'password': password});

    /// يجلب الاستحقاق: المستوى + الحدود + استهلاك اليوم.
  Future<ApiResult> me() => _getJson('/api/me');

  /// قائمة القرّاء المرجعيين المتاحين على السيرفر.
  Future<ApiResult> reciters() => _getJson('/api/reciters');

  // ----- التحليل والتقسيم -----
  /// يرسل بايتات الصوت كجسم الطلب (الـ API يقرأ الجسم مباشرةً كملف صوت).
  Future<ApiResult> analyze({
    required Uint8List audio,
    required String name,
    String range = 'all',
    String level = 'ayah',
    String? method,
    String edition = 'ar.alafasy',
  }) async {
    final qp = {
      'name': name,
      'range': range,
      'level': level,
      'edition': edition,
      if (method != null) 'method': method,
    };
    final uri = Uri.parse('$baseUrl/api/analyze').replace(queryParameters: qp);
    try {
      final resp = await http
          .post(uri,
              headers: {..._authHeaders, 'Content-Type': 'application/octet-stream'},
              body: audio)
          .timeout(const Duration(seconds: 480));
      return _decode(resp);
    } on TimeoutException {
      return ApiResult(false, 0, {
        'error': 'انتهت المهلة. السيرفر قد يكون نائمًا (يصحو خلال دقيقة) '
            'أو الملف كبير — انتظر قليلًا وأعد المحاولة.'
      });
    } catch (e) {
      return ApiResult(false, 0, {'error': 'تعذّر الاتصال بالسيرفر: $e'});
    }
  }

  /// يطلب ملف الـ zip النهائي بالحدود الناتجة من analyze.
  Future<ApiResult> save(String sessionToken, List bounds) async {
    final uri = Uri.parse('$baseUrl/api/save');
    try {
      final resp = await http
          .post(uri,
              headers: {..._authHeaders, 'Content-Type': 'application/json'},
              body: jsonEncode({'token': sessionToken, 'bounds': bounds}))
          .timeout(const Duration(seconds: 480));
      if (resp.statusCode == 200 &&
          (resp.headers['content-type']?.contains('zip') ?? false)) {
        return ApiResult(true, 200, {}, bytes: resp.bodyBytes);
      }
      return _decode(resp);
    } on TimeoutException {
      return ApiResult(false, 0,
          {'error': 'انتهت المهلة أثناء تجهيز الملف. أعد المحاولة.'});
    } catch (e) {
      return ApiResult(false, 0, {'error': 'تعذّر تحميل الملف: $e'});
    }
  }

  // ----- التحقّق من شراء Play على السيرفر -----
  Future<ApiResult> verifyPlayPurchase(String purchaseToken, String productId) =>
      _postJson('/api/play/verify',
          {'purchase_token': purchaseToken, 'product_id': productId});

  // ----- مساعدات -----
  Future<ApiResult> _postJson(String path, Map body) async {
    try {
      final resp = await http
          .post(Uri.parse('$baseUrl$path'),
              headers: {..._authHeaders, 'Content-Type': 'application/json'},
              body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
      return _decode(resp);
    } on TimeoutException {
      return ApiResult(false, 0, {'error': 'انتهت المهلة — السيرفر قد يكون نائمًا. أعد المحاولة بعد لحظات.'});
    } catch (e) {
      return ApiResult(false, 0, {'error': 'تعذّر الاتصال بالسيرفر: $e'});
    }
  }

  Future<ApiResult> _getJson(String path) async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl$path'), headers: _authHeaders)
          .timeout(const Duration(seconds: 30));
      return _decode(resp);
    } on TimeoutException {
      return ApiResult(false, 0, {'error': 'انتهت المهلة — السيرفر قد يكون نائمًا. أعد المحاولة بعد لحظات.'});
    } catch (e) {
      return ApiResult(false, 0, {'error': 'تعذّر الاتصال بالسيرفر: $e'});
    }
  }

  /// يُستدعى عند اكتشاف جلسة منتهية (401) — يُمسح التوكن.
  void Function()? onSessionExpired;

  ApiResult _decode(http.Response resp) {
    if (resp.statusCode == 401) {
      _saveToken(null);
      onSessionExpired?.call();
    }
    Map<String, dynamic> data = {};
    try {
      final parsed = jsonDecode(utf8.decode(resp.bodyBytes));
      if (parsed is Map<String, dynamic>) data = parsed;
    } catch (_) {}
    final ok = resp.statusCode >= 200 && resp.statusCode < 300;
    return ApiResult(ok, resp.statusCode, data);
  }
}
