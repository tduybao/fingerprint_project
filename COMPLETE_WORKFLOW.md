# 🎯 **WORKFLOW CHI TIẾT - Capture & Display Hình Vân Tay**

## 📱 **User's Perspective**

```
[App - Flutter]
│
├─ Màn hình: "Bắt đầu quét"
│  └─ User nhấn nút
│
├─ Status: "Đang quét..."
│  └─ Cảm biến chờ ngón tay
│
├─ [User đặt ngón tay]
│
├─ Status: "✓ Ảnh vân tay mới (73728 bytes)"
│  └─ Hiển thị ảnh grayscale rõ ràng
│
└─ [Có thể quét lại]
   └─ Không bị "đơ"
```

---

## 🔧 **Device's Perspective (3 STEPS)**

### **STEP 1: GENIMG - Chụp Ảnh (~500ms - 2s)**

```cpp
p = finger.getImage();  // Adafruit API
```

**Chi tiết công việc bên AS608**:
```
1. AS608 nhận command GENIMG (0x01)
2. AS608 bắt đầu sensor scanning
3. AS608 chờ ngón tay → "Đặt ngón tay lên"
4. User đặt ngón tay vào cảm biến
5. AS608 detect contact & ánh sáng → OK
6. AS608 capture ảnh 256×288 → ImageBuffer
7. AS608 trả lại: FINGERPRINT_OK (0x00)
```

**Possible Returns**:
- `FINGERPRINT_OK` ✅ - Ảnh đẹp, lưu thành công
- `FINGERPRINT_NOFINGER` ❌ - Timeout (chờ 1s, không detect)
- `FINGERPRINT_IMAGEFAIL` ❌ - Capture fail (sensor error)

**Serial Log**:
```
[FP] STEP 1: Waiting for valid finger to generate image...
[FP] getImage() took 1500ms
[FP] ✓ STEP 1 OK: Finger detected! Image generated.
```

---

### **STEP 2: IMG2TZ - Convert Template (~50-150ms)**

```cpp
p = finger.image2Tz(1);  // Adafruit API
```

**Chi tiết công việc bên AS608**:
```
1. AS608 nhận command IMG2TZ (0x02)
2. AS608 lấy ảnh từ ImageBuffer
3. AS608 extract fingerprint features/minutiae
4. AS608 convert thành CharBuffer slot 1
5. AS608 xác nhận: FINGERPRINT_OK
```

**Image Quality Checks**:
- `FINGERPRINT_IMAGEMESS` ❌ - Ảnh quá mờ/nhiễu
- `FINGERPRINT_FEATUREFAIL` ❌ - Không tìm được vân tay
- `FINGERPRINT_INVALIDIMAGE` ❌ - Ảnh không hợp lệ

**Serial Log**:
```
[FP] STEP 2: Converting image to template...
[FP] image2Tz() took 50ms
[FP] ✓ STEP 2 OK: Image converted. Ready to download RAW image.
```

---

### **STEP 3: DOWNLOAD RAW IMAGE (~2-4s)**

```cpp
if (!downloadImageFromAS608()) return false;
```

**Chi tiết công việc bên AS608**:
```
1. ESP32 gửi UpImage command (0x0A) tới AS608
2. AS608 nhận command → Bắt đầu gửi data packets
3. AS608 gửi data packets:
   ├─ Packet 1: Header + Address + Type + Length + [256 bytes] + Checksum
   ├─ Packet 2: [tiếp...]
   ├─ Packet 3: ...
   └─ Packet 288: [bytes 73472-73727]
4. AS608 gửi END packet (0x08) → Transfer done
5. ESP32 nhận tất cả 73,728 bytes vào imageBuf[]
```

**Packet Structure**:
```
┌──────┬─────────┬──────┬────────┬──────────────┬──────────┐
│Header│Address  │Type  │Length  │Data (256B)   │Checksum  │
├──────┼─────────┼──────┼────────┼──────────────┼──────────┤
│EF01  │FFFFFFFF │0x02  │0100    │[pixel bytes] │xxxx      │
└──────┴─────────┴──────┴────────┴──────────────┴──────────┘
```

**Download Process**:
```
Start:                0 bytes
After packet 1:       256 bytes (0.3%)
After packet 32:      8,192 bytes (11.1%)
After packet 64:      16,384 bytes (22.2%)
After packet 128:     32,768 bytes (44.4%)
After packet 192:     49,152 bytes (66.7%)
After packet 256:     65,536 bytes (88.9%)
After packet 288:     73,728 bytes (100%)
```

