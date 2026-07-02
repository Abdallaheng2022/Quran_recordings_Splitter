// main.dart — نقطة الدخول: تحميل اللغة المحفوظة، إعادة البناء عند تغييرها،
// واتجاه الواجهة (RTL للعربية) — ثم التوجيه حسب حالة الدخول.
import 'package:flutter/material.dart';
import 'api.dart';
import 'l10n.dart';
import 'theme.dart';
import 'screens/login.dart';
import 'screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedLocale();
  runApp(const QuranSplitterApp());
}

class QuranSplitterApp extends StatelessWidget {
  const QuranSplitterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: appLocale,
      builder: (context, code, _) => MaterialApp(
        title: 'Quran Splitter',
        debugShowCheckedModeBanner: false,
        locale: Locale(code),
        theme: mushafTheme(),
        builder: (context, child) => Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child!,
        ),
        home: const _Bootstrap(),
      ),
    );
  }
}

class _Bootstrap extends StatefulWidget {
  const _Bootstrap();
  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  final Api api = Api();
  bool _loading = true;
  bool _loggedIn = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await api.loadToken();
    if (api.token != null) {
      final r = await api.me();
      _loggedIn = r.ok && r.data['ok'] == true;
      if (!_loggedIn) await api.logout();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _loggedIn
        ? HomeScreen(api: api)
        : LoginScreen(
            api: api,
            onLoggedIn: () => setState(() => _loggedIn = true),
          );
  }
}
