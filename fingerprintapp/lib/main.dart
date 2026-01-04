import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart'
    as img; // Đảm bảo đã thêm 'image' trong pubspec.yaml

// =======================================================================
// UUIDs CỦA BLE PROVISIONING
// =======================================================================
final Guid PROV_SERVICE_UUID = Guid("0000FF01-0000-1000-8000-00805F9B34FB");
final Guid SSID_CHAR_UUID = Guid("0000FF02-0000-1000-8000-00805F9B34FB");
final Guid PASSWORD_CHAR_UUID = Guid("0000FF03-0000-1000-8000-00805F9B34FB");
final Guid CONNECT_CHAR_UUID = Guid("0000FF04-0000-1000-8000-00805F9B34FB");
final Guid STATUS_CHAR_UUID = Guid("0000FF05-0000-1000-8000-00805F9B34FB");

const String TARGET_DEVICE_NAME = "FP_Sensor_Front_01";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterBluePlus.setLogLevel(LogLevel.verbose, color: true);
  runApp(const ProvisioningApp());
}

class ProvisioningApp extends StatelessWidget {
  const ProvisioningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ESP32 BLE + Fingerprint',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ProvisioningScreen(),
    );
  }
}

class ProvisioningScreen extends StatefulWidget {
  const ProvisioningScreen({super.key});

  @override
  State<ProvisioningScreen> createState() => _ProvisioningScreenState();
}

class _ProvisioningScreenState extends State<ProvisioningScreen> {
  BluetoothDevice? targetDevice;
  bool isScanning = false;
  String connectionStatus = "Chưa quét";

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _statusSub;

  // STATE CHO FINGERPRINT
  String? _espIp;
  Uint8List? _fpImageBytes;
  bool _isFpScanning = false; // Trạng thái quét vân tay
  Timer? _fpScanTimer; // Timer gọi HTTP

  @override
  void initState() {
    super.initState();
    checkPermissionsAndInitialize();
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _statusSub?.cancel();
    _stopFpScanTimer();
    super.dispose();
  }

