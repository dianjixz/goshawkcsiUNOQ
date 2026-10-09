#!/bin/bash
#
# 修复 LPASS LPI pinctrl 的 "Failed to get clk 'audio'" 延迟探测失败问题
#
# 问题：
#   pinctrl@a7c0000 (lpass_tlmm) 需要来自 q6afecc 的 "audio" 时钟；
#   q6afecc 是 q6afe（APR 服务）的子节点，而 q6afe 位于 ADSP remoteproc 中。
#   如果 QDSP6 音频模块加载过晚，lpass_tlmm 的延迟探测会超时，
#   导致整个音频子系统失败：
#
#     platform a7c0000.pinctrl: deferred probe pending: Failed to get clk 'audio'
#     platform a740000.soundwire-controller: deferred probe pending
#     platform a610000.soundwire-controller: deferred probe pending
#     platform sound: deferred probe pending
#
# 根本原因：
#   所有音频模块均为 CONFIG_*=m（可加载）。依赖链如下：
#     qcom_glink_smem → ADSP 启动 → qcom_apr → q6afe → q6afe-clocks (q6afecc)
#   如果此链中的任一模块在 deferred_probe_timeout（30 秒）后才加载，
#   lpass_tlmm 将无法获取其时钟并永久失败。
#
# 修复方法：
#   1. 通过 /etc/modules-load.d/ 提前加载音频模块
#   2. 可选择增大 deferred_probe_timeout 作为安全余量
#
# 用法：
#   sudo ./fix-audio-clock.sh          # 应用修复
#   sudo ./fix-audio-clock.sh status   # 检查当前状态
#   sudo ./fix-audio-clock.sh revert   # 移除修复
#

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

MODULES_CONF="/etc/modules-load.d/audio-clock-chain.conf"

# 按依赖顺序排列的模块，必须在 deferred_probe_timeout 前加载
AUDIO_MODULES=(
    qcom_glink_smem    # 通往 ADSP 的 GLINK 传输层
    qcom_apr           # APR 协议（注册 APR 总线）
    snd_soc_qdsp6      # QDSP6 汇总模块（引入 q6afe、q6afe-clocks 等）
)

ACTION="${1:-apply}"

check_status() {
    echo ""
    echo -e "${BOLD}=== LPASS 音频时钟状态 ===${NC}"
    echo ""

    # 检查 lpass_tlmm 是否探测成功
    if [ -d /sys/bus/platform/drivers/qcom-sm6115-lpass-lpi-pinctrl/a7c0000.pinctrl ]; then
        echo -e "  ${GREEN}✓${NC}  lpass_tlmm (pinctrl@a7c0000) - 探测成功"
    else
        if dmesg 2>/dev/null | grep -q "a7c0000.pinctrl.*deferred probe"; then
            echo -e "  ${RED}✗${NC}  lpass_tlmm (pinctrl@a7c0000) - 延迟探测失败"
        else
            echo -e "  ${YELLOW}?${NC}  lpass_tlmm (pinctrl@a7c0000) - 状态未知"
        fi
    fi

    # 检查 q6afecc
    if [ -d /sys/bus/platform/drivers/q6afe ]; then
        echo -e "  ${GREEN}✓${NC}  q6afe - 已加载"
    else
        echo -e "  ${RED}✗${NC}  q6afe - 未加载"
    fi

    # 检查已加载的模块
    echo ""
    echo "  模块状态："
    for mod in "${AUDIO_MODULES[@]}"; do
        mod_under="${mod//-/_}"
        if lsmod 2>/dev/null | grep -q "^${mod_under}"; then
            echo -e "    ${GREEN}✓${NC}  $mod"
        else
            echo -e "    ${RED}✗${NC}  $mod（未加载）"
        fi
    done

    # 检查 modules-load.d 配置
    echo ""
    if [ -f "$MODULES_CONF" ]; then
        echo -e "  ${GREEN}✓${NC}  $MODULES_CONF 存在（已配置提前加载）"
    else
        echo -e "  ${YELLOW}!${NC}  未找到 $MODULES_CONF（未配置提前加载）"
    fi

    # 检查声卡
    echo ""
    if [ -f /proc/asound/cards ]; then
        local cards
        cards=$(cat /proc/asound/cards 2>/dev/null)
        if [ -n "$cards" ] && ! echo "$cards" | grep -q "no soundcards"; then
            echo -e "  ${GREEN}✓${NC}  检测到声卡："
            echo "$cards" | sed 's/^/        /'
        else
            echo -e "  ${RED}✗${NC}  未检测到声卡"
        fi
    fi

    # 检查延迟探测超时时间
    echo ""
    local timeout
    timeout=$(cat /sys/module/driver_core/parameters/deferred_probe_timeout 2>/dev/null || echo "unknown")
    echo "  延迟探测超时时间：${timeout} 秒"

    echo ""
}

