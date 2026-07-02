// editor.dart — محرر المقاطع: اسمع كل مقطع، حرّك الحدود (المقاطع المتجاورة
// تتأثر ببعضها تلقائيًا لأن نهاية مقطع هي بداية التالي)، ومؤشر تشغيل متحرك
// قابل للسحب داخل المقطع. ثم احفظ في المكان الذي تختاره.
import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../api.dart';
import '../l10n.dart';
import '../theme.dart';

class EditorScreen extends StatefulWidget {
  final Api api;
  final String sessionToken;
  final String audioPath; // نسخة محلية من الملف للتشغيل
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

class _EditorScreenState extends State<EditorScreen> {
  final _player = AudioPlayer();
  // الحدود المشتركة: edges[i] = بداية المقطع i = نهاية المقطع i-1.
  late List<double> _edges;
  int? _playing; // فهرس المقطع قيد التشغيل
  double _pos = 0; // موضع التشغيل داخل المقطع (ثوانٍ نسبية)
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<PlayerState>? _stateSub;
  bool _saving = false;
  bool _dragging = false;

  static const _minGap = 0.3; // أقل طول مسموح للمقطع (ثوانٍ)

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
      await _player.setFilePath(widget.audioPath);
    } catch (_) {}
    _posSub = _player.positionStream.listen((d) {
      if (_playing != null && !_dragging && mounted) {
        setState(() => _pos = d.inMilliseconds / 1000.0);
      }
    });
    _stateSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() {
          _playing = null;
          _pos = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(int i) async {
    if (_playing == i && _player.playing) {
      await _player.pause();
      setState(() {});
      return;
    }
    await _playSegment(i, from: _playing == i ? _pos : 0);
  }

  Future<void> _playSegment(int i, {double from = 0}) async {
    final start = _edges[i], end = _edges[i + 1];
    try {
      await _player.setClip(
        start: Duration(milliseconds: (start * 1000).round()),
        end: Duration(milliseconds: (end * 1000).round()),
      );
      await _player
          .seek(Duration(milliseconds: (from.clamp(0, end - start) * 1000).round()));
      setState(() {
        _playing = i;
        _pos = from;
      });
      _player.play();
    } catch (_) {}
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await _player.pause();
    final bounds = [
      for (var i = 0; i < _n; i++)
        [
          double.parse(_edges[i].toStringAsFixed(2)),
          double.parse(_edges[i + 1].toStringAsFixed(2)),
        ]
    ];
    final r = await widget.api.save(widget.sessionToken, bounds);
    if (!mounted) return;
    if (!r.ok || r.bytes == null) {
      setState(() => _saving = false);
      final msg = r.data['error']?.toString() ?? t('unexpected');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    // (التعديل 6) المستخدم يختار مكان الحفظ عبر نافذة النظام
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
    if (path == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('saveCanceled'))));
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${t('savedTo')} $path')));
    Navigator.of(context).pop(true);
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

  Widget _segmentCard(int i) {
    final start = _edges[i], end = _edges[i + 1];
    final isActive = _playing == i;
    final isPlaying = isActive && _player.playing;
    // حدود السحب: لا يتجاوز حدود الجيران (فيتأثر الجار تلقائيًا عبر edges)
    final lo = i == 0 ? 0.0 : _edges[i - 1] + _minGap;
    final hi = i == _n - 1 ? widget.duration : _edges[i + 2] - _minGap;
    final label =
        i < widget.labels.length ? widget.labels[i] : '${i + 1}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      decoration: BoxDecoration(
        color: Mushaf.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? Mushaf.primary : Mushaf.border,
          width: isActive ? 1.4 : 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InkWell(
                onTap: () => _togglePlay(i),
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isPlaying
                        ? Mushaf.primary
                        : Mushaf.primary.withOpacity(.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    color: isPlaying
                        ? Mushaf.primaryForeground
                        : Mushaf.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${i + 1}. $label',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Mushaf.foreground)),
                    Text('${_fmt(start)} ← ${_fmt(end)}',
                        style: const TextStyle(
                            fontSize: 12, color: Mushaf.mutedForeground)),
                  ],
                ),
              ),
            ],
          ),
          // حدود المقطع (تحريكها يعدّل الجار تلقائيًا)
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: Mushaf.primary,
              inactiveTrackColor: Mushaf.muted,
              rangeThumbShape:
                  const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              trackHeight: 3,
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
              onChangeEnd: (_) {
                if (isActive) _playSegment(i); // أعد التشغيل بالحدود الجديدة
              },
            ),
          ),
          // مؤشر التشغيل المتحرك — قابل للسحب للاستماع من أي موضع
          if (isActive)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: Mushaf.accent,
                inactiveTrackColor: Mushaf.muted,
                thumbColor: Mushaf.accent,
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 12),
                trackHeight: 2,
              ),
              child: Slider(
                min: 0,
                max: (end - start).clamp(0.1, double.infinity),
                value: _pos.clamp(0, end - start).toDouble(),
                onChangeStart: (_) => _dragging = true,
                onChanged: (v) => setState(() => _pos = v),
                onChangeEnd: (v) async {
                  _dragging = false;
                  await _player
                      .seek(Duration(milliseconds: (v * 1000).round()));
                  if (!_player.playing) _player.play();
                },
              ),
            ),
        ],
      ),
    );
  }
}
