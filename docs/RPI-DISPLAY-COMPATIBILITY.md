# Raspberry Pi DSI 显示屏与 Arduino UNO Q 的兼容性

## 概述

本文列出了与 Raspberry Pi 兼容的 DSI 显示屏，以及 Arduino UNO Q (QRB2210) 对它们的支持情况。许多兼容 RPi 的显示屏需要 Arduino UNO Q 内核中**未包含**的内核模块。

---

## Arduino UNO Q 内核显示驱动程序状态

**内核版本**：6.16.7-g0dd6551ae96b

### 已包含的 DSI 桥接器/面板驱动程序

| 驱动程序 | 内核配置 | 状态 | 模块 |
|--------|---------------|--------|--------|
| TC358767 (DP 桥接器) | `CONFIG_DRM_TOSHIBA_TC358767=m` | 可用 | `tc358767.ko` |
| TC358768 (DSI 转 DPI) | `CONFIG_DRM_TOSHIBA_TC358768=m` | 可用 | `tc358768.ko` |
| ANX7625 (USB-C/DP) | `CONFIG_DRM_ANX7625=m` | 可用 | `anx7625.ko` |

### 缺失的 DSI 桥接器/面板驱动程序

以下驱动程序不在原厂内核中，但可以使用 `scripts/build-dsi-modules.sh` 构建为树外模块：

| 驱动程序 | 内核配置 | 适用对象 | 构建命令 | 状态 |
|--------|---------------|--------------|---------------|--------|
| **TC358762** | `CONFIG_DRM_TOSHIBA_TC358762` | **Freenove 4.3"、官方 RPi 7"** | `build-dsi-ondevice.sh tc358762` | **已验证** |
| **panel_dpi** | 自定义（不在内核中） | TC358762 的下游 DPI 面板 | `build-dsi-ondevice.sh panel_dpi` | **已验证** |
| ILI9881C | `CONFIG_DRM_PANEL_ILITEK_ILI9881C` | WaveShare 5"/7" ILI9881 面板 | `build-dsi-ondevice.sh ili9881c` | 未测试 |
| ST7701 | `CONFIG_DRM_PANEL_SITRONIX_ST7701` | Arduino GigaDisplay、通用 480x800 面板 | `build-dsi-ondevice.sh st7701` | 未测试 |
| HX8394 | `CONFIG_DRM_PANEL_HIMAX_HX8394` | 经济型 720p DSI 显示屏 | `build-dsi-ondevice.sh hx8394` | 未测试 |
| OTM8009A | `CONFIG_DRM_PANEL_ORISETECH_OTM8009A` | STM32 Discovery 显示屏 | `build-dsi-ondevice.sh otm8009a` | 未测试 |
| **goodix_ts** | `CONFIG_TOUCHSCREEN_GOODIX`（已修补） | **Freenove 4.3" GT911 触摸屏** | `build-dsi-modules.sh goodix_ts` | **已修补** |

> **注意**：原厂内核中确实包含 `goodix_ts` (`=m`)，但原厂驱动程序需要 IRQ GPIO。`scripts/src/goodix.c` 中的修补版本为 INT 引脚无法由 Linux 访问的开发板增加了 `input_setup_polling()` 回退机制。

> **注意**：TC358762 是 DSI 转 DPI **桥接器**，并非面板驱动程序。它的 `port@1` 上需要一个下游 DPI 面板驱动程序。`panel_dpi.ko` 模块提供了此功能，它从设备树 `panel-timing` 节点读取显示时序。原始 `panel-dpi.c` 已从上游 Linux 6.16 中移除；`scripts/src/panel_dpi.c` 提供了自定义替代实现。

> 注意：`ILI9341` 是 SPI 面板驱动程序，与 DSI 连接器无关。

---

## 兼容 RPi 的 DSI 显示屏 - 兼容性矩阵

### 类别 1：不支持（缺少内核模块）

这些显示屏可在 Raspberry Pi 上工作，但如果不构建自定义内核模块，便**无法在 Arduino UNO Q 上工作**。

