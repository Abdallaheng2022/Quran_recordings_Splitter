// home.dart — الشاشة الرئيسية: اختيار المدى من قائمة السور (مترجمة)،
// مستوى وطريقة التقسيم، القارئ المرجعي، ثم التحليل → محرر المقاطع.
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../api.dart';
import '../l10n.dart';
import '../surahs.dart';
import '../theme.dart';
import 'about.dart';
import 'editor.dart';
import 'login.dart';
import 'paywall.dart';

class HomeScreen extends StatefulWidget {
  final Api api;
  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with LocaleRebuild<HomeScreen> {
  Map<String, dynamic>? _me;
  String? _fileName;
  Uint8List? _fileBytes;
  String? _localPath; // نسخة محلية للتشغيل في المحرر

  // المدى: all | surah | juz
  String _rangeKind = 'surah';
  int _surah = 36;
  int _juz = 30;

  String _level = 'ayah';
  String _method = 'auto';
  String _edition = 'ar.alafasy';
  List<Map<String, dynamic>> _reciters = [];

  bool _busy = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _refreshMe();
    _loadReciters();
  }

  Future<void> _refreshMe() async {
    final r = await widget.api.me();
    if (r.ok && r.data['ok'] == true && mounted) setState(() => _me = r.data);
  }

  Future<void> _loadReciters() async {
    final r = await widget.api.reciters();
    if (r.ok && r.data['ok'] == true && r.data['reciters'] is List && mounted) {
      setState(() {
        _reciters = (r.data['reciters'] as List)
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        _edition = (r.data['default'] as String?) ?? _edition;
      });
    }
  }

  bool get _isPaid => _me?['tier'] == 'paid';

  String get _rangeParam {
    switch (_rangeKind) {
      case 'all':
        return 'all';
      case 'juz':
        return 'juz:$_juz';
      default:
        return 'surah:$_surah';
    }
  }

  String _surahDisplay(Surah s) => appLocale.value == 'ar'
      ? '${s.number}. ${s.arabic}'
      : '${s.number}. ${s.latin}';

