# 🚀 Guide Cài Đặt & Test Fingerprint AS608

## 📦 Bước 1: Cài Đặt Arduino Libraries

### 1.1 Mở Arduino IDE
- **Sketch** → **Include Library** → **Manage Libraries**

### 1.2 Cài Adafruit Fingerprint Library
- Tìm: `Adafruit Fingerprint Sensor Library`
- Cài phiên bản **2.0 hoặc mới hơn**
- Click **Install**

### 1.3 Cài Dependencies (tự động)
- Adafruit sẽ yêu cầu cài `Adafruit BusIO`
- Click **Install All**

---

## ⚙️ Bước 2: Cấu Hình Arduino Sketch

### 2.1 Setup Board (ESP32-C6)
```
Tools → Board → esp32 → ESP32-C6 Dev Module
Tools → Port → COM3 (hoặc port của bạn)
Tools → Upload Speed → 921600
```

### 2.2 Verify Pin Configuration
Trong `FingerprintSensor.h`:
```cpp
#define FP_RX 6   // RX pin của AS608
#define FP_TX 7   // TX pin của AS608
```

**Kiểm tra lại board của bạn**:
- ESP32-C6: RX/TX pins có thể khác
- Tìm datasheet hoặc dùng lệnh sau để test

### 2.3 Compile
```
Sketch → Verify/Compile
```

---

## 🔌 Bước 3: Kết Nối Hardware

### 3.1 Sơ đồ kết nối AS608 ↔ ESP32-C6

```
AS608          ESP32-C6
-----          --------
VCC      →     5V / 3.3V
GND      →     GND
RX       →     GPIO 7 (TX)
TX       →     GPIO 6 (RX)
```

**Lưu ý**: RX/TX đảo (AS608 RX ← ESP32 TX)

### 3.2 Kết Nối Cảm Biến
- Đặt cảm biến trên bàn tay
- Cơm gạo/bụi bẩn sẽ ảnh hưởng
- Tay ẩm hoặc quá khô cũng không tốt

---

## 📤 Bước 4: Upload Code

### 4.1 Upload
```
Sketch → Upload
```

### 4.2 Mở Serial Monitor
```
Tools → Serial Monitor
Baud Rate: 115200
```

### 4.3 Kỳ vọng thấy:
```
=== ESP32-C6 AS608 FINGERPRINT SERVER ===
[FP] AS608 initialized and verified
[FP] Found fingerprint sensor with ID: 0
[SYS] Setup done
[WEB] HTTP server started
```

---

## 🧪 Bước 5: Test API HTTP

### 5.1 Tìm IP ESP32
Trong Serial Monitor:
```
[BLE] Provisioning started...
```
Hay dùng router để check IP

### 5.2 Test /fpcontrol
```bash
curl "http://192.168.1.100/fpcontrol?cmd=start"
```

Kỳ vọng:
```
FP scan started
```

### 5.3 Test /fpimage
```bash
# Nhanh sau khi gọi /fpcontrol
curl "http://192.168.1.100/fpimage" --output fingerprint.raw

# Check kích thước
ls -lh fingerprint.raw
# Kỳ vọng: 73.7K (73728 bytes đúng không?)
```

---

## 📱 Bước 6: Test Flutter App

### 6.1 Cập nhật pubspec.yaml
```yaml
dependencies:
  image: ^4.1.0
  http: ^1.2.1
  flutter_blue_plus: ^1.29.15
  permission_handler: ^11.3.1
```

### 6.2 Chạy app
```bash
flutter pub get
flutter run
```

### 6.3 Workflow App
1. Quét BLE → Chọn `FP_Sensor_Front_01`
2. Kết nối BLE
3. Nhập Wi-Fi SSID + Password
4. Gửi cấu hình
5. Chờ kết nối Wi-Fi
6. **Bắt đầu quét** button
7. Đặt ngón tay lên cảm biến
8. ✓ Hiển thị ảnh vân tay

