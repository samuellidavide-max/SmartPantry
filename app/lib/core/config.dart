import 'package:shared_preferences/shared_preferences.dart';

/// Indirizzo del backend.
/// Default: emulatore Android (10.0.2.2 = il "localhost" del computer).
/// Si cambia con:  flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
/// oppure dall'app (schermata di errore di connessione o Profilo > Server).
class AppConfig {
  static const String defaultBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
  static const _key = 'api_base_url';

  static Future<String> loadBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? defaultBaseUrl;
  }

  static Future<void> saveBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    await prefs.setString(_key, u);
  }
}
