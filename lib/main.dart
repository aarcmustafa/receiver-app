import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const ReceiverApp());
}

class ReceiverApp extends StatelessWidget {
  const ReceiverApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'رصد إشارة الرسيفر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF1E88E5),
        cardColor: const Color(0xFF1E293B),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.2');
  final int _port = 20000;

  Socket? _socket;
  bool _isConnected = false;
  bool _isSignalMonitoring = false;

  Timer? _heartbeatTimer;
  Timer? _signalTimer;

  int _strength = 0;
  int _quality = 0;

  String _freq = '-';
  String _pol = '-';
  String _sym = '-';

  // مدخلات تعديل التردد
  final TextEditingController _freqEdit = TextEditingController(text: '11411');
  final TextEditingController _symEdit = TextEditingController(text: '30000');
  int _polEdit = 0;

  @override
  void dispose() {
    _disconnect();
    _ipController.dispose();
    _freqEdit.dispose();
    _symEdit.dispose();
    super.dispose();
  }

  // تغليف الحزمة بالترويسة القياسية Start0000XXXEnd
  void _formatAndSend(String payload) {
    if (_socket != null && _isConnected) {
      List<int> bytes = utf8.encode(payload);
      String lenStr = bytes.length.toString().padLeft(7, '0');
      String header = 'Start${lenStr}End';
      _socket!.write(header + payload);
    }
  }

  // الاتصال بالرسيفر
  Future<void> _connect() async {
    try {
      _socket = await Socket.connect(_ipController.text, _port, timeout: const Duration(seconds: 5));
      setState(() {
        _isConnected = true;
      });

      // 1. المصادقة الأولية (Request 998)
      const authXml = '<Command request="998"><data>23129RN51X</data><uuid>f8380111-ad71-46a3-9988-e7988860454a-02:00:00:00:00:00</uuid></Command>';
      _formatAndSend(authXml);

      // 2. نبضات الاستمرار (Request 26) كل 4 ثوانٍ
      _heartbeatTimer?.cancel();
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        _formatAndSend(jsonEncode({"request": "26"}));
      });

      // الاستماع للبيانات القادمة من TCP Socket
      _socket!.listen(
        _onDataReceived,
        onError: (error) => _disconnect(),
        onDone: () => _disconnect(),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل الاتصال بالرسيفر: $e')),
      );
      _disconnect();
    }
  }

  void _disconnect() {
    _heartbeatTimer?.cancel();
    _signalTimer?.cancel();
    _socket?.destroy();
    _socket = null;
    setState(() {
      _isConnected = false;
      _isSignalMonitoring = false;
    });
  }

  // استقبال ومعالجة بيانات الحزم المباشرة
  void _onDataReceived(Uint8List data) {
    // البحث عن توقيع ضغط Zlib (0x78, 0x9C) الخاص بأوامر الإشارة (Request 403)
    int zlibIndex = -1;
    for (int i = 0; i < data.length - 1; i++) {
      if (data[i] == 0x78 && data[i + 1] == 0x9C) {
        zlibIndex = i;
        break;
      }
    }

    if (zlibIndex != -1) {
      try {
        List<int> compressed = data.sublist(zlibIndex);
        List<int> decompressed = zlib.decode(compressed);
        String jsonStr = utf8.decode(decompressed);
        Map<String, dynamic> parsed = jsonDecode(jsonStr);

        setState(() {
          if (parsed.containsKey('strength')) _strength = parsed['strength'] ?? _strength;
          if (parsed.containsKey('quality')) _quality = parsed['quality'] ?? _quality;
        });
      } catch (_) {
        // تجاهل أخطاء فك الحزم الجزئية
      }
    } else {
      // معالجة النصوص والبيانات العادية (مثل Request 402)
      try {
        String text = utf8.decode(data, allowMalformed: true);
        if (text.contains('cur_tuned_freq')) {
          int start = text.indexOf('{');
          int end = text.lastIndexOf('}');
          if (start != -1 && end != -1 && end > start) {
            String jsonSub = text.substring(start, end + 1);
            Map<String, dynamic> parsed = jsonDecode(jsonSub);
            setState(() {
              _freq = parsed['cur_tuned_freq']?.toString() ?? _freq;
              _sym = parsed['request_sym']?.toString() ?? _sym;
              _pol = (parsed['vertical_polor'] == 0) ? 'أفقي (H)' : 'عمودي (V)';
            });
          }
        }
      } catch (_) {}
    }
  }

  // تفعيل/إيقاف رصد الإشارة
  void _toggleSignalMonitoring(bool enable) {
    if (!_isConnected) return;

    if (enable) {
      _formatAndSend(jsonEncode({"request": "401"}));
      _signalTimer?.cancel();
      _signalTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
        _formatAndSend(jsonEncode({"request": "403"}));
      });
      setState(() {
        _isSignalMonitoring = true;
      });
    } else {
      _signalTimer?.cancel();
      _formatAndSend(jsonEncode({"request": "405"}));
      setState(() {
        _isSignalMonitoring = false;
      });
    }
  }

  // إرسال تعديل التردد
  void _sendTPUpdate() {
    if (!_isConnected) return;
    final payload = {
      "request": "update_tp",
      "freq": int.tryParse(_freqEdit.text) ?? 11411,
      "polarization": _polEdit,
      "symbol_rate": int.tryParse(_symEdit.text) ?? 30000
    };
    _formatAndSend(jsonEncode(payload));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إرسال أمر التحديث إلى الرسيفر')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تطبيق رصد إشارة الرسيفر'),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E293B),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // بطاقة الاتصال بالشبكة
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              labelText: 'عنوان IP للرسيفر',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: _isConnected ? _disconnect : _connect,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _isConnected ? Colors.red : Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          ),
                          child: Text(_isConnected ? 'قطع الاتصال' : 'اتصال'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isConnected ? Icons.check_circle : Icons.cancel,
                          color: _isConnected ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isConnected ? 'متصل بالرسيفر' : 'غير متصل',
                          style: TextStyle(
                            fontSize: 16,
                            color: _isConnected ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // بطاقة رصد الإشارة الحية
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'إشارة الصحن الحية',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        Switch(
                          value: _isSignalMonitoring,
                          onChanged: _isConnected ? _toggleSignalMonitoring : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildProgressBar('قوة الإشارة (Strength)', _strength, Colors.blue),
                    const SizedBox(height: 16),
                    _buildProgressBar('جودة الإشارة (Quality)', _quality, Colors.green),
                    const SizedBox(height: 16),
                    const Divider(),
                    Text('التردد الموزون: $_freq MHz | الاستقطاب: $_pol | الترميز: $_sym'),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // بطاقة تعديل الترددات
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'تعديل التردد (Transponder Editor)',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _freqEdit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'التردد (MHz)', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _polEdit,
                            decoration: const InputDecoration(labelText: 'الاستقطاب', border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('أفقي (H)')),
                              DropdownMenuItem(value: 1, child: Text('عمودي (V)')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _polEdit = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _symEdit,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'معدل الترميز', border: OutlineInputBorder()),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _isConnected ? _sendTPUpdate : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                          ),
                          child: const Text('إرسال التحديث'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar(String title, int value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('$value%', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            value: value / 100.0,
            minHeight: 18,
            backgroundColor: Colors.grey[800],
            color: color,
          ),
        ),
      ],
    );
  }
}
