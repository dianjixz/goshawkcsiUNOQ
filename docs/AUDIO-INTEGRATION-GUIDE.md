# Zephyria Shield 音频集成指南

## 概述

Arduino UNO Q 使用 **PM4125 PMIC 集成音频编解码器**实现模拟音频 I/O。Zephyria Shield 将这些信号从 JMISC 连接器路由至标准音频连接器。

**好消息：** 基础 Arduino DTB 中已配置音频。扩展板只需正确路由物理信号。

---

## 音频硬件架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    QRB2210 音频子系统                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌─────────────────┐                                          │
│   │  ADSP（音频     │ ← 固件 (adsp.mbn)                        │
│   │  DSP 处理器）   │                                          │
│   └────────┬────────┘                                          │
│            │                                                    │
│            ▼                                                    │
│   ┌─────────────────┐      ┌───────────────┐                   │
│   │  LPASS（低功耗  │      │  SoundWire    │                   │
│   │  音频子系统）   │◄────►│  控制器       │                   │
│   │                 │      │  (swr0, swr1) │                   │
│   └────────┬────────┘      └───────────────┘                   │
│            │                       │                            │
│            ▼                       ▼                            │
│   ┌─────────────────────────────────────────┐                  │
│   │           PM4125 PMIC 编解码器          │                  │
│   │  ┌─────────────┐   ┌─────────────┐     │                  │
│   │  │ TX（录音）  │   │ RX（播放）  │     │                  │
│   │  │ - AMIC1     │   │ - HPH_L     │     │                  │
│   │  │ - AMIC2  ◄──┼───┼── HPH_R     │     │                  │
│   │  │ - AMIC3     │   │ - LO（线路）│     │                  │
│   │  │ - DMIC      │   └─────────────┘     │                  │
│   │  └─────────────┘                       │                  │
│   └─────────────────────────────────────────┘                  │
│            │                       │                            │
└────────────┼───────────────────────┼────────────────────────────┘
             │                       │
             ▼                       ▼
      ┌──────────────┐        ┌──────────────┐
      │   JMISC      │        │   JMISC      │
      │（MIC 引脚）  │        │（HPH 引脚）  │
      └──────┬───────┘        └──────┬───────┘
             │                       │
             ▼                       ▼
      ┌──────────────┐        ┌──────────────┐
      │  Zephyria    │        │  Zephyria    │
      │  Shield MIC  │        │  Shield HPH  │
      │  连接器      │        │  连接器      │
      └──────────────┘        └──────────────┘
