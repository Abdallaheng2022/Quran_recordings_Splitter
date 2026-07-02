// login.dart — شاشة الدخول/التسجيل بهوية «المصحف» (مطابقة لتصميم نسخة Expo).
import 'package:flutter/material.dart';
import '../api.dart';
import '../theme.dart';

class LoginScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onLoggedIn;
  const LoginScreen({super.key, required this.api, required this.onLoggedIn});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
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
          _msg = r.data['error']?.toString() ?? 'تعذّر التسجيل.';
        });
        return;
      }
    }
    final r = await widget.api.login(email, pass);
    setState(() => _busy = false);
    if (r.ok && r.data['ok'] == true) {
      widget.onLoggedIn();
    } else {
      setState(() => _msg = r.data['error']?.toString() ?? 'تعذّر الدخول.');
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
                _registerMode ? 'إنشاء حساب' : 'مرحبًا بعودتك',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Mushaf.primary),
              ),
              const SizedBox(height: 6),
              Text(
                _registerMode
                    ? 'أنشئ حسابك لبدء تقسيم التلاوة'
                    : 'سجّل الدخول لمتابعة تقسيم التلاوة',
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: Mushaf.mutedForeground),
              ),
              const SizedBox(height: 28),
              _label('البريد الإلكتروني'),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration:
                    const InputDecoration(hintText: 'example@email.com'),
              ),
              _label('كلمة المرور'),
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
                    : Text(_registerMode ? 'إنشاء حساب' : 'دخول'),
              ),
              const SizedBox(height: 26),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _registerMode ? 'لديك حساب بالفعل؟ ' : 'ليس لديك حساب؟ ',
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
                      _registerMode ? 'دخول' : 'إنشاء حساب',
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
