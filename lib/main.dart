import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

void main() {
  runApp(const ReceiverControlApp());
}

class ReceiverControlApp extends StatelessWidget {
  const ReceiverControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق رصد إشارة الرسيفر',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        primaryColor: const Color(0xFF1E88E5),
        cardColor: const Color(0xFF1E293B),
      ),
      home: const ReceiverHomeScreen(),
    );
  }
}

class ReceiverHomeScreen extends StatefulWidget {
  const ReceiverHomeScreen({super.key});

  @override
  State<ReceiverHomeScreen> createState() => _ReceiverHomeScreenState();
}

class _ReceiverHomeScreenState extends State<ReceiverHomeScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.2');
  final TextEditingController _portController = TextEditingController(text: '20000');

  Socket? _socket;
  bool _isConnected = false;
  bool _isLoading = false; // تم تعريف المتغير بنجاح لتجنب خطأ البناء
  bool _isSignalMonitoring = false;
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _statusMessage = 'جاهز للاتصال بالرسيفر';

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
    _portController.dispose();
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

  // ميزة البحث الآلي عن الرسيفر في الشبكة المحلية
  Future<void> _autoDiscoverReceiver() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
      _statusMessage = 'جاري البحث عن الرسيفر في الشبكة المحلية...';
    });

    final int targetPort = int.tryParse(_portController.text.trim()) ?? 20000;
    
    try {
      List<NetworkInterface> interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );

      String? subnet;
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith('192.168.')) {
            List<String> parts = addr.address.split('.');
            subnet = '${parts[0]}.${parts[1]}.${parts[2]}';
            break;
          }
        }
        if (subnet != null) break;
      }

      subnet ??= '192.168.1';
      bool found = false;
      int totalIPs = 254;

      for (int i = 1; i <= totalIPs; i += 10) {
        if (!mounted || found) break;

        List<Future<void>> tasks = [];
        for (int j = i; j < i + 10 && j <= totalIPs; j++) {
          String testIp = '$subnet.$j';
          tasks.add(_testIpAndPort(testIp, targetPort).then((success) {
            if (success && !found) {
              found = true;
              _ipController.text = testIp;
              _statusMessage = 'تم العثور على الرسيفر تلقائياً: $testIp';
              _connect();
            }
          }));
        }

        await Future.wait(tasks);
        setState(() {
          _scanProgress = i / totalIPs;
        });
      }

      if (!found && mounted) {
        setState(() {
          _statusMessage = 'لم يتم العثور على أي رسيفر على المنفذ $targetPort';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'خطأ أثناء البحث الآلي: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<bool> _testIpAndPort(String ip, int port) async {
    try {
      Socket socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 300));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // الاتصال بالرسيفر وتطبيق البروتوكول الكامل
  Future<void> _connect() async {
    _disconnect();
    final int port = int.tryParse(_portController.text.trim()) ?? 20000;

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري الاتصال بالرسيفر ${_ipController.text}:$port...';
    });

    try {
      _socket = await Socket.connect(_ipController.text, port, timeout: const Duration(seconds: 5));
      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusMessage = 'تم الاتصال بنجاح بالرسيفر';
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
      setState(() {
        _statusMessage = 'فشل الاتصال بالرسيفر: $e';
        _isConnected = false;
        _isLoading = false;
      });
    }
  }

  void _disconnect() {
    _heartbeatTimer?.cancel();
    _signalTimer?.cancel();
    _socket?.destroy();
    _socket = null;
    setState(() {
      _isConnected = false;
      _isLoading = false;
      _isSignalMonitoring = false;
      _statusMessage = 'تم قطع الاتصال';
    });
  }

  // استقبال ومعالجة بيانات الحزم المباشرة وفك ضغط Zlib
  void _onDataReceived(Uint8List data) {
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
      } catch (_) {}
    } else {
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
            // بطاقة الاتصال والبحث الآلي
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(
                              labelText: 'عنوان IP للرسيفر',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _portController,
                            decoration: const InputDecoration(
                              labelText: 'المنفذ',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: (_isLoading || _isScanning) ? null : (_isConnected ? _disconnect : _connect),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isConnected ? Colors.red : Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _isLoading 
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : Text(_isConnected ? 'قطع الاتصال' : 'اتصال', style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: (_isLoading || _isScanning) ? null : _autoDiscoverReceiver,
                          icon: const Icon(Icons.search),
                          label: const Text('بحث آلي'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                          ),
                        ),
                      ],
                    ),
                    if (_isScanning) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _scanProgress),
                    ],
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

            const SizedBox(height: 16),

            // شريط حالة الاتصال والرسائل
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 20),

            // توقيع المبرمج
            const Center(
              child: Text(
                'Developer: Djellouli Mustafa',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
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
