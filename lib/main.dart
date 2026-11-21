import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'oyen.dart';

const _oren = Color(0xFFFF8A2B);
const _bg = Color(0xFF12121A);

void main() => runApp(const OyenApp());

class OyenApp extends StatelessWidget {
  const OyenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Oyen',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _oren,
          secondary: _oren,
          surface: Color(0xFF1C1C26),
        ),
      ),
      home: const VoiceCatPage(),
    );
  }
}

class VoiceTurn {
  final String userSaid;
  final String oyenReply;
  final bool isError;
  VoiceTurn({required this.userSaid, required this.oyenReply, this.isError = false});
}

class VoiceCatPage extends StatefulWidget {
  const VoiceCatPage({super.key});

  @override
  State<VoiceCatPage> createState() => _VoiceCatPageState();
}

class _VoiceCatPageState extends State<VoiceCatPage> with TickerProviderStateMixin {
  late final AnimationController _tomCtrl;
  late final AnimationController _bobCtrl;
  late final AnimationController _pulseCtrl;

  final _tts = FlutterTts();
  final _speech = SpeechToText();
  final _history = <VoiceTurn>[];

  String _base = kDefaultBaseUrl;
  String _model = kDefaultModel;
  String _level = 'pedas';
  String _liveTranscript = '';
  String _lastReply = 'Pencet mic terus ngomong. Jangan lembek.';
  bool _lastIsError = false;
  bool _ttsOn = true;
  bool _thinking = false;
  bool _listening = false;
  bool _siap = false;

  @override
  void initState() {
    super.initState();
    _bobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _tomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);

