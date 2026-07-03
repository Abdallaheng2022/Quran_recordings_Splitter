// reset_password.dart — إعادة تعيين كلمة المرور بالبريد (طلب رمز ثم تعيين جديد).
import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../theme.dart';

class ResetPasswordScreen extends StatefulWidget {
  final Api api;
  const ResetPasswordScreen({super.key, required this.api});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen>
    with LocaleRebuild<ResetPasswordScreen> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  bool _sent = false; // بعد إرسال الرمز نظهر خانتي الرمز والباسورد
  String? _msg;
  bool _ok = false;

  Future<void> _request() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = await widget.api.requestReset(_email.text.trim());
    setState(() {
      _busy = false;
      if (r.ok && r.data['ok'] == true) {
        _sent = true;
        _ok = true;
        _msg = t('resetSent');
      } else {
        _msg = r.data['error']?.toString() ?? t('loginFailed');
      }
    });
  }

  Future<void> _reset() async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    final r = await widget.api
        .resetPassword(_email.text.trim(), _code.text.trim(), _pass.text);
    setState(() => _busy = false);
    if (r.ok && r.data['ok'] == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('resetDone'))));
      Navigator.of(context).pop();
    } else {
      setState(() {
        _ok = false;
        _msg = r.data['error']?.toString() ?? t('loginFailed');
      });
    }
  }

  Widget _label(String s) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 8),
        child: Text(s,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Mushaf.foreground)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Mushaf.background,
        elevation: 0,
        foregroundColor: Mushaf.foreground,
        title: Text(t('resetTitle'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(t('resetIntro'),
              style: const TextStyle(
                  fontSize: 14, color: Mushaf.mutedForeground)),
          _label(t('email')),
          TextField(
            controller: _email,
            enabled: !_sent,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'example@email.com'),
          ),
          if (_sent) ...[
            _label(t('resetCode')),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: '000000'),
            ),
            _label(t('newPassword')),
            TextField(
              controller: _pass,
              obscureText: true,
              decoration: const InputDecoration(hintText: '••••••••'),
            ),
          ],
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_msg!,
                  style: TextStyle(
                      fontSize: 13,
                      color: _ok ? Mushaf.primary : Mushaf.destructive)),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : (_sent ? _reset : _request),
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Mushaf.primaryForeground))
                : Text(_sent ? t('resetConfirm') : t('resetRequest')),
          ),
          if (_sent)
            TextButton(
              onPressed: _busy ? null : _request,
              child: Text(t('resetResend')),
            ),
        ],
      ),
    );
  }
}
