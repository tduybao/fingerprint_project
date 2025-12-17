#pragma once
#include <Arduino.h>

#define FP_IMG_WIDTH   256
#define FP_IMG_HEIGHT  288
#define FP_IMG_SIZE    (FP_IMG_WIDTH * FP_IMG_HEIGHT)

void fpInit();
bool fpLoop();                 // chụp ảnh nếu có ngón tay

uint16_t fpGetImageSize();
uint8_t* fpGetImageData();
