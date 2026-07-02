// home.dart — الشاشة الرئيسية بهوية «المصحف» (مطابقة لتصميم نسخة Expo).
// المنطق كما هو: اختيار ملف → تحليل → حفظ zip. تغيّر الشكل فقط.
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../api.dart';
import '../theme.dart';
import 'login.dart';
import 'paywall.dart';

class HomeScreen extends StatefulWidget {
  final Api api;
  const HomeScreen({super.key, required this.api});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _me;
  String? _fileName;
  Uint8List? _fileBytes;

  final _range = TextEditingController(text: 'surah:36');
  String _level = 'ayah';
  String _method = 'auto';
  String _edition = 'ar.alafasy';
  List<Map<String, dynamic>> _reciters = [];

  bool _busy = false;
  String? _status;
  String? _savedPath;

  final _levels = const {
    'ayah': 'آيات',
    'rub': 'أرباع',
    'hizb': 'أحزاب',
    'juz': 'أجزاء',
    'page': 'صفحات',
  };

  @override
  void initState() {
    super.initState();
    _refreshMe();
    _loadReciters();
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

  Future<void> _refreshMe() async {
    final r = await widget.api.me();
    if (r.ok && r.data['ok'] == true && mounted) {
      setState(() => _me = r.data);
    }
  }

  bool get _isPaid => _me?['tier'] == 'paid';

  Future<void> _pickAudio() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'ogg', 'aac', 'opus'],
      withData: true,
    );
    if (res != null && res.files.isNotEmpty) {
      final f = res.files.first;
      setState(() {
        _fileName = f.name;
        _fileBytes = f.bytes;
        _savedPath = null;
        _status = null;
      });
    }
  }

  Future<void> _run() async {
    if (_fileBytes == null) {
      setState(() => _status = 'اختر ملف صوت أولًا.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'جارٍ التحليل والتقسيم...';
      _savedPath = null;
    });

    final analyze = await widget.api.analyze(
      audio: _fileBytes!,
      name: _fileName ?? 'audio.mp3',
      range: _range.text.trim().isEmpty ? 'all' : _range.text.trim(),
      level: _level,
      method: _method == 'auto' ? null : _method,
      edition: _edition,
    );

    if (!analyze.ok) {
      setState(() => _busy = false);
      _handleError(analyze);
      return;
    }

    if (analyze.data['downgraded'] == true && analyze.data['upsell'] != null) {
      _snack(analyze.data['upsell'].toString());
    }

    final sessionToken = analyze.data['token']?.toString();
    final bounds = analyze.data['bounds'] as List?;
    if (sessionToken == null || bounds == null) {
      setState(() {
        _busy = false;
        _status = 'ردّ غير متوقّع من السيرفر.';
      });
      return;
    }

    setState(() => _status = 'جارٍ تجهيز الملف...');
    final save = await widget.api.save(sessionToken, bounds);
    if (!save.ok || save.bytes == null) {
      setState(() => _busy = false);
      _handleError(save);
      return;
    }

    final dir = await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = '${dir.path}/quran_split_$stamp.zip';
    await File(path).writeAsBytes(save.bytes!);

    await _refreshMe();
    setState(() {
      _busy = false;
      _savedPath = path;
      _status = 'تمّ! حُفظ الملف بنجاح.';
    });
  }

  void _handleError(ApiResult r) {
    final needSub = r.data['need_subscription'] == true;
    final msg = r.data['error']?.toString() ?? 'حدث خطأ (${r.status}).';
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

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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
                  _sectionLabel('المدى والمستوى'),
                  _settingsCard(),
                  _sectionLabel('طريقة التقسيم'),
                  _methodCard(
                    id: 'auto',
                    icon: Icons.auto_awesome,
                    title: 'تلقائي',
                    subtitle: 'يختار الأنسب حسب مستواك',
                  ),
                  const SizedBox(height: 10),
                  _methodCard(
                    id: 'silence',
                    icon: Icons.graphic_eq,
                    title: 'السكتات',
                    subtitle: 'سريع — يقسّم عند الوقفات',
                  ),
                  const SizedBox(height: 10),
                  _methodCard(
                    id: 'refdtw',
                    icon: Icons.track_changes,
                    title: 'المحاذاة بالمرجع',
                    subtitle: 'دقيق — للتلاوات المتّصلة',
                    locked: !_isPaid,
                  ),
                  if (_method == 'refdtw' ||
                      (_method == 'auto' && _isPaid)) ...[
                    _sectionLabel('القارئ المرجعي'),
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
                    label: Text(_busy ? 'جارٍ المعالجة...' : 'قسّم وحمّل'),
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
                  if (_savedPath != null) _savedCard(),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Mushaf.border, width: 0.6)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // شريحة الحالة (المجاني/المدفوع) — pill بحدود
              GestureDetector(
                onTap: _isPaid ? null : () => _openPaywall(),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: _isPaid ? Mushaf.accent.withOpacity(.15) : Mushaf.muted,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: _isPaid ? Mushaf.accent : Mushaf.border),
                  ),
                  child: Text(
                    _isPaid
                        ? 'المستوى المدفوع'
                        : (jobsLeft != null
                            ? 'مجاني · متبقٍ $jobsLeft'
                            : 'المستوى المجاني'),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _isPaid
                            ? Mushaf.accentForeground
                            : Mushaf.secondaryForeground),
                  ),
                ),
              ),
              IconButton(
                onPressed: _logout,
                icon: const Icon(Icons.logout,
                    size: 20, color: Mushaf.mutedForeground),
                tooltip: 'خروج',
              ),
            ],
          ),
          const Text('مُقسّم التلاوة',
              style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Mushaf.primary)),
          const SizedBox(height: 4),
          const Text('قسّم تلاوتك إلى مقاطع منفصلة',
              style:
                  TextStyle(fontSize: 13, color: Mushaf.mutedForeground)),
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
          padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
          child: Column(
            children: [
              Icon(picked ? Icons.audiotrack : Icons.cloud_upload_outlined,
                  size: 34,
                  color: picked ? Mushaf.primary : Mushaf.mutedForeground),
              const SizedBox(height: 6),
              Text(
                picked ? _fileName! : 'اختر ملف الصوت',
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
                picked ? 'اضغط لاختيار ملف آخر' : 'mp3 · m4a · wav · ogg',
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

  Widget _settingsCard() {
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
          TextField(
            controller: _range,
            decoration: const InputDecoration(
              labelText: 'المدى',
              hintText: 'surah:36 أو juz:30 أو all',
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _levels.entries.map((e) {
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
                  side: BorderSide(
                      color: selected ? Mushaf.primary : Mushaf.border),
                ),
                showCheckmark: false,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _methodCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    bool locked = false,
  }) {
    final selected = _method == id;
    return GestureDetector(
      onTap: () {
        if (locked) {
          _openPaywall(reason: 'الطريقة الدقيقة متاحة في المستوى المدفوع.');
          return;
        }
        setState(() => _method = id);
      },
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
                  color: selected ? Mushaf.primaryForeground : Mushaf.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Mushaf.foreground)),
                      if (locked) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Mushaf.accent.withOpacity(.18),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text('مدفوع',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Mushaf.accentForeground)),
                        ),
                      ],
                    ],
                  ),
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
    final value = ids.contains(_edition) ? _edition : items.first['id'].toString();
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
          icon: const Icon(Icons.expand_more, color: Mushaf.mutedForeground),
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

  Widget _savedCard() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Mushaf.primary.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Mushaf.primary.withOpacity(.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_zip, color: Mushaf.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ملف المقاطع (zip)',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Mushaf.foreground)),
                Text(_savedPath!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: Mushaf.mutedForeground)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
