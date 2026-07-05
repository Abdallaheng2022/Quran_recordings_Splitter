// billing.dart — اشتراك Google Play عبر in_app_purchase (شهري + سنوي).
//
// التدفّق:
//   1) نستعلم عن تفاصيل المنتجات (شهري/سنوي) من جوجل.
//   2) المستخدم يختار خطة ويضغط «اشترك» → buyNonConsumable.
//   3) عند نجاح الشراء نأخذ purchaseToken ونرسله للسيرفر (/api/play/verify)
//      ليتحقّق منه عبر Google Play Developer API (لا نثق بالعميل).
//   4) بعد تأكيد السيرفر نُكمل الشراء (completePurchase).
//
// مهم: الأسعار (1$ شهري / 10$ سنوي) تُضبط في Play Console عند إنشاء المنتجات،
// لا في الكود. التطبيق يعرض السعر القادم من المتجر. والفوترة لا تعمل إلا
// لتطبيق مرفوع على Play Console (ولو اختبار داخلي) وموقّع بمفتاح اللعب.
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'api.dart';
import 'l10n.dart';

// عدّلهما ليطابقا معرّفي المنتجين في Play Console (وأيضًا PLAY_SUBSCRIPTION_IDS بالسيرفر).
const String kMonthlyId = 'quran_pro_monthly';
const String kYearlyId = 'quran_pro_yearly';
const Set<String> kProductIds = {kMonthlyId, kYearlyId};

class BillingService {
  final Api api;
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  bool available = false;
  ProductDetails? monthly;
  ProductDetails? yearly;

  void Function(String message)? onError;
  void Function()? onPurchaseSuccess;
  void Function(bool busy)? onBusy;

  BillingService(this.api);

  bool get hasAnyProduct => monthly != null || yearly != null;

  Future<void> init() async {
    available = await _iap.isAvailable();
    if (!available) {
      onError?.call(t('billingUnavailable'));
      return;
    }
    _sub = _iap.purchaseStream.listen(_onPurchases, onError: (e) {
      onError?.call('${t('purchaseError')}: $e');
    });
    final resp = await _iap.queryProductDetails(kProductIds);
    for (final pd in resp.productDetails) {
      if (pd.id == kMonthlyId) monthly = pd;
      if (pd.id == kYearlyId) yearly = pd;
    }
    if (!hasAnyProduct) {
      onError?.call(t('billingUnavailable'));
    }
  }

  String priceOf(ProductDetails? p) => p?.price ?? '—';

  /// يبدأ تدفّق شراء المنتج المختار.
  Future<void> subscribe(ProductDetails product) async {
    onBusy?.call(true);
    final param = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.status == PurchaseStatus.pending) {
        continue;
      }
      if (p.status == PurchaseStatus.error) {
        onBusy?.call(false);
        onError?.call(p.error?.message ?? t('purchaseFailed'));
      } else if (p.status == PurchaseStatus.purchased ||
          p.status == PurchaseStatus.restored) {
        final purchaseToken = p.verificationData.serverVerificationData;
        final res = await api.verifyPlayPurchase(purchaseToken, p.productID);
        if (res.ok && res.data['ok'] == true) {
          onBusy?.call(false);
          onPurchaseSuccess?.call();
        } else {
          onBusy?.call(false);
          onError?.call(res.data['error']?.toString() ?? t('verifyFailed'));
        }
      }
      if (p.pendingCompletePurchase) {
        await _iap.completePurchase(p);
      }
    }
  }

  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  void dispose() {
    _sub?.cancel();
  }
}