| 显示屏 | 桥接 IC | RPi 覆盖层 | 所需模块 | 备注 |
|---------|-----------|-------------|-----------------|-------|
| **Freenove 4.3" 触摸屏** | TC358762 | `vc4-kms-dsi-7inch` | `tc358762.ko` | 使用与 RPi 官方显示屏相同的桥接器 |
| **官方 RPi 7" 触摸屏** | TC358762 | `vc4-kms-dsi-7inch` | `tc358762.ko` | 最常见的 RPi 显示屏 |
| WaveShare 4.3" DSI LCD | TC358762 | `vc4-kms-dsi-waveshare-panel` | `tc358762.ko` | 800x480 |
| WaveShare 5" DSI LCD | ILI9881C | `vc4-kms-dsi-ili9881-5inch` | `ili9881c.ko` | 800x480 |
| WaveShare 7" DSI LCD | ILI9881C | `vc4-kms-dsi-ili9881-7inch` | `ili9881c.ko` | 800x480 |
| WaveShare 7.9" DSI LCD | ILI9881C | `vc4-kms-dsi-ili9881-7inch` | `ili9881c.ko` | 400x1280 |
| WaveShare 8" DSI LCD (C) | ILI9881C | `vc4-kms-dsi-waveshare-panel` | `ili9881c.ko` | 1280x800 |
| WaveShare 10.1" DSI LCD | ILI9881C | `vc4-kms-dsi-waveshare-panel` | `ili9881c.ko` | 1280x800 |
| WaveShare 11.9" DSI LCD | ILI9881C | `vc4-kms-dsi-waveshare-panel` | `ili9881c.ko` | 320x1480 |
| WaveShare 800x480 触摸屏 | TC358762 | `vc4-kms-dsi-waveshare-800x480` | `tc358762.ko` | 多种尺寸 |
| Pimoroni HyperPixel 4 | ST7701 | `vc4-kms-dpi-hyperpixel4` | `st7701.ko` | 800x480 |
| Arduino GigaDisplay | ST7701 | N/A（Arduino 专用） | `st7701.ko` | Arduino 自有显示屏 |
| 通用 ST7701 面板 | ST7701 | `vc4-kms-dsi-generic` | `st7701.ko` | 多种 480x800 面板 |
| 通用 HX8394 面板 | HX8394 | N/A | `hx8394.ko` | 多种 720p 面板 |
| Sharp LQ070M1SX01 | LT070ME05000 | `vc4-kms-dsi-lt070me05000` | `lt070me05000.ko` | 7" 1200x1920 |

### 类别 2：可能支持（需要测试）

如果硬件兼容，这些显示屏可能可以使用现有的 TC358768 桥接器工作：

| 显示屏 | 备注 |
|---------|-------|
| 使用 TC358768 的显示屏 | TC358768 驱动程序可用 |
| 配有简单 DSI 面板的显示屏 | 可能可配合 `panel-simple` 工作 |

### 类别 3：不适用（非 DSI）

| 显示屏类型 | 接口 | UNO Q 支持情况 |
|--------------|-----------|---------------|
| HDMI 显示屏 | HDMI | 支持（通过 ANX7625 USB-C） |
| SPI 显示屏 | SPI | 支持 (fbtft/fb_ili9341) |
| DPI 显示屏 | 并行 RGB | JMEDIA 上不支持 |

---

## 构建缺失的内核模块

> **使用所提供的脚本**，它们会自动执行以下所有步骤：
> ```bash
> # 在设备上：
> scripts/build-dsi-modules.sh tc358762
>
> # 在主机 PC 上交叉编译（更快）：
> scripts/cross-build-dsi-modules.sh tc358762
> ```

### 内核源代码仓库

```
https://github.com/arduino/linux-qcom
```

设备上运行的内核：`6.16.7-g0dd6551ae96b`

### 前提条件

```bash
# 在 Arduino UNO Q 上
sudo apt update
sudo apt install build-essential bc flex bison libssl-dev libelf-dev

# 获取内核头文件（如果已有软件包，请先尝试此方法）
sudo apt install linux-headers-$(uname -r)

# 或者克隆内核源代码并手动准备头文件
git clone --depth=1 https://github.com/arduino/linux-qcom.git
cd linux-qcom
make ARCH=arm64 defconfig          # arduino/linux-qcom 使用单一的 "defconfig"
make ARCH=arm64 scripts prepare modules_prepare
export KERNEL_DIR=$(pwd)
```

