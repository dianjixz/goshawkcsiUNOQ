#!/bin/bash
#
# Zephyria Shield——启动时设备设置
#
# 配置扩展板的所有外设，使开发板可直接使用：
#   - Audio: headphone output + microphone capture routing
#   - Camera: detect sensors, configure media pipelines
#   - Display: verify DSI panel status
#
# 启动时由 zephyria-setup.service 调用，也可手动运行。
#
# 用法：
#   sudo zephyria-setup.sh           # Configure everything
#   sudo zephyria-setup.sh status    # Show device status summary
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_TAG="zephyria-setup"
LOGFILE="/var/log/zephyria-setup.log"

# ── Logging ─────────────────────────────────────────────────────────────

log() {
    local msg="[$(date '+%H:%M:%S')] $*"
    echo "$msg" >> "$LOGFILE"
    logger -t "$LOG_TAG" -- "$*"
    echo "$msg"
}

log_ok()   { log "成功：$*"; }
log_warn() { log "警告：$*"; }
log_fail() { log "失败：$*"; }

# ── Audio ───────────────────────────────────────────────────────────────

setup_audio() {
    log "--- 音频设置 ---"

    # 声卡依赖 ADSP remoteproc → APR → 编解码器链（启动后约 12-15 秒）
    local retries=0
    while ! grep -q 'card 0' /proc/asound/cards 2>/dev/null; do
        retries=$((retries + 1))
        if [ $retries -gt 6 ]; then
            log_fail "未检测到声卡（已等待 30 秒）"
            return 1
        fi
        log "正在等待声卡...（${retries}/6）"
        sleep 5
    done

    local card_name
    card_name=$(cat /proc/asound/cards 2>/dev/null | head -1)
    log "声卡：$card_name"

    # 耳机播放路由
    amixer -c 0 cset name='RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 1 >/dev/null 2>&1
    amixer -c 0 cset name='RX_MACRO RX0 MUX' 'AIF1_PB' >/dev/null 2>&1
    amixer -c 0 cset name='RX_MACRO RX1 MUX' 'AIF1_PB' >/dev/null 2>&1
    amixer -c 0 cset name='RX INT0_1 MIX1 INP0' 'RX0' >/dev/null 2>&1
    amixer -c 0 cset name='RX INT1_1 MIX1 INP0' 'RX1' >/dev/null 2>&1
    amixer -c 0 cset name='RX INT0 DEM MUX' 'CLSH_DSM_OUT' >/dev/null 2>&1
    amixer -c 0 cset name='RX INT1 DEM MUX' 'CLSH_DSM_OUT' >/dev/null 2>&1
    amixer -c 0 cset name='HPHL_RDAC Switch' 1 >/dev/null 2>&1
    amixer -c 0 cset name='HPHR_RDAC Switch' 1 >/dev/null 2>&1
    amixer -c 0 cset name='HPHL Switch' 1 >/dev/null 2>&1
    amixer -c 0 cset name='HPHR Switch' 1 >/dev/null 2>&1

    # 音量：80% (67/84)
    amixer -c 0 cset name='RX_RX0 Digital' 67 >/dev/null 2>&1
    amixer -c 0 cset name='RX_RX1 Digital' 67 >/dev/null 2>&1

    log_ok "耳机输出已配置（80%）"

    # 麦克风采集路由
    amixer -c 0 cset name='MultiMedia1 Mixer TX_CODEC_DMA_TX_3' 1 >/dev/null 2>&1
    amixer -c 0 cset name='TX DEC0 MUX' 'SWR_MIC' >/dev/null 2>&1
    amixer -c 0 cset name='TX SMIC MUX0' 'ADC2' >/dev/null 2>&1
    amixer -c 0 cset name='ADC2 MUX' 'INP3' >/dev/null 2>&1
    amixer -c 0 cset name='TX_AIF1_CAP Mixer DEC0' 1 >/dev/null 2>&1

    # 麦克风增益：60% (12/20)
    amixer -c 0 cset name='TX_DEC0' 12 >/dev/null 2>&1

    log_ok "麦克风采集已配置（60%）"
}

# ── Camera ──────────────────────────────────────────────────────────────

