# GosHawk Hat Shield - 摄像头集成指南

本项目汇总了在 Arduino UNO Q 的 Linux 设备树中添加 GosHawk Hat Shield 所管理全部设备的相关信息。

Uno Q 是一款较新的单板计算机（SBC），包含两个域：可运行 Linux 的微处理器（MPU，QRB2210 SoC）和运行 Zephyr 的微控制器（MCU，STM32U585）。两个域彼此互连，可高效处理 IPC。

## 目录

1. [GosHawk Hat Shield 管理的设备](#goshawk-hat-shield-管理的设备)
2. [摄像头硬件分析](#摄像头硬件分析)
3. [设备树配置](#设备树配置)
4. [在 Linux 中配置摄像头](#在-linux-中配置摄像头)
5. [图像和视频采集](#图像和视频采集)
6. [故障排查](#故障排查)
7. [DSI 显示屏集成](#dsi-显示屏集成)
8. [音频集成](#音频集成)
9. [触摸屏（GT911）](#触摸屏gt911)
10. [参考资料](#参考资料)

---
公告：CSI 摄像头功能已可用。适用于 DSI 显示屏的更新补丁即将发布！
---

## GosHawk Hat Shield 管理的设备

- 通过 UNO Q JMEDIA/JMISC 连接器连接 2 个 CSI 摄像头
- 通过 UNO Q JMEDIA/JMISC 连接器连接 1 个 DSI 显示屏
- 1 路音频输出
- 1 路麦克风输入

### 支持的摄像头

- IMX219 摄像头（RPi Camera v2）

---

## 摄像头硬件分析

### 扩展板设计限制

**当前设计（不理想）：**
```
摄像头 ENABLE → JMISC → STM32 MCU 域（Linux 无法控制）
```

**理想设计：**
```
摄像头 ENABLE → JMEDIA → QRB2210 SoC 域（Linux 可控 GPIO）
```

**变通方案：** 将 CSI 引脚 11 跳接至引脚 15（3.3V），使摄像头电源永久启用。

也可以由 STM32 Zephyr 固件控制这些引脚。请参阅 `arduino_ide/cam_dual_io/cam_dual_io.ino`，其中的参考草图会在启动时启用所有设备。

### 扩展板原理图分析

#### J4 - CSI0 连接器（摄像头 1）

| J4 引脚 | 信号 | 来源 | 用途 |
|--------|--------|--------|---------|
| 1, 4, 7, 10 | GND | — | 地线 |
| 2-3 | CSI0_DATA_LN0_N/P | JMEDIA | CSI 数据通道 0 ✓ |
| 5-6 | CSI0_DATA_LN1_N/P | JMEDIA | CSI 数据通道 1 ✓ |
| 8-9 | CSI0_CLK_N/P | JMEDIA | CSI 时钟通道 ✓ |
| 11 | CAM0_EN | JMISC 引脚 12（STM32 PE7） | **ENABLE**：接 3V3 或 Zephyr GPIO 36 |
| 12 | CAM0_LED_EN | JMISC 引脚 12（STM32 PE7） | 摄像头板 LED（与 CAM0 的 EN 共用） |
| 13 | CCI_I2C_SCL0 | 通过 PCA9306 | I2C 时钟 ✓ |
| 14 | CCI_I2C_SDA0 | 通过 PCA9306 | I2C 数据 ✓ |
| 15 | VCC_3V3 | JMEDIA | 电源（常开）✓ |

#### J3 - CSI1 连接器（摄像头 2）

| J3 引脚 | 信号 | 来源 | 用途 |
|--------|--------|--------|---------|
| 1, 4, 7, 10 | GND | — | 地线 |
| 2-3 | CSI1_DATA_LN0_N/P | JMEDIA | CSI 数据通道 0 ✓ |
| 5-6 | CSI1_DATA_LN1_N/P | JMEDIA | CSI 数据通道 1 ✓ |
| 8-9 | CSI1_CLK_N/P | JMEDIA | CSI 时钟通道 ✓ |
| 11 | CAM1_EN | JMISC 引脚 23（STM32 PA8） | **ENABLE**：接 3V3 或 Zephyr GPIO 47 |
| 12 | CAM1_LED_EN | JMISC 引脚 25（STM32） | 摄像头板 LED（Zephyr GPIO 49） |
| 13 | CCI_I2C_SCL1 | 通过 PCA9306 | I2C 时钟 ✓ |
| 14 | CCI_I2C_SDA1 | 通过 PCA9306 | I2C 数据 ✓ |
| 15 | VCC_3V3 | JMEDIA | 电源（常开）✓ |

> **注意：** RPi Camera v2（IMX219）的 **FPC 连接器上没有 RESET 引脚**。传感器 XCLR（复位）通过摄像头模块 PCB 上的上拉电阻保持高电平。CSI 引脚 12 是 LED_EN（控制摄像头板上的红色小 LED），不是复位引脚。

### RPi Camera v2 分析

**从摄像头原理图中得到的关键发现：**

RPi Camera v2 板载 24 MHz 振荡器，不需要主机提供外部 MCLK **信号**。但 Linux IMX219 驱动会**验证**时钟配置，因此设备树中仍需配置 24 MHz，尽管实际时钟来自摄像头内部振荡器。

**摄像头上电顺序：**
1. 主机将 **ENABLE**（CSI 引脚 11）置高
2. 启用板载 LDO：U1（1.8V）和 U2（2.8V）
3. 板载振荡器开始向 IMX219 提供 MCLK
4. 板载上拉将传感器 XCLR 保持高电平（始终处于非复位状态）
5. 传感器上电，I2C 接口开始响应

> **注意：** CSI 连接器上没有独立的 RESET 引脚。CSI 引脚 12 是 **LED_EN**（摄像头板 LED 指示灯），不是传感器复位。IMX219 XCLR 由摄像头模块 PCB 内部管理。

---

## 设备树配置

### 与 Raspberry Pi 的差异

| 组件 | Raspberry Pi 5 | Arduino UNO Q（QRB2210） |
|-----------|---------------|------------------------|
| **CSI 接收器** | Unicam（Broadcom） | CAMSS（Qualcomm） |
| **设备树结构** | `&cam0`, `&cam1` | `&csiphy0`, `&csid0`, `&vfe0` |
| **摄像头 I2C** | 专用 I2C | CCI（摄像头控制接口） |
| **摄像头驱动** | `ov5647.ko`, `imx219.ko` | `imx219.ko` |
| **叠加层系统** | `/boot/firmware/overlays/` | `/boot/efi/dtb/qcom/` |
| **引导配置** | 含 `dtoverlay=` 的 `config.txt` | 含 `devicetree` 的加载器条目 |

### 摄像头流水线架构

```
摄像头传感器（IMX219）
    ↓ [MIPI CSI-2，2 条通道]
CSIPHY（物理层）
    ↓
CSID（CSI 解码器）
    ↓
VFE（视频前端）
    ↓
/dev/videoX
```

###### 参考：Raspberry Pi 5 摄像头流水线：
```
摄像头传感器（OV5647）
    ↓ [MIPI CSI-2]
Unicam（CSI 接收器）
    ↓
/dev/video0
```

### GCC 时钟 ID（QCM2290）

| 时钟名称 | ID（十进制） | ID（十六进制） | 用途 |
|------------|----------|----------|---------|
| GCC_CAMSS_MCLK0_CLK | 37 | 0x25 | 摄像头 1 门控时钟 |
| GCC_CAMSS_MCLK0_CLK_SRC | 38 | 0x26 | 摄像头 1 源时钟 |
| GCC_CAMSS_MCLK1_CLK | 39 | 0x27 | 摄像头 2 门控时钟 |
| GCC_CAMSS_MCLK1_CLK_SRC | 40 | 0x28 | 摄像头 2 源时钟 |

### 摄像头 1 设备树节点

```dts
/* 电源稳压器：由于 ENABLE 由硬件控制，因此保持常开 */
cam0-pwr {
    compatible = "regulator-fixed";
    regulator-name = "cam0-pwr";
    phandle = <0xfb>;
    regulator-always-on;
    regulator-boot-on;
};

/* CCI i2c-bus@0 内的传感器节点 */
sensor@10 {
    compatible = "sony,imx219";
    reg = <0x10>;
    
    /* 电源 */
    VANA-supply = <0xfb>;
    VDIG-supply = <0xfb>;
    VDDL-supply = <0xfb>;
    
    /* 时钟配置：务必使用正确的 ID */
    clocks = <0x26 0x25>;              /* GCC（phandle），MCLK0_CLK (37) */
    clock-names = "xclk";
    assigned-clocks = <0x26 0x26>;     /* GCC, MCLK0_CLK_SRC (38) */
    assigned-clock-rates = <24000000>; /* 24 MHz */
    
    /* CSI-2 端口 */
    port {
        endpoint {
            phandle = <0xf9>;
            remote-endpoint = <0xfc>;  /* 链接到 csiphy0 */
            data-lanes = <0x01 0x02>;
            clock-lanes = <0x00>;
            link-frequencies = <0x00 0x1b2e0200>; /* 456 MHz */
        };
    };
};
```

### 摄像头 2 设备树节点

```dts
/* 摄像头 2 的电源稳压器 */
cam1-pwr {
    compatible = "regulator-fixed";
    regulator-name = "cam1-pwr";
    phandle = <0xfd>;
    regulator-always-on;
    regulator-boot-on;
};

/* CCI i2c-bus@1 内的传感器节点 */
i2c-bus@1 {
    reg = <0x01>;
    #address-cells = <0x01>;
    #size-cells = <0x00>;
    clock-frequency = <1000000>;
    
    sensor@10 {
        compatible = "sony,imx219";
        reg = <0x10>;
        
        /* 电源 */
        VANA-supply = <0xfd>;
        VDIG-supply = <0xfd>;
        VDDL-supply = <0xfd>;
        
        /* 时钟配置：摄像头 2 使用 MCLK1 */
        clocks = <0x26 0x27>;              /* GCC, MCLK1_CLK (39) */
        clock-names = "xclk";
        assigned-clocks = <0x26 0x28>;     /* GCC, MCLK1_CLK_SRC (40) */
        assigned-clock-rates = <24000000>; /* 24 MHz */
        
        /* CSI-2 端口：连接到 csiphy1 */
        port {
            cam1_endpoint: endpoint {
                remote-endpoint = <&csiphy1_ep>;
                data-lanes = <0x01 0x02>;
                clock-lanes = <0x00>;
                link-frequencies = /bits/ 64 <456000000>;
            };
        };
    };
};
```

### 摄像头 2 的 CSIPHY1 配置

```dts
/* 在 camss@5c11000 节点内添加 csiphy1 端口 */
port@1 {
    reg = <0x01>;
    csiphy1_ep: endpoint {
        remote-endpoint = <&cam1_endpoint>;
        clock-lanes = <0x07>;
        data-lanes = <0x00 0x01>;
    };
};
```

### 添加摄像头 2 的完整步骤

1. **反编译当前 DTB：**
   ```bash
   cd ~/inspection
   dtc -I dtb -O dts -o camera-dual.dts /boot/efi/dtb/qcom/qrb2210-arduino-imola-camera-shield.dtb
   ```

2. **添加 cam1-pwr 稳压器**（位于根节点中，靠近 cam0-pwr）

3. 在 cci@5c1b000 节点内**添加带 sensor@10 的 i2c-bus@1**

4. 在 camss@5c11000 内为 csiphy1 **添加 port@1**

5. **编译并安装：**
   ```bash
   dtc -I dts -O dtb -o camera-dual.dtb camera-dual.dts
   sudo cp camera-dual.dtb /boot/efi/dtb/qcom/qrb2210-arduino-imola-camera-dual.dtb
   sudo sed -i 's/camera-shield.dtb/camera-dual.dtb/' /boot/efi/loader/entries/*.conf
   sudo reboot
   ```

6. **硬件：** 将 J3 CSI 引脚 11 跳接至引脚 15（3.3V），作为摄像头 2 的 ENABLE

---

## 在 Linux 中配置摄像头

### 自动配置摄像头（推荐）

使用 `camera-setup.sh` 脚本自动检测摄像头、识别 `/dev/videoX` 设备并配置媒体流水线：

```bash
# 检测并配置所有已连接的摄像头
scripts/camera-setup.sh

# 检测、配置并从每个摄像头采集一帧
scripts/camera-setup.sh capture

# 从指定摄像头连续传输
scripts/camera-setup.sh stream CAM0
scripts/camera-setup.sh stream CAM1
```

该脚本会：
- 解析 `media-ctl -p` 以查找所有 IMX219 传感器
- 沿流水线跟踪已启用的链接，为每个传感器找到对应的 `/dev/videoX`
- 分配稳定名称：CAM0 = 较低编号的 I2C 总线（J4），CAM1 = 较高编号的 I2C 总线（J3）
- 自动配置所有流水线元素的格式

> **注意：** 连接一个或两个摄像头时，摄像头子系统需要 CAMSS 可选传感器补丁（`scripts/build-camss-patched.sh`）才能工作。若没有此补丁，设备树声明的所有传感器都必须存在，否则 `/dev/media0` 不会出现。

### 验证摄像头检测

```bash
# 检查 I2C 检测结果（0x10 = IMX219）
sudo i2cdetect -y 0  # CCI 总线 0 上的摄像头 1
sudo i2cdetect -y 1  # CCI 总线 1 上的摄像头 2

# 在 dmesg 中检查驱动
dmesg | grep -i imx219

# 列出视频设备
v4l2-ctl --list-devices

# 显示媒体流水线
media-ctl -d /dev/media0 -p
```

### 手动配置流水线

如果希望手动配置（或 camera-setup.sh 不可用）：

#### CCI 总线 1 上的摄像头（典型单摄像头配置）

I2C 适配器编号可能不同，请通过 `media-ctl -p` 查看实际传感器名称（例如 `imx219 2-0010`）。

```bash
# 设置所有流水线元素
media-ctl -d /dev/media0 --set-v4l2 '"imx219 2-0010":0[fmt:SRGGB10_1X10/1920x1080]'
media-ctl -d /dev/media0 --set-v4l2 '"msm_csiphy1":0[fmt:SRGGB10_1X10/1920x1080]'
media-ctl -d /dev/media0 --set-v4l2 '"msm_csiphy1":1[fmt:SRGGB10_1X10/1920x1080]'
media-ctl -d /dev/media0 --set-v4l2 '"msm_csid0":0[fmt:SRGGB10_1X10/1920x1080]'
media-ctl -d /dev/media0 --set-v4l2 '"msm_csid0":1[fmt:SRGGB10_1X10/1920x1080]'
media-ctl -d /dev/media0 --set-v4l2 '"msm_vfe0_rdi0":0[fmt:SRGGB10_1X10/1920x1080]'
media-ctl -d /dev/media0 --set-v4l2 '"msm_vfe0_rdi0":1[fmt:SRGGB10_1X10/1920x1080]'

# 从 /dev/video0 采集
timeout 10 v4l2-ctl -d /dev/video0 \
    --set-fmt-video=width=1920,height=1080,pixelformat=pRAA \
    --stream-mmap --stream-count=1 --stream-to=capture.raw
```

#### 双摄像头流水线

使用两个摄像头时，流水线路由会动态分配。请使用 `camera-setup.sh` 或查看 `media-ctl -p`，确定每个传感器连接到哪个 csiphy/csid/vfe。`/dev/videoX` 设备会随当前连接的摄像头而变化。

### 设置曝光和增益

```bash
# 查找传感器子设备
media-ctl -d /dev/media0 -p | grep -B2 "imx219"

# 设置曝光（按需调整）
v4l2-ctl -d /dev/v4l-subdev12 --set-ctrl=exposure=5000
v4l2-ctl -d /dev/v4l-subdev12 --set-ctrl=analogue_gain=400

# 列出所有控件
v4l2-ctl -d /dev/v4l-subdev12 -l
```

---

## 图像和视频采集

### 采集原始图像

```bash
# 使用 camera-setup.sh（推荐，会自动处理设备检测）：
scripts/camera-setup.sh capture

# 或手动采集：使用 camera-setup.sh 或 media-ctl -p 识别出的 /dev/videoX：
timeout 10 v4l2-ctl -d /dev/video0 --set-fmt-video=width=1920,height=1080,pixelformat=pRAA \
    --stream-mmap --stream-count=1 --stream-to=camera.raw

# 检查文件大小（1920x1080 10 位图像应约为 2.5 MB）
ls -la *.raw
```

### 将原始图像转换为 JPEG

```python
#!/usr/bin/env python3
# 保存为 convert_raw.py
import numpy as np
import sys

width = 1920
height = 1080
input_file = sys.argv[1] if len(sys.argv) > 1 else "capture.raw"
output_file = input_file.replace('.raw', '.jpg')

# 读取打包的 10 位数据
packed = np.fromfile(input_file, dtype=np.uint8)
print(f"读取 {len(packed)} 字节，最小值：{packed.min()}，最大值：{packed.max()}，平均值：{packed.mean():.1f}")

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

print(f"已解包 10 位数据：最小值：{img.min()}，最大值：{img.max()}，平均值：{img.mean():.1f}")

# 拉伸对比度
img_min, img_max = img.min(), img.max()
if img_max > img_min:
    img_stretched = ((img - img_min) * 1023 / (img_max - img_min)).astype(np.uint16)
else:
    img_stretched = img

# 转换为 8 位
img8 = (img_stretched >> 2).astype(np.uint8)

# 使用 OpenCV 进行去马赛克处理
try:
    import cv2
    bgr = cv2.cvtColor(img8, cv2.COLOR_BAYER_RG2BGR)
    bgr_bright = cv2.convertScaleAbs(bgr, alpha=2.0, beta=30)
    cv2.imwrite(output_file, bgr_bright)
    print(f"已保存 {output_file}")
except ImportError:
    print("请安装 OpenCV：pip install opencv-python --break-system-packages")
```

用法：
```bash
python3 convert_raw.py camera1.raw
python3 convert_raw.py camera2.raw
```

---

## 故障排查

### Error: "xclk frequency not supported: 19200000 Hz"

**原因：** 设备树中的时钟 ID 错误，`assigned-clocks` 使用了门控时钟而非源时钟。

**解决方案：** 确保设备树使用：
```dts
clocks = <&gcc 37>;              /* 驱动使用的门控时钟 */
assigned-clocks = <&gcc 38>;     /* 用于设置频率的源时钟 */
assigned-clock-rates = <24000000>;
```

### Error: "Error reading reg 0x0000: -6" (ENXIO)

**原因：** 摄像头未供电或 ENABLE 引脚未置高。

**解决方案：**
1. 检查 ENABLE：CSI 引脚 11 已接至 3V3，或 Zephyr 草图（`cam_dual_io.ino`）正在运行
2. 检查 FFC 排线是否正确就位
3. 在 Raspberry Pi 上测试摄像头，确认其工作正常

### Error: "Broken pipe" 或视频流卡住

**原因：** 媒体流水线未配置或格式不匹配。

**解决方案：**
```bash
# 采集前配置完整流水线
media-ctl -d /dev/media0 --set-v4l2 '"imx219 0-0010":0[fmt:SRGGB10_1X10/1920x1080]'
# ...（所有流水线元素）

# 使用 10 位格式，而不是 8 位格式
v4l2-ctl -d /dev/video0 --set-fmt-video=pixelformat=pRAA  # 不是 RGGB
```

### Error: "VFE0: Input data violation"

**原因：** 传感器输出与流水线配置的格式不匹配。

**解决方案：** 全程使用原生 10 位格式：
```bash
# IMX219 输出 SRGGB10_1X10，而不是 SRGGB8_1X8
media-ctl -d /dev/media0 --set-v4l2 '"imx219 0-0010":0[fmt:SRGGB10_1X10/1920x1080]'
```

### 已检测到摄像头，但图像为黑色

**可能的原因：**
1. 摄像头镜头盖尚未取下
2. 摄像头朝向昏暗场景
3. 曝光过低

**解决方案：**
```bash
# 设置最大曝光以便测试
v4l2-ctl -d /dev/v4l-subdev12 --set-ctrl=exposure=10000
v4l2-ctl -d /dev/v4l-subdev12 --set-ctrl=analogue_gain=800

# 将摄像头朝向明亮光源
# 检查原始数据是否包含内容：
hexdump -C capture.raw | head -10
```

---

## Linux 诊断命令

### 设备树

```bash
# 将 DTB 反编译为 DTS
dtc -I dtb -O dts -o output.dts input.dtb

# 将 DTS 编译为 DTB
dtc -I dts -O dtb -o output.dtb input.dts

# 查看实时设备树
ls /proc/device-tree/
```

### I2C

```bash
# 列出 I2C 总线
ls /dev/i2c-*

# 扫描设备
sudo i2cdetect -y 0

# 列出 I2C 设备名称
cat /sys/bus/i2c/devices/*/name
```

### 时钟

```bash
# 检查时钟频率
sudo cat /sys/kernel/debug/clk/gcc_camss_mclk0_clk_src/clk_rate

# 检查时钟是否已启用
sudo cat /sys/kernel/debug/clk/gcc_camss_mclk0_clk/clk_enable_count

# 查看时钟树
sudo cat /sys/kernel/debug/clk/clk_summary | grep -i cam
```

### 视频

```bash
# 列出视频设备
ls -la /dev/video* /dev/media*

# 列出 V4L2 设备
v4l2-ctl --list-devices

# 显示支持的格式
v4l2-ctl -d /dev/video0 --list-formats-ext

# 显示媒体流水线
media-ctl -d /dev/media0 -p
```

### 驱动管理

```bash
# 重新加载驱动
sudo modprobe -r imx219
sudo modprobe imx219

# 检查 dmesg
dmesg | grep -i imx219
```

---

## DSI 显示屏集成

### 文档

请参阅专门的显示文档：

- **[DSI-DISPLAY-GUIDE.md](docs/DSI-DISPLAY-GUIDE.md)** - 显示子系统架构、设备树配置及已验证的 Freenove 4.3 英寸显示屏设置
- **[RPI-DISPLAY-COMPATIBILITY.md](docs/RPI-DISPLAY-COMPATIBILITY.md)** - RPi 显示屏兼容性矩阵及缺失的内核模块

### 状态概览

| 显示屏 | 桥接 IC | 内核支持 | 状态 |
|---------|-----------|----------------|--------|
| Freenove 4.3 英寸 | TC358762 | 树外模块 | **已验证可用** |
| RPi 官方 7 英寸 | TC358762 | 树外模块 | 应可工作（使用相同桥接器） |
| WaveShare ILI9881 | ILI9881C | 树外模块 | 未测试 |
| Arduino GigaDisplay | ST7701 | 树外模块 | 未测试 |

### 显示流水线（已验证可用）

```
DPU @5e01000 → DSI @5e94000 → TC358762（DSI 转 DPI 桥接器）
                                    → panel-dpi（通用 DPI 面板）
                                        → 800×480 帧缓冲区
```

已验证的输出：
- `/dev/dri/card0`, `/dev/dri/renderD128`
- `/dev/fb0` — `msmdrmfb` 800×480 @ 32bpp
- 连接器状态：`connected`

### 构建显示模块

```bash
# 在设备上构建所有显示模块：
scripts/build-dsi-ondevice.sh all

# 或构建指定模块：
scripts/build-dsi-ondevice.sh tc358762
scripts/build-dsi-ondevice.sh panel_dpi

# 在主机 PC 上交叉编译：
scripts/cross-build-dsi-modules.sh all
```

Freenove 4.3 英寸显示屏所需模块：`tc358762.ko` + `panel_dpi.ko`

完整设置说明请参阅 [DSI-DISPLAY-GUIDE.md](docs/DSI-DISPLAY-GUIDE.md#freenove-43-英寸显示屏已验证可用)。

---

## 音频集成

### 文档

完整的音频架构和参考资料请参阅 **[AUDIO-INTEGRATION-GUIDE.md](docs/AUDIO-INTEGRATION-GUIDE.md)**。

### 快速设置

```bash
scripts/configure-audio.sh              # 配置路由、80% 音量和 60% 麦克风增益
scripts/configure-audio.sh volume 50    # 调整耳机音量（0–100%）
scripts/configure-audio.sh mic-gain 80  # 调整麦克风增益（0–100%）
scripts/configure-audio.sh status       # 显示当前配置
scripts/configure-audio.sh test         # 快速播放测试
```

### DSI 面板用户：HDMI 音频 DAI 修复

使用 Freenove DSI 显示屏 DTB（已禁用 ANX7625）时，声卡会报告：
```
snd-sm8250: HDMI/I2S Playback: codec dai not found
```
**修复：** Freenove DTS 中的 `hdmi-i2s-dai-link` 节点必须包含 `status = "disabled"`。当前 `dts/imola-camera-dsi-freenove.dts` 已应用此修改。

### 硬件：扩展板引脚映射

| 功能 | 信号 | JMISC 引脚 |
|----------|--------|-----------|
| 麦克风负极 | MIC2_INM | 31 |
| 麦克风正极 | MIC2_INP | 29 |
| 麦克风偏置 | MIC2_BIAS | 33 |
| 耳机参考 | HPH_REF | 40 |
| 耳机左声道 | HPH_L | 36 |
| 耳机右声道 | HPH_R | 38 |

### 音频流水线架构

PM4125 编解码器使用带 SoundWire 的 Qualcomm QDSP6 流水线，因此**没有传统的 "Volume" 或 "Mic" 混音器控件**。DSP 通过数百个路由开关连接到编解码器硬件。`configure-audio.sh` 脚本会自动处理所有路由。

```
播放：Q6ASM → RX_CODEC_DMA_RX_0 → LPASS RX 宏 → 插值器 → DEM → RDAC → HPH 左/右
采集：AMIC2 → ADC2 → SoundWire TX → TX 宏 DEC0 → TX_CODEC_DMA_TX_3 → Q6ASM → MultiMedia1
```

**关键控件**（由 `configure-audio.sh` 设置）：

| 控件 | 范围 | 用途 |
|---------|-------|---------|
| `RX_RX0 Digital` / `RX_RX1 Digital` | 0–84（84 = 0dB） | 耳机音量（左/右） |
| `TX_DEC0` | 0–20（最高 +20dB） | 麦克风抽取器增益 |
| `HPHL Switch` / `HPHR Switch` | 0/1 | 耳机使能 |
| `HPHL_RDAC Switch` / `HPHR_RDAC Switch` | 0/1 | DAC 使能 |
| `RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1` | 0/1 | DSP → 编解码器播放路由 |
| `MultiMedia1 Mixer TX_CODEC_DMA_TX_3` | 0/1 | 编解码器 → DSP 采集路由 |

### 测试

```bash
# 播放测试
speaker-test -c 2 -t sine -f 440 -l 2

# 录音并播放
arecord -d 5 -r 48000 -c 2 -f S16_LE -t wav /tmp/test.wav && aplay /tmp/test.wav
```

### 音频诊断

```bash
cat /proc/asound/cards                              # 列出声卡
dmesg | grep -iE 'adsp|q6afe|soundwire|pm4125'     # 检查编解码器探测
lsmod | grep -iE 'snd|q6|soundwire'                # 检查音频模块
scripts/configure-audio.sh status                    # 显示路由状态
```

### 已知问题

| 问题 | 原因 | 修复方法 |
|-------|-------|-----|
| 未找到声卡 | HDMI DAI 链接引用了已禁用的 ANX7625 | 使用包含 `hdmi-i2s-dai-link { status = "disabled"; }` 的 Freenove DTS |
| 播放时出现 `Write error: -5` | 未配置路由 | 先运行 `scripts/configure-audio.sh` |
| alsamixer 中没有 "Volume"/"Mic" | 正常现象，PM4125 使用路由控件 | 在 alsamixer 中按 **F5**（全部）；使用 `configure-audio.sh volume/mic-gain` |
| 录音音量很低 | 抽取器增益过低 | `scripts/configure-audio.sh mic-gain 100` |
| 欠载错误 | 系统负载或 DSP 时序问题 | 减小缓冲区：`speaker-test --period-size 4096 --buffer-size 16384` |

---

## 触摸屏（GT911）

Freenove 4.3 英寸显示屏包含一个通过 CCI I2C 总线 0 连接的 **Goodix GT911** 电容触摸控制器。

### 状态：驱动补丁已就绪，等待硬件修复

| 项目 | 详情 |
|------|--------|
| IC | Goodix GT911 |
| I2C 总线 | CCI I2C0（gpio22/gpio23）= Linux **i2c-2** |
| I2C 地址 | 0x5D（ADDR 锁存为低电平）或 0x14（ADDR 锁存为高电平） |
| INT 引脚 | STM32 域（JMISC → Zephyr GPIO 35），**Linux 无法访问** |
| RESET 引脚 | 与 DISP_RESET 共用（JMISC → Zephyr GPIO 37） |
| 驱动 | 带轮询模式的**补丁版** `goodix_ts.ko`（替换原版） |

### 问题：原版驱动需要 IRQ

上游 `goodix_ts.ko`（`CONFIG_TOUCHSCREEN_GOODIX=m`）会无条件调用 `devm_request_threaded_irq()`。由于 GT911 INT 引脚位于 STM32 域，`client->irq == 0`，因此探测失败。

### 修复：使用带轮询模式的驱动补丁

`scripts/src/` 中修补后的 `goodix.c` 在没有可用 IRQ 时增加了 `input_setup_polling()` 回退机制（间隔 17 ms，约 60 Hz）：

```bash
# 构建（在设备上构建或交叉编译）
scripts/build-dsi-modules.sh goodix_ts

# 安装：替换原版模块
KVER=$(uname -r)
sudo cp /tmp/dsi-modules-build/goodix_ts/goodix_ts.ko \
  /lib/modules/$KVER/kernel/drivers/input/touchscreen/
sudo depmod -a
sudo modprobe goodix_ts
```

### 当前阻塞问题：CCI 总线 0 硬件超时

CCI I2C 主控制器 0 在每次事务中都报告 `queue 0 timeout`，总线上没有设备响应（包括摄像头 0）。由于 GT911 和摄像头 0 共用 I2C 线路，两者都会受到影响：

```
gpio22/23 → JMEDIA 51/53 → PCA9306 电平转换器 → DSI 连接器引脚 13/14
                                                → J4 CSI 连接器 I2C
```

**诊断：** `sudo i2cdetect -y 2` 全部显示 `--`（任何地址都没有 ACK）。`dmesg` 显示 `i2c-qcom-cci: master 0 queue 0 timeout`。CCI 主控制器 1（总线 3，摄像头 1）工作正常。

**所需硬件检查**（需要接触实体设备）：
1. 断开摄像头 0（J4）；故障摄像头可能将 SDA/SCL 拉低
2. 检查 DSI FPC 排线是否正确就位（引脚 13/14 = I2C）
3. 检查 PCA9306 电平转换器两侧是否都有 VREF

### MCU 固件：GT911 复位时序

GT911 会在 RESET 上升沿根据 INT 引脚状态锁存其 I2C 地址。MCU 固件必须执行：

```
INT  → 输出低电平          （将地址设为 0x5D）
RESET → 低电平（保持 ≥10ms）
RESET → HIGH
等待 5ms
INT  → 输入（释放）
等待 ≥50ms                 （GT911 已准备好进行 I2C 通信）
```

---

## 参考资料

### 文档

- [设备树规范](https://devicetree.org/specifications/)
- [Linux V4L2 文档](https://www.kernel.org/doc/html/latest/userspace-api/media/v4l/v4l2.html)
- [Qualcomm CAMSS 驱动](https://github.com/torvalds/linux/tree/master/drivers/media/platform/qcom/camss)
- [IMX219 驱动](https://github.com/torvalds/linux/blob/master/drivers/media/i2c/imx219.c)

### 时钟定义

- [QCM2290 GCC 时钟 ID](https://github.com/torvalds/linux/blob/master/include/dt-bindings/clock/qcom,gcc-qcm2290.h)

### 硬件

- Arduino UNO Q 原理图：ABX00162-schematics.pdf
- RPi Camera v2 原理图：RP-008150-DS-1-camera-module-2-schematics.pdf
- GosHawk Hat Shield 原理图

---

## 版本历史

| 版本 | 日期 | 变更 |
|---------|------|---------|
| 1.0 | 2026 年 2 月 | 初步集成摄像头 1 |
| 1.1 | 2026 年 2 月 | 添加摄像头 2 的设备树配置 |
| 1.2 | 2026 年 2 月 | 添加 DSI 显示屏文档和 RPi 兼容性矩阵 |
| 1.3 | 2026 年 2 月 | 添加音频集成指南（麦克风和耳机） |
| 1.4 | 2026 年 2 月 | 完整的音频配置（ALSA 混音器设置、录音和诊断） |
| 2.0 | 2026 年 3 月 | 验证 Freenove 4.3 英寸显示屏可用（tc358762 + panel_dpi）；添加 CAMSS 可选传感器补丁、camera-setup.sh 自动检测脚本并更新构建脚本 |
| 2.1 | 2026 年 3 月 | 音频修复：在 Freenove DTS 中禁用 HDMI DAI 链接；使用正确的 PM4125 控件（RX_RX0/RX1 Digital、TX_DEC0）重写 configure-audio.sh；添加 volume/mic-gain 子命令 |
| 2.2 | 2026 年 3 月 | 修正 CSI/DSI 引脚信息：CSI 引脚 12 = LED_EN（不是 RESET）；IMX219 XCLR 在摄像头 PCB 上拉高；添加 Zephyr GPIO 映射和 systemd 启动服务（zephyria-setup.sh） |
| 2.3 | 2026 年 3 月 | GT911 触摸屏：为 goodix_ts 添加轮询模式补丁（原版需要 IRQ）；诊断 CCI 总线 0 超时；记录 I2C 地址锁存和 MCU 复位时序 |