  Future<void> checkPermissionsAndInitialize() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    if (!(await FlutterBluePlus.isSupported)) {
      setState(() => connectionStatus = "Thiết bị không hỗ trợ Bluetooth.");
      return;
    }

    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState != BluetoothAdapterState.on) {
      setState(
        () =>
            connectionStatus = "Vui lòng bật Bluetooth (và Location nếu cần).",
      );
      return;
    }

    setState(() => connectionStatus = "Sẵn sàng quét.");
  }

  void startScan() async {
    if (await FlutterBluePlus.isScanning.first) {
      await FlutterBluePlus.stopScan();
    }

    setState(() {
      isScanning = true;
      targetDevice = null;
      connectionStatus = "Đang quét...";
    });

    StreamSubscription<List<ScanResult>>? subscription;

    try {
      subscription = FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final name = r.device.platformName;
          final advName = r.advertisementData.advName;

          if (name == TARGET_DEVICE_NAME || advName == TARGET_DEVICE_NAME) {
            FlutterBluePlus.stopScan();
            setState(() {
              targetDevice = r.device;
              isScanning = false;
              connectionStatus = "Đã tìm thấy: $TARGET_DEVICE_NAME";
            });
            return;
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
      await FlutterBluePlus.isScanning.where((val) => val == false).first;
      await subscription.cancel();

      if (targetDevice == null) {
        setState(() => connectionStatus = "Không tìm thấy thiết bị.");
      }
    } catch (e) {
      setState(() => connectionStatus = "Lỗi quét: $e");
      await FlutterBluePlus.stopScan();
      await subscription?.cancel();
    } finally {
      setState(() => isScanning = false);
    }
  }

  Future<void> connectBleOnly() async {
    if (targetDevice == null) return;

    setState(
      () => connectionStatus = "Đang kết nối BLE tới $TARGET_DEVICE_NAME ...",
    );

    try {
      await targetDevice!.connect(timeout: const Duration(seconds: 15));

      _connSub ??= targetDevice!.connectionState.listen((s) {
        setState(() => _connectionState = s);
      });

      setState(
        () => connectionStatus = "Đã kết nối BLE. Sẵn sàng gửi cấu hình.",
      );
    } catch (e) {
      setState(() => connectionStatus = "Lỗi kết nối BLE: $e");
      try {
        await targetDevice?.disconnect();
      } catch (_) {}
    }
  }

  void connectAndProvision(String ssid, String password) async {
    if (targetDevice == null ||
        _connectionState != BluetoothConnectionState.connected) {
      setState(
        () => connectionStatus = "Chưa kết nối BLE. Nhấn 'Kết nối BLE' trước.",
      );
      return;
    }

    setState(() => connectionStatus = "Đang khám phá services...");

    try {
      List<BluetoothService> services = await targetDevice!.discoverServices();

      BluetoothService provService = services.firstWhere(
        (s) => s.uuid == PROV_SERVICE_UUID,
        orElse: () =>
            throw Exception("Không tìm thấy Provisioning Service (FF01)"),
      );

      BluetoothCharacteristic ssidChar = provService.characteristics.firstWhere(
        (c) => c.uuid == SSID_CHAR_UUID,
        orElse: () =>
            throw Exception("Không tìm thấy SSID Characteristic (FF02)"),
      );

      BluetoothCharacteristic passChar = provService.characteristics.firstWhere(
        (c) => c.uuid == PASSWORD_CHAR_UUID,
        orElse: () =>
            throw Exception("Không tìm thấy Password Characteristic (FF03)"),
      );

      BluetoothCharacteristic connectChar = provService.characteristics
          .firstWhere(
            (c) => c.uuid == CONNECT_CHAR_UUID,
            orElse: () =>
                throw Exception("Không tìm thấy Connect Characteristic (FF04)"),
          );

      BluetoothCharacteristic statusChar = provService.characteristics
          .firstWhere(
            (c) => c.uuid == STATUS_CHAR_UUID,
            orElse: () =>
                throw Exception("Không tìm thấy Status Characteristic (FF05)"),
          );

      setState(() => connectionStatus = "Đang gửi cấu hình...");

      await ssidChar.write(utf8.encode(ssid), allowLongWrite: true);
      await passChar.write(utf8.encode(password), allowLongWrite: true);
      await connectChar.write(Uint8List.fromList([1]));

      setState(() => connectionStatus = "Đã gửi. ESP32 đang kết nối Wi-Fi...");

      await statusChar.setNotifyValue(true);

      _statusSub?.cancel();
      _statusSub = statusChar.onValueReceived.listen((value) {
        final statusText = utf8.decode(value);
        String uiText;
        String? espIp;

        if (statusText.startsWith("connected:")) {
          espIp = statusText.substring("connected:".length);
          uiText = "Wi-Fi OK! IP: $espIp ✅";
          targetDevice?.disconnect();
        } else if (statusText == "connecting") {
          uiText = "Đang kết nối Wi-Fi...";
        } else if (statusText == "failed") {
          uiText = "Wi-Fi thất bại. Kiểm tra SSID/Pass.";
        } else {
          uiText = "Trạng thái: $statusText";
        }

        if (mounted) {
          setState(() {
            connectionStatus = uiText;
            _espIp = espIp;
            _fpImageBytes = null;
            _isFpScanning = false;
          });
        }
      });

      targetDevice!.cancelWhenDisconnected(_statusSub!);
    } catch (e) {
      setState(() => connectionStatus = "Lỗi Provisioning: $e");
    }
  }

  // =======================================================================
  // HÀM ĐIỀU KHIỂN VÂN TAY
  // =======================================================================

  /// Bước 1: Gửi lệnh START, rồi chờ status DONE (không polling /fpimage sớm)
  Future<void> _startFingerprintScan() async {
    if (_espIp == null || _isFpScanning) return;

    setState(() => _isFpScanning = true);

    // Gửi lệnh START
    try {
      final url = 'http://$_espIp/fpcontrol?cmd=start';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        connectionStatus = "🔄 Đang chờ cảm biến...";

        // Bắt timer để poll /fpstatus (không gửi request mới, chỉ check state)
        _startStatusPoller();
      } else {
        setState(
          () => connectionStatus = "❌ Lỗi gửi START: ${response.statusCode}",
        );
        setState(() => _isFpScanning = false);
      }
    } catch (e) {
      setState(() {
        connectionStatus = "❌ Lỗi: $e";
        _isFpScanning = false;
      });
    }
  }

  /// Bước 2: Poll /fpstatus để chờ state = DONE (an toàn, không gián đoạn cảm biến)
  void _startStatusPoller() {
    _stopFpScanTimer();
    _fpScanTimer = Timer.periodic(const Duration(milliseconds: 300), (
      timer,
    ) async {
      if (_espIp != null && _isFpScanning) {
        await _checkSensorStatus();
      }
    });
  }

  /// Poll /fpstatus - chỉ check state, không download ảnh
  Future<void> _checkSensorStatus() async {
    if (_espIp == null) return;

    try {
      final response = await http
          .get(Uri.parse('http://$_espIp/fpstatus'))
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final state = json['state'] as String?;

        if (state == 'SCANNING') {
          setState(() => connectionStatus = "🔄 Cảm biến đang chạy...");
        } else if (state == 'DONE') {
          // ✅ Quét xong! Giờ mới download ảnh (an toàn)
          connectionStatus = "✅ Đã quét xong, đang lấy ảnh...";
          await _fetchFingerprintImage();
          _stopFpScanTimer();
        } else if (state == 'FAILED') {
          connectionStatus = "⚠️ Quét thất bại (không đặt ngón tay?)";
          setState(() => _isFpScanning = false);
          _stopFpScanTimer();
        } else if (state == 'IDLE') {
          connectionStatus = "⚠️ Cảm biến không hoạt động";
          setState(() => _isFpScanning = false);
          _stopFpScanTimer();
        }
      }
    } catch (e) {
      // Timeout/lỗi status - vẫn chờ
      setState(() => connectionStatus = "⏳ Chờ (kiểm tra trạng thái...)");
    }
  }

  /// Bước 3: Sau khi state = DONE, gọi /fpimage một lần duy nhất
  Future<void> _fetchFingerprintImage() async {
    if (_espIp == null) return;

    try {
      final response = await http
          .get(
            Uri.parse('http://$_espIp/fpimage'),
            headers: {'Accept': 'application/octet-stream'},
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final expectedSize = 256 * 288;

        if (response.bodyBytes.length == expectedSize) {
          setState(() {
            _fpImageBytes = response.bodyBytes;
            connectionStatus = "✓ Ảnh vân tay (${_fpImageBytes!.length} bytes)";
            _isFpScanning = false;
          });
          print("[DEBUG] Image received successfully");
        } else {
          setState(
            () => connectionStatus =
                "⚠ Kích thước sai: ${response.bodyBytes.length}/${expectedSize}",
          );
        }
      } else if (response.statusCode == 404) {
        setState(() => connectionStatus = "⚠ Ảnh chưa sẵn sàng");
      } else {
        setState(() => connectionStatus = "❌ HTTP ${response.statusCode}");
      }
    } catch (e) {
      setState(() => connectionStatus = "❌ Lỗi tải ảnh: $e");
    }
  }

  void _stopFpScanTimer() {
    _fpScanTimer?.cancel();
    _fpScanTimer = null;
  }

  // =======================================================================
  // BUILD UI
  // =======================================================================
  @override
  Widget build(BuildContext context) {
    final bool isConnected =
        _connectionState == BluetoothConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('BLE + Fingerprint Scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trạng thái: $connectionStatus',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'BLE: ${_connectionState.name}',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),

            // Nút Scan
            ElevatedButton(
              onPressed: isScanning ? null : startScan,
              child: isScanning
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text("Quét thiết bị BLE"),
            ),

            const SizedBox(height: 10),

            // Nút Connect BLE
            if (targetDevice != null)
              ElevatedButton(
                onPressed: isConnected ? null : connectBleOnly,
                child: const Text("Kết nối BLE"),
              ),

            const SizedBox(height: 10),

            // Nút Disconnect
            if (targetDevice != null)
              ElevatedButton(
                onPressed: isConnected
                    ? () async {
                        _statusSub?.cancel();
                        await targetDevice!.disconnect();
                        setState(() {
                          connectionStatus = "Đã ngắt kết nối BLE.";
                          _espIp = null;
                          _fpImageBytes = null;
                          _isFpScanning = false;
                        });
                      }
                    : null,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Ngắt kết nối"),
              ),

            // Form Provisioning
            if (targetDevice != null && !isScanning && _espIp == null)
              Padding(
                padding: const EdgeInsets.only(top: 30.0),
                child: ProvisioningForm(onSubmit: connectAndProvision),
              ),

            // Khu vực điều khiển vân tay
            if (_espIp != null) ...[
              const SizedBox(height: 30),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.wifi, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            "ESP32 IP: $_espIp",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Nút START (Chỉ còn START)
                      ElevatedButton.icon(
                        onPressed: _isFpScanning ? null : _startFingerprintScan,
                        icon: const Icon(Icons.play_arrow, color: Colors.white),
                        label: const Text(
                          "Bắt đầu quét",
                          style: TextStyle(fontSize: 16),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Hiển thị ảnh
              if (_fpImageBytes != null) ...[
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Row(
                          children: [
                            Icon(Icons.fingerprint, color: Colors.blue),
                            SizedBox(width: 8),
                            Text(
                              "Ảnh vân tay (256x288 Grayscale)",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Container(
                        height: 320,
                        color: Colors.grey[100],
                        padding: const EdgeInsets.all(8),
                        child: ImageWidgetFromRawData(
                          rawData: _fpImageBytes!,
                          width: 256,
                          height: 288,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Dung lượng: ${_fpImageBytes!.length} bytes",
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _startFingerprintScan,
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text("Quét lại"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// =======================================================================
// Widget hiển thị RAW → PNG
// =======================================================================
class ImageWidgetFromRawData extends StatelessWidget {
  final Uint8List rawData;
  final int width;
  final int height;

  const ImageWidgetFromRawData({
    super.key,
    required this.rawData,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (rawData.length != width * height) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text("Lỗi: Dữ liệu ảnh không đúng"),
            const SizedBox(height: 8),
            Text(
              "Dự kiến: ${width * height} bytes\nNhận được: ${rawData.length} bytes",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    try {
      // Tạo Image object từ raw data (8-bit grayscale)
      // Dùng format rgba để compatible với image package
      final image = img.Image(
        width: width,
        height: height,
        format: img.Format.uint8,
      );

      // Copy raw data vào image (mỗi pixel là 1 byte grayscale)
      // Sử dụng .buffer để truy cập mảng bytes directly
      final imageBytes = image.toUint8List();
      for (int i = 0; i < rawData.length; i++) {
        imageBytes[i] = rawData[i];
      }

      // Tạo Image mới từ bytes
      final newImage = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: imageBytes.buffer,
        format: img.Format.uint8,
      );

      // Encode thành PNG
      final pngBytes = img.encodePng(newImage);

      return SingleChildScrollView(
        child: Column(
          children: [
            Image.memory(
              pngBytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
            ),
            const SizedBox(height: 8),
            Text(
              "Kích thước: ${width}x${height} | Dung lượng: ${rawData.length} bytes",
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    } catch (e) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image, color: Colors.orange, size: 48),
            const SizedBox(height: 16),
            Text(
              "Lỗi xử lý ảnh: $e",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
      );
    }
  }
}

// =======================================================================
// Form Wi-Fi
// =======================================================================
class ProvisioningForm extends StatefulWidget {
  final void Function(String, String) onSubmit;
  const ProvisioningForm({super.key, required this.onSubmit});

  @override
  State<ProvisioningForm> createState() => _ProvisioningFormState();
}

class _ProvisioningFormState extends State<ProvisioningForm> {
  final TextEditingController ssidController = TextEditingController(
    text: "Ten_Wifi_Cua_Toi",
  );
  final TextEditingController passController = TextEditingController(
    text: "MatKhau_Cua_Toi",
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Cấu hình Wi-Fi:",
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        const Text(
          TARGET_DEVICE_NAME,
          style: TextStyle(color: Colors.blueAccent, fontSize: 16),
        ),
        const SizedBox(height: 15),
        TextField(
          controller: ssidController,
          decoration: const InputDecoration(
            labelText: 'SSID (Tên Wi-Fi)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.wifi),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: passController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock),
          ),
        ),
        const SizedBox(height: 30),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () {
              if (ssidController.text.isEmpty || passController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Vui lòng nhập SSID và Password."),
                  ),
                );
                return;
              }
              widget.onSubmit(ssidController.text, passController.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text(
              "Gửi cấu hình Wi-Fi",
              style: TextStyle(fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }
}