setup_camera() {
    log "--- 摄像头设置 ---"

    if [ ! -e /dev/media0 ]; then
        log_warn "没有 /dev/media0，CAMSS 不可用（是否已加载 qcom-camss？）"
        return 1
    fi

    if ! command -v media-ctl &>/dev/null; then
        log_warn "未找到 media-ctl，跳过管线配置"
        return 1
    fi

    local MEDIA_OUTPUT
    MEDIA_OUTPUT="$(media-ctl -d /dev/media0 -p 2>/dev/null)"

    local FORMAT="SRGGB10_1X10"
    local WIDTH=1920
    local HEIGHT=1080
    local FMT="${FORMAT}/${WIDTH}x${HEIGHT}"

    # 查找所有 imx219 传感器
    local sensor_count=0
    while IFS= read -r line; do
        if [[ "$line" =~ entity\ [0-9]+:\ (imx219\ [0-9]+-[0-9a-f]+)\ \( ]]; then
            local entity="${BASH_REMATCH[1]}"
            sensor_count=$((sensor_count + 1))
            log "发现传感器：$entity"

            # 配置传感器格式
            media-ctl -d /dev/media0 --set-v4l2 "\"${entity}\":0[fmt:${FMT}]" 2>/dev/null && \
                log_ok "已配置 $entity" || \
                log_warn "配置 $entity 失败"
        fi
    done <<< "$MEDIA_OUTPUT"

    if [ $sensor_count -eq 0 ]; then
        log_warn "未检测到 IMX219 传感器"
        return 1
    fi

    # 配置管线元素 (csiphy、csid、vfe)
    for element_type in msm_csiphy msm_csid msm_vfe; do
        while IFS= read -r line; do
            if [[ "$line" =~ entity\ [0-9]+:\ (${element_type}[0-9a-z_]+)\ \( ]]; then
                local elem="${BASH_REMATCH[1]}"
                # 从实体行中查找焊盘数量
                local pads
                pads=$(echo "$line" | grep -oP '\d+ pads' | grep -oP '\d+')
                if [ -n "$pads" ]; then
                    for ((p=0; p<pads; p++)); do
                        media-ctl -d /dev/media0 --set-v4l2 "\"${elem}\":${p}[fmt:${FMT}]" 2>/dev/null || true
                    done
                fi
            fi
        done <<< "$MEDIA_OUTPUT"
    done

    log_ok "已将 $sensor_count 个摄像头配置为 ${WIDTH}x${HEIGHT}"

    # 在传感器子设备上设置默认曝光/增益
    for subdev in /dev/v4l-subdev*; do
        if v4l2-ctl -d "$subdev" --list-ctrls 2>/dev/null | grep -q exposure; then
            v4l2-ctl -d "$subdev" --set-ctrl=exposure=5000 2>/dev/null || true
            v4l2-ctl -d "$subdev" --set-ctrl=analogue_gain=400 2>/dev/null || true
        fi
    done

    log_ok "已为传感器子设备设置默认曝光和增益"
}

# ── Display ─────────────────────────────────────────────────────────────

setup_display() {
    log "--- 显示设置 ---"

    if [ ! -d /dev/dri ]; then
        log_fail "没有 /dev/dri，显示子系统不可用"
        return 1
    fi

    local connected=0
    for conn in /sys/class/drm/card0-*/status; do
        local name="${conn%/status}"
        name="${name##*/}"
        local status
        status=$(cat "$conn" 2>/dev/null)
        if [ "$status" = "connected" ]; then
            local mode
            mode=$(cat "${conn%/status}/modes" 2>/dev/null | head -1)
            log_ok "显示器 $name：已连接（$mode）"
            connected=1
        fi
    done

    if [ $connected -eq 0 ]; then
        log_warn "未检测到已连接的显示器"
    fi

    # 检查帧缓冲区
    if [ -e /dev/fb0 ]; then
        log_ok "/dev/fb0 可用"
    fi
}

# ── Touchscreen ─────────────────────────────────────────────────────────

check_touch() {
    log "--- 触摸屏检查 ---"

    local found=0
    for input in /sys/class/input/input*/name; do
        local name
        name=$(cat "$input" 2>/dev/null)
        if [[ "$name" == *oodix* ]] || [[ "$name" == *GT911* ]] || [[ "$name" == *gt9* ]]; then
            log_ok "触摸屏：$name"
            found=1
        fi
    done

    if [ $found -eq 0 ]; then
        # 检查 I2C 上地址为 0x5D 或 0x14 的 GT911
        if command -v i2cdetect &>/dev/null; then
            for bus in /dev/i2c-*; do
                local busnum="${bus##*-}"
                if i2cdetect -y "$busnum" 2>/dev/null | grep -qE '\b(5d|14)\b'; then
                    log_warn "i2c-${busnum} 上可能存在 GT911，但驱动尚未绑定"
                    found=2
                fi
            done
        fi
        if [ $found -eq 0 ]; then
            log_warn "未检测到触摸屏（I2C 上未找到 GT911）"
        fi
    fi
}

# ── Status ──────────────────────────────────────────────────────────────

show_status() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Zephyria Shield — 设备状态"
    echo "════════════════════════════════════════════════════════════"
    echo ""

    # 显示屏
    echo "  显示："
    if [ -d /dev/dri ]; then
        for conn in /sys/class/drm/card0-*/status; do
            local name="${conn%/status}"; name="${name##*/}"
            local st=$(cat "$conn" 2>/dev/null)
            local mode=$(cat "${conn%/status}/modes" 2>/dev/null | head -1)
            [ "$st" = "connected" ] && echo "    OK  $name ($mode)" || echo "    --  $name ($st)"
        done
    else
        echo "    失败  没有 /dev/dri"
    fi

    # 触摸屏
    echo ""
    echo "  触摸屏："
    local touch_found=0
    for input in /sys/class/input/input*/name; do
        local n=$(cat "$input" 2>/dev/null)
        if [[ "$n" == *oodix* ]] || [[ "$n" == *GT911* ]] || [[ "$n" == *gt9* ]]; then
            local dev_path="${input%/name}"
            local evdev=$(ls "$dev_path"/event* 2>/dev/null | head -1)
            evdev="${evdev##*/}"
            echo "    OK  $n (/dev/input/$evdev)"
            touch_found=1
        fi
    done
    [ $touch_found -eq 0 ] && echo "    --  未检测到"

    # 音频
    echo ""
    echo "  音频："
    if grep -q 'card 0' /proc/asound/cards 2>/dev/null; then
        local hphl=$(amixer -c 0 cget name='HPHL Switch' 2>/dev/null | grep 'values=' | sed 's/.*values=//')
        local rx0=$(amixer -c 0 cget name='RX_RX0 Digital' 2>/dev/null | grep 'values=' | sed 's/.*values=//')
        if [ "$hphl" = "1" ]; then
            echo "    成功  耳机已配置（音量：${rx0}/84）"
        else
            echo "    --  声卡存在但未设置路由（运行：configure-audio.sh）"
        fi
        local tx=$(amixer -c 0 cget name='MultiMedia1 Mixer TX_CODEC_DMA_TX_3' 2>/dev/null | grep 'values=' | sed 's/.*values=//')
        local dec0=$(amixer -c 0 cget name='TX_DEC0' 2>/dev/null | grep 'values=' | sed 's/.*values=//')
        if [ "$tx" = "1" ]; then
            echo "    成功  麦克风已配置（增益：${dec0}/20）"
        else
            echo "    --  麦克风采集未路由"
        fi
    else
        echo "    失败  没有声卡"
    fi

    # 摄像头
    echo ""
    echo "  摄像头："
    if [ -e /dev/media0 ] && command -v media-ctl &>/dev/null; then
        local sensors
        sensors=$(media-ctl -d /dev/media0 -p 2>/dev/null | grep -oP 'imx219 \d+-[0-9a-f]+' | sort -u)
        if [ -n "$sensors" ]; then
            while read -r s; do
                echo "    OK  $s"
            done <<< "$sensors"
        else
            echo "    --  未检测到传感器"
        fi
        # 列出视频设备
        if command -v v4l2-ctl &>/dev/null; then
            local videos
            videos=$(v4l2-ctl --list-devices 2>/dev/null | grep '/dev/video' | tr -d '\t ')
            if [ -n "$videos" ]; then
                echo "    视频设备：$(echo $videos | tr '\n' ' ')"
            fi
        fi
    else
        echo "    失败  没有 /dev/media0"
    fi

    echo ""
    echo "  日志：$LOGFILE"
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────

ACTION="${1:-setup}"

case "$ACTION" in
    setup)
        echo "" >> "$LOGFILE"
        log "=== Zephyria Shield 设置开始 ==="

        # 短暂等待设备稳定（启动时很重要）
        if [ "$(cat /proc/uptime | cut -d. -f1)" -lt 20 ]; then
            log "系统启动初期，等待 5 秒让设备就绪..."
            sleep 5
        fi

        setup_display
        setup_audio
        setup_camera

        # 确保为 GT911 触摸屏加载支持轮询模式的已修补 goodix_ts
        if ! lsmod | grep -q goodix_ts 2>/dev/null; then
            modprobe goodix_ts 2>/dev/null || true
        fi

        check_touch

        log "=== 设置完成 ==="
        show_status
        ;;

    status)
        show_status
        ;;

    *)
        echo "用法：$0 [setup|status]"
        exit 1
        ;;
esac