### 方法 1：在设备上构建单个模块（推荐）

```bash
# 仅构建 tc358762（或任何其他模块）
scripts/build-dsi-modules.sh tc358762

# 验证
lsmod | grep tc358762
modinfo tc358762
```

### 方法 2：在主机 PC 上交叉编译（最快）

```bash
# Ubuntu/Debian 主机上的依赖项
sudo apt install gcc-aarch64-linux-gnu make bc flex bison \
                 libssl-dev libelf-dev git curl

# 运行交叉编译脚本（自动克隆 arduino/linux-qcom）
scripts/cross-build-dsi-modules.sh tc358762

# 复制到目标设备
scp /tmp/dsi-modules-cross/modules/tc358762.ko user@<uno-q-ip>:/tmp/

# 在 Uno Q 上安装并加载
ssh user@<uno-q-ip> "
  sudo cp /tmp/tc358762.ko \
    /lib/modules/\$(uname -r)/kernel/drivers/gpu/drm/bridge/
  sudo depmod -a
  sudo modprobe tc358762
"
```

---

## Freenove 4.3" 显示屏完整设置（已验证可用）

### 硬件要求

- Freenove 4.3" 触摸屏（DSI 接口、800x480、TC358762 + GT911）
- 已构建并安装 `tc358762.ko` + `panel_dpi.ko`
- 使用 FPC 排线将显示屏连接到 Zephyria 扩展板 DSI 连接器

### 扩展板限制：DISP_EN 和 DISP_RESET

DSI 连接器的引脚 11 (DISP_EN) 和引脚 12 (DISP_RESET) 经由
**JMISC 连接到 STM32 域**，它们不是 Linux 可访问的 GPIO。

| DSI 引脚 | 信号 | JMISC 引脚 | STM32 GPIO | Zephyr GPIO |
|---------|--------|-----------|------------|-------------|
| 11 | DISP_EN | 11 | PI4 | 35 |
| 12 | DISP_RESET | 13 | PI6 | 37 |

所需的硬件变通方案（或使用 Zephyr 草图 `cam_dual_io.ino`）：
- **DISP_EN（引脚 11）**：连接到 DSI 连接器上的 3V3（引脚 15）
- **DISP_RESET（引脚 12）**：添加一个接 GND 的 100 nF 电容和一个接 3V3 的 10 kΩ 上拉电阻
  （RC 上电复位），或者直接连接到 3V3

### 分步设置

```bash
# 1. 构建所需模块（在设备上）
scripts/build-dsi-ondevice.sh tc358762
scripts/build-dsi-ondevice.sh panel_dpi

# 2. 确保模块在启动时加载
echo "tc358762" | sudo tee -a /etc/modules
echo "panel_dpi" | sudo tee -a /etc/modules

# 3. 编译并安装 Freenove DTB
dtc -I dts -O dtb -o imola-camera-dsi-freenove.dtb \
    dts/imola-camera-dsi-freenove.dts
sudo cp imola-camera-dsi-freenove.dtb /boot/efi/dtb/qcom/

# 4. 更新启动配置
#    编辑 /boot/efi/loader/entries/*.conf：
#    devicetree /dtb/qcom/imola-camera-dsi-freenove.dtb

# 5. 重新启动
sudo reboot
```

### 验证

```bash
ls /dev/dri/                              # card0、renderD128
dmesg | grep -iE 'panel|tc358762|fb0'    # panel-dpi 探测，fb0 已注册
cat /sys/class/drm/card0-*/status         # 已连接
cat /sys/class/drm/card0-*/modes          # 800x480
cat /dev/urandom > /dev/fb0               # 屏幕上显示随机像素
```

### DTS 的作用

`dts/imola-camera-dsi-freenove.dts` 是基于 `imola-camera-shield.dts` 的**独立 DTB**（不是 overlay），包含以下针对性更改：

