// paywall.dart — شاشة الاشتراك بخطتين (شهري + سنوي) بهوية «المصحف».
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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

class _PaywallScreenState extends State<PaywallScreen>
    with LocaleRebuild<PaywallScreen> {
  late final BillingService _billing;
  bool _busy = false;
  bool _ready = false;
  String? _msg;
  String _selected = kYearlyId; // السنوي مختار افتراضيًا (الأوفر)

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('subscribed'))));
      Navigator.of(context).pop(true);
    };
    _init();
  }

  Future<void> _init() async {
    await _billing.init();
    if (mounted) setState(() => _ready = _billing.hasAnyProduct);
  }

  @override
  void dispose() {
    _billing.dispose();
    super.dispose();
  }

  void _subscribe() {
    final product =
        _selected == kMonthlyId ? _billing.monthly : _billing.yearly;
    if (product == null) {
      setState(() => _msg = t('billingUnavailable'));
      return;
    }
    _billing.subscribe(product);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Mushaf.background,
        elevation: 0,
        foregroundColor: Mushaf.foreground,
        title: Text(t('paidTier'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
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
          const SizedBox(height: 22),
          Text(t('choosePlan'),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Mushaf.foreground)),
          const SizedBox(height: 12),
          if (_ready) ...[
            _planCard(
              id: kMonthlyId,
              title: t('monthlyPlan'),
              price: _billing.priceOf(_billing.monthly),
              per: t('perMonth'),
              product: _billing.monthly,
            ),
            const SizedBox(height: 10),
            _planCard(
              id: kYearlyId,
              title: t('yearlyPlan'),
              price: _billing.priceOf(_billing.yearly),
              per: t('perYear'),
              product: _billing.yearly,
              badge: t('bestValue'),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _busy ? null : _subscribe,
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
          ],
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

  Widget _planCard({
    required String id,
    required String title,
    required String price,
    required String per,
    required ProductDetails? product,
    String? badge,
  }) {
    final selected = _selected == id;
    final enabled = product != null;
    return GestureDetector(
      onTap: enabled ? () => setState(() => _selected = id) : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Mushaf.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? Mushaf.primary : Mushaf.border,
              width: selected ? 1.8 : 0.8,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected ? Mushaf.primary : Mushaf.border,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Mushaf.foreground)),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Mushaf.accent.withOpacity(.18),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(badge,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Mushaf.accentForeground)),
                      ),
                    ],
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(price,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Mushaf.primary)),
                  Text(per,
                      style: const TextStyle(
                          fontSize: 12, color: Mushaf.mutedForeground)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<String> _benefits() =>
      [t('benefit1'), t('benefit2'), t('benefit3'), t('benefit4')];
}
