# Zephyria Shield DSI 显示屏集成指南

## 概述

UNO Q 通过 JMEDIA 连接器支持 DSI（Display Serial Interface，显示串行接口）显示屏。本指南介绍如何在正常工作的摄像头配置中添加 DSI 显示支持。

---

## 显示子系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                       QRB2210 显示流水线                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   帧缓冲区（/dev/fb0 或 DRM）                                   │
│           │                                                     │
│           ▼                                                     │
│   ┌───────────────┐                                            │
│   │     DPU       │  显示处理单元                              │
│   │  @0x5e01000   │  (QCM2290-DPU)                            │
│   └───────┬───────┘                                            │
│           │                                                     │
│           ▼                                                     │
│   ┌───────────────┐                                            │
│   │     DSI       │  DSI 控制器                                │
│   │  @0x5e94000   │  (QCM2290-DSI-CTRL)                       │
│   └───────┬───────┘                                            │
│           │                                                     │
│           ▼                                                     │
│   ┌───────────────┐                                            │
│   │   DSI PHY     │  物理层                                    │
│   │  @0x5e94400   │  (DSI-PHY-14NM-2290)                      │
│   └───────┬───────┘                                            │
│           │                                                     │
│           ▼                                                     │
│       MIPI DSI                                                  │
│     （2 或 4 条通道）                                           │
│           │                                                     │
│           ▼                                                     │
│   ┌───────────────┐                                            │
│   │    面板       │  显示面板（ST7701、ILI9881C 等）            │
│   └───────────────┘                                            │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## 关键组件

### 1. 显示子系统（MDSS）
- **地址**：`0x5e00000`
- **兼容字符串**：`qcom,qcm2290-mdss`
- **用途**：顶层显示子系统控制器

### 2. 显示处理单元（DPU）
- **地址**：`0x5e01000`
- **兼容字符串**：`qcom,qcm2290-dpu`
- **用途**：帧缓冲区处理、缩放和颜色转换

### 3. DSI 控制器
- **地址**：`0x5e94000`
- **兼容字符串**：`qcom,qcm2290-dsi-ctrl`
- **用途**：处理 MIPI DSI 协议

### 4. DSI PHY
- **地址**：`0x5e94400`
- **兼容字符串**：`qcom,dsi-phy-14nm-2290`
- **用途**：物理层和时钟生成

### 5. 显示时钟控制器
- **地址**：`0x5f00000`
- **兼容字符串**：`qcom,qcm2290-dispcc`
- **用途**：显示专用时钟

---

## 设备树配置

### 第 1 步：添加面板电源稳压器

```dts
/* 添加到根节点中，靠近摄像头稳压器 */
panel-pwr {
    compatible = "regulator-fixed";
    regulator-name = "panel-pwr";
    phandle = <0x1f0>;
    regulator-always-on;
    regulator-boot-on;
    /* 如果由 GPIO 控制电源，请添加：
    gpio = <&tlmm XX 0>;
    enable-active-high;
    startup-delay-us = <10000>;
    */
};
```

### 第 2 步：启用显示子系统（MDSS）

找到并修改 `display-subsystem@5e00000` 节点：

```dts
display-subsystem@5e00000 {
    compatible = "qcom,qcm2290-mdss";
    reg = <0x00 0x5e00000 0x00 0x1000>;
    /* ... 现有属性 ... */
    status = "okay";  /* <-- 启用此项 */

    /* 内含 display-controller 和 dsi 节点 */
};
```

### 第 3 步：启用 DPU（显示控制器）

在 `display-subsystem@5e00000` 内：

```dts
display-controller@5e01000 {
    compatible = "qcom,qcm2290-dpu";
    /* ... 现有属性 ... */
    status = "okay";  /* 基础配置中已经是 okay */

    ports {
        port@0 {
            reg = <0>;
            dpu_intf1_out: endpoint {
                remote-endpoint = <&dsi0_in>;  /* 连接至 DSI */
            };
        };
    };
};
```

### 第 4 步：配置 DSI 控制器

在 `display-subsystem@5e00000` 内：