```

---

## 扩展板引脚映射

### 麦克风连接器

| MIC 引脚 | 信号 | JMISC 引脚 | PM4125 功能 | 说明 |
|---------|--------|-----------|-----------------|-------------|
| 1 | MIC2_INM | 31 | AMIC2 负端 | 差分麦克风输入 (-) |
| 2 | MIC2_INP | 29（RC 滤波器） | AMIC2 正端 | 差分麦克风输入 (+) |
| 3 | MIC2_BIAS | 33（RC 滤波器） | MIC BIAS2 | 麦克风偏置电压 (1.8V) |

### 耳机连接器

| HPH 引脚 | 信号 | JMISC 引脚 | PM4125 功能 | 说明 |
|---------|--------|-----------|-----------------|-------------|
| 1 | HPH_REF | 40 | 接地参考 | 耳机地线 |
| 2 | HPH_L | 36 | HPH_L | 左声道输出 |
| 3 | HPH_R | 38 | HPH_R | 右声道输出 |

---

## 当前设备树配置

### PM4125 编解码器节点

位于 SPMI PMIC 块中：

```dts
codec {
    compatible = "qcom,pm4125-codec";

    /* 电源 */
    vdd-io-supply = <&vreg_l3a>;       /* I/O 电压 */
    vdd-cp-supply = <&vreg_l5a>;       /* 电荷泵 */
    vdd-pa-vpos-supply = <&vreg_l5a>;  /* 功率放大器 */
    vdd-mic-bias-supply = <&vreg_l4a>; /* 麦克风偏置源 */

    /* 麦克风偏置电压（均为 1.8V = 0x1b7740 µV） */
    qcom,micbias1-microvolt = <1800000>;
    qcom,micbias2-microvolt = <1800000>;
    qcom,micbias3-microvolt = <1800000>;

    /* SoundWire 设备引用 */
    qcom,rx-device = <&pm4125_rx>;
    qcom,tx-device = <&pm4125_tx>;

    #sound-dai-cells = <1>;
    phandle = <0x8b>;
};
```

### 声卡节点

```dts
sound {
    compatible = "qcom,qrb2210-rb1-sndcard", "qcom,qrb4210-rb2-sndcard";
    model = "Arduino-Imola-HPH-LOUT";

    pinctrl-0 = <&lpass_rx_swr_active>;
    pinctrl-names = "default";

    /* 音频路由：将 PM4125 输出连接至输入 */
    audio-routing =
        "IN1_HPHL", "HPHL_OUT",   /* 耳机左声道 */
        "IN2_HPHR", "HPHR_OUT",   /* 耳机右声道 */
        "AMIC2", "MIC BIAS2";     /* 带偏置的麦克风 2 */

    /* 多媒体播放 DAI 链路 */
    mm1-dai-link { link-name = "MultiMedia1"; ... };
    mm2-dai-link { link-name = "MultiMedia2"; ... };
    mm3-dai-link { link-name = "MultiMedia3"; ... };
    mm4-dai-link { link-name = "MultiMedia4"; ... };

    /* 耳机播放 */
    hph-playback-dai-link {
        link-name = "HPH Playback";
        cpu { sound-dai = <&q6apm 0x71>; };
        platform { sound-dai = <&q6apm>; };
        codec { sound-dai = <&pm4125_codec 0x00
                             &pm4125_rx 0x00
                             &rxmacro 0x00>; };
    };

    /* 耳机/麦克风采集 */
    hph-capture-dai-link {
        link-name = "HP Capture";
        cpu { sound-dai = <&q6apm 0x78>; };
        platform { sound-dai = <&q6apm>; };
        codec { sound-dai = <&pm4125_codec 0x01
                             &pm4125_tx 0x00
                             &txmacro 0x00>; };
    };

    /* HDMI 音频（通过 ANX7625 USB-C） */
    hdmi-i2s-dai-link {
        link-name = "HDMI/I2S Playback";
        ...
    };
};
```

---

## 音频应已可以工作！

根据现有 DTB 配置：

1. **耳机输出**通过 `hph-playback-dai-link` 配置
2. **麦克风输入**通过 `hph-capture-dai-link` 配置，并使用 AMIC2
3. **音频路由**将 AMIC2 映射至 MIC BIAS2（与扩展板布线一致）

扩展板的 MIC2 和 HPH 引脚直接连接至 PM4125 引脚，因此**应该无需更改 DTS**。

---

## 测试音频

### 检查音频设备

```bash
# 列出声卡
cat /proc/asound/cards

# 列出 PCM 设备
aplay -l
arecord -l

# 检查 ALSA 控件
amixer -c 0 contents
```

### 测试耳机输出

```bash
# 安装音频工具
sudo apt install alsa-utils sox

# 生成测试音调
speaker-test -c 2 -t sine -f 440

# 播放音频文件
aplay -D hw:0,0 test.wav

# 或使用 PulseAudio/PipeWire
paplay test.wav
```

### 测试麦克风输入

```bash
# 录制 5 秒音频
arecord -d 5 -f cd -t wav recording.wav

# 使用指定设备录音
arecord -D hw:0,0 -d 5 -f cd recording.wav

# 实时监听麦克风
arecord -f cd | aplay
```

### 调整音量

```bash
# 打开 ALSA 混音器
alsamixer

# 或设置指定控件
amixer -c 0 set 'Headphone' 80%
amixer -c 0 set 'Mic' 80%

