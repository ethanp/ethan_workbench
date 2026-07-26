import 'package:shared_preferences/shared_preferences.dart';

/// Persists the phone's paired session token across app launches.
class SessionTokenStore {
  static const _tokenKey = 'phone_deploy_session_token';

  Future<String?> loadToken() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_tokenKey)?.trim();
    if (token == null || token.isEmpty) return null;
    return token;
  }

  Future<void> saveToken(String token) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, token);
  }

  Future<void> clearToken() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
  }
}