```dts
dsi@5e94000 {
    compatible = "qcom,qcm2290-dsi-ctrl", "qcom,mdss-dsi-ctrl";
    reg = <0x00 0x5e94000 0x00 0x400>;
    /* ... 时钟、电源域 ... */

    status = "okay";
    vdda-supply = <&vreg_l5a>;  /* 1.2V DSI PLL 电源 */

    #address-cells = <1>;
    #size-cells = <0>;

    /* 面板节点——请根据你的显示屏进行定制 */
    panel@0 {
        compatible = "your-vendor,your-panel";  /* <-- 修改此项 */
        reg = <0>;
        status = "okay";

        /* 面板配置 */
        dsi-lanes = <2>;           /* DSI 通道数（2 或 4） */
        video-mode = <2>;          /* 0=命令，1=视频同步脉冲，2=视频同步事件，3=视频突发 */

        /* 电源 */
        VCC-supply = <&panel_pwr>;
        IOVCC-supply = <&panel_pwr>;

        /* 复位 GPIO——请根据你的扩展板调整 */
        reset-gpios = <&tlmm 2 0>;  /* GPIO2，低电平有效 */

        /* 可选：背光 */
        /* backlight = <&backlight>; */

        port {
            panel_in: endpoint {
                remote-endpoint = <&dsi0_out>;
            };
        };
    };

    ports {
        #address-cells = <1>;
        #size-cells = <0>;

        port@0 {
            reg = <0>;
            dsi0_in: endpoint {
                remote-endpoint = <&dpu_intf1_out>;
            };
        };

        port@1 {
            reg = <1>;
            dsi0_out: endpoint {
                remote-endpoint = <&panel_in>;
                data-lanes = <0 1>;  /* 通道映射 */
            };
        };
    };
};
```

### 第 5 步：启用 DSI PHY

在 `display-subsystem@5e00000` 内：

```dts
phy@5e94400 {
    compatible = "qcom,dsi-phy-14nm-2290";
    /* ... 现有属性 ... */
    status = "okay";
};
```

---

## 常见面板驱动

### Linux 主线支持的面板

| 面板 IC | 兼容字符串 | 通道数 | 备注 |
|----------|-------------------|-------|-------|
| ST7701 | `sitronix,st7701` | 2 | Arduino GigaDisplay 使用此芯片 |
| ILI9881C | `ilitek,ili9881c` | 4 | 常见于平板电脑 |
| NT35596 | `novatek,nt35596` | 4 | 高分辨率手机 |
| HX8394 | `himax,hx8394` | 4 | 经济型显示屏 |
| OTM8009A | `orisetech,otm8009a` | 2 | 常见评估板 |

### Arduino GigaDisplay 配置

摘自 Arduino 的 `qrb2210-arduino-imola-gigadisplay.dtb`：

```dts
panel@0 {
    compatible = "arduino,giga-display", "sitronix,st7701";
    reg = <0>;
    status = "okay";

    video-mode = <2>;           /* 视频同步事件模式 */
    dsi-lanes = <2>;            /* 双通道 DSI */

    reset-gpios = <&tlmm 2 0>;  /* GPIO2 用于复位 */

    IOVCC-supply = <&panel_pwr>;
    VCC-supply = <&panel_pwr>;

    port {
        endpoint {
            remote-endpoint = <&dsi0_out>;
        };
    };
};
```

---

## Zephyria Shield DSI 连接器引脚定义（已确认）

| DSI 引脚 | 信号             | JMEDIA 引脚      | JMISC 引脚 | 所属域              |
|----------|------------------|------------------|------------|---------------------|
| 1,4,7,10 | GND              | —                | —          | —                   |
| 2        | MIPI_DSI0_L0_N   | 10               | —          | QRB2210（Linux）✓   |
| 3        | MIPI_DSI0_L0_P   | 12               | —          | QRB2210（Linux）✓   |
| 5        | MIPI_DSI0_L1_N   | 6                | —          | QRB2210（Linux）✓   |
| 6        | MIPI_DSI0_L1_P   | 4                | —          | QRB2210（Linux）✓   |
| 8        | MIPI_DSI0_CLK_N  | 3                | —          | QRB2210（Linux）✓   |
| 9        | MIPI_DSI0_CLK_P  | 5                | —          | QRB2210（Linux）✓   |
| 11       | DISP_EN          | —                | 11（STM32 PI4，Zephyr GPIO 35）| **仅限 STM32** ⚠ |
| 12       | DISP_RESET       | —                | 13（STM32 PI6，Zephyr GPIO 37）| **仅限 STM32** ⚠ |
| 13       | CCI_I2C_SCL0     | 51（经 PCA9306） | —          | QRB2210（Linux）✓   |
| 14       | CCI_I2C_SDA0     | 53（经 PCA9306） | —          | QRB2210（Linux）✓   |
| 15       | 3V3              | —                | —          | 始终开启 ✓          |

