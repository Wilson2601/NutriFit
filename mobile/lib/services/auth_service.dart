import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Holds the signed-in user's profile and Firebase ID token, and exposes
/// register/login/logout. Registration goes through our backend (which creates
/// both the Firebase Auth account and the Firestore profile using admin
/// privileges), then the app signs in normally via FirebaseAuth to obtain a
/// real ID token for all subsequent API calls.
class AuthService extends ChangeNotifier {
  final ApiService api;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  AuthService(this.api);

  Map<String, dynamic>? _user;
  String? _token;
  bool _loading = true;

  Map<String, dynamic>? get user => _user;
  String? get token => _token;
  bool get isLoading => _loading;
  bool get isSignedIn => _user != null && _token != null;
  String? get role => _user?['role'] as String?;

  /// Call once at app startup: restores a cached session if the Firebase Auth
  /// SDK still has a valid signed-in user.
  Future<void> restoreSession() async {
    _loading = true;
    notifyListeners();
    try {
      final firebaseUser = _firebaseAuth.currentUser;
      if (firebaseUser != null) {
        final idToken = await firebaseUser.getIdToken(true);
        final profile = await api.me(idToken!);
        _token = idToken;
        _user = profile['user'] as Map<String, dynamic>;
      }
    } catch (_) {
      _token = null;
      _user = null;
    }
    _loading = false;
    notifyListeners();
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    String? phone,
    required String role,
    String? goal,
    double? weightKg,
    double? goalWeightKg,
  }) async {
    await api.register({
      'name': name,
      'email': email,
      'password': password,
      'phone': phone,
      'role': role,
      'goal': goal,
      'weightKg': weightKg,
      'goalWeightKg': goalWeightKg,
    });
    // Registration created the Firebase Auth account server-side (with admin
    // privileges) — sign in normally now to obtain a real client-side ID token.
    await login(email: email, password: password, role: role);
  }

  Future<void> login({required String email, required String password, required String role}) async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
    final idToken = await credential.user!.getIdToken(true);
    final profileResponse = await api.me(idToken!);
    final profile = profileResponse['user'] as Map<String, dynamic>;

    if (profile['role'] != role) {
      await _firebaseAuth.signOut();
      throw ApiException("This account is registered as a ${profile['role']}, not a $role");
    }

    _token = idToken;
    _user = profile;
    notifyListeners();
  }

  Future<void> logout() async {
    await _firebaseAuth.signOut();
    _token = null;
    _user = null;
    notifyListeners();
  }

  void updateUser(Map<String, dynamic> profile) {
    _user = profile;
    notifyListeners();
  }
}
