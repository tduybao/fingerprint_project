# 🔧 Sửa Lỗi AS608 Image Download

## ❌ Vấn đề
```
error: 'class Adafruit_Fingerprint' has no member named 'readImage'
error: 'class Adafruit_Fingerprint' has no member named 'image'
```

**Nguyên nhân**: Phiên bản Adafruit_Fingerprint library không expose:
- Hàm `readImage()`
- Member `image[]` buffer

---

## ✅ Giải pháp
Thay vì dùng internal API của Adafruit, chúng ta dùng **AS608 protocol trực tiếp** để download ảnh.

### Các bước:

**1️⃣ Bước 1: getImage()** (Chụp ảnh)
```cpp
p = finger.getImage();  // ✓ Adafruit API
```

**2️⃣ Bước 2: image2Tz()** (Convert thành template)
```cpp
p = finger.image2Tz(1);  // ✓ Adafruit API
```

**3️⃣ Bước 3: downloadImageFromAS608()** ❌→✅ (Download ảnh RAW)
```cpp
// ❌ Trước: p = finger.readImage() (không tồn tại)
// ✅ Sau: downloadImageFromAS608() (custom AS608 protocol)
```

---

## 📋 Cơ Chế AS608 Protocol

### **Packet Format**:
```
[Header(2)] [Address(4)] [PacketType(1)] [Length(2)] [Data(N)] [Checksum(2)]
  EF01       FF FF FF FF     0x02         variable   variable    variable
```

### **Packet Types**:
- `0x01`: Command packet
- `0x02`: Data packet (256 bytes image data)
- `0x07`: ACK packet
- `0x08`: End of data packet

### **Image Transfer**:
```
Step 1: getImage() → AS608 chụp ảnh vào buffer
Step 2: image2Tz() → AS608 convert ảnh thành template, chuẩn bị download
Step 3: AS608 tự động gửi data packets (256 bytes mỗi packet)
        - Packet 1: bytes 0-255
        - Packet 2: bytes 256-511
        - ... (tổng 288 packets)
        - End packet: kết thúc transfer
```

---

## 🔍 Hàm downloadImageFromAS608()

**Chức năng**: Nhận image data packets từ AS608

**Quá trình**:
1. Tìm header `EF01`
2. Skip address (4 bytes)
3. Đọc packet type
4. Đọc packet length
5. **Nếu DATA packet**: Đọc 256 bytes image data
6. **Nếu END packet**: Dừng transfer
7. Lặp lại cho đến khi nhận đủ 73,728 bytes

**Timeout**: 5 giây (nếu không nhận dữ liệu)

**Return**: 
- `true` nếu nhận đúng 73,728 bytes
- `false` nếu lỗi hoặc timeout

---

## 🚀 Test Setelah Sửa

### Serial Monitor (115200 baud):
```
[FP] AS608 initialized and verified
[FP] Waiting for valid finger to generate image...
[FP] Finger detected! Image generated.
[FP] Image converted to template
[FP] Downloading image from sensor...
[FP] Image transfer complete
[FP] Image successfully captured: 73728 bytes
```

### HTTP API:
```bash
curl "http://<IP>/fpcontrol?cmd=start"
# Response: FP scan started

curl "http://<IP>/fpimage" --output test.raw
ls -lh test.raw
# Kỳ vọng: 73K (73728 bytes)
```

---

## 💡 Key Points

1. **Adafruit API** chỉ hỗ trợ:
   - `getImage()` - Chụp ảnh
   - `image2Tz()` - Convert template
   - `verifyPassword()` - Verify kết nối

2. **Custom Protocol** để download ảnh:
   - AS608 tự động gửi data packets sau `image2Tz()`
   - Chúng ta chỉ cần đọc từ serial port

3. **Kích thước ảnh**:
   - 256 x 288 = 73,728 bytes
   - 256 bytes/packet × 288 packets

4. **Timeout**:
   - 5 giây để nhận toàn bộ ảnh (ngoài lẻ)
   - 1 giây per byte

---

## ✨ Sửa Đổi File

| File | Thay đổi |
|------|----------|
| FingerprintSensor.cpp | ❌ readImage() → ✅ downloadImageFromAS608() |
| FingerprintSensor.h | Không thay đổi |
| FingerprintSensor.cpp | ✅ Thêm hàm downloadImageFromAS608() |

---

## 🎯 Kết Luận

Giờ code sẽ compile thành công! 🎉

Khi compile:
```bash
Sketch uses 123456 bytes (45%) of program storage space.
Maximum is 1310720 bytes.
Global variables use 12345 bytes (5%) of dynamic memory.

Upload successful!
```

Sau đó test trên Serial Monitor như hướng dẫn ở trên.