### 扩展板设计限制——DISP_EN 和 DISP_RESET

只有 **DSI 引脚 11（DISP_EN）**和 **12（DISP_RESET）**通过 JMISC 连接到 STM32U585 MCU（Zephyr）域。它们**无法**作为 Linux TLMM GPIO 访问。

DSI 连接器的所有其他信号（MIPI 通道、CCI I2C、3V3）都位于 QRB2210（Linux/MPU）域，可由 Linux 完全控制。

> **关于 CSI 与 DSI 连接器的说明：** 每个 CSI 摄像头连接器只引出**一个**控制引脚（ENABLE，即 CSI 引脚 11）。CSI 引脚 12 是 **LED_EN**（摄像头板 LED），而非复位引脚；IMX219 XCLR 在摄像头模块 PCB 上被上拉为 HIGH。DSI 连接器则不同：它通过 JMISC 同时引出了 DISP_EN（引脚 11）和 DISP_RESET（引脚 12）。

### 硬件变通方案

**DISP_EN (DSI pin 11 → JMISC pin 11 / STM32 PI4 / Zephyr GPIO 35):**
必须保持 HIGH，显示屏才能工作：
```
将 DSI 连接器引脚 11 接至引脚 15（3V3）
```

**DISP_RESET (DSI pin 12 → JMISC pin 13 / STM32 PI6 / Zephyr GPIO 37):**
TC358762 + GT911 复位（低电平有效；HIGH = 正常工作）：

| 选项 | 电路 | 备注 |
|--------|---------|-------|
| A——RC 复位 | 100 nF（引脚 12 → GND）+ 10 kΩ（引脚 12 → 3V3） | 上电约 1 ms 后释放复位 |
| B——上拉 | 将引脚 12 接至 3V3 | 如果冷启动时 3V3 电源稳定，即可工作 |
| C——STM32 固件 | Zephyr 草图：`digitalWrite(37, LOW); delay(100); digitalWrite(37, HIGH);` | 最可靠，可产生正确的复位脉冲。参见 `arduino_ide/cam_dual_io/cam_dual_io.ino` |

---

## Freenove 4.3 英寸显示屏——已验证可用

Freenove 4.3 英寸 DSI 显示屏已在搭载 Zephyria Shield 的 Arduino UNO Q 上完成全面验证。显示流水线可生成正常工作的 800x480 帧缓冲区。

### 架构

Freenove 4.3 英寸显示屏采用**两级桥接**方案。TC358762 是 DSI 转 DPI 桥接器（而非面板驱动），因此需要下游 DPI 面板驱动：

```
DPU → DSI 主机 → TC358762（DSI 转 DPI）→ panel-dpi（通用 DPI）→ LCD
                 ├── port@0 ← DSI 输入          └── 来自 DT 的 panel-timing
                 └── port@1 → DPI 输出
```

**关键发现**：TC358762 调用 `devm_drm_of_get_bridge(dev, dev->of_node, 1, 0)`，它会在 `port@1` 上查找下游桥接器/面板。缺少该项时，DSI 设备会一直处于延迟探测状态，`/dev/dri/` 永远不会出现。

### 必需的内核模块

| 模块 | 源码 | 用途 |
|--------|--------|---------|
| `tc358762.ko` | `drivers/gpu/drm/bridge/tc358762.c` | DSI 转 DPI 桥接器 |
| `panel_dpi.ko` | `scripts/src/panel_dpi.c`（自定义） | 从 DT 读取时序的通用 DPI 面板 |

**为什么需要 `panel_dpi.ko`？** 上游 `panel-dpi.c` 已从 Linux 6.16 中移除。原版内核的 `panel-simple` 模块不包含 `seiko,43wvf1g` 或其他与 Freenove 兼容的条目。`scripts/src/panel_dpi.c` 提供了一个自定义的精简 DPI 面板驱动（约 160 行）。

### 快速开始

