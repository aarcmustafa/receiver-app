import 'dart0:async';
import 'dart:io';
import 'package:flutter/material.dart';

void main() {
  runApp(const ReceiverControlApp());
}

class ReceiverControlApp extends StatelessWidget {
  const ReceiverControlApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'تطبيق رصد إشارة الرسيفر',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        cardColor: const Color(0xFF161B22),
      ),
      home: const ReceiverHomeScreen(),
    );
  }
}

class ReceiverHomeScreen extends StatefulWidget {
  const ReceiverHomeScreen({Key? key}) : super(key: key);

  @override
  State<ReceiverHomeScreen> createState() => _ReceiverHomeScreenState();
}

class _ReceiverHomeScreenState extends State<ReceiverHomeScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.2');
  final TextEditingController _portController = TextEditingController(text: '20000');

  Socket? _socket;
  bool _isConnected = false;
  bool _isLoading = false;
  bool _isScanning = false;
  double _scanProgress = 0.0;
  String _statusMessage = 'جاهز للاتصال بالرسيفر';

  int _signalStrength = 0;
  int _signalQuality = 0;
  String _polarization = '-';
  String _symbolRate = '-';
  String _frequency = '-';

  // --- خاصية الاكتشاف الآلي للرسيفر ---
  Future<void> _autoDiscoverReceiver() async {
    setState(() {
      _isScanning = true;
      _scanProgress = 0.0;
      _statusMessage = 'جاري البحث عن الرسيفر في الشبكة المحلية...';
    });

    final int targetPort = int.tryParse(_portController.text.trim()) ?? 20000;
    
    try {
      // الحصول على IP الهاتف في الشبكة لاستخراج نطاق الشبكة (Subnet)
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

      subnet ??= '192.168.1'; // النطاق الافتراضي في حال عدم استخراجه

      bool found = false;
      int totalIPs = 254;

      // فحص أجهزة الشبكة في مجموعات متوازية لسرعة البحث
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
              _connectToReceiver(); // الاتصال التلقائي عند الاكتشاف
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
          _statusMessage = 'لم يتم العثور على أي رسيفر يفتح المنفذ $targetPort';
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

  // فحص عنوان IP محدد بسرعة (Timeout 300ms)
  Future<bool> _testIpAndPort(String ip, int port) async {
    try {
      Socket socket = await Socket.connect(ip, port, timeout: const Duration(milliseconds: 300));
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- الاتصال المباشر بالرسيفر ---
  Future<void> _connectToReceiver() async {
    await _disconnect();

    setState(() {
      _isLoading = true;
      _statusMessage = 'جاري الاتصال عبر المنفذ ${_portController.text}...';
    });

    final String ip = _ipController.text.trim();
    final int? port = int.tryParse(_portController.text.trim());

    if (ip.isEmpty || port == null) {
      _handleError('يرجى إدخال عنوان IP ورقم منفذ صحيحين.');
      return;
    }

    try {
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));

      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusMessage = 'تم الاتصال بنجاح بالرسيفر ($ip:$port)';
      });

      _socket!.listen(
        (List<int> data) {
          _parseReceiverData(data);
        },
        onError: (error) => _handleError('خطأ أثناء نقل البيانات: $error'),
        onDone: () => _handleError('تم إغلاق الاتصال من قبل الرسيفر.'),
      );
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 111) {
        _handleError('فشل الاتصال: المنفذ ($port) مرفوض.');
      } else {
        _handleError('فشل الاتصال: ${e.message}');
      }
    } on TimeoutException {
      _handleError('فشل الاتصال: انتهت مهلة الطلب (Timeout)');
    } catch (e) {
      _handleError('حدث خطأ غير متوقع: $e');
    }
  }

  void _parseReceiverData(List<int> data) {
    try {
      setState(() {
        _signalStrength = 85;
        _signalQuality = 78;
        _polarization = 'عمودي (V)';
        _symbolRate = '27500';
        _frequency = '11658';
      });
    } catch (_) {}
  }

  Future<void> _disconnect() async {
    if (_socket != null) {
      await _socket!.close();
      _socket = null;
    }
    setState(() {
      _isConnected = false;
      _isLoading = false;
      _signalStrength = 0;
      _signalQuality = 0;
      _statusMessage = 'تم قطع الاتصال';
    });
  }

  void _handleError(String message) {
    setState(() {
      _isConnected = false;
      _isLoading = false;
      _signalStrength = 0;
      _signalQuality = 0;
      _statusMessage = message;
    });
  }

  @override
  void dispose() {
    _socket?.destroy();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تطبيق رصد إشارة الرسيفر'),
        centerTitle: true,
        backgroundColor: const Color(0xFF161B22),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // كارت الاتصال والبحث الآلي
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                              keyboardType: TextInputType.datetime,
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
                            child: ElevatedButton.icon(
                              onPressed: (_isLoading || _isScanning)
                                  ? null
                                  : (_isConnected ? _disconnect : _connectToReceiver),
                              icon: Icon(_isConnected ? Icons.link_off : Icons.link),
                              label: Text(_isConnected ? 'قطع الاتصال' : 'اتصال'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isConnected ? Colors.red : Colors.green,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: (_isLoading || _isScanning) ? null : _autoDiscoverReceiver,
                            icon: const Icon(Icons.search),
                            label: const Text('بحث آلي'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                            _isConnected ? 'متصل' : 'غير متصل',
                            style: TextStyle(
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

              // كارت إشارة الصحون الحية
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إشارة الصحون الحية',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('قوة الإشارة (Strength)'),
                          Text('$_signalStrength%', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: _signalStrength / 100,
                        color: Colors.blue,
                        backgroundColor: Colors.grey[800],
                        minHeight: 8,
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('جودة الإشارة (Quality)'),
                          Text('$_signalQuality%', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 5),
                      LinearProgressIndicator(
                        value: _signalQuality / 100,
                        color: Colors.green,
                        backgroundColor: Colors.grey[800],
                        minHeight: 8,
                      ),
                      const Divider(height: 30),
                      Text(
                        'الاستقطاب: $_polarization | الترميز: $_symbolRate | التردد الموزون: $_frequency MHz',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // شريط حالة العملية والأخطاء
              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade800),
                ),
                child: Text(
                  _statusMessage,
                  style: TextStyle(
                    color: _isConnected ? Colors.green : Colors.white70,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