# 启用麦克风偏置（可能需要）
amixer -c 0 set 'MIC BIAS2' on
```

---

## 故障排查

### 未发现声音设备

1. **检查 ADSP 固件：**
   ```bash
   ls -la /lib/firmware/qcom/qrb2210/adsp*
   dmesg | grep -i adsp
   ```

2. **检查已加载的音频模块：**
   ```bash
   lsmod | grep -i snd
   lsmod | grep -i soundwire
   ```

3. **检查 remoteproc 状态：**
   ```bash
   cat /sys/class/remoteproc/remoteproc*/state
   cat /sys/class/remoteproc/remoteproc*/name
   ```

### 耳机没有声音

1. **检查路由：**
   ```bash
   amixer -c 0 | grep -A2 "HPH\|Headphone"
   ```

2. **检查是否已静音：**
   ```bash
   amixer -c 0 set 'Headphone' unmute
   ```

3. **检查物理连接** - 确认扩展板连接器已正确插接

### 麦克风不工作

1. **启用麦克风偏置：**
   ```bash
   amixer -c 0 set 'MIC BIAS2' on
   ```

2. **检查采集控件：**
   ```bash
   amixer -c 0 | grep -A2 "Mic\|AMIC"
   ```

3. **检查布线** - 检查扩展板 MIC 连接器与 JMISC 之间的连接

### ADSP 未加载

检查是否缺少固件：
```bash
# 所需固件文件
ls -la /lib/firmware/qcom/qrb2210/
# 应包含：adsp.mbn, adsp*.mdt
```

---

## 修改音频配置（如有需要）

### 更改麦克风偏置电压

如果麦克风需要不同的偏置电压（例如某些驻极体麦克风需要 2.7V）：

```dts
codec {
    compatible = "qcom,pm4125-codec";
    /* ... 其他属性 ... */

    /* 将麦克风偏置从 1.8V 改为 2.7V */
    qcom,micbias2-microvolt = <2700000>;
};
```

### 使用其他麦克风输入

如果使用 AMIC1 或 AMIC3 代替 AMIC2：

```dts
sound {
    /* ... */

    /* 从 AMIC2 改为 AMIC1 */
    audio-routing =
        "IN1_HPHL", "HPHL_OUT",
        "IN2_HPHR", "HPHR_OUT",
        "AMIC1", "MIC BIAS1";  /* 已从 AMIC2, MIC BIAS2 更改 */
};
```

### 添加线路输出

如果扩展板除耳机输出外还有线路输出：

```dts
sound {
    audio-routing =
        "IN1_HPHL", "HPHL_OUT",
        "IN2_HPHR", "HPHR_OUT",
        "AMIC2", "MIC BIAS2",
        "IN3_LO", "LO_OUT";  /* 添加线路输出 */
};
```

---

## 音频路由参考

### PM4125 输出引脚（RX/播放）

| 输出 | 信号 | 说明 |
|--------|--------|-------------|
| HPHL_OUT | HPH_L | 耳机左声道 |
| HPHR_OUT | HPH_R | 耳机右声道 |
| LO_OUT | LO | 线路输出 |
| EAR_OUT | EAR | 听筒（扩展板未使用） |

### PM4125 输入引脚（TX/采集）

| 输入 | 信号 | 说明 |
|-------|--------|-------------|
| AMIC1 | MIC1 | 模拟麦克风 1（带 BIAS1） |
| AMIC2 | MIC2 | 模拟麦克风 2（带 BIAS2）- **扩展板使用此项** |
| AMIC3 | MIC3 | 模拟麦克风 3（带 BIAS3） |
| DMIC | DMIC | 数字麦克风（I2S 接口） |

---

## 所需内核模块

这些模块应已内置于 Arduino 内核中：

| 模块 | 用途 |
|--------|---------|
| `snd_soc_qcom_common` | Qualcomm 声音核心 |
| `snd_soc_sm8250` | SM8250/QCM2290 音频 |
| `snd_soc_qcom_sdw` | SoundWire 支持 |
| `snd_soc_wcd_mbhc` | 耳机检测 |
| `snd_soc_wcd_swr` | WCD SoundWire |

---

## 版本历史

| 版本 | 日期 | 更改 |
|---------|------|---------|
| 1.0 | 2026 年 2 月 | 初始音频集成指南 |