```bash
# 第 1 步——构建必需的内核模块
scripts/build-dsi-ondevice.sh tc358762
scripts/build-dsi-ondevice.sh panel_dpi
# 或构建全部模块：scripts/build-dsi-ondevice.sh all

# 第 2 步——确保模块在启动时加载
echo "tc358762" | sudo tee -a /etc/modules
echo "panel_dpi" | sudo tee -a /etc/modules

# 第 3 步——在扩展板上实施硬件变通方案
#   • 将 DSI 连接器引脚 11 接至引脚 15（DISP_EN = 3V3）
#   • 添加 RC 复位电路，或将引脚 12 接至 3V3（参见上方引脚表）

# 第 4 步——安装 Freenove DTB
#   该 DTS 文件是在 imola-camera-shield.dts 基础上进行针对性修改的
#   独立 DTB（并非 overlay）。
dtc -I dts -O dtb -o imola-camera-dsi-freenove.dtb \
    dts/imola-camera-dsi-freenove.dts
sudo cp imola-camera-dsi-freenove.dtb /boot/efi/dtb/qcom/

# 第 5 步——在引导加载程序中选择新的 DTB
#   编辑 /boot/efi/loader/entries/*.conf：
#   devicetree /dtb/qcom/imola-camera-dsi-freenove.dtb

# 第 6 步——重启
sudo reboot
```

### 验证

重启后，确认显示流水线：

```bash
# DRM 设备应当存在
ls /dev/dri/
# 预期结果：card0  renderD128

# 帧缓冲区应已注册
dmesg | grep fb0
# 预期结果：fb0: msmdrmfb frame buffer device

# 连接器应处于已连接状态
cat /sys/class/drm/card0-*/status
# 预期结果：connected

# 检查显示模式
cat /sys/class/drm/card0-*/modes
# 预期结果：800x480

# 测试：用随机像素填充屏幕
cat /dev/urandom > /dev/fb0
```

### DTS 所做的更改

| 更改 | 原因 |
|--------|--------|
| 添加 `panel-pwr` 稳压器（始终开启的 3V3） | 为 TC358762 桥接器供电 |
| 添加带 `panel-timing` 的 `lcd-panel` 节点（`compatible = "panel-dpi"`） | 采用 800x480 @ 33.3 MHz 时序的通用 DPI 面板 |
| 添加带 `ports { port@0, port@1 }` 的 `panel@0` 节点（`toshiba,tc358762`） | 具有下游面板连接的 DSI 转 DPI 桥接器 |
| 将 `data-lanes` 从 `<0 1 2 3>` 改为 `<0 1>` | 扩展板只引出了 2 条 DSI 通道 |
| 禁用 ANX7625（`status = "disabled"`） | 防止 DSI 总线上出现重复的 sysfs 项 |
| 将 `mdss_dsi0_out` 的 remote-endpoint 从 ANX7625 重定向到 TC358762 | 连接显示流水线 |
| 在 `cci_i2c0` 上添加 `touchscreen@5d`（Goodix GT911） | 通过 JMEDIA/PCA9306 实现 I2C 触控 |

### 面板时序（Freenove 4.3 英寸 / 800x480）

```dts
panel-timing {
    clock-frequency = <33333000>;   /* 33.3 MHz 像素时钟 */
    hactive = <800>;
    hfront-porch = <164>;
    hback-porch = <89>;
    hsync-len = <8>;
    vactive = <480>;
    vfront-porch = <37>;
    vback-porch = <23>;
    vsync-len = <6>;
    hsync-active = <0>;
    vsync-active = <0>;
    de-active = <1>;
    pixelclk-active = <0>;
};
```

> **注意**：Freenove DTB 将 DSI-0 输出从 ANX7625 USB-C 编码器重定向到
> TC358762 桥接器。启用此 DTB 时，HDMI-over-USB-C 不可用。使用
> `imola-camera-shield.dtb` 启动可恢复 HDMI 输出。

### 调试过程中已解决的问题

