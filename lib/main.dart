import 'dart:async';
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
  // الإعدادات الافتراضية للاتصال
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.2');
  final TextEditingController _portController = TextEditingController(text: '20000');

  Socket? _socket;
  bool _isConnected = false;
  bool _isLoading = false;
  String _statusMessage = 'جاهز للاتصال بالرسيفر';

  // بيانات إشارة الصحون
  int _signalStrength = 0;
  int _signalQuality = 0;
  String _polarization = '-';
  String _symbolRate = '-';
  String _frequency = '-';

  // دالة الاتصال بالرسيفر عبر TCP Socket على المنفذ 20000
  Future<void> _connectToReceiver() async {
    // إغلاق أي اتصال سابق إذا كان مفتوحاً
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
      // فتح اتصال Socket مباشر مع مهلة 5 ثوانٍ
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));

      setState(() {
        _isConnected = true;
        _isLoading = false;
        _statusMessage = 'تم الاتصال بنجاح بالرسيفر ($ip:$port)';
      });

      // الاستماع للبيانات القادمة من الرسيفر لتحديث الإشارة تلقائياً
      _socket!.listen(
        (List<int> data) {
          _parseReceiverData(data);
        },
        onError: (error) {
          _handleError('خطأ أثناء نقل البيانات: $error');
        },
        onDone: () {
          _handleError('تم إغلاق الاتصال من قبل الرسيفر.');
        },
      );

    } on SocketException catch (e) {
      if (e.osError?.errorCode == 111) {
        _handleError('فشل الاتصال: المنفذ ($port) مرفوض. تحقق من خيارات السيرفر في الرسيفر.');
      } else {
        _handleError('فشل الاتصال: ${e.message}');
      }
    } on TimeoutException {
      _handleError('فشل الاتصال: انتهت مهلة الطلب (Timeout)');
    } catch (e) {
      _handleError('حدث خطأ غير متوقع: $e');
    }
  }

  // معالجة البيانات القادمة من الرسيفر وقراءتها
  void _parseReceiverData(List<int> data) {
    try {
      String response = String.fromCharCodes(data).trim();
      
      // هنا يمكن تحليل البيانات القادمة حسب البروتوكول المعتمد للرسيفر
      // كنموذج لمعالجة البيانات:
      setState(() {
        // تحديث قيم افتراضية عند استقبال أي حزمة بيانات ناجحة
        _signalStrength = 85; 
        _signalQuality = 78;
        _polarization = 'عمودي (V)';
        _symbolRate = '27500';
        _frequency = '11658';
      });
    } catch (e) {
      debugPrint('خطأ في تحليلات البيانات المرجعة: $e');
    }
  }

  // قطع الاتصال بالمقبس
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
              // كارت الاتصال
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
                          const SizedBox(width: 10),
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
                      ElevatedButton(
                        onPressed: _isLoading ? null : (_isConnected ? _disconnect : _connectToReceiver),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isConnected ? Colors.red : Colors.green,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                _isConnected ? 'قطع الاتصال' : 'اتصال',
                                style: const TextStyle(fontSize: 18, color: Colors.white),
                              ),
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
                        'الاستقطاب: $_polarization | الترمز: $_symbolRate | التردد الموزون: $_frequency MHz',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // شريط لعرض تفاصيل وأخطاء الاتصال بدلاً من الكراش
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
                    color: _isConnected ? Colors.greenLight : Colors.white70,
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