apply_fix() {
    echo ""
    echo -e "${BOLD}=== 正在应用 LPASS 音频时钟修复 ===${NC}"
    echo ""

    # 第 1 步：创建 modules-load.d 配置以提前加载
    info "正在创建 $MODULES_CONF"

    cat > "$MODULES_CONF" << 'EOF'
# 提前加载音频时钟链模块，防止 lpass_tlmm 延迟探测失败。
# pinctrl@a7c0000 (lpass_tlmm) 需要来自 q6afecc 的 "audio" 时钟，
# 因此必须在 deferred_probe_timeout 到期前加载完整的 QDSP6 音频栈。
#
# 依赖链：
#   qcom_glink_smem → ADSP remoteproc → qcom_apr → q6afe → q6afe-clocks
#
# 详情参见 scripts/fix-audio-clock.sh。

qcom_glink_smem
qcom_apr
snd_soc_qdsp6
EOF

    echo -e "  ${GREEN}✓${NC}  已创建 $MODULES_CONF"

    # 第 2 步：立即尝试加载模块（无需重启即可生效）
    info "正在加载音频模块..."
    local loaded=0
    for mod in "${AUDIO_MODULES[@]}"; do
        if modprobe "$mod" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC}  modprobe $mod"
            loaded=$((loaded + 1))
        else
            warn "modprobe $mod 失败（可能需要重启）"
        fi
    done

    # 第 3 步：加载模块后，尝试重新触发延迟探测
    if [ $loaded -gt 0 ]; then
        info "正在重新触发延迟探测..."
        # 写入 /sys/bus/platform/drivers_probe 可重新触发探测
        if [ -w /sys/bus/platform/drivers_probe ]; then
            echo "a7c0000.pinctrl" > /sys/bus/platform/drivers_probe 2>/dev/null || true
        fi
        # 备选方案：若驱动存在，则解除绑定后重新绑定
        if [ -d /sys/bus/platform/drivers/qcom-sm6115-lpass-lpi-pinctrl ]; then
            echo "a7c0000.pinctrl" > /sys/bus/platform/drivers/qcom-sm6115-lpass-lpi-pinctrl/unbind 2>/dev/null || true
            sleep 1
            echo "a7c0000.pinctrl" > /sys/bus/platform/drivers/qcom-sm6115-lpass-lpi-pinctrl/bind 2>/dev/null || true
        fi
    fi

    echo ""
    echo -e "${BOLD}修复已应用。${NC}"
    echo ""
    echo "  建议重启以使修复完全生效。"
    echo "  此后每次启动时都会提前加载这些模块。"
    echo ""
    echo "  重启后使用以下命令验证："
    echo "    dmesg | grep -E 'a7c0000|q6afe|lpass'"
    echo "    cat /proc/asound/cards"
    echo ""
}

revert_fix() {
    echo ""
    echo -e "${BOLD}=== 正在撤销 LPASS 音频时钟修复 ===${NC}"
    echo ""

    if [ -f "$MODULES_CONF" ]; then
        rm -f "$MODULES_CONF"
        echo -e "  ${GREEN}✓${NC}  已移除 $MODULES_CONF"
    else
        info "无需撤销，未找到 $MODULES_CONF"
    fi

    echo ""
    echo "  请重启以应用更改。音频模块将恢复为默认加载时机。"
    echo ""
}

case "$ACTION" in
    apply)
        [ "$(id -u)" -eq 0 ] || error "请以 root 身份运行：sudo $0"
        apply_fix
        check_status
        ;;
    status)
        check_status
        ;;
    revert)
        [ "$(id -u)" -eq 0 ] || error "请以 root 身份运行：sudo $0 revert"
        revert_fix
        ;;
    *)
        echo "用法：$0 [apply|status|revert]"
        exit 1
        ;;
esac