| 问题 | 根本原因 | 修复方法 |
|-------|-----------|-----|
| ANX7625 sysfs 重复（`-EEXIST`） | ANX7625 在与 panel@0 相同的地址注册了 DSI 设备 | 在 ANX7625 节点上设置 `status = "disabled"` |
| tc358762 已加载但没有 `/dev/dri/` | TC358762 要求 `port@1` 上存在下游面板 | 添加 `ports { port@0, port@1 }` 和 `lcd-panel` 节点 |
| panel-simple 中没有 `seiko,43wvf1g` | 此内核的 panel-simple 条目有限 | 改用自定义 `panel-dpi` 驱动 |
| 上游内核中没有 `panel-dpi.c` | 该文件已从 Linux 6.16 中移除 | 使用自定义 `scripts/src/panel_dpi.c` |
| `drm_panel_add()` 构建错误 | 在 Linux 6.16 中返回 void，而非 int | 已在自定义 panel_dpi.c 中修复 |
| DSI 设备卡在延迟探测状态 | panel-simple 未自动加载 | 将模块添加到 `/etc/modules` |

---

## 测试显示屏

### 检查 DRM 设备

```bash
# 列出 DRM 设备
ls -la /dev/dri/

# 显示屏信息
cat /sys/class/drm/card*/status
cat /sys/class/drm/card*/modes

# 使用 modetest
modetest -M msm
```

### 检查显示流水线

```bash
# 内核消息
dmesg | grep -iE "dsi|dpu|mdss|panel|display"

# 检查面板驱动是否已加载
lsmod | grep -iE "panel|st7701"

# 检查 DSI PHY
cat /sys/kernel/debug/dri/*/state
```

### 简单显示测试

```bash
# 用颜色填充帧缓冲区
cat /dev/urandom > /dev/fb0

# 或使用 fbset
fbset -i

# 测试图案
apt install fbset
fbset -test
```

### 使用 DRM（推荐）

```bash
# 安装工具
apt install libdrm-tests

# 运行模式设置测试
modetest -M msm -s <connector_id>@<crtc_id>:<mode>

# 示例
modetest -M msm -s 35@31:480x800
```

---

## 故障排查

### 没有 /dev/fb0 或 /dev/dri

1. 检查 MDSS 是否已启用：
   ```bash
   cat /sys/devices/platform/soc@0/5e00000.display-subsystem/status
   ```

2. 检查驱动错误：
   ```bash
   dmesg | grep -i "mdss\|dpu\|fail\|error"
   ```

3. 验证 DSI PHY 时钟：
   ```bash
   cat /sys/kernel/debug/clk/clk_summary | grep -i dsi
   ```

### 未检测到面板

1. 检查面板兼容字符串是否与某个内核驱动匹配
2. 验证复位 GPIO 是否正确
3. 检查电源连接
4. 查找面板探测错误：
   ```bash
   dmesg | grep -i "panel\|st7701\|probe"
   ```

### 显示乱码/伪影

1. 检查 DSI 通道配置是否与面板匹配
2. 验证 video-mode 设置
3. 如果使用自定义面板，请检查时序参数
4. 验证电压电平（大多数面板使用 1.8V I/O）

### 黑屏（背光已开启）

1. 检查 DPU → DSI → 面板的端点连接
2. 验证像素格式兼容性
3. 检查分辨率是否与面板原生分辨率匹配

### LPASS Pinctrl "Failed to get clk 'audio'"（音频无法工作）

**症状**：`dmesg` 显示：
```
platform a7c0000.pinctrl: deferred probe pending: Failed to get clk 'audio'
platform a740000.soundwire-controller: deferred probe pending
platform sound: deferred probe pending
```

**根本原因**：LPASS LPI 引脚控制器（`pinctrl@a7c0000`）需要来自 `q6afecc` 的 `"audio"` 时钟；`q6afecc` 是 ADSP remoteproc 内 Q6 AFE APR 服务的子节点。完整依赖链如下：

```
lpass_tlmm → q6afecc（时钟）→ q6afe（APR 服务）→ qcom_apr → ADSP remoteproc
                                                       ↑
                                                 qcom_glink_smem
```

所有音频模块都以 `=m`（可加载）方式构建。如果它们在内核的 `deferred_probe_timeout`（默认 30 秒）之后才加载，时钟提供者将始终不可用，`lpass_tlmm` 会永久失败，并连带导致所有 SoundWire 控制器和声卡失败。

**修复方法**：
```bash
sudo scripts/fix-audio-clock.sh
sudo reboot
```

此操作会创建 `/etc/modules-load.d/audio-clock-chain.conf`，确保 `qcom_glink_smem`、`qcom_apr` 和 `snd_soc_qdsp6` 在启动早期加载，远早于延迟探测超时。

