// editor.dart — محرر المقاطع (مكتبة audioplayers).
// نحمّل الملف مرة واحدة، وكل مقطع يُشغَّل بالقفز لبدايته (seek + resume)
// والإيقاف تلقائيًا عند نهايته. المؤشر يظهر دائمًا للمقطع النشط، يتحرك مع
// الصوت، وقابل للسحب للاستماع من أي موضع. الحدود مشتركة: سحب حدٍّ يزيح جاره.
import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../l10n.dart';
import '../theme.dart';

class EditorScreen extends StatefulWidget {
  final Api api;
  final String sessionToken;
  final String audioPath;
  final double duration;
  final List<List<double>> initialBounds;
  final List<String> labels;
  const EditorScreen({
    super.key,
    required this.api,
    required this.sessionToken,
    required this.audioPath,
    required this.duration,
    required this.initialBounds,
    required this.labels,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen>
    with LocaleRebuild<EditorScreen> {
  final AudioPlayer _player = AudioPlayer();
  late List<double> _edges;
  int? _active;
  double _absPos = 0;
  bool _isPlaying = false;
  bool _dragging = false;
  bool _ready = false;
  String? _loadError;
  bool _saving = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stSub;

  static const _minGap = 0.3;

  int get _n => _edges.length - 1;

  @override
  void initState() {
    super.initState();
    _edges = [
      widget.initialBounds.first[0],
      for (final b in widget.initialBounds) b[1],
    ];
    _init();
  }

  Future<void> _init() async {
    try {
      final f = File(widget.audioPath);
      if (!await f.exists() || await f.length() == 0) {
        _loadError = t('playbackError');
      } else {
        await _player.setReleaseMode(ReleaseMode.stop);
        await _player.setVolume(1.0);
        // مهم لأندرويد: وجّه الصوت لمسار الوسائط المسموع (لا سمّاعة المكالمات)
        try {
          await _player.setAudioContext(AudioContext(
            android: AudioContextAndroid(
              isSpeakerphoneOn: false,
              stayAwake: true,
              contentType: AndroidContentType.music,
              usageType: AndroidUsageType.media,
              audioFocus: AndroidAudioFocus.gain,
            ),
          ));
        } catch (_) {}
        _ready = true;
      }
    } catch (e) {
      _ready = false;
      _loadError = t('playbackError');
    }

    _posSub = _player.onPositionChanged.listen((d) {
      if (_dragging) return;
      _absPos = d.inMilliseconds / 1000.0;
      if (_active != null && _isPlaying) {
        final end = _edges[_active! + 1];
        if (_absPos >= end) {
          _player.pause();
          _absPos = end;
        }
      }
      if (mounted) setState(() {});
    });
    _stSub = _player.onPlayerStateChanged.listen((st) {
      final playing = st == PlayerState.playing;
      if (mounted) setState(() => _isPlaying = playing);
    });

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  bool _started = false; // هل بدأ تحميل المصدر مرة؟

  Future<void> _play(int i, {double? fromAbs}) async {
    final from = fromAbs ?? _edges[i];
    setState(() {
      _active = i;
      _absPos = from;
      _loadError = null;
    });
    try {
      if (!_started) {
        // play(source) يجهّز الملف ويبدأ التشغيل معًا (موثوق على أندرويد)
        await _player.setVolume(1.0);
        await _player.play(DeviceFileSource(widget.audioPath), volume: 1.0);
        _started = true;
      } else {
        await _player.resume();
      }
      if (from > 0.05) {
        await _player.seek(Duration(milliseconds: (from * 1000).round()));
      }
    } catch (e) {
      setState(() => _loadError = t('playbackError'));
    }
  }

  Future<void> _toggle(int i) async {
    if (_active == i && _isPlaying) {
      await _player.pause();
      return;
    }
    final resume =
        _active == i && _absPos > _edges[i] && _absPos < _edges[i + 1] - 0.05;
    await _play(i, fromAbs: resume ? _absPos : _edges[i]);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _player.pause();
    final bounds = [
      for (var i = 0; i < _n; i++)
        [
          double.parse(_edges[i].toStringAsFixed(3)),
          double.parse(_edges[i + 1].toStringAsFixed(3)),
        ]
    ];
    final r = await widget.api.save(widget.sessionToken, bounds);
    if (!mounted) return;
    if (!r.ok || r.bytes == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(r.data['error']?.toString() ?? t('unexpected'))));
      return;
    }
    String? path;
    try {
      path = await FilePicker.platform.saveFile(
        dialogTitle: t('chooseSaveLocation'),
        fileName: 'quran_split.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: r.bytes!,
      );
    } catch (_) {}
    setState(() => _saving = false);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text(path == null ? t('saveCanceled') : '${t('savedTo')} $path')));
    if (path != null) Navigator.of(context).pop(true);
  }

