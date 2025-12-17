import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img; // *** Đảm bảo đã thêm 'image' trong pubspec.yaml ***

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

  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
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
    _stopFpScanTimer(); // Huỷ Timer khi đóng màn hình
    super.dispose();
  }

// =======================================================================
// CÁC HÀM CŨ (Scan, Connect BLE, Provisioning)
// =======================================================================

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
      setState(() => connectionStatus = "Vui lòng bật Bluetooth (và Location nếu cần).");
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

    setState(() => connectionStatus = "Đang kết nối BLE tới $TARGET_DEVICE_NAME ...");

    try {
      await targetDevice!.connect(timeout: const Duration(seconds: 15));

      _connSub ??= targetDevice!.connectionState.listen((s) {
        setState(() => _connectionState = s);
      });

      setState(() => connectionStatus = "Đã kết nối BLE. Sẵn sàng gửi cấu hình.");
    } catch (e) {
      setState(() => connectionStatus = "Lỗi kết nối BLE: $e");
      try {
        await targetDevice?.disconnect();
      } catch (_) {}
    }
  }

  void connectAndProvision(String ssid, String password) async {
    if (targetDevice == null || _connectionState != BluetoothConnectionState.connected) {
      setState(() => connectionStatus = "Chưa kết nối BLE. Nhấn 'Kết nối BLE' trước.");
      return;
    }

    setState(() => connectionStatus = "Đang khám phá services...");

    try {
      List<BluetoothService> services = await targetDevice!.discoverServices();

      BluetoothService provService = services.firstWhere(
        (s) => s.uuid == PROV_SERVICE_UUID,
        orElse: () => throw Exception("Không tìm thấy Provisioning Service (FF01)"),
      );

      BluetoothCharacteristic ssidChar = provService.characteristics.firstWhere(
        (c) => c.uuid == SSID_CHAR_UUID,
        orElse: () => throw Exception("Không tìm thấy SSID Characteristic (FF02)"),
      );

      BluetoothCharacteristic passChar = provService.characteristics.firstWhere(
        (c) => c.uuid == PASSWORD_CHAR_UUID,
        orElse: () => throw Exception("Không tìm thấy Password Characteristic (FF03)"),
      );

      BluetoothCharacteristic connectChar = provService.characteristics.firstWhere(
        (c) => c.uuid == CONNECT_CHAR_UUID,
        orElse: () => throw Exception("Không tìm thấy Connect Characteristic (FF04)"),
      );

      BluetoothCharacteristic statusChar = provService.characteristics.firstWhere(
        (c) => c.uuid == STATUS_CHAR_UUID,
        orElse: () => throw Exception("Không tìm thấy Status Characteristic (FF05)"),
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
          // Khi Wi-Fi thành công, ngắt kết nối BLE để tối ưu
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
// HÀM ĐIỀU KHIỂN VÂN TAY QUA HTTP
// =======================================================================

  Future<void> _sendFpControlCommand(bool start) async {
    if (_espIp == null) {
      setState(() => connectionStatus = "Chưa có IP Wi-Fi.");
      return;
    }

    final command = start ? "start" : "stop";

    try {
      // Gọi endpoint fpcontrol qua HTTP GET
      final url = 'http://$_espIp/fpcontrol?cmd=$command';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        setState(() => _isFpScanning = start);

        if (start) {
          _startFpScanTimer();
          connectionStatus = "Đã gửi lệnh START quét vân tay (Wi-Fi).";
        } else {
          _stopFpScanTimer();
          connectionStatus = "Đã gửi lệnh STOP. Giữ nguyên ảnh cuối.";
        }
      } else {
        setState(() => connectionStatus = "Lỗi gửi lệnh FP (HTTP ${response.statusCode}): ${utf8.decode(response.bodyBytes)}");
      }
    } catch (e) {
      setState(() => connectionStatus = "Lỗi HTTP gửi lệnh: $e");
    }
  }

  // LẤY ẢNH VÂN TAY (Cập nhật logic Status 204)
  Future<void> _fetchFingerprintImage() async {
    if (_espIp == null) return;

    try {
      final response = await http.get(Uri.parse('http://$_espIp/fpimage'));

      if (response.statusCode == 200) {
        // Thành công: Nhận RAW bytes
        setState(() {
          _fpImageBytes = response.bodyBytes;
          connectionStatus = _isFpScanning
            ? "Đang quét/Ảnh mới (${_fpImageBytes!.length} bytes)"
            : "Ảnh cuối (${_fpImageBytes!.length} bytes)";
        });
      } else if (response.statusCode == 204) { // No Content (Không có ngón tay)
        setState(() => connectionStatus = _isFpScanning ? "Đang quét, chờ ngón tay..." : "Ảnh cuối: Không thay đổi.");
      } else {
        setState(() => connectionStatus = "Lỗi HTTP: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => connectionStatus = "Lỗi HTTP Request: $e");
    }
  }

  // TIMER CHO CHẾ ĐỘ QUÉT LIÊN TỤC
  void _startFpScanTimer() {
    _stopFpScanTimer();
    // Gọi API HTTP cứ mỗi 700ms
    _fpScanTimer = Timer.periodic(const Duration(milliseconds: 700), (timer) {
      if (_espIp != null && _isFpScanning) {
        _fetchFingerprintImage();
      }
    });
  }

  void _stopFpScanTimer() {
    _fpScanTimer?.cancel();
    _fpScanTimer = null;
  }


// =======================================================================
// UI BUILD
// =======================================================================
  @override
  Widget build(BuildContext context) {
    final bool isConnected = _connectionState == BluetoothConnectionState.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('BLE + Fingerprint Scanner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Trạng thái: $connectionStatus', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('BLE: ${_connectionState.name}', style: const TextStyle(color: Colors.grey)),
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

            // Form Provisioning (Chỉ hiển thị khi đã kết nối BLE nhưng chưa có IP)
            if (targetDevice != null && !isScanning && _espIp == null)
              Padding(
                padding: const EdgeInsets.only(top: 30.0),
                child: ProvisioningForm(
                  onSubmit: connectAndProvision,
                ),
              ),

            // Khu vực điều khiển và hiển thị Vân tay (Chỉ hiển thị khi đã có IP)
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
                          Text("ESP32 IP: $_espIp", style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Nút START/STOP (Điều khiển qua HTTP)
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isFpScanning ? null : () => _sendFpControlCommand(true),
                              icon: const Icon(Icons.play_arrow, color: Colors.white),
                              label: const Text("Bắt đầu quét", style: TextStyle(fontSize: 16)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _isFpScanning ? () => _sendFpControlCommand(false) : null,
                              icon: const Icon(Icons.stop, color: Colors.white),
                              label: const Text("Dừng", style: TextStyle(fontSize: 16)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // Khu vực hiển thị Ảnh
              if (_fpImageBytes != null) ...[
                const SizedBox(height: 20),
                Card(
                  elevation: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text("Ảnh vân tay (RAW Grayscale):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                      Container(
                        height: 250,
                        width: double.infinity,
                        color: Colors.black, // Background đen cho vân tay nổi bật
                        // Widget hiển thị ảnh RAW
                        child: ImageWidgetFromRawData(
                          rawData: _fpImageBytes!,
                          width: 256, // Kích thước chuẩn AS608
                          height: 288,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text("${_fpImageBytes!.length} bytes", style: const TextStyle(color: Colors.grey)),
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
// WIDGET XỬ LÝ ẢNH RAW (Cần thư viện 'image')
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
    // Kích thước chuẩn 256*288 = 73728 bytes cho 8-bit grayscale
    if (rawData.length != width * height) {
      return Center(child: Text("Lỗi: Dữ liệu ảnh không đủ/không khớp: ${rawData.length} bytes."));
    }

    try {
        // 1. Tạo đối tượng image từ Raw Grayscale bytes (8-bit)
        final image = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rawData.buffer,
          numChannels: 1, // 1 kênh màu (Grayscale)
        );

        // 2. Chuyển đổi sang PNG để hiển thị trên Flutter
        final pngBytes = img.encodePng(image);

        // 3. Hiển thị ảnh PNG
        return Image.memory(
          pngBytes,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        );
    } catch (e) {
        return Center(child: Text("Lỗi hiển thị ảnh: $e"));
    }
  }
}

// =======================================================================
// CLASS PROVISIONING FORM (Đã sửa lỗi ký tự)
// =======================================================================
class ProvisioningForm extends StatefulWidget {
  final void Function(String, String) onSubmit;
  const ProvisioningForm({super.key, required this.onSubmit});

  @override
  State<ProvisioningForm> createState() => _ProvisioningFormState();
}

class _ProvisioningFormState extends State<ProvisioningForm> {
  final TextEditingController ssidController = TextEditingController(text: "Ten_Wifi_Cua_Toi");
  final TextEditingController passController = TextEditingController(text: "MatKhau_Cua_Toi");

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text("Cấu hình Wi-Fi:", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        const Text(TARGET_DEVICE_NAME, style: TextStyle(color: Colors.blueAccent, fontSize: 16)),
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
                  const SnackBar(content: Text("Vui lòng nhập SSID và Password.")),
                );
                return;
              }
              widget.onSubmit(ssidController.text, passController.text);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("Gửi cấu hình Wi-Fi", style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }
}