**验证**：
```bash
scripts/fix-audio-clock.sh status     # 检查所有组件
dmesg | grep -E 'a7c0000|q6afe'      # 应显示探测成功
cat /proc/asound/cards                # 应列出声卡
```

### 没有声卡——"HDMI/I2S Playback: codec dai not found"

**Symptom**: `dmesg` shows:
```
platform sound: deferred probe pending: snd-sm8250: HDMI/I2S Playback: codec dai not found
```
`alsamixer` 报告 "cannot open mixer: No such file or directory"。

**根本原因**：DTS 中的 `sound` 节点包含引用 ANX7625 音频编解码器的 `hdmi-i2s-dai-link`。当 ANX7625 的 `status = "disabled"`（用于 DSI 面板）时，编解码器 DAI 不存在，导致整个声卡注册失败。

**修复方法**：在 Freenove DTS 的 `hdmi-i2s-dai-link` 节点中添加 `status = "disabled"`：
```dts
hdmi-i2s-dai-link {
    link-name = "HDMI/I2S Playback";
    status = "disabled";
    ...
};
```
这是因为 Qualcomm 声卡驱动（`sound/soc/qcom/common.c`）使用 `for_each_available_child_of_node()`，它会跳过已禁用的节点。

此修改已应用于 `dts/imola-camera-dsi-freenove.dts`。请重新编译并安装 DTB。

### alsamixer 中没有音量/麦克风控件

**症状**：alsamixer 可以打开，但只显示路由开关，没有 "Volume" 或 "Mic" 滑块。

**根本原因**：采用 QDSP6 流水线的 PM4125 编解码器使用基于路由的 ALSA 控件，没有传统的简单混音器控件。耳机音量为 `RX_RX0 Digital` / `RX_RX1 Digital`（0–84），麦克风增益为 `TX_DEC0`（0–20）。

**修复方法**：使用 `scripts/configure-audio.sh` 设置所有路由，并使用其 volume/mic-gain 子命令：
```bash
scripts/configure-audio.sh              # 完整设置（音量 80%，麦克风 60%）
scripts/configure-audio.sh volume 50    # 将耳机调整为 0–100%
scripts/configure-audio.sh mic-gain 80  # 将麦克风调整为 0–100%
```
在 alsamixer 中按 **F5** 显示所有控件；音量控件位于 `RX_RX0 Digital` 下。

### GT911 触摸屏无法工作——"I2C communication failure: -110"

**症状**：`dmesg` 显示：
```
Goodix-TS 2-005d: Error reading 1 bytes from 0x8140: -110
Goodix-TS 2-005d: I2C communication failure: -110
Goodix-TS 2-005d: probe with driver Goodix-TS failed with error -110
```
CCI I2C 总线 0 (i2c-2) 上地址为 0x5D 的 GT911 没有响应。

**根本原因——原厂驱动需要 IRQ**：上游 `goodix_ts.ko` (`CONFIG_TOUCHSCREEN_GOODIX=m`) 会无条件调用 `devm_request_threaded_irq()`。由于 GT911 INT 引脚连接到 STM32 域（JMISC 引脚 → Zephyr GPIO 35），Linux 没有可供它使用的 GPIO。当 `client->irq == 0` 时，探测失败。

**修复方法——使用支持轮询模式的已修补 goodix_ts**：
`scripts/src/` 中已修补的 `goodix.c` 会在没有可用 IRQ 时添加 `input_setup_polling()` 回退机制。构建并安装：
```bash
# 交叉编译（也可在设备上构建）：
scripts/build-dsi-modules.sh goodix_ts

# 在 UNO Q 上替换原厂模块：
KVER=$(uname -r)
sudo cp /tmp/dsi-modules-build/goodix_ts/goodix_ts.ko \
  /lib/modules/$KVER/kernel/drivers/input/touchscreen/
sudo depmod -a
sudo rmmod goodix_ts 2>/dev/null
sudo modprobe goodix_ts
```

**如果仍然失败（-110 超时）**：I2C 总线本身未工作。请检查：
```bash
# 扫描 CCI 总线 0 上的所有设备
sudo i2cdetect -y 2

# 检查 CCI 硬件超时
dmesg | grep -i cci
```

