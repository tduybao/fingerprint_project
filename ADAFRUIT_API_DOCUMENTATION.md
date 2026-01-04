# 📚 Adafruit Fingerprint Sensor Library - API Documentation

**Chi tiết API của Adafruit Fingerprint Sensor Library cho AS608**

---

## 📋 Mục Lục

1. [Public Methods/Functions](#1-public-methodsfunctions-để-lấy-dữ-liệu-ảnh)
2. [Buffer Memory & getImage()](#2-buffer-memory--getimage-lưu-ảnh-ở-đâu)
3. [Raw Image Functions](#3-raw-image-functions)
4. [Header File (Adafruit_Fingerprint.h)](#4-header-file-adafruit_fingerprinph)
5. [Accessing Pixel Data](#5-cách-access-pixel-data-sau-khi-getimage)
6. [SYDEMO Method](#6-phương-pháp-sydemo)
7. [Code Examples](#7-code-examples)

---

## 1. Public Methods/Functions Để Lấy Dữ Liệu Ảnh

### ✅ Các hàm có sẵn trong Adafruit_Fingerprint:

| Method | Return Type | Description |
|--------|------------|-------------|
| `getImage()` | `uint8_t` | **Chụp ảnh từ cảm biến** vào ImageBuffer (AS608 internal) |
| `image2Tz(slot)` | `uint8_t` | **Convert ảnh thành template** và lưu vào CharBuffer slot (1 or 2) |
| `readImage()` | `uint8_t` | ❌ **KHÔNG CÓ** - Hàm này không public trong library |
| `downloadImage()` | ❌ | **KHÔNG CÓ** - Phải dùng custom protocol |
| `getRawImage()` | ❌ | **KHÔNG CÓ** - Phải dùng custom protocol |
| `getImageBuffer()` | ❌ | **KHÔNG CÓ** - Phải dùng direct protocol |
| `image[]` | `uint8_t[1024]` | ❌ **KHÔNG PUBLIC** - Không accessible trực tiếp từ public API |

### 📝 Return Codes (Result Codes):

```cpp
#define FINGERPRINT_OK                0x00
#define FINGERPRINT_NOFINGER          0x01  // getImage: Không có ngón tay
#define FINGERPRINT_IMAGEFAIL         0x02  // getImage: Chụp ảnh thất bại
#define FINGERPRINT_IMAGEMESS         0x03  // image2Tz: Ảnh quá "messy"
#define FINGERPRINT_FEATUREFAIL       0x04  // image2Tz: Không tìm được feature
#define FINGERPRINT_PACKETRECIEVEERR  0x05  // Packet error
#define FINGERPRINT_INVALIDIMAGE      0x06  // Ảnh không hợp lệ
```

---

## 2. Buffer Memory - getImage() Lưu Ảnh Ở Đâu?

### 📍 Khi `getImage()` được gọi:

```
┌─────────────────────────────────────────────────────┐
│         AS608 Sensor (Internal Memory)              │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │      ImageBuffer (256 × 288 = 73,728 bytes) │  │
│  │    (Lưu ảnh raw sau khi chụp)                │  │
│  └──────────────────────────────────────────────┘  │
│         ↓ (image2Tz)                                │
│  ┌──────────────────────────────────────────────┐  │
│  │    CharBuffer Slot (1 or 2) - 512 bytes      │  │
│  │    (Lưu template sau khi convert)            │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
        ↓
    Nếu muốn download ảnh raw:
    Phải dùng AS608 UPIMAGE protocol
    để đọc từ ImageBuffer
```

### **Chi tiết:**

1. **getImage() → ImageBuffer (AS608 internal)**
   - Ảnh được lưu **bên trong AS608**, không phải ESP32
   - Phải dùng custom protocol để download

2. **image2Tz(slot) → CharBuffer (AS608 internal)**
   - Convert ảnh thành feature vector (512 bytes)
   - Lưu ở slot 1 hoặc 2 trong AS608

3. **Adafruit không expose internal buffers**
   - Phần `private` của Adafruit class
   - Phải dùng AS608 protocol trực tiếp

---

## 3. Raw Image Functions - Kiểm Tra Hàm Nào Có

### ❌ Hàm KHÔNG CÓ trong Adafruit_Fingerprint:

```cpp
// ❌ Không tồn tại
finger.readImage();           // Không có
finger.getImageBuffer();      // Không có
finger.getRawImage();         // Không có
finger.image[];               // Không public
finger.imageBuffer[];         // Không có
finger.downloadImage();       // Không có
```

### ✅ Giải pháp: Dùng AS608 Protocol Trực Tiếp

Xem project của bạn: `FingerprintSensor.cpp` - Hàm `downloadImageFromAS608()`

```cpp
// Custom protocol để download ảnh raw từ AS608
static bool downloadImageFromAS608() {
  // Gửi UPIMAGE command (0x0A) qua serial
  // AS608 tự động gửi về data packets (256 bytes/packet)
  // Tổng 288 packets = 73,728 bytes
  
  // Lưu vào imageBuf[FP_IMG_SIZE]
  // Return true nếu nhận đủ dữ liệu
}
```

---

## 4. Header File - Adafruit_Fingerprint.h

### 📄 Public Members & Methods:

```cpp
// ==================== PUBLIC ====================

// Constructor
Adafruit_Fingerprint(HardwareSerial *serial);

// ===== Initialization =====
boolean verifyPassword(void);           // Check connection
uint16_t templateCount;                 // Property: Số template
uint16_t templateDatabase;              // Property: Database status

// ===== Capture Image =====
uint8_t getImage(void);                 // GENIMG command
    // Chụp ảnh từ cảm biến vào ImageBuffer
    // Return: FINGERPRINT_OK, FINGERPRINT_NOFINGER, etc.

// ===== Process Image =====
uint8_t image2Tz(uint8_t slot);         // UPIMAGE command
    // Convert ảnh thành feature vector (template)
    // slot: 1 or 2 (CharBuffer location)
    // Return: FINGERPRINT_OK, FINGERPRINT_FEATUREFAIL, etc.

uint8_t createModel(void);              // REGMODEL command
    // Merge 2 templates (slot 1 & 2) thành final template

uint8_t storeModel(uint16_t location);  // STORE command
    // Lưu template vào FLASH (location: 0-161)

uint8_t fastSearch(void);               // SEARCH command
    // Tìm kiếm template trong FLASH database

uint8_t matchTemplate(void);            // MATCH command
    // Compare templates từ 2 slots

// ===== Delete =====
uint8_t deleteModel(uint16_t location); // DELETE command
uint8_t emptyDatabase(void);            // EMPTYDB command

// ===== Utility =====
uint8_t getParameters(void);            // Get sensor parameters
uint32_t readAddress;                   // Current packet address
uint32_t capacity;                      // Sensor capacity
uint32_t securityLevel;                 // Security level

// ==================== PRIVATE ====================
// ❌ Không access từ ngoài:

// uint8_t image[1024];                 // Private: ImageBuffer
// void writeStructuredPacket(...);     // Private
// uint8_t readStructuredPacket(...);   // Private
// ... (các method khác)
```

### ❌ Không Expose:

```cpp
// Không public:
uint8_t image[];                    // Image buffer (512 bytes/row × 288 rows)
uint8_t fingerBuffer[];             // Template buffer
uint8_t readImage();                // Method không public
uint8_t downloadImage();            // Method không public
uint8_t getRawImage();              // Method không public
uint8_t getImageBuffer();           // Method không public
```

---

## 5. Cách Access Pixel Data Sau Khi getImage()

### ❌ Cách KHÔNG làm (Adafruit không expose):

```cpp
// ❌ Lỗi - private member
uint8_t byte = finger.image[100];

// ❌ Lỗi - method không tồn tại
uint8_t* ptr = finger.getImageBuffer();

// ❌ Lỗi - method không tồn tại
finger.readImage();
```

### ✅ Cách ĐÚNG: Dùng AS608 Protocol Trực Tiếp

Từ project của bạn (`FingerprintSensor.cpp`):

```cpp
// ===== Bước 1: Chụp ảnh =====
p = finger.getImage();          // Ảnh lưu trong AS608 ImageBuffer
if (p != FINGERPRINT_OK) return false;

// ===== Bước 2: Convert thành template =====
p = finger.image2Tz(1);         // Convert & lưu vào CharBuffer slot 1
if (p != FINGERPRINT_OK) return false;

// ===== Bước 3: Download ảnh raw từ AS608 =====
// Gửi UPIMAGE command (0x0A) qua serial port
// AS608 sẽ tự động gửi về data packets

if (!downloadImageFromAS608()) {  // Custom function
  return false;
}

// ===== Giờ pixel data lưu trong imageBuf[] =====
uint8_t pixel = imageBuf[0];      // Pixel 0
uint16_t width = 256;
uint16_t height = 288;
uint16_t row = 5, col = 10;
uint8_t pixelAt = imageBuf[row * width + col];
```

### 📊 Buffer Structure:

```
imageBuf[73728] = {
  // Row 0
  imageBuf[0],    imageBuf[1],    ... imageBuf[255],
  // Row 1
  imageBuf[256],  imageBuf[257],  ... imageBuf[511],
  // ...
  // Row 287
  imageBuf[73472], ... imageBuf[73727]
}

// Access formula:
pixel_at(row, col) = imageBuf[row * 256 + col]
```

---

## 6. Phương Pháp SYDEMO

### 🔍 SYDEMO (Synaptics Demo):

SYDEMO là **official demo application** từ Synaptics cho AS608. Họ download ảnh bằng **AS608 protocol trực tiếp**, KHÔNG dùng Adafruit library.

### Các hàm SYDEMO dùng:

```cpp
// ===== SYDEMO Protocol =====

1. GenImage()           // Command 0x01 - Chụp ảnh
   - Gửi: packet với cmd 0x01
   - Nhận: ACK with status

2. Img2Tz()            // Command 0x02 - Upload & Convert
   - Gửi: packet với cmd 0x02
   - Nhận: ACK with status

3. UpImage()           // Command 0x0A - Download ảnh
   - Gửi: packet với cmd 0x0A + parameter (ImageBuffer=0x01)
   - Nhận: Data packets (256 bytes/packet) × 288 packets
           + End packet
   - Lưu vào buffer
```

### 📝 Packet Format SYDEMO sử dụng:

```
Command Packet:
┌────────────────────────────────────────────┐
│ Header   │ Address  │ PktType │ Len │ Cmd │ Checksum │
│ EF 01    │ FF... FF │   01    │ ... │ ... │   ...    │
│ (2 byte) │ (4 byte) │ (1 byte)│(2)  │ (?) │ (2 byte) │
└────────────────────────────────────────────┘

Data Packet (AS608 gửi về):
┌──────────────────────────────────────────────┐
│ Header   │ Address  │ PktType │ Len │ Data  │ Checksum │
│ EF 01    │ FF... FF │   02    │256  │ [256] │   ...    │
│ (2)      │ (4)      │ (1)     │ (2) │ (256) │ (2)      │
└──────────────────────────────────────────────┘
```

### Adafruit Implementation:

```cpp
// Adafruit cũng dùng cách này nhưng:
// 1. Wrap trong object-oriented API
// 2. Expose: getImage(), image2Tz()
// 3. Không expose: readImage(), image[] buffer

// Cách SYDEMO download ảnh:
getImage() → image2Tz() → [Manual Serial Protocol] → Download raw bytes
```

---

## 7. Code Examples

### ✅ Example 1: Chụp & Lưu Ảnh (Adafruit + Custom Protocol)

```cpp
#include <Adafruit_Fingerprint.h>
#include <HardwareSerial.h>

HardwareSerial FPSerial(1);
Adafruit_Fingerprint finger(&FPSerial);

uint8_t imageBuf[256 * 288];  // Raw image buffer

void setup() {
  Serial.begin(115200);
  FPSerial.begin(57600, SERIAL_8N1, 6, 7);  // RX=6, TX=7 (ESP32-C6)
  
  delay(300);
  
  if (!finger.verifyPassword()) {
    Serial.println("ERROR: AS608 not found!");
    while(1);
  }
  
  Serial.println("✓ AS608 initialized");
}

void loop() {
  // ===== Bước 1: Chụp ảnh =====
  uint8_t p = finger.getImage();
  
  if (p == FINGERPRINT_OK) {
    Serial.println("✓ Image captured");
  } else if (p == FINGERPRINT_NOFINGER) {
    Serial.println("No finger detected");
    return;
  } else {
    Serial.printf("✗ getImage failed: 0x%02X\n", p);
    return;
  }
  
  // ===== Bước 2: Convert thành template =====
  p = finger.image2Tz(1);
  
  if (p != FINGERPRINT_OK) {
    Serial.printf("✗ image2Tz failed: 0x%02X\n", p);
    return;
  }
  
  Serial.println("✓ Image converted to template");
  
  // ===== Bước 3: Download ảnh raw (Custom Protocol) =====
  if (downloadImageFromAS608()) {
    Serial.println("✓ Image downloaded!");
    
    // Giờ imageBuf[] có chứa raw pixel data
    Serial.printf("Pixel[0,0] = %d\n", imageBuf[0]);
    Serial.printf("Pixel[10,10] = %d\n", imageBuf[10 * 256 + 10]);
  } else {
    Serial.println("✗ Failed to download image");
  }
}

// ===== Custom Protocol: Download Image =====
bool downloadImageFromAS608() {
  const uint32_t TIMEOUT = 5000;
  const uint32_t PIXEL_TIMEOUT = 1000;
  
  uint32_t lastData = millis();
  uint32_t idx = 0;
  
  while (idx < (256 * 288)) {
    // Tìm header EF01
    while (FPSerial.available() < 2 && millis() - lastData < TIMEOUT) {
      delay(10);
    }
    
    if (millis() - lastData > TIMEOUT) {
      return false;
    }
    
    uint8_t h1 = FPSerial.read();
    uint8_t h2 = FPSerial.read();
    
    if (h1 != 0xEF || h2 != 0x01) continue;
    
    // Skip address (4 bytes)
    for (int i = 0; i < 4; i++) {
      if (FPSerial.available()) FPSerial.read();
    }
    
    // Read packet type
    uint8_t pktType = FPSerial.available() ? FPSerial.read() : 0;
    
    // Read length
    uint16_t len = 0;
    if (FPSerial.available()) len = (FPSerial.read() << 8);
    if (FPSerial.available()) len |= FPSerial.read();
    
    // Data packet (0x02) = image data
    if (pktType == 0x02 && len >= 256) {
      for (int i = 0; i < 256; i++) {
        uint32_t pixelStart = millis();
        while (!FPSerial.available() && millis() - pixelStart < PIXEL_TIMEOUT) {
          delay(1);
        }
        
        if (FPSerial.available()) {
          imageBuf[idx++] = FPSerial.read();
          lastData = millis();
        } else {
          return false;
        }
      }
      
      // Skip checksum (2 bytes)
      if (FPSerial.available()) FPSerial.read();
      if (FPSerial.available()) FPSerial.read();
    }
    // End packet (0x08) = transfer done
    else if (pktType == 0x08) {
      return (idx == (256 * 288));
    }
    
    if (idx >= (256 * 288)) break;
  }
  
  return (idx == (256 * 288));
}
```

### ✅ Example 2: Access Pixel Data

```cpp
// ===== Sau khi downloadImageFromAS608() =====

// Access single pixel
uint8_t getPixel(uint16_t row, uint16_t col) {
  if (row >= 288 || col >= 256) return 0;
  return imageBuf[row * 256 + col];
}

// Get grayscale value (0-255)
uint8_t gray = getPixel(100, 50);  // Row 100, Col 50
Serial.printf("Grayscale: %d\n", gray);

// Print row (first 16 pixels)
for (int col = 0; col < 16; col++) {
  uint8_t pixel = getPixel(0, col);
  Serial.printf("%02X ", pixel);
}
Serial.println();

// Calculate image statistics
uint32_t sum = 0;
uint8_t minVal = 255, maxVal = 0;

for (int i = 0; i < (256 * 288); i++) {
  uint8_t pixel = imageBuf[i];
  sum += pixel;
  if (pixel < minVal) minVal = pixel;
  if (pixel > maxVal) maxVal = pixel;
}

uint32_t mean = sum / (256 * 288);
Serial.printf("Min=%d, Max=%d, Mean=%d\n", minVal, maxVal, mean);
```

### ✅ Example 3: Dùng Pixel Data (Dart)

```dart
// Flutter app nhận raw image từ ESP32 HTTP API

import 'package:image/image.dart' as img;

Future<img.Image?> decodeRawImage(List<int> rawData) {
  // rawData: 73728 bytes (256 × 288)
  
  try {
    // Tạo Image từ raw data
    img.Image image = img.Image(
      width: 256,
      height: 288,
    );
    
    // Copy pixel data
    for (int i = 0; i < rawData.length; i++) {
      image.data![i] = rawData[i];  // 8-bit grayscale
    }
    
    // Giờ có thể render hoặc save
    return image;
  } catch (e) {
    print('Error decoding image: $e');
    return null;
  }
}

// Display image
void displayImage(img.Image image) {
  // Encode to PNG
  List<int> pngBytes = img.encodePng(image);
  
  // Tạo Image widget từ PNG bytes
  Image.memory(
    Uint8List.fromList(pngBytes),
    width: 256,
    height: 288,
    fit: BoxFit.contain,
  );
}
```

---

## 📊 Tóm Tắt API

| Yêu Cầu | Giải Pháp | Public? | Note |
|--------|---------|--------|------|
| Chụp ảnh | `finger.getImage()` | ✅ Yes | Return code chỉ ra kết quả |
| Convert template | `finger.image2Tz(slot)` | ✅ Yes | Slot 1 or 2 |
| Access pixel data | Custom `downloadImageFromAS608()` | ❌ No | Phải dùng AS608 protocol |
| Get image buffer | ❌ Không có | ❌ No | `image[]` là private |
| Get raw image | ❌ Không có | ❌ No | Phải download qua serial |
| readImage() | ❌ Không có | ❌ No | Không public trong library |
| getRawImage() | ❌ Không có | ❌ No | Không tồn tại |

---

## 🔗 References

- **Adafruit Library**: https://github.com/adafruit/Adafruit-Fingerprint-Sensor-Library
- **AS608 Datasheet**: Protocol documentation
- **Project Files**: `/home/ncd/workspace/fingerprint_project/fingerprint/`

---

## ✅ Kết Luận

1. **Adafruit chỉ expose 2 hàm chính**:
   - `getImage()` - Chụp ảnh
   - `image2Tz(slot)` - Convert template

2. **Không có public API để access pixel data trực tiếp**:
   - `image[]` buffer không public
   - `readImage()` không tồn tại
   - Phải dùng custom AS608 protocol

3. **SYDEMO cũng dùng cách tương tự**:
   - Gửi command GENIMG (0x01)
   - Gửi command UPIMAGE (0x02)
   - Nhận data packets từ serial port
   - Save vào local buffer

4. **Project của bạn implement đúng cách**:
   - Dùng Adafruit API (getImage + image2Tz)
   - Custom protocol (downloadImageFromAS608) để download raw
   - Lưu vào `imageBuf[73728]`
   - Expose getters: `fpGetImageData()`, `fpGetImageSize()`
