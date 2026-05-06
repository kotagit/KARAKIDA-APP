import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService extends ChangeNotifier {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/spreadsheets',
    'https://www.googleapis.com/auth/drive.readonly',
  ];

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    // 6.x系では scopes を指定して初期化
    scopes: _scopes,
  );
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  GoogleSignInAccount? _currentUser;
  Map<String, String>? _authHeaders;
  String? _lastError;
  bool _isSigningIn = false;
  Future<bool>? _currentSignInFuture;

  AuthService();

  GoogleSignInAccount? get currentUser => _currentUser;
  Map<String, String>? get authHeaders => _authHeaders;
  bool get isSignedIn => _currentUser != null;
  String? get lastError => _lastError;
  bool get isSigningIn => _isSigningIn;

  /// Try silent sign-in (uses cached credentials)
  Future<bool> trySilentSignIn() async {
    if (_isSigningIn && _currentSignInFuture != null) {
      debugPrint('Auth: trySilentSignIn called while another sign-in is in progress. Waiting for it...');
      return _currentSignInFuture!;
    }
    
    _currentSignInFuture = _performSignIn(() async {
      debugPrint('Auth: trySilentSignIn started');
      // 6.x API: signInSilently
      final result = await _googleSignIn.signInSilently();
      debugPrint('Auth: signInSilently finished, account=${result?.email}');
      return result;
    }, isSilent: true);

    return _currentSignInFuture!;
  }

  /// Interactive sign-in (shows account picker)
  Future<bool> signIn() async {
    if (_isSigningIn && _currentSignInFuture != null) {
      debugPrint('Auth: signIn called while another sign-in is in progress. Waiting for it...');
      return _currentSignInFuture!;
    }

    _currentSignInFuture = _performSignIn(() async {
      debugPrint('Auth: signIn started');
      // 6.x API: signIn
      final result = await _googleSignIn.signIn();
      debugPrint('Auth: googleSignIn.signIn finished, account=${result?.email}');
      return result;
    }, isSilent: false);

    return _currentSignInFuture!;
  }

  /// 共通のサインイン実行処理
  Future<bool> _performSignIn(Future<GoogleSignInAccount?> Function() getAccount, {required bool isSilent}) async {
    _isSigningIn = true;
    _lastError = null;
    
    // 非同期で通知することでビルドフェーズ中の setState を防ぐ
    Future.microtask(() => notifyListeners());

    try {
      final account = await getAccount();
      if (account != null) {
        _currentUser = account;
        notifyListeners();

        try {
          // Google から認証トークンを取得
          debugPrint('Auth: Fetching authentication tokens...');
          final authData = await account.authentication;
          
          _authHeaders = {
            'Authorization': 'Bearer ${authData.accessToken}',
            'X-Goog-AuthUser': '0',
          };
          debugPrint('Auth: authHeaders derived.');

          // Firebase ログインを実行 (取得済みのトークンを使用)
          debugPrint('Auth: Firebase signInWithCredential starting...');
          final credential = GoogleAuthProvider.credential(
            accessToken: authData.accessToken,
            idToken: authData.idToken,
          );
          
          final authResult = await _firebaseAuth.signInWithCredential(credential);
          debugPrint('Auth: Firebase Auth sign-in completed. User: ${authResult.user?.uid}');
          
          _isSigningIn = false;
          _currentSignInFuture = null;
          notifyListeners();
          return true;
        } catch (e) {
          debugPrint('Auth: Authentication/Firebase login failed: $e');
          
          if (_firebaseAuth.currentUser != null && _authHeaders != null) {
            _isSigningIn = false;
            _currentSignInFuture = null;
            notifyListeners();
            return true;
          }

          _lastError = '認証に失敗しました。通信環境を確認し、もう一度お試しください。($e)';
          _currentUser = null;
          _authHeaders = null;
          await _googleSignIn.signOut().catchError((_) => null);
          await _firebaseAuth.signOut().catchError((_) => null);
        }
      }
    } catch (e) {
      _lastError = isSilent ? null : 'サインインに失敗しました: $e';
      debugPrint('Auth: Sign-in failed: $e');
    }

    _isSigningIn = false;
    _currentSignInFuture = null;
    notifyListeners();
    return false;
  }

  Future<void> signOut() async {
    if (_isSigningIn) {
      debugPrint('Auth: Cannot signOut while signing in');
      return;
    }
    debugPrint('Auth: signOut started');
    try {
      await _firebaseAuth.signOut();
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('Auth: Error during signOut: $e');
    }
    _currentUser = null;
    _authHeaders = null;
    _isSigningIn = false;
    notifyListeners();
  }
}