| 更改 | 原因 |
|--------|--------|
| `panel-pwr` 稳压器（始终开启的 3V3） | 为 TC358762 桥接器供电 |
| `lcd-panel` 节点（`panel-dpi` + `panel-timing`） | 具有 800x480 时序的通用 DPI 面板 |
| 带有 `ports { port@0, port@1 }` 的 `panel@0` (`toshiba,tc358762`) | 连接到 lcd-panel 的 DSI 转 DPI 桥接器 |
| `data-lanes = <0 1>`（原为 `<0 1 2 3>`） | 扩展板仅布设 2 条 DSI 通道 |
| ANX7625 `status = "disabled"` | 防止 DSI 总线上出现重复的 sysfs 项 |
| 将 `mdss_dsi0_out` 重定向到 TC358762 | 连接显示流水线 |
| CCI I2C0 上的 `touchscreen@5d` | 通过 PCA9306 电平转换器连接 Goodix GT911 触摸屏 |

### 触摸控制器

Freenove 4.3" 显示屏使用 **Goodix GT911**（而非 FT5x06）。
它通过 CCI I2C 总线 0（JMEDIA 路径，Linux 可访问）连接：

| 属性 | 值 |
|----------|-------|
| Compatible | `goodix,gt911` |
| I2C 地址 | `0x5D`（ADDR 低电平）或 `0x14`（ADDR 高电平） |
| I2C 总线 | CCI I2C0（gpio22/gpio23，通过 PCA9306 电平转换器）= Linux i2c-2 |
| IRQ | STM32 域 (JMISC) 上的 INT 引脚，**Linux 无法使用** |
| 驱动程序 | 带有 `input_setup_polling()` (17ms/60Hz) 的**修补版** `goodix_ts.ko`；原厂驱动程序在没有 IRQ 时会失败 |
| 构建 | `scripts/build-dsi-modules.sh goodix_ts` |
| 注意 | 触摸功能需要实际连接显示屏并提供 DISP_RESET |

> **已知问题**：CCI I2C 总线 0 与摄像头 0 (J4) 共用 gpio22/gpio23。如果摄像头 0 出现故障或将总线拉低，CCI 总线 0 上包括 GT911 在内的所有设备都会超时 (`master 0 queue 0 timeout`)。断开摄像头 0 以进行隔离排查。

> **I2C 地址锁存**：GT911 在 RESET 上升沿锁存其 I2C 地址。若要使用地址 0x5D，MCU 固件必须在释放 RESET 之前将 INT 驱动为低电平。如果 INT 悬空，地址可能会锁存为 0x14。

---

## 可以工作的替代显示屏

如果希望避免构建内核模块，可以考虑以下替代方案：

### 选项 1：通过 USB-C 连接 HDMI 显示屏

已包含 ANX7625 驱动程序。可使用 USB-C 转 HDMI 适配器和任意 HDMI 显示屏。

### 选项 2：SPI 显示屏（小尺寸）

通过 fbtft 框架支持使用 ILI9341/ST7789 的 SPI 显示屏：
- 2.4" - 3.5" SPI TFT 显示屏
- 刷新率较低，但无需重新构建内核

### 选项 3：使用 TC358768 的显示屏

TC358768 驱动程序可用。请选择使用此桥接芯片的显示屏。

---

## 内核模块请求

可以请求 Arduino 在未来的内核版本中包含以下模块：

1. **tc358762.ko** - 官方 RPi 显示屏和大多数 RPi DSI 显示屏所需
2. **ili9881c.ko** - WaveShare 5"/7" 显示屏所需
3. **st7701.ko** - GigaDisplay 所需

Arduino linux-qcom 仓库：https://github.com/arduino/linux-qcom

---

## 版本历史

| 版本 | 日期 | 更改 |
|---------|------|---------|
| 1.0 | 2026 年 2 月 | 初始 RPi 显示屏兼容性指南 |
| 1.1 | 2026 年 2 月 | 更正内核仓库 (arduino/linux-qcom)；添加构建脚本参考；确认 Freenove GT911 触摸 IC 和 JMISC 域限制 |
| 2.0 | 2026 年 3 月 | 验证 Freenove 4.3" 可用；添加 panel_dpi 模块；补充 TC358762 port@1 要求；添加经过验证的分步说明 |
| 2.1 | 2026 年 3 月 | GT911 触摸功能：修补 goodix_ts 以使用轮询模式；CCI 总线 0 与摄像头 0 共用；I2C 地址锁存顺序；已知总线超时问题 |