如果看到 `master 0 queue 0 timeout` 且总线上没有设备，这说明 CCI I2C 总线 0 存在**物理连接问题**：

| 检查项 | 详情 |
|-------|--------|
| **摄像头 0 (J4)** | 同一 I2C 总线上的故障摄像头可能会将 SDA/SCL 拉低。断开摄像头后重新扫描。 |
| **DSI FPC 线缆** | 引脚 13 (SCL) 和 14 (SDA) 必须在连接器中可靠接触 |
| **PCA9306 电平转换器** | 两侧都需要 VREF，才能在 1.8V 和 3.3V 之间转换 |
| **CCI 总线 0 共享设备**： | 摄像头 0 I2C + DSI 连接器 I2C (gpio22/gpio23 → JMEDIA 51/53) |

**GT911 I2C 地址锁存**：GT911 在 RESET 上升沿期间，根据 INT 引脚电平锁存其 I2C 地址：
- RESET↑ 期间 INT 为 LOW → **0x5D**（DTS 默认值）
- RESET↑ 期间 INT 为 HIGH → **0x14**

MCU 固件必须在释放 RESET 前将 INT 驱动为 LOW：
```
INT  → OUTPUT LOW
RESET → LOW (hold ≥10ms)
RESET → HIGH
wait 5ms
INT  → INPUT (release)
wait ≥50ms        ← GT911 ready for I2C
```

---

## 显示时钟 ID (DISPCC)

| 时钟名称 | ID | 用途 |
|------------|-----|---------|
| DISP_CC_MDSS_BYTE0_CLK | 3 | DSI 字节时钟 |
| DISP_CC_MDSS_BYTE0_INTF_CLK | 6 | DSI 字节接口 |
| DISP_CC_MDSS_PCLK0_CLK | 13 | 像素时钟 |
| DISP_CC_MDSS_ESC0_CLK | 7 | 逃逸时钟 |
| DISP_CC_MDSS_AHB_CLK | 1 | AHB 接口 |
| DISP_CC_MDSS_MDP_CLK | 9 | MDP 核心时钟 |
| DISP_CC_MDSS_VSYNC_CLK | 15 | VSync 时钟 |

---

## 内核模块构建参考

以下模块必须构建为树外 `.ko` 文件；Arduino UNO Q 原厂内核均未包含这些模块：

| 模块 | 适用对象 | 构建命令 | 状态 |
|--------|-----|---------------|--------|
| `tc358762.ko` | Freenove 4.3 英寸、RPi 7 英寸、WaveShare DSI | `build-dsi-ondevice.sh tc358762` | **已验证** |
| `panel_dpi.ko` | 通用 DPI 面板（TC358762 下游） | `build-dsi-ondevice.sh panel_dpi` | **已验证** |
| `ili9881c.ko` | WaveShare 5/7/10.1 英寸 DSI | `build-dsi-ondevice.sh ili9881c` | 未测试 |
| `st7701.ko` | Arduino GigaDisplay、HyperPixel 4 | `build-dsi-ondevice.sh st7701` | 未测试 |
| `hx8394.ko` | 通用低成本 720p DSI 面板 | `build-dsi-ondevice.sh hx8394` | 未测试 |
| `otm8009a.ko` | STM32 Discovery / 评估板 | `build-dsi-ondevice.sh otm8009a` | 未测试 |
| `goodix_ts.ko` | Goodix GT911/GT9xx 触摸屏（轮询模式） | `build-dsi-modules.sh goodix_ts` | **已修补** |

### 构建脚本

| 脚本 | 使用场景 | 备注 |
|--------|----------|-------|
| `scripts/build-dsi-ondevice.sh` | 在 UNO Q 板上 | 按需克隆内核源码；自动安装模块 |
| `scripts/cross-build-dsi-modules.sh` | 在 Linux 主机上 | 为 arm64 交叉编译；将 .ko 复制到 `/tmp/dsi-modules-cross/modules/` |
| `scripts/build-camss-patched.sh` | 配有可选传感器的摄像头 | 修补 CAMSS 以跳过缺失的摄像头（见下文） |
| `scripts/camera-setup.sh` | 检测并配置摄像头 | 自动检测传感器、跟踪管线、配置格式并采集 |
| `scripts/fix-audio-clock.sh` | 修复 LPASS 音频时钟故障 | 确保 QDSP6 模块在延迟探测超时前加载 |
| `scripts/configure-audio.sh` | 配置耳机和麦克风 | 设置 PM4125 路由；提供 volume/mic-gain/status 子命令 |

