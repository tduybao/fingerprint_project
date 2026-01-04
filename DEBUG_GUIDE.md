# Hướng dẫn Debug - Fingerprint AS608

## Vấn đề chính đã sửa:

### 1. **Code C++ (FingerprintSensor.cpp)**
- ✅ **Thay đổi**: Dùng Adafruit AS608 library thay vì custom protocol
- **Tại sao**: Adafruit đã xử lý tất cả chi tiết giao thức phức tạp
  - `finger.getImage()` - Chụp ảnh từ cảm biến
  - `finger.image2Tz()` - Convert ảnh thành template
  - `finger.readImage()` - Download ảnh RAW từ cảm biến
  - `finger.image[]` - Buffer lưu ảnh RAW (512 bytes/hàng)

**Lưu ý quan trọng**: 
- Buffer của Adafruit là 512 bytes/hàng (do AS608 spec), nhưng chỉ 256 bytes dữ liệu đầu tiên
- Phần còn lại là padding/reserved
- Chúng ta memcpy chỉ 256 bytes từ mỗi hàng vào imageBuf

### 2. **Code Dart (main.dart)**
- ✅ **Thay đổi**: Cải thiện xử lý ảnh và UI hiển thị
  - Tạo Image object đúng cách (grayscale 8-bit)
  - Sử dụng `image.data!` để access pixel buffer
  - Thêm error handling chi tiết
  - UI hiển thị kích thước ảnh và dung lượng

## Checklist Debug:

### **Bước 1: Kiểm tra Serial Monitor (Arduino IDE)**
```
Mục tiêu: Xem log từ ESP32
```
- Mở Serial Monitor ở 115200 baud
- Nhấn "Bắt đầu quét"
- **Kỳ vọng thấy**:
```
[FP] Waiting for valid finger to generate image...
[FP] Finger detected! Image generated.
[FP] Image converted to template
[FP] Downloading image from sensor...
[FP] Image successfully captured: 73728 bytes
```

**Nếu không thấy**:
- Kiểm tra kết nối UART (RX=6, TX=7)
- Kiểm tra pin AS608: VCC, GND, RX, TX
- Thử `finger.verifyPassword()` - phải return true

---

### **Bước 2: Kiểm tra API HTTP**
```
Mục tiêu: Xem ảnh từ API trước khi hiển thị app
```

**Test /fpcontrol**:
```bash
curl "http://<ESP32_IP>/fpcontrol?cmd=start"
# Kỳ vọng: "FP scan started" (200 OK)
```

**Test /fpimage**:
```bash
curl "http://<ESP32_IP>/fpimage" --output /tmp/fp.raw
hexdump -C /tmp/fp.raw | head
# Kỳ vọng: File có kích thước 73728 bytes (256*288)
```

---

### **Bước 3: Kiểm tra Flutter App**
```
Mục tiêu: Xem ảnh hiển thị trên app
```

**Kỳ vọng khi nhấn "Bắt đầu quét"**:
1. Trạng thái: "⏳ Đang chờ ảnh từ cảm biến..."
2. Đặt ngón tay lên cảm biến
3. Trạng thái: "✓ Ảnh vân tay mới (73728 bytes)"
4. Hiển thị hình ảnh vân tay grayscale

**Nếu thất bại**:
- Kiểm tra log Dart: `flutter logs`
- Xem trạng thái trong app
- Kiểm tra IP ESP32 chính xác

---

## Các thay đổi cụ thể:

### FingerprintSensor.h
```cpp
// Thêm include Adafruit_Fingerprint.h
#include <Adafruit_Fingerprint.h>

// Thêm hàm getter instance
Adafruit_Fingerprint* getFingerprintSensor();
```

### FingerprintSensor.cpp
```cpp
// 1. Dùng Adafruit instance
static Adafruit_Fingerprint finger(&FPSerial);

// 2. Hàm fpInit()
if (finger.verifyPassword()) {
    // AS608 connected ✓
}

// 3. Hàm fpLoop() - dùng Adafruit API
p = finger.getImage();           // GENIMG
p = finger.image2Tz(1);          // UPIMAGE
p = finger.readImage();          // Download RAW

// 4. Copy ảnh từ finger.image[] vào imageBuf
// Lưu ý: finger.image[row * 512] là data hàng row
```

### main.dart
```dart
// 1. _fetchFingerprintImage() - thêm timeout và validate
if (response.bodyBytes.length == expectedSize) {
    // ✓ Ảnh đúng kích thước
}

// 2. ImageWidgetFromRawData - cách tạo Image đúng
final image = img.Image(width: 256, height: 288);
for (int i = 0; i < rawData.length; i++) {
    image.data![i] = rawData[i];
}

// 3. UI - hiển thị ảnh trong Card với info
Container(
    height: 320,
    child: ImageWidgetFromRawData(...)
)
```

---

## Kích thước lý thuyết:
- **Ảnh RAW**: 256 x 288 = 73,728 bytes (8-bit grayscale)
- **Mỗi pixel**: 1 byte (0-255)
- **Khu vực hợp lệ**: Toàn bộ 73,728 bytes

---

## Nếu vẫn không hoạt động:

### 1. Kiểm tra Adafruit library
```bash
# Trong Arduino IDE: Sketch → Include Library → Manage Libraries
# Tìm "Adafruit Fingerprint Sensor Library"
# Cài phiên bản mới nhất (≥2.0)
```

### 2. Kiểm tra pubspec.yaml
```yaml
dependencies:
  image: ^4.1.0  # Cần package này để convert RAW → PNG
  http: ^1.2.1   # Để gọi HTTP API
```

### 3. Serial debug từ app
```dart
// Thêm vào _fetchFingerprintImage()
print("[DEBUG] Response size: ${response.bodyBytes.length}");
print("[DEBUG] First 10 bytes: ${response.bodyBytes.take(10).toList()}");
```

---

## Lệnh test nhanh:

```bash
# 1. Ping ESP32
ping <ESP32_IP>

# 2. Test API
curl -v http://<ESP32_IP>/fpcontrol?cmd=start

# 3. Lấy ảnh
curl http://<ESP32_IP>/fpimage --output test.raw
stat test.raw  # Xem kích thước (73728 bytes?)
```

Chúc bạn thành công! 🎯
