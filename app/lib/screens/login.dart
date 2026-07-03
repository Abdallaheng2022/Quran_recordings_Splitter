// login.dart — شاشة الدخول/التسجيل بهوية «المصحف» (مطابقة لتصميم نسخة Expo).
import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import 'reset_password.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.api, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with LocaleRebuild<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _msg;
  bool _registerMode = false;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final email = _email.text.trim();
    final pass = _pass.text;

    if (_registerMode) {
      final r = await widget.api.register(email, pass);
      if (!(r.ok && r.data['ok'] == true)) {
        setState(() {
          _busy = false;
          _msg = r.data['error']?.toString() ?? t('registerFailed');
        });
        return;
      }
    }
    final r = await widget.api.login(email, pass);
    setState(() => _busy = false);
    if (r.ok && r.data['ok'] == true) {
      widget.onLoggedIn();
    } else {
      setState(() => _msg = r.data['error']?.toString() ?? t('loginFailed'));
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Mushaf.foreground)),
      );

  @override
  Widget build(BuildContext context) {
    final canSubmit = !_busy;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.topEnd,
                child: PopupMenuButton<String>(
                  tooltip: t('language'),
                  icon: const Icon(Icons.language,
                      size: 22, color: Mushaf.mutedForeground),
                  onSelected: (code) => setLocale(code),
                  itemBuilder: (_) => [
                    for (final l in kLanguages)
                      PopupMenuItem(value: l.code, child: Text(l.nameNative)),
                  ],
                ),
              ),
              // الشعار — مربع أخضر 72×72 بزوايا 20 (مطابق لـ brand في Expo)
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Mushaf.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.menu_book_rounded,
                      size: 34, color: Mushaf.primaryForeground),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _registerMode ? t('createAccount') : t('welcomeBack'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Mushaf.primary),
              ),
              const SizedBox(height: 6),
              Text(
                _registerMode
                    ? t('registerSubtitle')
                    : t('loginSubtitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: Mushaf.mutedForeground),
              ),
              const SizedBox(height: 28),
              _label(t('email')),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration:
                    const InputDecoration(hintText: 'example@email.com'),
              ),
              _label(t('password')),
              TextField(
                controller: _pass,
                obscureText: true,
                decoration: const InputDecoration(hintText: '••••••••'),
              ),
              if (_msg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_msg!,
                      style: const TextStyle(
                          fontSize: 13, color: Mushaf.destructive)),
                ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: canSubmit ? _submit : null,
                child: _busy
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Mushaf.primaryForeground),
                      )
                    : Text(_registerMode ? t('createAccount') : t('login')),
              ),
              const SizedBox(height: 10),
              if (!_registerMode)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) =>
                              ResetPasswordScreen(api: widget.api))),
                  child: Text(t('forgotPassword')),
                ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _registerMode ? t('haveAccount') : t('noAccount'),
                    style: const TextStyle(color: Mushaf.mutedForeground),
                  ),
                  GestureDetector(
                    onTap: _busy
                        ? null
                        : () => setState(() {
                              _registerMode = !_registerMode;
                              _msg = null;
                            }),
                    child: Text(
                      _registerMode ? t('login') : t('createAccount'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Mushaf.primary),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