**Serial Log**:
```
[FP] STEP 3: Downloading RAW image from AS608...
[FP] Data packet 0: reading 256 bytes
[FP] Progress: 256/73728 bytes (0.3%)
[FP] Progress: 2048/73728 bytes (2.8%)
[FP] Progress: 4096/73728 bytes (5.5%)
[FP] Progress: 8192/73728 bytes (11.1%)
...
[FP] Received END packet
[FP] SUCCESS: Received all 73728 bytes in 3200ms
[FP] ✓ STEP 3 OK
```

---

## 📊 **Timeline Example**

```
T=0ms       User clicks "Bắt đầu quét"
│           GET /fpcontrol?cmd=start
│
T=50ms      STEP 1 START: getImage()
│           [AS608 waiting for finger]
│
T=500ms     [User lightly touches sensor]
│
T=1000ms    [User presses harder]
│
T=1550ms    STEP 1 DONE: Image captured
│           getImage() took ~1500ms
│
T=1600ms    STEP 2 START: image2Tz()
│           [Feature extraction]
│
T=1650ms    STEP 2 DONE: Template ready
│           image2Tz() took ~50ms
│
T=1700ms    STEP 3 START: downloadImageFromAS608()
│           [Send UpImage command]
│
T=1750ms    [Packet 1 arrives]
T=1800ms    [Packet 2 arrives]
T=1850ms    [Packet 3 arrives]
│           ...
T=4900ms    [All 288 packets received]
│           [END packet arrives]
│
T=4950ms    STEP 3 DONE: Image stored
│           Download took ~3250ms
│
T=4960ms    [imageBuf[73728] = ready]
│
═════════════════════════════════════════
TOTAL TIME: ~4950ms (~5 seconds)
═════════════════════════════════════════

T=5000ms    App polling: GET /fpimage
│           ↓ Receive 73,728 bytes
│
T=5020ms    App: Convert RAW → PNG
│
T=5050ms    App: Display fingerprint image ✓
│
T=5500ms    User: Can scan again
│           GET /fpcontrol?cmd=start (STEP 1 again)
│           [No hang/freeze - responsive!]
```

---

## 🔄 **Repeat Scan Behavior**

### **Scan 1**:
```
T=0s    Start scan → STEP 1: getImage()
T=2s    Image captured → STEP 2: image2Tz()
T=2.1s  Template ready → STEP 3: download
T=5s    Download done → Display image ✓
```

### **Scan 2** (immediately after):
```
T=5s    Tap "Scan again"
T=5.05s Start STEP 1: getImage() [NEW instance]
        [Waiting for NEW finger image]
T=5.5s  [User places different finger]
T=6.5s  Image captured → STEP 2
T=7.5s  Download done → Display NEW image ✓
        [No freeze - fresh state!]
```

**Key Point**: Each scan is independent - no state carryover

---

## 🚀 **Why This Design Prevents Freezing**

### **❌ Old Design (Freezes)**:
```
timeout while(!available && millis() - start < 1000) {  // 1 second!
  delay(1);
}
// If byte is lost: wait 1s × 256 bytes = 256 seconds = 4+ minutes = FREEZE!
```

### **✅ New Design (Responsive)**:
```
timeout while(!available && millis() - start < 100) {  // 100ms!
  delayMicroseconds(100);  // 0.1ms
}
// If byte is lost: wait 100ms → skip packet → continue = NO FREEZE!
```

---

## 📱 **App Integration**

### **Flutter Code Flow**:

```dart
// main.dart - _startFingerprintScan()
Future<void> _startFingerprintScan() async {
  // 1. Send start command
  http.get('http://$_espIp/fpcontrol?cmd=start')
  // → ESP32 starts STEP 1: getImage()

  // 2. Poll for image every 700ms
  Timer.periodic(Duration(ms: 700), (timer) {
    http.get('http://$_espIp/fpimage')
    // → GET imageBuf[] data
  });
}

// ImageWidgetFromRawData.build()
// 3. Convert RAW → PNG
img.Image(...).data![i] = rawData[i];
encodePng() → PNG bytes

// 4. Display
Image.memory(pngBytes) → 显示图像 ✓
```

---

## 💡 **Summary**

| Phase | Time | Job | Status |
|-------|------|-----|--------|
| STEP 1 | 500ms-2s | getImage() | ✓ Adafruit API |
| STEP 2 | 50-150ms | image2Tz() | ✓ Adafruit API |
| STEP 3 | 2-4s | Download RAW | ✓ Custom protocol |
| **TOTAL** | **3-6s** | **All steps** | **✓ No freeze** |
| Repeat | **Instant** | **No carryover** | **✓ Independent** |

---

**Bạn có workflow tối ưu, safe, và responsive! 🎉**