  Future<void> _pickAudio() async {
    // withData: false — لا نحمّل الملف في الذاكرة عبر قناة النظام (يجمّد الملفات
    // الكبيرة). نأخذ المسار وننسخه نسخًا قرصيًا سريعًا لاسم ASCII آمن للتشغيل.
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'],
      withData: false,
    );
    if (res == null || res.files.isEmpty) return;
    final f = res.files.first;
    String? path = f.path;
    try {
      if (f.path != null) {
        final dir = await getTemporaryDirectory();
        final ext = f.extension ?? 'mp3';
        final dst =
            '${dir.path}/clip_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await File(f.path!).copy(dst); // نسخ قرصي — بلا تحميل في الذاكرة
        path = dst;
      }
    } catch (_) {}
    setState(() {
      _fileName = f.name;
      _fileBytes = null; // لا نحتفظ بالبايتات؛ تُقرأ وقت الرفع فقط
      _localPath = path;
      _status = null;
    });
  }

  Future<void> _run() async {
    if (_localPath == null) {
      setState(() => _status = t('pickFirst'));
      return;
    }
    setState(() {
      _busy = true;
      _status = t('analyzingLong');
    });

    // اقرأ البايتات وقت الرفع فقط (يقلّل استهلاك الذاكرة للملفات الكبيرة)
    Uint8List audioBytes;
    try {
      audioBytes = await File(_localPath!).readAsBytes();
    } catch (e) {
      setState(() {
        _busy = false;
        _status = t('pickFirst');
      });
      return;
    }

    final analyze = await widget.api.analyze(
      audio: audioBytes,
      name: _fileName ?? 'audio.mp3',
      range: _rangeParam,
      level: _level,
      method: _method == 'auto' ? null : _method,
      edition: _edition,
    );

    setState(() => _busy = false);
    if (!analyze.ok) {
      _handleError(analyze);
      return;
    }

    final sessionToken = analyze.data['token']?.toString();
    final rawBounds = analyze.data['bounds'] as List?;
    final duration = (analyze.data['duration'] as num?)?.toDouble();
    if (sessionToken == null || rawBounds == null || duration == null) {
      setState(() => _status = t('unexpected'));
      return;
    }
    final bounds = rawBounds
        .map((b) => [
              ((b as List)[0] as num).toDouble(),
              (b[1] as num).toDouble(),
            ])
        .toList();
    final labels = ((analyze.data['segments'] as List?) ?? [])
        .whereType<Map>()
        .map((s) => s['labelAr']?.toString() ?? '')
        .toList();

    if (!mounted) return;
    setState(() => _status = null);
    // (التعديل 5) المراجعة والتعديل قبل الحفظ
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => EditorScreen(
        api: widget.api,
        sessionToken: sessionToken,
        audioPath: _localPath!,
        duration: duration,
        initialBounds: bounds,
        labels: labels,
      ),
    ));
    await _refreshMe();
    if (saved == true && mounted) {
      setState(() => _status = t('done'));
    }
  }

  void _handleError(ApiResult r) {
    final needSub = r.data['need_subscription'] == true;
    final msg = r.data['error']?.toString() ?? '(${r.status})';
    if (needSub || r.status == 402) {
      _openPaywall(reason: msg);
    } else {
      setState(() => _status = msg);
    }
  }

  void _openPaywall({String? reason}) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PaywallScreen(api: widget.api, reason: reason),
        ))
        .then((_) => _refreshMe());
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => LoginScreen(
          api: widget.api,
          onLoggedIn: () => Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => HomeScreen(api: widget.api)),
          ),
        ),
      ),
      (r) => false,
    );
  }

  // ---------------------------- الواجهة ----------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _uploadCard(),
                  _sectionLabel(t('range')),
                  _rangeCard(),
                  _sectionLabel(t('level')),
                  _levelChips(),
                  _sectionLabel(t('method')),
                  _methodCard(
                    id: 'auto',
                    icon: Icons.auto_awesome,
                    title: t('methodAuto'),
                    subtitle: t('methodAutoDesc'),
                  ),
                  const SizedBox(height: 10),
                  _methodCard(
                    id: 'silence',
                    icon: Icons.graphic_eq,
                    title: t('methodSilence'),
                    subtitle: t('methodSilenceDesc'),
                  ),
                  const SizedBox(height: 10),
                  _methodCard(
                    id: 'refdtw',
                    icon: Icons.track_changes,
                    title: t('methodRef'),
                    subtitle: t('methodRefDesc'),
                  ),
                  if (_method != 'silence') ...[
                    _sectionLabel(t('reciter')),
                    _reciterCard(),
                  ],
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: _busy ? null : _run,
                    icon: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Mushaf.primaryForeground))
                        : const Icon(Icons.content_cut),
                    label: Text(_busy ? t('processing') : t('split')),
                  ),
                  if (_status != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(_status!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Mushaf.foreground)),
                    ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final jobsLeft = _me?['usage']?['jobs_remaining'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Mushaf.border, width: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // شريحة الحالة
              GestureDetector(
                onTap: _isPaid ? null : () => _openPaywall(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color:
                        _isPaid ? Mushaf.accent.withOpacity(.15) : Mushaf.muted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: _isPaid ? Mushaf.accent : Mushaf.border),
                  ),
                  child: Text(
                    _isPaid
                        ? t('paidTier')
                        : (jobsLeft != null
                            ? '${t('freeTier')} · $jobsLeft ${t('triesLeft')}'
                            : t('freeTier')),
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: _isPaid
                            ? Mushaf.accentForeground
                            : Mushaf.secondaryForeground),
                  ),
                ),
              ),
              const Spacer(),
              // (التعديل 1) قائمة اللغات
              PopupMenuButton<String>(
                tooltip: t('language'),
                icon: const Icon(Icons.language,
                    size: 21, color: Mushaf.mutedForeground),
                onSelected: (code) => setLocale(code),
                itemBuilder: (_) => [
                  for (final l in kLanguages)
                    PopupMenuItem(
                      value: l.code,
                      child: Row(
                        children: [
                          if (l.code == appLocale.value)
                            const Icon(Icons.check,
                                size: 16, color: Mushaf.primary)
                          else
                            const SizedBox(width: 16),
                          const SizedBox(width: 8),
                          Text(l.nameNative),
                        ],
                      ),
                    ),
                ],
              ),
              // (التعديل 3) عن التطبيق
              IconButton(
                tooltip: t('about'),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AboutScreen())),
                icon: const Icon(Icons.info_outline,
                    size: 21, color: Mushaf.mutedForeground),
              ),
              IconButton(
                tooltip: t('logout'),
                onPressed: _logout,
                icon: const Icon(Icons.logout,
                    size: 20, color: Mushaf.mutedForeground),
              ),
            ],
          ),
          Text(t('appTitle'),
              style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Mushaf.primary)),
          const SizedBox(height: 4),
          Text(t('appSubtitle'),
              style: const TextStyle(
                  fontSize: 13, color: Mushaf.mutedForeground)),
        ],
      ),
    );
  }

  Widget _uploadCard() {
    final picked = _fileName != null;
    return GestureDetector(
      onTap: _busy ? null : _pickAudio,
      child: DashedBorder(
        color: picked ? Mushaf.primary : Mushaf.border,
        radius: 18,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
          child: Column(
            children: [
              Icon(picked ? Icons.audiotrack : Icons.cloud_upload_outlined,
                  size: 34,
                  color: picked ? Mushaf.primary : Mushaf.mutedForeground),
              const SizedBox(height: 6),
              Text(
                picked ? _fileName! : t('pickAudio'),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Mushaf.foreground),
              ),
              const SizedBox(height: 2),
              Text(
                picked ? t('pickAnother') : 'mp3 · m4a · wav · ogg',
                style: const TextStyle(
                    fontSize: 13, color: Mushaf.mutedForeground),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Mushaf.foreground)),
      );

  Widget _rangeCard() {
    final surah = kSurahs[_surah - 1];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Mushaf.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Mushaf.border, width: 0.6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            children: [
              _pill('surah', t('surah')),
              _pill('juz', t('juz')),
              _pill('all', t('allQuran')),
            ],
          ),
          if (_rangeKind == 'surah') ...[
            const SizedBox(height: 12),
            // (التعديل 1) قائمة السور — تفتح منتقيًا ببحث بكل الأسماء
            InkWell(
              onTap: _openSurahPicker,
              borderRadius: BorderRadius.circular(Mushaf.radius),
              child: InputDecorator(
                decoration: const InputDecoration(
                    suffixIcon: Icon(Icons.expand_more,
                        color: Mushaf.mutedForeground)),
                child: Text(_surahDisplay(surah),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Mushaf.foreground)),
              ),
            ),
          ],
          if (_rangeKind == 'juz') ...[
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: _juz,
                  isExpanded: true,
                  isDense: true,
                  icon: const Icon(Icons.expand_more,
                      color: Mushaf.mutedForeground),
                  items: [
                    for (var j = 1; j <= 30; j++)
                      DropdownMenuItem(
                          value: j, child: Text('${t('juz')} $j')),
                  ],
                  onChanged: (v) => setState(() => _juz = v ?? _juz),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pill(String kind, String label) {
    final selected = _rangeKind == kind;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _rangeKind = kind),
      selectedColor: Mushaf.primary,
      backgroundColor: Mushaf.muted,
      labelStyle: TextStyle(
          fontWeight: FontWeight.w700,
          color: selected
              ? Mushaf.primaryForeground
              : Mushaf.secondaryForeground),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? Mushaf.primary : Mushaf.border),
      ),
      showCheckmark: false,
    );
  }

  void _openSurahPicker() {
    String query = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Mushaf.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final q = query.trim().toLowerCase();
          final filtered = q.isEmpty
              ? kSurahs
              : kSurahs
                  .where((s) =>
                      s.arabic.contains(query.trim()) ||
                      s.latin.toLowerCase().contains(q) ||
                      s.number.toString() == q)
                  .toList();
          return SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: TextField(
                    autofocus: false,
                    decoration: InputDecoration(
                      hintText: t('searchSurah'),
                      prefixIcon: const Icon(Icons.search,
                          color: Mushaf.mutedForeground),
                    ),
                    onChanged: (v) => setSheet(() => query = v),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final s = filtered[i];
                      final selected = s.number == _surah;
                      return ListTile(
                        dense: true,
                        title: Text(_surahDisplay(s),
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: selected
                                    ? Mushaf.primary
                                    : Mushaf.foreground)),
                        trailing: Text('${s.ayahs}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Mushaf.mutedForeground)),
                        onTap: () {
                          setState(() => _surah = s.number);
                          Navigator.of(ctx).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _levelChips() {
    final levels = {
      'ayah': t('levelAyah'),
      'rub': t('levelRub'),
      'hizb': t('levelHizb'),
      'juz': t('levelJuz'),
      'page': t('levelPage'),
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: levels.entries.map((e) {
        final selected = _level == e.key;
        return ChoiceChip(
          label: Text(e.value),
          selected: selected,
          onSelected: (_) => setState(() => _level = e.key),
          selectedColor: Mushaf.primary,
          backgroundColor: Mushaf.muted,
          labelStyle: TextStyle(
              fontWeight: FontWeight.w700,
              color: selected
                  ? Mushaf.primaryForeground
                  : Mushaf.secondaryForeground),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side:
                BorderSide(color: selected ? Mushaf.primary : Mushaf.border),
          ),
          showCheckmark: false,
        );
      }).toList(),
    );
  }

  Widget _methodCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _method == id;
    return GestureDetector(
      onTap: () => setState(() => _method = id),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Mushaf.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? Mushaf.primary : Mushaf.border,
            width: selected ? 1.6 : 0.6,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected
                    ? Mushaf.primary
                    : Mushaf.primary.withOpacity(.10),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon,
                  size: 22,
                  color:
                      selected ? Mushaf.primaryForeground : Mushaf.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Mushaf.foreground)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Mushaf.mutedForeground)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20,
              color: selected ? Mushaf.primary : Mushaf.border,
            ),
          ],
        ),
      ),
    );
  }

  Widget _reciterCard() {
    final items = _reciters.isNotEmpty
        ? _reciters
        : [
            {'id': 'ar.alafasy', 'name': 'مشاري راشد العفاسي'}
          ];
    final ids = items.map((r) => r['id'].toString()).toSet();
    final value =
        ids.contains(_edition) ? _edition : items.first['id'].toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Mushaf.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Mushaf.border, width: 0.6),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon:
              const Icon(Icons.expand_more, color: Mushaf.mutedForeground),
          items: items
              .map((r) => DropdownMenuItem(
                    value: r['id'].toString(),
                    child: Text(r['name'].toString(),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Mushaf.foreground)),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _edition = v ?? _edition),
        ),
      ),
    );
  }
}
