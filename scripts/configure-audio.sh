#!/bin/bash
#
# 在 Arduino UNO Q 上配置音频——Zephyria Shield
#
# Qualcomm QDSP6 音频管线没有传统的 "Volume" 或 "Mic" 混音器控件。
# 数百个路由开关将 DSP 流 (MultiMedia1–8) 依次连接到
# LPASS 宏 (RX/TX) → SoundWire → PM4125 编解码器 → 耳机/麦克风硬件。
#
# 此脚本设置完整的路由链，并通过数字增益寄存器提供音量/增益控制。
#
# 用法：
#   ./configure-audio.sh                  # Configure routing + 80% volume
#   ./configure-audio.sh volume 50        # Set headphone volume (0–100%)
#   ./configure-audio.sh mic-gain 60      # Set microphone gain (0–100%)
#   ./configure-audio.sh status           # Show current configuration
#   ./configure-audio.sh test             # Quick playback test
#

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
section() { echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}\n"; }

CARD=0

# ── Helper ──────────────────────────────────────────────────────────────

set_ctl() {
    local name="$1"
    local value="$2"
    if amixer -c $CARD cset name="$name" "$value" >/dev/null 2>&1; then
        echo -e "    ${GREEN}✓${NC}  $name = $value"
    else
        echo -e "    ${YELLOW}!${NC}  $name — 未找到"
    fi
}

get_ctl() {
    amixer -c $CARD cget name="$1" 2>/dev/null | grep ': values=' | sed 's/.*values=//'
}

# 将百分比 (0–100) 映射为数字增益值（0–84，其中 84 = 0dB）
pct_to_rx_digital() {
    local pct="$1"
    echo $(( pct * 84 / 100 ))
}

# 将百分比 (0–100) 映射为 TX 抽取器增益（0–20，其中 20 = +20dB）
pct_to_tx_digital() {
    local pct="$1"
    echo $(( pct * 20 / 100 ))
}

# ── Detect sound card ───────────────────────────────────────────────────

check_card() {
    if [ ! -f /proc/asound/cards ]; then
        error "未找到 ALSA 子系统。"
    fi
    if ! grep -q "card $CARD" /proc/asound/cards 2>/dev/null; then
        error "未找到声卡 $CARD。请检查：cat /proc/asound/cards"
    fi
}

# ── Configure headphone playback ────────────────────────────────────────

configure_playback() {
    local vol_pct="${1:-80}"
    local rx_dig=$(pct_to_rx_digital "$vol_pct")

    section "Headphone Playback Routing"

    info "DSP → CODEC DMA 路由"
    set_ctl 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1' 1

    info "LPASS RX 宏 MUX → AIF1 播放"
    set_ctl 'RX_MACRO RX0 MUX' 'AIF1_PB'
    set_ctl 'RX_MACRO RX1 MUX' 'AIF1_PB'

    info "插值器（通往 DAC 的信号路径）"
    set_ctl 'RX INT0_1 MIX1 INP0' 'RX0'
    set_ctl 'RX INT1_1 MIX1 INP0' 'RX1'

    info "解调器 → Class-H"
    set_ctl 'RX INT0 DEM MUX' 'CLSH_DSM_OUT'
    set_ctl 'RX INT1 DEM MUX' 'CLSH_DSM_OUT'

    info "启用 RDAC 和耳机开关"
    set_ctl 'HPHL_RDAC Switch' 1
    set_ctl 'HPHR_RDAC Switch' 1
    set_ctl 'HPHL Switch' 1
    set_ctl 'HPHR Switch' 1

    info "数字音量：${vol_pct}%（寄存器=${rx_dig}/84）"
    set_ctl 'RX_RX0 Digital' "$rx_dig"
    set_ctl 'RX_RX1 Digital' "$rx_dig"
}

# ── Configure microphone capture ────────────────────────────────────────

configure_capture() {
    local gain_pct="${1:-60}"
    local tx_dig=$(pct_to_tx_digital "$gain_pct")

    section "Microphone Capture Routing"

    info "CODEC DMA TX → DSP 采集（MultiMedia1）"
    set_ctl 'MultiMedia1 Mixer TX_CODEC_DMA_TX_3' 1

    info "TX 宏抽取器 → SoundWire 麦克风"
    set_ctl 'TX DEC0 MUX' 'SWR_MIC'
    set_ctl 'TX SMIC MUX0' 'ADC2'

    info "ADC2 输入选择 → INP3（Zephyria Shield 上的 AMIC2）"
    set_ctl 'ADC2 MUX' 'INP3'

    info "TX 采集路径 → AIF1"
    set_ctl 'TX_AIF1_CAP Mixer DEC0' 1

    info "抽取器增益：${gain_pct}%（寄存器=${tx_dig}/20）"
    set_ctl 'TX_DEC0' "$tx_dig"
}

# ── Set volume only ─────────────────────────────────────────────────────

