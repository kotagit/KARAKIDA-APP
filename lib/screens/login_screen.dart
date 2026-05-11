import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../providers/sheets_provider.dart';
import '../providers/theme_provider.dart';

/// ログイン画面
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _isLoading = false;
  String? _statusMessage;

  /// Google サインイン処理
  Future<void> _handleSignIn() async {
    debugPrint('Login: _handleSignIn started');
    final auth = context.read<AuthService>();
    
    // すでに処理中の場合は待つだけにする（AuthService側で制御）
    if (auth.isSigningIn) {
      debugPrint('Login: Already signing in, waiting for current process...');
    }

    setState(() {
      _isLoading = true;
      _statusMessage = null;
    });

    try {
      debugPrint('Login: auth.signIn starting...');
      final result = await auth.signIn();
      debugPrint('Login: auth.signIn finished, result=$result');

      if (!result) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _statusMessage = auth.lastError ?? 'ログインがキャンセルされました';
          });
        }
        return;
      }

      final user = auth.currentUser;
      if (user == null || user.email == null) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'ユーザー情報の取得に失敗しました';
        });
        return;
      }

      // Firestore 許可リストから情報を取得
      debugPrint('Login: Firestore check starting for ${user.email}...');
      final userData = await FirestoreService.getUserByEmail(user.email!)
          .timeout(const Duration(seconds: 15));
      debugPrint('Login: Firestore check finished, found=${userData != null}');

      if (userData == null) {
        // 許可されていない場合はサインアウト
        debugPrint('Login: User not allowed, signing out');
        await auth.signOut();
        setState(() {
          _isLoading = false;
          _statusMessage = 'このアカウントはアクセスが許可されていません';
        });
        return;
      }

      // ログイン成功: SheetsProvider を更新
      if (mounted) {
        debugPrint('Login: Updating SheetsProvider and completing login');
        final sheets = context.read<SheetsProvider>();
        sheets.updateAuth(
              auth.authHeaders,
              name: userData['name'] as String?,
              group: userData['group'] as String?,
              furigana: userData['furigana'] as String?,
              isAdmin: userData['isAdmin'] == true,
              isCho: userData['isCho'] == true,
              isTerritoryServant: userData['isTerritoryServant'] == true,
              isPW: userData['isPW'] == true,
              email: user.email,
            );
        sheets.loadFiles(userEmail: user.email);
        setState(() {
          _isLoading = false;
          _statusMessage = 'ログイン成功';
        });
      }
    } catch (e) {
      debugPrint('Login: Error in _handleSignIn: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _statusMessage = 'エラーが発生しました: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final isProcessing = _isLoading || auth.isSigningIn;

    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SvgPicture.asset(
                'assets/APP_LOGO.svg',
                width: 280,
                colorFilter: ColorFilter.mode(
                  context.watch<ThemeProvider>().logoColor,
                  BlendMode.srcIn,
                ),
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isProcessing ? null : _handleSignIn,
                  icon: isProcessing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.login),
                  label: Text(isProcessing ? 'ログイン中...' : 'Googleアカウントでログイン'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black87,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: Colors.grey),
                    ),
                  ),
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusMessage!.contains('失敗') ||
                            _statusMessage!.contains('エラー') ||
                            _statusMessage!.contains('許可')
                        ? Colors.red
                        : Colors.orange,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
