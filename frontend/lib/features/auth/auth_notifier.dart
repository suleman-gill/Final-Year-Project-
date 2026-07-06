import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

class AuthState {
  final bool isLoading;
  final String? errorMessage;
  final User? firebaseUser;
  final String? token;

  const AuthState({
    this.isLoading = false,
    this.errorMessage,
    this.firebaseUser,
    this.token,
  });

  bool get isAuthenticated => firebaseUser != null && token != null;

  String get displayName => firebaseUser?.displayName ?? 
      firebaseUser?.email?.split('@').first ?? 'User';
  String get email => firebaseUser?.email ?? '';
  String get photoUrl => firebaseUser?.photoURL ?? '';

  AuthState copyWith({
    bool? isLoading,
    String? errorMessage,
    User? firebaseUser,
    String? token,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      firebaseUser: firebaseUser ?? this.firebaseUser,
      token: token ?? this.token,
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _init();
  }

  final _auth = FirebaseAuth.instance;

  final _secureStorage = const FlutterSecureStorage();

  void _init() {
    // Listen to Firebase auth state changes automatically
    _auth.authStateChanges().listen((user) async {
      if (user != null) {
        final token = await user.getIdToken();
        await _secureStorage.write(key: 'auth_token', value: token);
        state = AuthState(firebaseUser: user, token: token);
      } else {
        await _secureStorage.delete(key: 'auth_token');
        state = const AuthState();
      }
    });
  }

  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      // _init listener handles state update automatically
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _mapError(e.code));
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Login failed. Please try again.');
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      await cred.user?.updateDisplayName(name.trim());
      // Refresh token after updating display name
      await cred.user?.reload();
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _mapError(e.code));
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: 'Registration failed.');
    }
  }

  Future<void> sendPasswordReset(String email) async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      state = state.copyWith(isLoading: false);
    } on FirebaseAuthException catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: _mapError(e.code));
    }
  }

  /// Returns a fresh Firebase ID token. Call this before WebSocket auth.
  Future<String?> getFreshToken() async {
    try {
      return await _auth.currentUser?.getIdToken(true);
    } catch (e) {
      return null;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    await _secureStorage.delete(key: 'auth_token');
    state = const AuthState();
  }

  // Keep this for backwards compatibility with any code that calls checkToken()
  Future<void> checkToken() async {}

  String _mapError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection. Please check your network.';
      default:
        return 'Authentication failed. Please try again.';
    }
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(),
);
