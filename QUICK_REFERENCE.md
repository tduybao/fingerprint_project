# ⚡ Quick Reference - Fingerprint AS608

## 🎯 Vấn đề & Giải pháp

| Vấn đề | Giải pháp |
|--------|-----------|
| Ảnh không hiển thị | Dùng Adafruit API thay vì custom protocol |
| getImage/upimage fail | Check Adafruit library ≥2.0, pin RX/TX |
| Image size sai | readImage() buffer là 512 bytes/hàng, chỉ copy 256 |
| PNG encode fail | Kiểm tra image package ^4.1.0 trong pubspec.yaml |

---

## 📋 Tệp thay đổi

### `FingerprintSensor.h`
```cpp
#include <Adafruit_Fingerprint.h>
Adafruit_Fingerprint* getFingerprintSensor();
```

### `FingerprintSensor.cpp`
**Xoá**: Custom protocol (sendCommand, readAck, etc.)
**Thêm**: Adafruit API
```cpp
static Adafruit_Fingerprint finger(&FPSerial);

// fpLoop()
finger.getImage();      // GENIMG
finger.image2Tz(1);     // UPIMAGE  
finger.readImage();     // Download RAW

// Copy từ finger.image[] (512 bytes/row)
memcpy(&imageBuf[idx], &finger.image[row * 512], 256);
```

### `main.dart`
**Cải thiện**:
- _fetchFingerprintImage(): thêm timeout, validate size
- ImageWidgetFromRawData: dùng `image.data![i]` để copy pixels
- UI: hiển thị ảnh trong Card

---

## 🔗 Hardware

```
AS608     →  ESP32-C6
VCC       →  5V/3.3V
GND       →  GND
RX        →  GPIO 7 (ESP32 TX)
TX        →  GPIO 6 (ESP32 RX)
Baud      →  57600
```

---

## 🚀 Quick Test

```bash
# 1. Upload Arduino code
# Mở Serial Monitor → check "AS608 initialized"

# 2. Test HTTP
curl "http://<IP>/fpcontrol?cmd=start"
curl "http://<IP>/fpimage" --output test.raw
ls -lh test.raw  # Kỳ vọng 73.7K

# 3. Run Flutter app
flutter run
# Nhấn "Bắt đầu quét" → hiển thị ảnh
```

---

## 📊 Thông số ảnh

| Thông số | Giá trị |
|----------|--------|
| Chiều rộng | 256 pixels |
| Chiều cao | 288 pixels |
| Format | 8-bit grayscale |
| Kích thước | 256 × 288 = 73,728 bytes |
| Buffer Adafruit | 512 bytes/row (padding 256 bytes) |

---

## 🧪 Verify Checklist

```
Serial Monitor:
  ☐ [FP] AS608 initialized and verified
  ☐ [FP] Found fingerprint sensor with ID: X
  ☐ [FP] Waiting for valid finger...
  ☐ [FP] Finger detected! Image generated.
  ☐ [FP] Image converted to template
  ☐ [FP] Downloading image from sensor...
  ☐ [FP] Image successfully captured: 73728 bytes

HTTP API:
  ☐ /fpcontrol?cmd=start → 200 OK
  ☐ /fpimage → 73728 bytes

Flutter App:
  ☐ Quét BLE thành công
  ☐ Kết nối WiFi thành công
  ☐ Nút "Bắt đầu quét" work
  ☐ Hiển thị ảnh vân tay
```

---

## 💡 Key Points

1. **Dùng Adafruit API** không phải custom protocol
2. **Buffer Adafruit** 512 bytes/row → copy chỉ 256 bytes
3. **Image size** phải đúng 73,728 bytes
4. **Pin RX/TX đảo** (AS608 RX ← ESP32 TX)
5. **Baud rate** 57600 cố định
6. **Polling** mỗi 700ms trong app

---

## 📞 Debug Links

- [Adafruit AS608 Library](https://github.com/adafruit/Adafruit-Fingerprint-Sensor-Library)
- [AS608 Protocol](https://www.adafruit.com/product/751)
- [image package](https://pub.dev/packages/image)
- [ESP32-C6 Pinout](https://docs.espressif.com/projects/esp-idf/en/latest/esp32c6/hw-reference/esp32c6_devkitc-1_v1.2_pinlayout.pdf)

---

Đủ rồi! Ready to test? 🚀
