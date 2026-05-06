import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'providers/sheets_provider.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/service_report_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Firestore の詳細なデバッグログを有効にする
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: true);
  runApp(const KarakidaApp());
}

final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();

class KarakidaApp extends StatelessWidget {
  const KarakidaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => SheetsProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) => MaterialApp(
        title: '唐木田会衆アプリ',
        navigatorKey: rootNavigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: themeProvider.primaryColor,
            primary: themeProvider.primaryColor,
            secondary: themeProvider.accentColor,
            tertiary: themeProvider.textColor,
          ),
          appBarTheme: AppBarTheme(
            backgroundColor: themeProvider.primaryColor,
            foregroundColor: Colors.white,
          ),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(1.2),
          ),
          child: _ServiceReportBannerWrapper(child: child!),
        ),
        home: const AuthGate(),
      ),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _initialized = false;
  bool _initStarted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // 初回のみサイレントサインインを試みる（起動時・ホットリスタート時）
    if (!_initStarted) {
      _initStarted = true;
      // ビルドフェーズ後の次のフレームで実行するようにスケジュールする
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _init();
      });
    }

    // サインイン状態の変化に反応する
    final auth = context.watch<AuthService>();
    final sheets = context.read<SheetsProvider>();

    if (auth.isSignedIn) {
      // サインイン済みだが、まだ SheetsProvider が初期化されていない場合
      if (sheets.currentUserEmail == null && auth.currentUser?.email != null) {
        final email = auth.currentUser!.email!;
        debugPrint('AuthGate: Signed in, but user data missing. Fetching Firestore for $email...');
        sheets.loadAccessControl(email);
        context.read<ThemeProvider>().loadSettings(email);
      }
    }
  }

  Future<void> _init() async {
    debugPrint('Init: _init started');
    final auth = context.read<AuthService>();
    
    try {
      // 起動時の待機時間を 2秒に短縮 (ユーザーを長く待たせない)
      // 2秒以内に終わらなくても、裏で処理は継続され、完了次第画面が切り替わる
      debugPrint('Init: Attempting silent sign-in (quick wait)...');
      await auth.trySilentSignIn().timeout(const Duration(seconds: 2));
    } catch (e) {
      debugPrint('Init: Silent sign-in is taking longer, moving to next screen. ($e)');
    }

    if (mounted) {
      debugPrint('Init: Final state reached, initialized=true');
      setState(() => _initialized = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sheets = context.watch<SheetsProvider>();

    // サインイン中、または初期化直後でデータ取得中の場合はスプラッシュを表示し続ける
    final bool isAuthenticating = auth.isSigningIn || (auth.isSignedIn && sheets.currentUserName == null);

    if (!_initialized || isAuthenticating) {
      // ロゴを固定サイズのSizedBoxで囲むことでレイアウトジャンプを防ぐ
      return const Scaffold(
        body: Center(
          child: SizedBox(
            width: 240,
            height: 240,
            child: Image(
              image: AssetImage('assets/APP_LOGO.png'),
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
    }

    // Googleサインイン済み、かつGASの許可チェック（ユーザー名取得）が完了している場合のみホームへ
    final bool isFullyAuthenticated = auth.isSignedIn && sheets.currentUserName != null;

    final next = isFullyAuthenticated
        ? const HomeScreen(key: ValueKey('home'))
        : const LoginScreen(key: ValueKey('login'));

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: next,
    );
  }
}

/// 毎月1日〜10日の間、画面最上部に奉仕報告の提出案内バナーを表示する。
class _ServiceReportBannerWrapper extends StatefulWidget {
  final Widget child;
  const _ServiceReportBannerWrapper({required this.child});

  @override
  State<_ServiceReportBannerWrapper> createState() =>
      _ServiceReportBannerWrapperState();
}

class _ServiceReportBannerWrapperState
    extends State<_ServiceReportBannerWrapper> {
  bool _dismissed = false;

  bool _isReportingPeriod() {
    final day = DateTime.now().day;
    return day >= 1 && day <= 10;
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final sheets = context.watch<SheetsProvider>();
    final bool isFullyAuthenticated =
        auth.isSignedIn && sheets.currentUserName != null;

    if (_dismissed || !isFullyAuthenticated || !_isReportingPeriod()) {
      return widget.child;
    }

    final mq = MediaQuery.of(context);
    const bannerHeight = 48.0;

    return Stack(
      children: [
        // 子ウィジェット(各Scaffold)の上部 padding を bannerHeight 分増やして
        // AppBar を下に押し下げ、その分のスペースにバナーを描画する。
        MediaQuery(
          data: mq.copyWith(
            padding: mq.padding.copyWith(
              top: mq.padding.top + bannerHeight,
            ),
          ),
          child: widget.child,
        ),
        Positioned(
          top: mq.padding.top,
          left: 0,
          right: 0,
          height: bannerHeight,
          child: Material(
            color: Theme.of(context).colorScheme.secondary,
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      rootNavigatorKey.currentState?.push(
                        MaterialPageRoute(
                          builder: (_) => const ServiceReportScreen(),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.campaign,
                              color: Colors.black87, size: 16),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '奉仕報告をご提出ください。',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          SizedBox(width: 2),
                          Icon(Icons.chevron_right,
                              color: Colors.black87, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => setState(() => _dismissed = true),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.close,
                        color: Colors.black87, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}


