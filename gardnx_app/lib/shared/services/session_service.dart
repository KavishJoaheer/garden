import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const _sessionExpiresAtKey = 'session_expires_at_ms';
  static const Duration sessionDuration = Duration(hours: 24);

  final FirebaseAuth _firebaseAuth;

  SessionService({FirebaseAuth? firebaseAuth})
      : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  Future<void> startSession() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt =
        DateTime.now().add(sessionDuration).millisecondsSinceEpoch;
    await prefs.setInt(_sessionExpiresAtKey, expiresAt);
  }

  Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionExpiresAtKey);
  }

  Future<bool> isSessionExpired() async {
    final prefs = await SharedPreferences.getInstance();
    final expiresAt = prefs.getInt(_sessionExpiresAtKey);
    if (expiresAt == null) return _firebaseAuth.currentUser != null;

    return DateTime.now().millisecondsSinceEpoch >= expiresAt;
  }

  Future<void> enforceSession() async {
    final currentUser = _firebaseAuth.currentUser;
    if (currentUser == null) {
      await clearSession();
      return;
    }

    if (await isSessionExpired()) {
      await _firebaseAuth.signOut();
      await clearSession();
    }
  }
}
