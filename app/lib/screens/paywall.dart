// paywall.dart — شاشة الاشتراك بهوية «المصحف» (Google Play Billing).
import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../billing.dart';
import '../theme.dart';

class PaywallScreen extends StatefulWidget {
  final Api api;
  final String? reason;
  const PaywallScreen({super.key, required this.api, this.reason});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> with LocaleRebuild<PaywallScreen> {
  late final BillingService _billing;
  bool _busy = false;
  bool _ready = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _billing = BillingService(widget.api);
    _billing.onError = (m) => setState(() {
          _busy = false;
          _msg = m;
        });
    _billing.onBusy = (b) => setState(() => _busy = b);
    _billing.onPurchaseSuccess = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t('subscribed'))));
      Navigator.of(context).pop(true);
    };
    _init();
  }

  Future<void> _init() async {
    await _billing.init();
    if (mounted) setState(() => _ready = _billing.product != null);
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final price = _billing.priceLabel;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Mushaf.background,
        elevation: 0,
        foregroundColor: Mushaf.foreground,
        title: Text(t('paidTier'),
            style: TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (widget.reason != null)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Mushaf.accent.withOpacity(.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Mushaf.accent.withOpacity(.5)),
              ),
              child: Text(widget.reason!,
                  style: const TextStyle(color: Mushaf.accentForeground)),
            ),
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Mushaf.accent.withOpacity(.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.workspace_premium,
                  size: 36, color: Mushaf.accent),
            ),
          ),
          const SizedBox(height: 16),
          Text(t('yearlySub'),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Mushaf.foreground)),
          const SizedBox(height: 6),
          if (_ready)
            Text(price,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Mushaf.primary)),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Mushaf.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Mushaf.border, width: 0.6),
            ),
            child: Column(
              children: _benefits()
                  .map((b) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                size: 20, color: Mushaf.primary),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(b,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        color: Mushaf.foreground))),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (!_ready || _busy) ? null : _billing.subscribe,
            child: _busy
                ? const SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Mushaf.primaryForeground))
                : Text(t('subscribe')),
          ),
          TextButton(
            onPressed: _busy ? null : _billing.restore,
            child: Text(t('restore')),
          ),
          if (_msg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_msg!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 13, color: Mushaf.destructive)),
            ),
          if (!_ready && _msg == null)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Center(
                  child: CircularProgressIndicator(color: Mushaf.primary)),
            ),
        ],
      ),
    );
  }

  List<String> _benefits() =>
      [t('benefit1'), t('benefit2'), t('benefit3'), t('benefit4')];
}
