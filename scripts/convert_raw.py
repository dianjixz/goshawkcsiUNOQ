#!/usr/bin/env python3
import numpy as np
import sys

width = 1920
height = 1080
input_file = sys.argv[1] if len(sys.argv) > 1 else "capture.raw"
output_file = input_file.replace('.raw', '.jpg')

# 读取打包的 10 位数据
packed = np.fromfile(input_file, dtype=np.uint8)
print(f"已读取 {len(packed)} 字节，最小值:{packed.min()}，最大值:{packed.max()}，平均值:{packed.mean():.1f}")

# 将 10 位 MIPI 数据解包为 16 位
bytes_per_row = (width * 10) // 8
packed = packed[:bytes_per_row * height].reshape(height, bytes_per_row)

img = np.zeros((height, width), dtype=np.uint16)
for y in range(height):
    for x in range(0, width, 4):
        i = (x * 10) // 8
        b0, b1, b2, b3, b4 = packed[y, i:i+5]
        img[y, x]     = (b0 << 2) | ((b4 >> 0) & 0x03)
        img[y, x + 1] = (b1 << 2) | ((b4 >> 2) & 0x03)
        img[y, x + 2] = (b2 << 2) | ((b4 >> 4) & 0x03)
        img[y, x + 3] = (b3 << 2) | ((b4 >> 6) & 0x03)

print(f"已解包 10 位数据：最小值:{img.min()}，最大值:{img.max()}，平均值:{img.mean():.1f}")

# 拉伸对比度
img_min, img_max = img.min(), img.max()
if img_max > img_min:
    img_stretched = ((img - img_min) * 1023 / (img_max - img_min)).astype(np.uint16)
else:
    img_stretched = img

# 转换为 8 位
img8 = (img_stretched >> 2).astype(np.uint8)

# 使用 OpenCV 进行去拜耳处理
try:
    import cv2
    bgr = cv2.cvtColor(img8, cv2.COLOR_BAYER_RG2BGR)
    bgr_bright = cv2.convertScaleAbs(bgr, alpha=2.0, beta=30)
    cv2.imwrite(output_file, bgr_bright)
    print(f"已保存 {output_file}")
except ImportError:
    print("请安装 OpenCV：pip install opencv-python --break-system-packages")
