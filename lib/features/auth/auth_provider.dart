import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthState {
  final bool isLoggedIn;
  final String? username;
  final int? userId;

  const AuthState({
    this.isLoggedIn = false,
    this.username,
    this.userId,
  });

  AuthState copyWith({bool? isLoggedIn, String? username, int? userId}) {
    return AuthState(
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      username: isLoggedIn == false ? null : (username ?? this.username),
      userId: isLoggedIn == false ? null : (userId ?? this.userId),
    );
  }
}

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState()) {
    _loadSession();
  }

  Future<void> _loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString('loggedInUser');
    final userId = prefs.getInt('loggedInUserId');
    if (username != null && userId != null) {
      state = AuthState(isLoggedIn: true, username: username, userId: userId);
    }
  }

  Future<void> login(String username, int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('loggedInUser', username);
    await prefs.setInt('loggedInUserId', userId);
    state = AuthState(isLoggedIn: true, username: username, userId: userId);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('loggedInUser');
    await prefs.remove('loggedInUserId');
    state = const AuthState();
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
