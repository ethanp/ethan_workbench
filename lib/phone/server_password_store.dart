import 'package:shared_preferences/shared_preferences.dart';

/// Persists the iOS client's shared server password across app launches.
class ServerPasswordStore {
  static const _passwordKey = 'deploy_server_password';

  Future<String?> loadPassword() async {
    final preferences = await SharedPreferences.getInstance();
    final password = preferences.getString(_passwordKey)?.trim();
    if (password == null || password.isEmpty) return null;
    return password;
  }

  Future<void> savePassword(String password) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_passwordKey, password);
  }

  Future<void> clearPassword() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_passwordKey);
  }
}