---

## 🐛 Troubleshooting

### ❌ Serial Monitor: "AS608 not found"

**Kiểm tra**:
```cpp
// Trong setup()
Serial.begin(115200);
delay(1000);

// Check UART
Serial.println("Testing UART...");
FPSerial.begin(57600, SERIAL_8N1, FP_RX, FP_TX);
delay(500);

// Thử gửi cmd
finger.verifyPassword();
```

**Giải pháp**:
- Kiểm tra dây RX/TX không sai
- Đảo RX/TX thử lại
- Kiểm tra baud rate (57600)
- Kiểm tra GND connected

---

### ❌ Serial: "No finger detected"

**Kiểm tra**:
- Ngón tay sạch sẽ (gạo sẽ fail)
- Không quá ẩm
- Áp lực đủ
- Vân tay rõ ràng

**Giải pháp**:
- Thử cả 5 ngón tay
- Thử người khác
- Tăng thời gian giữ (getImage timeout default 2s)

---

### ❌ API trả về 404 "Image not ready"

**Nguyên nhân**: Chưa gọi /fpcontrol?cmd=start

**Giải pháp**:
1. Gọi /fpcontrol?cmd=start
2. Đặt ngón tay
3. **Ngay sau đó** gọi /fpimage
4. Hoặc dùng polling (app tự động làm)

---

### ❌ App: "Dữ liệu ảnh không đúng"

**Nguyên nhân**: `_fpImageBytes.length != 73728`

**Kiểm tra**:
```dart
print("Image size: ${_fpImageBytes.length}");
// Kỳ vọng: 73728
```

**Giải pháp**:
- Check `/fpimage` API trả về đúng size
- Check response.bodyBytes (byte stream) có bị cắt không
- Tăng timeout HTTP từ 5s → 10s

---

### ❌ App: "Lỗi hiển thị ảnh"

**Nguyên nhân**: image encoding fail

**Giải pháp**:
```dart
// Trong build()
try {
    final image = img.Image(width: 256, height: 288);
    for (int i = 0; i < rawData.length; i++) {
        image.data![i] = rawData[i];
    }
    final pngBytes = img.encodePng(image);
    // ✓ Success
} catch (e) {
    print("Error: $e");
}
```

---

## 🔧 Advanced Debugging

### Serial Log từ ESP32:
```cpp
// Thêm vào fpLoop()
Serial.printf("[DEBUG] Image buffer: %p\n", finger.image);
Serial.printf("[DEBUG] Row 0 first 10 bytes: ");
for (int i = 0; i < 10; i++) {
    Serial.printf("%02X ", finger.image[i]);
}
Serial.println();
```

### HTTP Debug từ App:
```dart
// Thêm vào _fetchFingerprintImage()
print("[HTTP] Status: ${response.statusCode}");
print("[HTTP] Length: ${response.bodyBytes.length}");
print("[HTTP] First 10 bytes: ${response.bodyBytes.take(10).toList()}");
```

### Test bằng terminal:
```bash
# Windows/Linux/Mac
# Tải ảnh
curl "http://192.168.1.100/fpimage" -o image.raw

# Xem dung lượng
stat image.raw          # Linux/Mac
dir image.raw           # Windows

# Convert thành PNG (nếu có imagemagick)
convert -depth 8 -size 256x288 gray:image.raw image.png
```

---

## ✅ Checklist Before Production

- [ ] AS608 kết nối đúng (VCC, GND, RX, TX)
- [ ] Adafruit library cài ≥2.0
- [ ] Serial Monitor show "AS608 initialized"
- [ ] /fpcontrol API return 200
- [ ] /fpimage API return 73728 bytes
- [ ] App hiển thị ảnh vân tay đúng
- [ ] Image output là grayscale (không bị color/RGB)
- [ ] Wi-Fi BLE provisioning work
- [ ] HTTP API accessible qua WiFi

---

Good luck! 💪 Chúc thành công!