set_volume() {
    local pct="$1"
    [ -z "$pct" ] && error "Usage: $0 volume <0-100>"
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local rx_dig=$(pct_to_rx_digital "$pct")

    info "耳机音量：${pct}%（寄存器=${rx_dig}/84）"
    set_ctl 'RX_RX0 Digital' "$rx_dig"
    set_ctl 'RX_RX1 Digital' "$rx_dig"
}

# ── Set mic gain only ───────────────────────────────────────────────────

set_mic_gain() {
    local pct="$1"
    [ -z "$pct" ] && error "Usage: $0 mic-gain <0-100>"
    [ "$pct" -lt 0 ] 2>/dev/null && pct=0
    [ "$pct" -gt 100 ] 2>/dev/null && pct=100
    local tx_dig=$(pct_to_tx_digital "$pct")

    info "麦克风增益：${pct}%（寄存器=${tx_dig}/20）"
    set_ctl 'TX_DEC0' "$tx_dig"
}

# ── Status ──────────────────────────────────────────────────────────────

show_status() {
    section "Audio Status"

    echo "  声卡："
    cat /proc/asound/cards 2>/dev/null | sed 's/^/    /'
    echo ""

    echo "  播放路由："
    local mm1_rx=$(get_ctl 'RX_CODEC_DMA_RX_0 Audio Mixer MultiMedia1')
    local hphl=$(get_ctl 'HPHL Switch')
    local hphr=$(get_ctl 'HPHR Switch')
    local rx0=$(get_ctl 'RX_RX0 Digital')
    local rx1=$(get_ctl 'RX_RX1 Digital')

    if [ "$mm1_rx" = "1" ] && [ "$hphl" = "1" ]; then
        echo -e "    ${GREEN}✓${NC}  MultiMedia1 → RX_CODEC_DMA_RX_0 → HPHL/HPHR"
        echo "    音量 左：${rx0}/84  右：${rx1}/84"
    else
        echo -e "    ${RED}✗${NC}  播放路由未配置（运行：$0）"
    fi
    echo ""

    echo "  采集路由："
    local mm1_tx=$(get_ctl 'MultiMedia1 Mixer TX_CODEC_DMA_TX_3')
    local dec0=$(get_ctl 'TX_DEC0')
    if [ "$mm1_tx" = "1" ]; then
        echo -e "    ${GREEN}✓${NC}  TX_CODEC_DMA_TX_3 → MultiMedia1"
        echo "    麦克风增益：${dec0}/20"
    else
        echo -e "    ${RED}✗${NC}  采集路由未配置（运行：$0）"
    fi
    echo ""

    echo "  延迟探测问题："
    if dmesg 2>/dev/null | grep -q 'deferred probe pending.*sound'; then
        echo -e "    ${RED}✗${NC}  声卡存在延迟探测失败"
        dmesg 2>/dev/null | grep 'deferred probe pending.*sound' | tail -1 | sed 's/^/        /'
    else
        echo -e "    ${GREEN}✓${NC}  没有延迟探测问题"
    fi
    echo ""
}

# ── Main ────────────────────────────────────────────────────────────────

ACTION="${1:-setup}"

case "$ACTION" in
    setup)
        check_card

        echo ""
        echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
        echo -e "${BOLD}  音频配置 — Arduino UNO Q / Zephyria Shield${NC}"
        echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"

        configure_playback "${2:-80}"
        configure_capture "${3:-60}"

        section "Done"

        echo "  耳机：已配置（音量 ${2:-80}%）"
        echo "  麦克风：已配置（增益 ${3:-60}%）"
        echo ""
        echo "  后续调整："
        echo -e "    ${GREEN}$0 volume 50${NC}       # headphone 0–100%"
        echo -e "    ${GREEN}$0 mic-gain 80${NC}     # microphone 0–100%"
        echo -e "    ${GREEN}$0 status${NC}          # show current config"
        echo -e "    ${GREEN}$0 test${NC}            # quick playback test"
        echo ""
        echo "  测试命令："
        echo -e "    ${GREEN}speaker-test -c 2 -t sine -f 440 -l 2${NC}"
        echo -e "    ${GREEN}arecord -d 5 -f cd -t wav /tmp/test.wav && aplay /tmp/test.wav${NC}"
        echo ""
        ;;

    volume)
        check_card
        set_volume "$2"
        ;;

    mic-gain)
        check_card
        set_mic_gain "$2"
        ;;

    status)
        check_card
        show_status
        ;;

    test)
        check_card
        info "正在播放 440 Hz 测试音（2 秒）..."
        speaker-test -c 2 -t sine -f 440 -l 2
        ;;

    *)
        echo "用法：$0 [setup|volume <0-100>|mic-gain <0-100>|status|test]"
        echo ""
        echo "  setup [vol%] [mic%]   配置完整路由（默认：音量 80%，麦克风 60%）"
        echo "  volume <0-100>        调整耳机音量"
        echo "  mic-gain <0-100>      Adjust microphone gain"
        echo "  status                Show current audio configuration"
        echo "  test                  Play a test tone"
        exit 1
        ;;
esac