    _tts.setLanguage('id-ID');
    _tts.setPitch(1.15);
    _tts.setSpeechRate(0.5);
    _muat();
  }

  Future<void> _muat() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _base = p.getString('base') ?? kDefaultBaseUrl;
      _model = p.getString('model') ?? kDefaultModel;
      _level = p.getString('level') ?? 'pedas';
      _ttsOn = p.getBool('tts') ?? true;
      _siap = true;
    });
  }

  @override
  void dispose() {
    _bobCtrl.dispose();
    _tomCtrl.dispose();
    _pulseCtrl.dispose();
    _tts.stop();
    _speech.stop();
    super.dispose();
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(t),
        backgroundColor: const Color(0xFF3A1C1C),
      ),
    );
  }

  Future<void> _kirimSuara(String spokenText) async {
    final clean = spokenText.trim();
    if (clean.isEmpty || _thinking) return;

    setState(() {
      _thinking = true;
      _lastIsError = false;
      _liveTranscript = clean;
    });

    try {
      final hist = >[
        {'role': 'system', 'content': oyenSystemPrompt(_level)},
      ];
      final start = _history.length > 6 ? _history.length - 6 : 0;
      for (int i = start; i < _history.length; i++) {
        if (_history[i].isError) continue;
        hist.add({'role': 'user', 'content': _history[i].userSaid});
        hist.add({'role': 'assistant', 'content': _history[i].oyenReply});
      }
      hist.add({'role': 'user', 'content': clean});

      final reply = await OyenApi(key: '', baseUrl: _base, model: _model).reply(hist);
      if (!mounted) return;

      setState(() {
        _lastReply = reply;
        _lastIsError = false;
        _history.add(VoiceTurn(userSaid: clean, oyenReply: reply));
      });

      if (_ttsOn) {
        await _bicara(reply);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastReply = '$e';
        _lastIsError = true;
        _history.add(VoiceTurn(userSaid: clean, oyenReply: '$e', isError: true));
      });
    } finally {
      if (mounted) {
        setState(() => _thinking = false);
      }
    }
  }

  Future<void> _bicara(String t) async {
    final bersih = t.replaceAll(RegExp(r'[^a-zA-Z0-9\s.,!?-]'), ' ').trim();
    if (bersih.isEmpty) return;
    await _tts.stop();
    await _tts.speak(bersih);
  }

  Future<void> _toggleMic() async {
    if (_thinking) return;

    if (_listening) {
      await _speech.stop();
      final finalText = _liveTranscript.trim();
      if (mounted) {
        setState(() => _listening = false);
      }
      if (finalText.isNotEmpty) {
        await _kirimSuara(finalText);
      }
      return;
    }

    await _tts.stop();

    bool ok = false;
    try {
      ok = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => _listening = false);
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _listening = false);
          }
        },
      );
    } catch (_) {
      ok = false;
    }

    if (!ok) {
      _snack('Mic gak bisa dipakai. Cek izin mikrofon di HP.');
      return;
    }

    if (!mounted) return;
    setState(() {
      _listening = true;
      _liveTranscript = '';
    });

    await _speech.listen(
      onResult: (r) async {
        if (!mounted) return;
        setState(() => _liveTranscript = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          if (r.recognizedWords.trim().isNotEmpty) {
            await _kirimSuara(r.recognizedWords);
          }
        }
      },
      localeId: 'id_ID',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  void _bukaSetting() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _SettingSheet(
        awalBase: _base,
        awalModel: _model,
        awalLevel: _level,
        awalTts: _ttsOn,
        onSimpan: (b, m, l, t) async {
          final p = await SharedPreferences.getInstance();
          await p.setString('base', b);
          await p.setString('model', m);
          await p.setString('level', l);
          await p.setBool('tts', t);
          if (!mounted) return;
          setState(() {
            _base = b;
            _model = m;
            _level = l;
            _ttsOn = t;
          });
        },
        onHapus: () => setState(() {
          _history.clear();
          _liveTranscript = '';
          _lastReply = 'Riwayat dibersihin. Pencet mic kalau mau mulai lagi.';
          _lastIsError = false;
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_siap) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: _oren)),
      );
    }

    final statusText = _listening
        ? 'kuping oren aktif • lagi dengerin lu...'
        : (_thinking ? 'lagi mikirin jawaban toxic...' : 'kucing oren • $_level');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF2A1A0C), _bg],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                child: Row(
                  children: [
                    const Text(
                      'Oyen',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFD3A8),
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        statusText,
                        style: TextStyle(fontSize: 12.5, color: _oren.withValues(alpha: 0.9)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _bukaSetting,
                      icon: const Icon(Icons.tune_rounded, color: Color(0xFFFFD3A8)),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _TomOyenAvatar(
                        size: 165,
                        bobAnim: _bobCtrl,
                        tomAnim: _tomCtrl,
                        listening: _listening,
                        thinking: _thinking,
                        level: _level,
                      ),
                      const SizedBox(height: 22),
                      if (_listening || _liveTranscript.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF22222E),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _oren.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            _liveTranscript.isEmpty ? 'Ngomong aja...' : '"$_liveTranscript"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFFFFD3A8),
                            ),
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _lastIsError ? const Color(0xFF3A1C1C) : const Color(0xFF1D1D28),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: _thinking
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: _oren),
                                ),
                              )
                            : Text(
                                _lastReply,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 15.5,
                                  height: 1.45,
                                  color: _lastIsError
                                      ? const Color(0xFFFF9C9C)
                                      : const Color(0xFFEDEDF2),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 28, top: 8),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) {
                        final scale = _listening ? (1.0 + _pulseCtrl.value * 0.12) : 1.0;
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: GestureDetector(
                        onTap: _toggleMic,
                        child: Container(
                          width: 84,
                          height: 84,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _listening
                                ? const LinearGradient(colors: [Color(0xFFFF4B4B), Color(0xFFC62018)])
                                : const LinearGradient(colors: [Color(0xFFFF9A45), Color(0xFFE86A00)]),
                            boxShadow: [
                              BoxShadow(
                                color: (_listening ? const Color(0xFFE0322A) : _oren)
                                    .withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _listening ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 38,
                            color: _listening ? Colors.white : const Color(0xFF17130E),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _listening ? 'Ketuk lagi buat kirim' : 'Ketuk mic buat ngomong',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF9C9CAC)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TomOyenAvatar extends StatelessWidget {
  final double size;
  final Animation<double> bobAnim;
  final Animation<double> tomAnim;
  final bool listening;
  final bool thinking;
  final String level;

  const _TomOyenAvatar({
    required this.size,
    required this.bobAnim,
    required this.tomAnim,
    required this.listening,
    required this.thinking,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final active = listening || thinking;

    return AnimatedBuilder(
      animation: Listenable.merge([bobAnim, tomAnim]),
      builder: (context, _) {
        final t = bobAnim.value;
        final cycle = tomAnim.value;

        final blinkPhase = (cycle * 3.0) % 1.0;
        final isBlinking = blinkPhase > 0.92;

        final lookX = listening
            ? math.sin(cycle * math.pi * 4) * 0.7
            : (thinking ? math.cos(cycle * math.pi * 2) * 0.8 : math.sin(cycle * math.pi) * 0.35);

        final headTilt = (active ? 0.14 : 0.05) * math.sin(cycle * math.pi * 2) + (lookX * 0.08);
        final bounceY = -(active ? 6.0 : 3.0) * t;
        final earWiggle = math.sin(cycle * math.pi * 6) * (active ? 0.18 : 0.05);

        final accentColor = level == 'neraka'
            ? const Color(0xFFFF4D3A)
            : (level == 'pedas' ? _oren : const Color(0xFFFFB469));

        return Transform.translate(
          offset: Offset(lookX * 4.0, bounceY),
          child: Transform.rotate(
            angle: headTilt,
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: -size * 0.06,
                    left: size * 0.12,
                    child: Transform.rotate(
                      angle: -0.22 - earWiggle,
                      child: _EarOyen(size: size * 0.28, color: accentColor),
                    ),
                  ),
                  Positioned(
                    top: -size * 0.06,
                    right: size * 0.12,
                    child: Transform.rotate(
                      angle: 0.22 + earWiggle,
                      child: _EarOyen(size: size * 0.28, color: accentColor),
                    ),
                  ),
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF22222E),
                      border: Border.all(color: accentColor.withValues(alpha: 0.85), width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: accentColor.withValues(alpha: active ? 0.38 : 0.18),
                          blurRadius: active ? 18 : 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.asset(
                            'assets/oyen.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Icon(Icons.pets_rounded, size: size * 0.5, color: accentColor),
                            ),
                          ),
                          CustomPaint(
                            painter: _TomExpressionPainter(
                              blink: isBlinking,
                              lookX: lookX,
                              isActive: active,
                              cycle: cycle,
                              accent: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EarOyen extends StatelessWidget {
  final double size;
  final Color color;
  const _EarOyen({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF2A1A0C),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(size * 0.7),
          topRight: Radius.circular(size * 0.7),
          bottomLeft: Radius.circular(size * 0.2),
          bottomRight: Radius.circular(size * 0.2),
        ),
        border: Border.all(color: color.withValues(alpha: 0.85), width: 2),
      ),
    );
  }
}

class _TomExpressionPainter extends CustomPainter {
  final bool blink;
  final double lookX;
  final bool isActive;
  final double cycle;
  final Color accent;

  _TomExpressionPainter({
    required this.blink,
    required this.lookX,
    required this.isActive,
    required this.cycle,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final browPaint = Paint()
      ..color = const Color(0xFFFFE0BE).withValues(alpha: 0.88)
      ..strokeWidth = math.max(1.8, w * 0.032)
      ..strokeCap = StrokeCap.round;

    final browLift = isActive ? math.sin(cycle * math.pi * 4) * h * 0.025 : 0.0;
    final shiftX = lookX * w * 0.06;

    canvas.drawLine(
      Offset(w * 0.24 + shiftX, h * 0.24 - browLift),
      Offset(w * 0.44 + shiftX, h * 0.28 - browLift),
      browPaint,
    );
    canvas.drawLine(
      Offset(w * 0.76 + shiftX, h * 0.24 - browLift),
      Offset(w * 0.56 + shiftX, h * 0.28 - browLift),
      browPaint,
    );

    if (blink) {
      final lidPaint = Paint()
        ..color = accent
        ..strokeWidth = math.max(2.0, w * 0.035)
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(w * 0.26 + shiftX, h * 0.35),
        Offset(w * 0.43 + shiftX, h * 0.35),
        lidPaint,
      );
      canvas.drawLine(
        Offset(w * 0.57 + shiftX, h * 0.35),
        Offset(w * 0.74 + shiftX, h * 0.35),
        lidPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TomExpressionPainter old) {
    return old.blink != blink ||
        old.lookX != lookX ||
        old.isActive != isActive ||
        old.cycle != cycle ||
        old.accent != accent;
  }
}

class _SettingSheet extends StatefulWidget {
  final String awalBase;
  final String awalModel;
  final String awalLevel;
  final bool awalTts;
  final void Function(String, String, String, bool) onSimpan;
  final VoidCallback onHapus;

  const _SettingSheet({
    required this.awalBase,
    required this.awalModel,
    required this.awalLevel,
    required this.awalTts,
    required this.onSimpan,
    required this.onHapus,
  });

  @override
  State<_SettingSheet> createState() => _SettingSheetState();
}

class _SettingSheet
