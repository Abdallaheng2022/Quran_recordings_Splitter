// editor.dart — محرر المقاطع.
// التشغيل: نحمّل الملف كاملًا مرة واحدة، وكل مقطع يُشغَّل بالقفز لبدايته
// (seek) والإيقاف تلقائيًا عند نهايته — أمتن من setClip. المؤشر يظهر دائمًا
// للمقطع النشط، يتحرك مع الصوت، وقابل للسحب للاستماع من أي موضع.
// الحدود مشتركة: نهاية مقطع = بداية التالي، فسحب حدٍّ يزيح جاره تلقائيًا.
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

class _EditorScreenState extends State<EditorScreen> with LocaleRebuild<EditorScreen> {
  final _player = AudioPlayer();
  late List<double> _edges; // edges[i] = بداية i = نهاية i-1
  int? _active;
  double _absPos = 0;
  bool _isPlaying = false;
  bool _dragging = false;
  bool _ready = false;
  bool _saving = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<bool>? _stSub;

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
      await _player.setFilePath(widget.audioPath);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
    _posSub = _player.positionStream.listen((d) {
      _absPos = d.inMilliseconds / 1000.0;
      if (_active != null && _isPlaying && !_dragging) {
        final end = _edges[_active! + 1];
        if (_absPos >= end) {
          _player.pause();
          _absPos = end;
        }
      }
      if (mounted && !_dragging) setState(() {});
    });
    _stSub = _player.playingStream.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
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

  Future<void> _play(int i, {double? fromAbs}) async {
    final start = _edges[i];
    final from = fromAbs ?? start;
    setState(() => _active = i);
    try {
      await _player.seek(Duration(milliseconds: (from * 1000).round()));
      await _player.play();
    } catch (_) {}
  }

  Future<void> _toggle(int i) async {
    if (_active == i && _isPlaying) {
      await _player.pause();
      return;
    }
    final resume =
        _active == i && _absPos > _edges[i] && _absPos < _edges[i + 1];
    await _play(i, fromAbs: resume ? _absPos : _edges[i]);
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
    final isActive = _active == i;
    final playingThis = isActive && _isPlaying;
    final lo = i == 0 ? 0.0 : _edges[i - 1] + _minGap;
    final hi = i == _n - 1 ? widget.duration : _edges[i + 2] - _minGap;
    final label = i < widget.labels.length && widget.labels[i].isNotEmpty
        ? widget.labels[i]
        : '${i + 1}';
    final rel = (_absPos - start).clamp(0.0, (end - start)).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                onTap: _ready ? () => _toggle(i) : null,
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: playingThis
                        ? Mushaf.primary
                        : Mushaf.primary.withOpacity(.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(playingThis ? Icons.pause : Icons.play_arrow,
                      color: playingThis
                          ? Mushaf.primaryForeground
                          : Mushaf.primary),
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
          Row(
            children: [
              SizedBox(
                width: 42,
                child: Text(_fmt(start + rel),
                    style: const TextStyle(
                        fontSize: 11, color: Mushaf.mutedForeground)),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Mushaf.accent,
                    inactiveTrackColor: Mushaf.muted,
                    thumbColor: Mushaf.accent,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 7),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    min: 0,
                    max: (end - start).clamp(0.1, double.infinity).toDouble(),
                    value: rel,
                    onChangeStart: (_) {
                      _dragging = true;
                      setState(() => _active = i);
                    },
                    onChanged: (v) => setState(() => _absPos = start + v),
                    onChangeEnd: (v) async {
                      _dragging = false;
                      await _play(i, fromAbs: start + v);
                    },
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 42),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: Mushaf.primary,
                    inactiveTrackColor: Mushaf.muted,
                    rangeThumbShape: const RoundRangeSliderThumbShape(
                        enabledThumbRadius: 8),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 14),
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
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
