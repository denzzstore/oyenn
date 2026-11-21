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
      home: const ChatPage(),
    );
  }
}

class Msg {
  final String role;
  String text;
  Msg(this.role, this.text);
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with SingleTickerProviderStateMixin {
  late final AnimationController _bob;
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  final _tts = FlutterTts();
  final _speech = SpeechToText();
  final _msgs = <Msg>[];

  String _key = '';
  String _base = kDefaultBaseUrl;
  String _model = kDefaultModel;
  String _level = 'pedas';
  bool _ttsOn = true;
  bool _typing = false;
  bool _siap = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _bob = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..repeat(reverse: true);
    _tts.setLanguage('id-ID');
    _tts.setPitch(1.15);
    _tts.setSpeechRate(0.5);
    _muat();
  }

  Future<void> _muat() async {
    final p = await SharedPreferences.getInstance();
    setState(() {
      _key = p.getString('key') ?? '';
      _base = p.getString('base') ?? kDefaultBaseUrl;
      _model = p.getString('model') ?? kDefaultModel;
      _level = p.getString('level') ?? 'pedas';
      _ttsOn = p.getBool('tts') ?? true;
      _siap = true;
    });
    if (_key.isEmpty) {
      _bukaSetting();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    _ctrl.dispose();
    _scroll.dispose();
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

  void _bawah() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _kirim() async {
    final t = _ctrl.text.trim();
    if (t.isEmpty || _typing) return;
    if (_key.isEmpty) {
      _bukaSetting();
      return;
    }
    setState(() {
      _msgs.add(Msg('user', t));
      _ctrl.clear();
      _typing = true;
    });
    _bawah();
    try {
      final hist = [
        {'role': 'system', 'content': oyenSystemPrompt(_level)},
      ];
      final potong = _msgs.length > 13 ? _msgs.sublist(_msgs.length - 13) : _msgs;
      for (final m in potong) {
        hist.add({'role': m.role, 'content': m.text});
      }
      final r = await OyenApi(key: _key, baseUrl: _base, model: _model).reply(hist);
      if (!mounted) return;
      setState(() => _msgs.add(Msg('assistant', r)));
      if (_ttsOn) {
        await _bicara(r);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(Msg('error', '$e')));
    } finally {
      if (mounted) {
        setState(() => _typing = false);
      }
      _bawah();
    }
  }

  Future<void> _bicara(String t) async {
    final bersih = t.replaceAll(RegExp(r'[^a-zA-Z0-9\s.,!?-]'), ' ').trim();
    await _tts.stop();
    await _tts.speak(bersih);
  }

  Future<void> _dengar() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) {
        setState(() => _listening = false);
      }
      return;
    }
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
      _ctrl.clear();
    });
    await _speech.listen(
      onResult: (r) {
        if (!mounted) return;
        setState(() => _ctrl.text = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          _kirim();
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
        awalKey: _key,
        awalBase: _base,
        awalModel: _model,
        awalLevel: _level,
        awalTts: _ttsOn,
        onSimpan: (k, b, m, l, t) async {
          final p = await SharedPreferences.getInstance();
          await p.setString('key', k);
          await p.setString('base', b);
          await p.setString('model', m);
          await p.setString('level', l);
          await p.setBool('tts', t);
          if (!mounted) return;
          setState(() {
            _key = k;
            _base = b;
            _model = m;
            _level = l;
            _ttsOn = t;
          });
        },
        onHapus: () => setState(_msgs.clear),
      ),
    );
  }

  Widget _kucing({double size = 46}) {
    return AnimatedBuilder(
      animation: _bob,
      builder: (context, child) {
        final t = _bob.value;
        return Transform.translate(
          offset: Offset(0, -3.5 * t),
          child: Transform.rotate(
            angle: (_typing || _listening ? 0.09 : 0.02) * (t * 2 - 1),
            child: _AvatarOyen(size: size),
          ),
        );
      },
    );
  }

  Widget _gelembung(Msg m) {
    final user = m.role == 'user';
    final err = m.role == 'error';
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          gradient: user
              ? const LinearGradient(colors: [Color(0xFFFF9A45), Color(0xFFE86A00)])
              : null,
          color: err ? const Color(0xFF3A1C1C) : (user ? null : const Color(0xFF22222E)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(user ? 18 : 5),
            bottomRight: Radius.circular(user ? 5 : 18),
          ),
        ),
        child: Text(
          m.text,
          style: TextStyle(
            fontSize: 15.5,
            height: 1.4,
            color: user
                ? const Color(0xFF17130E)
                : (err ? const Color(0xFFFF9C9C) : const Color(0xFFEDEDF2)),
            fontWeight: user ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _ngetik() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF22222E),
          borderRadius: BorderRadius.circular(18),
        ),
        child: AnimatedBuilder(
          animation: _bob,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              final f = (_bob.value + i * 0.33) % 1;
              final pulse = f < 0.5 ? f * 2 : (1 - f) * 2;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _oren.withValues(alpha: 0.35 + 0.65 * pulse),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_siap) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: _oren)),
      );
    }
    return Scaffold(
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 10,
              bottom: 10,
              left: 14,
              right: 6,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: const [Color(0xFF2A1A0C), _bg],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Row(
              children: [
                _kucing(),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Oyen',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFFD3A8),
                          letterSpacing: 0.3,
                        ),
                      ),
                      Text(
                        _listening
                            ? 'dengerin...'
                            : (_typing ? 'lagi ngeliatin lu...' : 'kucing oren • $_level'),
                        style: TextStyle(fontSize: 12, color: _oren.withValues(alpha: 0.85)),
                      ),
                    ],
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
            child: _msgs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _kucing(size: 110),
                        const SizedBox(height: 18),
                        const Text(
                          'Ngobrol, gak usah sopan.',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFB9B9C6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Dia yang bakal mulai nyolot duluan.',
                          style: TextStyle(fontSize: 13, color: Color(0xFF71717F)),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: _msgs.length + (_typing ? 1 : 0),
                    itemBuilder: (_, i) => i < _msgs.length ? _gelembung(_msgs[i]) : _ngetik(),
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
              decoration: const BoxDecoration(
                color: Color(0xFF17171F),
                border: Border(top: BorderSide(color: Color(0xFF26262F))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  GestureDetector(
                    onTap: _dengar,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _listening ? const Color(0xFFE0322A) : const Color(0xFF22222E),
                      ),
                      child: Icon(
                        _listening ? Icons.stop_rounded : Icons.mic_rounded,
                        color: _listening ? Colors.white : const Color(0xFFFFD3A8),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _kirim(),
                      style: const TextStyle(fontSize: 15.5),
                      decoration: InputDecoration(
                        hintText: _listening ? 'Dengerin lu ngomong...' : 'Ketik, atau tap mic...',
                        hintStyle: const TextStyle(color: Color(0xFF6C6C7A), fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF22222E),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _kirim,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFFFF9A45), Color(0xFFE86A00)]),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF17130E)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarOyen extends StatelessWidget {
  final double size;
  const _AvatarOyen({required this.size});

  @override
  Widget build(BuildContext context) {
    final double iconSize = size * 0.55;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF22222E),
        border: Border.all(color: _oren.withValues(alpha: 0.7), width: 2),
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Icon(
                Icons.pets_rounded,
                size: iconSize,
                color: _oren,
              ),
            ),
            Image.asset(
              'assets/oyen.png',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingSheet extends StatefulWidget {
  final String awalKey;
  final String awalBase;
  final String awalModel;
  final String awalLevel;
  final bool awalTts;
  final void Function(String, String, String, String, bool) onSimpan;
  final VoidCallback onHapus;

  const _SettingSheet({
    required this.awalKey,
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

class _SettingSheetState extends State<_SettingSheet> {
  late final _k = TextEditingController(text: widget.awalKey);
  late final _b = TextEditingController(text: widget.awalBase);
  late final _m = TextEditingController(text: widget.awalModel);
  late String _lv = widget.awalLevel;
  late bool _tts = widget.awalTts;

  @override
  void dispose() {
    _k.dispose();
    _b.dispose();
    _m.dispose();
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, {bool rahasia = false, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        obscureText: rahasia,
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
            _field('API Key', _k, rahasia: true, hint: 'sk-...'),
            _field('Base URL', _b, hint: kDefaultBaseUrl),
            _field('Model', _m, hint: kDefaultModel),
            const SizedBox(height: 4),
            const Text(
              'Level Ketoksikan',
              style: TextStyle(fontSize: 13, color: Color(0xFF9C9CAC)),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'santai', label: Text('Santai')),
                ButtonSegment(value: 'pedas', label: Text('Pedas')),
                ButtonSegment(value: 'neraka', label: Text('Neraka')),
              ],
              selected: {_lv},
              onSelectionChanged: (s) => setState(() => _lv = s.first),
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: _oren,
                selectedForegroundColor: Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Suara Oyen', style: TextStyle(fontSize: 14)),
              value: _tts,
              activeThumbColor: _oren,
              activeTrackColor: _oren.withValues(alpha: 0.4),
              onChanged: (v) => setState(() => _tts = v),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: () {
                widget.onSimpan(_k.text.trim(), _b.text.trim(), _m.text.trim(), _lv, _tts);
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
                widget.onHapus();
                Navigator.pop(context);
              },
              child: const Text(
                'Hapus semua chat',
                style: TextStyle(color: Color(0xFFFF9C9C)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