### 本地源码覆盖

构建脚本从 GitHub 下载前会先检查 `scripts/src/` 中的本地源文件。目前提供：

- `scripts/src/panel_dpi.c`：自定义 panel-dpi 驱动（上游已在 Linux 6.16 中移除）
- `scripts/src/goodix.c`：修补后的 Goodix 触摸屏驱动，带 `input_setup_polling()` 回退机制（原厂驱动要求使用不可用的 IRQ）
- `scripts/src/goodix.h`：Goodix 头文件（未经修改，构建需要）
- `scripts/src/goodix_fwupload.c`：Goodix 固件上传代码（未经修改，构建需要）

## CAMSS 可选传感器补丁

### 问题

原厂 CAMSS 内核模块使用 v4l2 异步通知器；它会等待设备树中声明的**所有**传感器完成绑定，然后才调用 `media_device_register()`。只要有任一摄像头连接器未安装设备（没有物理传感器），异步通知器就永远无法完成，`/dev/media0` 也不会出现，导致整个摄像头子系统不可用，甚至已连接的摄像头也无法使用。

### 解决方案

`build-camss-patched.sh` 脚本使用一个补丁重新构建 `qcom-camss.ko` 模块，该补丁会：

1. **检查 `of_device_is_available(remote)`**：跳过 DT 中 `status = "disabled"` 的传感器
2. **探测 I2C 总线**：调用 `i2c_smbus_xfer()` 检查传感器是否在其地址上响应。如果没有设备应答 (NACK)，则跳过该传感器并记录日志消息

这样，CAMSS 只需物理存在的传感器即可完成初始化。

### 构建和部署

```bash
# 在设备上构建（需要先前运行 build-dsi-ondevice.sh 时准备的内核源码）：
scripts/build-camss-patched.sh /opt/arduino-linux-qcom

# 交叉编译：
ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
  scripts/build-camss-patched.sh /tmp/dsi-modules-cross/linux-qcom
```

部署到开发板：
```bash
KVER=$(uname -r)
DEST=/lib/modules/$KVER/kernel/drivers/media/platform/qcom/camss
sudo cp $DEST/qcom-camss.ko $DEST/qcom-camss.ko.orig   # 备份
sudo cp /tmp/camss-patched/qcom-camss.ko $DEST/
sudo depmod -a && sudo reboot
```

### 验证

```bash
# 即使只连接一个摄像头，也应显示 /dev/media0
ls /dev/media*

# 检查检测到或跳过了哪些传感器
dmesg | grep -i 'sensor.*detected\|sensor.*skipping\|camss'

# 媒体管线应可用
media-ctl -d /dev/media0 -p
```

---

## 版本历史

| 版本 | 日期 | 更改 |
|---------|------|---------|
| 1.0 | 2026 年 2 月 | 初始 DSI 显示屏指南 |
| 1.1 | 2026 年 2 月 | 确认引脚映射；记录 DISP_EN/DISP_RESET 的 STM32 限制、Freenove overlay 和模块构建脚本 |
| 2.0 | 2026 年 3 月 | 验证 Freenove 4.3 英寸可正常工作；记录 TC358762 port@1 要求、自定义 panel_dpi 驱动、CAMSS 可选传感器补丁以及完整的启动问题和修复 |
| 2.1 | 2026 年 3 月 | 修复 LPASS 音频时钟依赖 (q6afecc/deferred probe)；添加 fix-audio-clock.sh 脚本 |
| 2.2 | 2026 年 3 月 | 修复 DSI 面板模式下的 HDMI DAI 链路；为 PM4125 控件重写 configure-audio.sh；添加 alsamixer 故障排查 |
| 2.3 | 2026 年 3 月 | 使用 STM32 引脚名称和 Zephyr GPIO 编号修正 DISP_EN/DISP_RESET；添加 cam_dual_io.ino 参考；补充 GT911 复位共享说明 |
| 2.4 | 2026 年 3 月 | 调查 GT911 触摸屏：原厂 goodix_ts 要求不可用的 IRQ；提供带轮询模式的修补驱动；诊断 CCI 总线 0 超时；记录 I2C 地址锁存时序 |
