import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'oyen.dart';

const _oren = Color(0xFFFF8A2B);
const _bg = Color(0xFF0E0E14);
const _wajibLevel = 'pedas';

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
          surface: Color(0xFF1A1A24),
        ),
      ),
      home: const TomOyenPage(),
    );
  }
}

class TomOyenPage extends StatefulWidget {
  const TomOyenPage({super.key});

  @override
  State<TomOyenPage> createState() => _TomOyenPageState();
}

class _TomOyenPageState extends State<TomOyenPage> with TickerProviderStateMixin {
  late final AnimationController _tomCtrl;
  late final AnimationController _bobCtrl;
  late final AnimationController _pulseCtrl;

  final _tts = FlutterTts();
  final _speech = SpeechToText();
  final List> _memori = [];

  String _base = kDefaultBaseUrl;
  String _model = kDefaultModel;
  String _dengerinTeks = '';
  String _jawabanOyen = 'Pencet mic, ngomong. Jangan kebanyakan gaya.';
  bool _errorBalasan = false;
  bool _suaraAktif = true;
  bool _mikir = false;
  bool _dengerin = false;
  bool _siap = false;

  @override
  void initState() {
    super.initState();
    _bobCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);

    _tomCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    )..repeat(reverse: true);

    _tts.setLanguage('id-ID');
    _tts.setPitch(1.15);
    _tts.setSpeechRate(0.5);
    _muat();
  }

  Future<void> _muat() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _base = p.getString('base') ?? kDefaultBaseUrl;
      _model = p.getString('model') ?? kDefaultModel;
      _suaraAktif = p.getBool('tts') ?? true;
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

  Future<void> _jawabToxic(String ucapanUser) async {
    final bersih = ucapanUser.trim();
    if (bersih.isEmpty || _mikir) return;

    setState(() {
      _mikir = true;
      _errorBalasan = false;
      _dengerinTeks = bersih;
    });

    try {
      final List> hist = [
        {'role': 'system', 'content': oyenSystemPrompt(_wajibLevel)},
      ];
      final mulai = _memori.length > 6 ? _memori.length - 6 : 0;
      for (int i = mulai; i < _memori.length; i++) {
        hist.add(_memori[i]);
      }
      hist.add({'role': 'user', 'content': bersih});

      final balasan =
          await OyenApi(key: '', baseUrl: _base, model: _model).reply(hist);
      if (!mounted) return;

      setState(() {
        _jawabanOyen = balasan;
        _errorBalasan = false;
        _memori.add({'role': 'user', 'content': bersih});
        _memori.add({'role': 'assistant', 'content': balasan});
      });

      if (_suaraAktif) {
        await _bicara(balasan);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _jawabanOyen = '$e';
        _errorBalasan = true;
      });
    } finally {
      if (mounted) {
        setState(() => _mikir = false);
      }
    }
  }

  Future<void> _bicara(String teks) async {
    final bersih = teks.replaceAll(RegExp(r'[^a-zA-Z0-9\s.,!?-]'), ' ').trim();
    if (bersih.isEmpty) return;
    await _tts.stop();
    await _tts.speak(bersih);
  }

  Future<void> _tekanMic() async {
    if (_mikir) return;

    if (_dengerin) {
      await _speech.stop();
      final hasil = _dengerinTeks.trim();
      if (mounted) {
        setState(() => _dengerin = false);
      }
      if (hasil.isNotEmpty) {
        await _jawabToxic(hasil);
      }
      return;
    }

    await _tts.stop();

    bool ok = false;
    try {
      ok = await _speech.initialize(
        onStatus: (s) {
          if ((s == 'done' || s == 'notListening') && mounted) {
            setState(() => _dengerin = false);
          }
        },
        onError: (_) {
          if (mounted) {
            setState(() => _dengerin = false);
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
      _dengerin = true;
      _dengerinTeks = '';
    });

    await _speech.listen(
      onResult: (r) async {
        if (!mounted) return;
        setState(() => _dengerinTeks = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _dengerin = false);
          if (r.recognizedWords.trim().isNotEmpty) {
            await _jawabToxic(r.recognizedWords);
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
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _SettingSingkat(
        awalBase: _base,
        awalModel: _model,
        awalTts: _suaraAktif,
        onSimpan: (b, m, t) async {
          final p = await SharedPreferences.getInstance();
          await p.setString('base', b);
          await p.setString('model', m);
          await p.setBool('tts', t);
          if (!mounted) return;
          setState(() {
            _base = b;
            _model = m;
            _suaraAktif = t;
          });
        },
        onReset: () => setState(() {
          _memori.clear();
          _dengerinTeks = '';
          _jawabanOyen = 'Ulang dari awal. Buruan ngomong.';
          _errorBalasan = false;
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

    final labelStatus = _dengerin
        ? 'LAGI DENGERIN LU NGOMONG...'
        : (_mikir ? 'LAGI NYIAPIN JAWABAN PEDAS...' : 'OYEN • PEDAS');

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.05,
            colors: [Color(0xFF331B09), _bg],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(
                  children: [
                    const Text(
                      'OYEN',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFFFD3A8),
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        labelStatus,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: _oren.withValues(alpha: 0.9),
                        ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _TomOyenKarakter(
                        size: 210,
                        bobAnim: _bobCtrl,
                        tomAnim: _tomCtrl,
                        dengerin: _dengerin,
                        mikir: _mikir,
                      ),
                      const SizedBox(height: 22),
                      if (_dengerin || _dengerinTeks.isNotEmpty)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _oren.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            _dengerinTeks.isEmpty ? 'Ngomong aja...' : '"$_dengerinTeks"',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontStyle: FontStyle.italic,
                              color: Color(0xFFFFD3A8),
                            ),
                          ),
                        ),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        decoration: BoxDecoration(
                          color: _errorBalasan
                              ? const Color(0xFF3A1C1C)
                              : const Color(0xFF1A1A24).withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _errorBalasan
                                ? const Color(0xFFFF6B6B).withValues(alpha: 0.4)
                                : _oren.withValues(alpha: 0.22),
                          ),
                        ),
                        child: _mikir
                            ? const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: _oren),
                                ),
                              )
                            : Text(
                                _jawabanOyen,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  height: 1.45,
                                  fontWeight: FontWeight.w600,
                                  color: _errorBalasan
                                      ? const Color(0xFFFF9C9C)
                                      : const Color(0xFFF3F3F8),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 28, top: 6),
                child: Column(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) {
                        final scale = _dengerin ? (1.0 + _pulseCtrl.value * 0.14) : 1.0;
                        return Transform.scale(scale: scale, child: child);
                      },
                      child: GestureDetector(
                        onTap: _tekanMic,
                        child: Container(
                          width: 88,
                          height: 88,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: _dengerin
                                ? const LinearGradient(colors: [Color(0xFFFF4B4B), Color(0xFFC62018)])
                                : const LinearGradient(colors: [Color(0xFFFF9A45), Color(0xFFE86A00)]),
                            boxShadow: [
                              BoxShadow(
                                color: (_dengerin ? const Color(0xFFE0322A) : _oren)
                                    .withValues(alpha: 0.45),
                                blurRadius: 22,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Icon(
                            _dengerin ? Icons.stop_rounded : Icons.mic_rounded,
                            size: 40,
                            color: _dengerin ? Colors.white : const Color(0xFF17130E),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _dengerin ? 'Ketuk lagi buat ngirim suara' : 'Ketuk mic buat ngomong ke Oyen',
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

class _TomOyenKarakter extends StatelessWidget {
  final double size;
  final Animation<double> bobAnim;
  final Animation<double> tomAnim;
  final bool dengerin;
  final bool mikir;

  const _TomOyenKarakter({
    required this.size,
    required this.bobAnim,
    required this.tomAnim,
    required this.dengerin,
    required this.mikir,
  });

  @override
  Widget build(BuildContext context) {
    final aktif = dengerin || mikir;

    return AnimatedBuilder(
      animation: Listenable.merge([bobAnim, tomAnim]),
      builder: (context, _) {
        final bob = bobAnim.value;
        final cycle = tomAnim.value;

        final berkedip = ((cycle * 3.0) % 1.0) > 0.92;
        final nolehX = dengerin
            ? math.sin(cycle * math.pi * 4) * 0.75
            : (mikir ? math.cos(cycle * math.pi * 2) * 0.85 : math.sin(cycle * math.pi) * 0.35);
        final miringKepala = (aktif ? 0.15 : 0.05) * math.sin(cycle * math.pi * 2) + (nolehX * 0.08);
        final lompatY = -(aktif ? 8.0 : 3.5) * bob;
        final gerakKuping = math.sin(cycle * math.pi * 6) * (aktif ? 0.2 : 0.05);

        return Transform.translate(
          offset: Offset(nolehX * 5.0, lompatY),
          child: Transform.rotate(
            angle: miringKepala,
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
                      angle: -0.22 - gerakKuping,
                      child: _KupingOyen(size: size * 0.28),
                    ),
                  ),
                  Positioned(
                    top: -size * 0.06,
                    right: size * 0.12,
                    child: Transform.rotate(
                      angle: 0.22 + gerakKuping,
                      child: _KupingOyen(size: size * 0.28),
                    ),
                  ),
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF22222E),
                      border: Border.all(color: _oren.withValues(alpha: 0.9), width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: _oren.withValues(alpha: aktif ? 0.42 : 0.2),
                          blurRadius: aktif ? 22 : 12,
                          spreadRadius: 2,
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
                            errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.pets_rounded, size: 80, color: _oren),
                            ),
                          ),
                          CustomPaint(
                            painter: _EkspresiTomPainter(
                              berkedip: berkedip,
                              nolehX: nolehX,
                              aktif: aktif,
                              cycle: cycle,
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

class _KupingOyen extends StatelessWidget {
  final double size;
  const _KupingOyen({required this.size});

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
        border: Border.all(color: _oren.withValues(alpha: 0.9), width: 2),
      ),
    );
  }
}

class _EkspresiTomPainter extends CustomPainter {
  final bool berkedip;
  final double nolehX;
  final bool aktif;
  final double cycle;

  _EkspresiTomPainter({
    required this.berkedip,
    required this.nolehX,
    required this.aktif,
    required this.cycle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final geserX = nolehX * w * 0.06;
    final angkatAlis = aktif ? math.sin(cycle * math.pi * 4) * h * 0.025 : 0.0;

    final alisPaint = Paint()
      ..color = const Color(0xFFFFE0BE).withValues(alpha: 0.9)
      ..strokeWidth = math.max(2.0, w * 0.032)
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(w * 0.24 + geserX, h * 0.24 - angkatAlis),
      Offset(w * 0.44 + geserX, h * 0.28 - angkatAlis),
      alisPaint,
    );
    canvas.drawLine(
      Offset(w * 0.76 + geserX, h * 0.24 - angkatAlis),
      Offset(w * 0.56 + geserX, h * 0.28 - angkatAlis),
      alisPaint,
    );

    if (berkedip) {
      final kelopakPaint = Paint()
        ..color = _oren
        ..strokeWidth = math.max(2.2, w * 0.035)
        ..strokeCap = StrokeCap.round;

      canvas.drawLine(
        Offset(w * 0.26 + geserX, h * 0.35),
        Offset(w * 0.43 + geserX, h * 0.35),
        kelopakPaint,
      );
      canvas.drawLine(
        Offset(w * 0.57 + geserX, h * 0.35),
        Offset(w * 0.74 + geserX, h * 0.35),
        kelopakPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _EkspresiTomPainter old) {
    return old.berkedip != berkedip ||
        old.nolehX != nolehX ||
        old.aktif != aktif ||
        old.cycle != cycle;
  }
}

class _SettingSingkat extends StatefulWidget {
  final String awalBase;
  final String awalModel;
  final bool awalTts;
  final void Function(String, String, bool) onSimpan;
  final VoidCallback onReset;

  const _SettingSingkat({
    required this.awalBase,
    required this.awalModel,
    required this.awalTts,
    required this.onSimpan,
    required this.onReset,
  });

  @override
  State<_SettingSingkat> createState() => _SettingSingkatState();
}

class _SettingSingkatState extends State<_SettingSingkat> {
  late final _b = TextEditingController(text: widget.awalBase);
  late final _m = TextEditingController(text: widget.awalModel);
  late bool _tts = widget.awalTts;

  @override
  void dispose() {
    _b.dispose();
    _m.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Color(0xFF9C9CAC)),
          filled: true,
          fillColor: const Color(0xFF26262F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFF3D3D4A),
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Setting', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            _field('Base URL', _b, hint: kDefaultBaseUrl),
            _field('Model', _m, hint: kDefaultModel),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suara Oyen', style: TextStyle(fontSize: 14)),
              value: _tts,
              activeThumbColor: _oren,
              activeTrackColor: _oren.withValues(alpha: 0.4),
              onChanged: (v) => setState(() => _tts = v),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                widget.onSimpan(_b.text.trim(), _m.text.trim(), _tts);
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(
                backgroundColor: _oren,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Simpan', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
            TextButton(
              onPressed: () {
                widget.onReset();
                Navigator.pop(context);
              },
              child: const Text(
                'Reset obrolan',
                style: TextStyle(color: Color(0xFFFF9C9C)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