  String _fmt(double s) {
    final m = s ~/ 60;
    final sec = (s - m * 60).toStringAsFixed(1);
    return '$m:${sec.padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Mushaf.background,
        elevation: 0,
        foregroundColor: Mushaf.foreground,
        title: Text(t('editorTitle'),
            style: const TextStyle(fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(t('editorHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 13, color: Mushaf.mutedForeground)),
          ),
          if (_loadError != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Mushaf.destructive.withOpacity(.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12.5, color: Mushaf.destructive)),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              itemCount: _n,
              itemBuilder: (_, i) => _segmentCard(i),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Mushaf.primaryForeground))
                      : const Icon(Icons.save_alt),
                  label: Text(_saving ? t('saving') : t('saveZip')),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // تنسيق دقيق بأعشار الثانية (مثل fmtPrecise في Expo)
  String _fmtP(double s) {
    final ms = (s * 1000).round();
    final m = ms ~/ 60000;
    final wholeSec = (ms % 60000) ~/ 1000;
    final milli = ms % 1000;
    return '$m:${wholeSec.toString().padLeft(2, '0')}.'
        '${milli.toString().padLeft(3, '0')}';
  }

  void _nudge(int i, bool isStart, double delta) {
    setState(() {
      if (isStart) {
        final lo = i == 0 ? 0.0 : _edges[i - 1] + _minGap;
        _edges[i] = (_edges[i] + delta).clamp(lo, _edges[i + 1] - _minGap);
      } else {
        final hi = i == _n - 1 ? widget.duration : _edges[i + 2] - _minGap;
        _edges[i + 1] = (_edges[i + 1] + delta).clamp(_edges[i] + _minGap, hi);
      }
    });
  }

  Widget _adjust(String title, String value, VoidCallback onMinus,
      VoidCallback onPlus, VoidCallback onEdit) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Mushaf.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _stepBtn(Icons.remove, onMinus),
            Expanded(
              // الضغط على القيمة يفتح إدخالًا يدويًا بالكيبورد
              child: InkWell(
                onTap: onEdit,
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 11, color: Mushaf.mutedForeground)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(value,
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Mushaf.foreground)),
                        const SizedBox(width: 3),
                        const Icon(Icons.edit,
                            size: 11, color: Mushaf.mutedForeground),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _stepBtn(Icons.add, onPlus),
          ],
        ),
      ),
    );
  }

  /// يحوّل نصًّا مثل "2:05.1" أو "125.1" إلى ثوانٍ. يرجع null إن كان غير صالح.
  double? _parseTime(String input) {
    final txt = input.trim();
    if (txt.isEmpty) return null;
    final parts = txt.split(':');
    try {
      if (parts.length == 2) {
        return int.parse(parts[0]) * 60 + double.parse(parts[1]);
      } else if (parts.length == 1) {
        return double.parse(parts[0]);
      }
    } catch (_) {}
    return null;
  }

  /// نافذة إدخال الوقت يدويًا بالكيبورد (دقائق:ثواني.أعشار).
  Future<void> _editTime(
      String title, double current, double lo, double hi,
      void Function(double) onSet) async {
    final ctrl = TextEditingController(text: _fmtP(current));
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Mushaf.card,
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: Mushaf.foreground)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.text,
              decoration: const InputDecoration(hintText: '0:00.0'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(t('timeFormatHint'),
                style: const TextStyle(
                    fontSize: 12, color: Mushaf.mutedForeground)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final v = _parseTime(ctrl.text);
              Navigator.pop(ctx, v);
            },
            child: Text(t('save')),
          ),
        ],
      ),
    );
    if (result != null) {
      onSet(result.clamp(lo, hi).toDouble());
    }
  }

  Widget _stepBtn(IconData icon, VoidCallback onTap) =>
      _HoldButton(icon: icon, onStep: onTap);

  Widget _segmentCard(int i) {
    final start = _edges[i], end = _edges[i + 1];
    final isActive = _active == i;
    final playingThis = isActive && _isPlaying;
    final lo = i == 0 ? 0.0 : _edges[i - 1] + _minGap;
    final hi = i == _n - 1 ? widget.duration : _edges[i + 2] - _minGap;
    final label = i < widget.labels.length && widget.labels[i].isNotEmpty
        ? widget.labels[i]
        : '${i + 1}';
    final span = (end - start).clamp(0.1, double.infinity).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Mushaf.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Mushaf.primary : Mushaf.border,
          width: isActive ? 1.6 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── العنوان: زر تشغيل + اسم المقطع + (البداية ← النهاية · المدة) ──
          Row(
            children: [
              InkWell(
                onTap: _ready ? () => _toggle(i) : null,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: playingThis ? Mushaf.accent : Mushaf.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(playingThis ? Icons.pause : Icons.play_arrow,
                      color: playingThis
                          ? Mushaf.accentForeground
                          : Mushaf.primaryForeground),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. $label',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Mushaf.foreground)),
                    const SizedBox(height: 2),
                    Text(
                      '${_fmtP(start)} ← ${_fmtP(end)}  ·  '
                      '${span.toStringAsFixed(1)} ${t('secondsShort')}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Mushaf.mutedForeground),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // ── الشريط يتبع اتجاه لغة التطبيق (RTL عربي / LTR إنجليزي) ──
          Column(
            children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Mushaf.primary,
                    inactiveTrackColor: Mushaf.muted,
                    rangeThumbShape: const RoundRangeSliderThumbShape(
                        enabledThumbRadius: 9),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                    trackHeight: 4,
                  ),
                  child: RangeSlider(
                    min: lo,
                    max: hi,
                    values: RangeValues(
                      start.clamp(lo, hi - _minGap),
                      end.clamp(lo + _minGap, hi),
                    ),
                    onChanged: (v) {
                      setState(() {
                        _edges[i] = v.start;
                        _edges[i + 1] =
                            v.end.clamp(v.start + _minGap, hi).toDouble();
                      });
                    },
                  ),
                ),
                // مؤشر التشغيل (ذهبي) — على نفس مقياس المحدّدات [lo, hi] تمامًا
                // مثل Expo، فيتحرك بين مقبضَي البداية والنهاية بالضبط. مقيّد إلى
                // [start, end] فلا يخرج عن حدود المقطع. المسار شفاف: تظهر النقطة فقط.
                if (isActive)
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      thumbColor: Mushaf.accent,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      trackHeight: 2,
                    ),
                    child: Slider(
                      min: lo,
                      max: hi,
                      value: _absPos.clamp(start, end).toDouble(),
                      onChangeStart: (_) {
                        _dragging = true;
                        setState(() => _active = i);
                      },
                      onChanged: (v) =>
                          setState(() => _absPos = v.clamp(start, end).toDouble()),
                      onChangeEnd: (v) async {
                        _dragging = false;
                        await _play(i, fromAbs: v.clamp(start, end).toDouble());
                      },
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 6),
          // ── صفّان محدّدان بالاسم: البداية / النهاية (يشيلان الغموض) ──
          Row(
            children: [
              _adjust(
                t('startLabel'),
                _fmtP(start),
                () => _nudge(i, true, -0.1),
                () => _nudge(i, true, 0.1),
                () => _editTime(
                  t('startLabel'),
                  start,
                  i == 0 ? 0.0 : _edges[i - 1] + _minGap,
                  _edges[i + 1] - _minGap,
                  (v) => setState(() => _edges[i] = v),
                ),
              ),
              _adjust(
                t('endLabel'),
                _fmtP(end),
                () => _nudge(i, false, -0.1),
                () => _nudge(i, false, 0.1),
                () => _editTime(
                  t('endLabel'),
                  end,
                  _edges[i] + _minGap,
                  i == _n - 1 ? widget.duration : _edges[i + 2] - _minGap,
                  (v) => setState(() => _edges[i + 1] = v),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


/// زر ضغط-مطوّل موثوق: يبدأ تكرارًا متسارعًا عند الضغط المطوّل ويوقفه بأمان
/// عند الرفع/الإلغاء/التخلص — يحل مشكلة "الاستمرار في التحرك بعد رفع الإصبع".
class _HoldButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStep;
  const _HoldButton({required this.icon, required this.onStep});

  @override
  State<_HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<_HoldButton> {
  Timer? _timer;

  void _startHold() {
    _stopHold();
    widget.onStep(); // خطوة فورية عند بدء الضغط
    _timer = Timer.periodic(
        const Duration(milliseconds: 120), (_) => widget.onStep());
  }

  void _stopHold() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopHold(); // ضمان الإلغاء دائمًا (يمنع الاستمرار/التعليق)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onStep,
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _stopHold(),
      onLongPressCancel: _stopHold,
      onTapCancel: _stopHold,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(widget.icon, size: 20, color: Mushaf.foreground),
      ),
    );
  }
}
