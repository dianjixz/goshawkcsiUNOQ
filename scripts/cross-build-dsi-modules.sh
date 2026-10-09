#!/bin/bash
#
# 在 Linux 主机 PC 上为 Arduino UNO Q 交叉编译 DSI 显示模块
#
# 此脚本在 x86-64 主机上自动完成整个交叉编译流程：
#   1. 安装 aarch64 交叉编译器
#   2. 浅克隆 Arduino Linux 内核源码（匹配相应标签）
#   3. 配置内核以启用所需的 DRM 面板配置项
#   4. 构建头文件和模块框架（不完整构建内核）
#   5. 调用 build-dsi-modules.sh 构建各个 .ko
#   6. 打包 .ko 文件，以便通过 scp 传至目标设备
#
# 要求（Ubuntu/Debian 主机）：
#   sudo apt install gcc-aarch64-linux-gnu make bc flex bison \
#                    libssl-dev libelf-dev python3 rsync
#
# 用法：
#   ./cross-build-dsi-modules.sh [module|all]
#
# 运行后：
#   scp /tmp/dsi-modules-cross/*.ko user@uno-q:/tmp/
#   # 在 UNO Q 上：
#   sudo cp /tmp/*.ko /lib/modules/$(uname -r)/kernel/drivers/gpu/drm/bridge/
#   sudo depmod -a && sudo modprobe tc358762
#

set -e

# ── 配置 ──────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Arduino Linux 内核源码仓库
# 设备上运行的内核：6.16.7-g0dd6551ae96b
# (uname -r: Linux Zephyria4GB 6.16.7-g0dd6551ae96b #1 SMP PREEMPT Tue Sep 23 12:46:06 UTC 2025 aarch64)
ARDUINO_LINUX_REPO="${ARDUINO_LINUX_REPO:-https://github.com/arduino/linux-qcom.git}"

# 目标设备运行的内核版本字符串（获取方式：ssh uno-q uname -r）
# 覆盖方式：TARGET_KERNEL=6.16.7-g0dd6551ae96b ./cross-build-dsi-modules.sh all
TARGET_KERNEL="${TARGET_KERNEL:-6.16.7-g0dd6551ae96b}"

CROSS_DIR="/tmp/dsi-modules-cross"
KERNEL_SRC="${CROSS_DIR}/linux-qcom"
OUTPUT_DIR="${CROSS_DIR}/modules"

ARCH="arm64"
CROSS_COMPILE="aarch64-linux-gnu-"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ── 检查 ──────────────────────────────────────────────────────────────────────

check_host_tools() {
    step "检查主机工具"

    local missing=()
    for tool in make git curl "${CROSS_COMPILE}gcc" bc flex bison; do
        if ! command -v "$tool" &>/dev/null; then
            missing+=("$tool")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        warn "缺少工具：${missing[*]}"
        echo ""
        echo "  使用以下命令安装："
        echo "    sudo apt-get install -y \\"
        echo "      build-essential gcc-aarch64-linux-gnu \\"
        echo "      bc flex bison libssl-dev libelf-dev python3 git curl"
        echo ""
        error "请安装缺少的工具后重试。"
    fi

    info "所有主机工具均可用。"
}

# ── 内核源码 ──────────────────────────────────────────────────────────────────

clone_or_update_kernel() {
    step "准备内核源码"

    mkdir -p "$CROSS_DIR" "$OUTPUT_DIR"

    if [ -d "${KERNEL_SRC}/.git" ]; then
        info "${KERNEL_SRC} 中已有内核源码"
        info "如需刷新：rm -rf ${KERNEL_SRC}，然后重新运行"
        return 0
    fi

    info "正在浅克隆 Arduino Linux 内核..."
    info "  ${ARDUINO_LINUX_REPO}"

    # 浅克隆可节省时间和磁盘空间
    git clone --depth=1 "$ARDUINO_LINUX_REPO" "$KERNEL_SRC"
}

configure_kernel() {
    step "配置内核（arduino/linux-qcom defconfig + DSI 面板模块）"

    cd "$KERNEL_SRC"

    # arduino/linux-qcom 提供一个覆盖所有受支持高通平台（包括 QRB2210/Imola）
    # 的 "defconfig"，直接使用即可。为保持向前兼容，先尝试具名变体。
    local defconfig=""
    for candidate in imola_defconfig qrb2210_defconfig qcom_defconfig defconfig; do
        if [ -f "arch/arm64/configs/${candidate}" ]; then
            defconfig="$candidate"
            break
        fi
    done
    if [ -z "$defconfig" ]; then
        error "在 arch/arm64/configs/ 中未找到 defconfig，请检查仓库。"
    fi
    info "使用 defconfig：$defconfig"
    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$defconfig"

    # 将 DSI 面板驱动启用为模块
    local configs=(
        "CONFIG_DRM_TOSHIBA_TC358762=m"
        "CONFIG_DRM_PANEL_ILITEK_ILI9881C=m"
        "CONFIG_DRM_PANEL_SITRONIX_ST7701=m"
        "CONFIG_DRM_PANEL_HIMAX_HX8394=m"
        "CONFIG_DRM_PANEL_ORISETECH_OTM8009A=m"
        # 依赖项（确保内置或编译为模块）
        "CONFIG_DRM_MIPI_DSI=y"
        "CONFIG_BACKLIGHT_CLASS_DEVICE=y"
        "CONFIG_DRM_KMS_HELPER=y"
    )

    for cfg in "${configs[@]}"; do
        scripts/config --set-val "${cfg%=*}" "${cfg#*=}"
    done

    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

    info "内核已配置为将 DSI 面板驱动编译成模块。"
}

prepare_kernel_headers() {
    step "准备内核头文件和模块框架"

    cd "$KERNEL_SRC"

    # 构建编译树外模块所需的最小框架。
    # 注意：'modules_prepare' 不会生成 Module.symvers；该文件仅由完整的
    # 'make modules' 生成。缺少它时，modpost 会将每个内核符号报告为
    # "undefined"，从而中止构建。
    #
    # 解决方法如下：
    #   1. 创建空的 Module.symvers，使 modpost 不因文件缺失警告而中止。
    #   2. 构建各个 .ko 时传入 KBUILD_MODPOST_WARN=1，使其余符号警告不再致命。
    #
    # 这些“未解析”符号（mipi_dsi_*、drm_bridge_* 等）均已内置于目标内核，
    # 会在 modprobe 时正确解析。

    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
         -j"$(nproc)" scripts prepare

    make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
         -j"$(nproc)" modules_prepare

    # 创建空的 Module.symvers，以消除文件缺失警告。modpost 仍会警告每个
    # 未解析符号，但构建时会由 KBUILD_MODPOST_WARN=1 抑制。
    touch "${KERNEL_SRC}/Module.symvers"

    info "头文件和模块框架已就绪。"
}

# ── 构建模块 ──────────────────────────────────────────────────────────────────

build_all_modules() {
    local target="$1"

    step "构建树外 DSI 模块"

    # SKIP_INSTALL=1    - 不安装到主机 /lib/modules，也不运行 modprobe；
    #                     单独收集 .ko 文件并通过 scp 传至目标设备。
    # KERNEL_VERSION    - 覆盖 uname -r，使主机侧路径使用目标版本而非主机版本。
    # KBUILD_MODPOST_WARN=1 - 将 modpost 未解析符号错误转为警告，使缺少
    #                     Module.symvers 时仍能生成 .ko（符号在目标内核中）。
    ARCH="$ARCH" \
    CROSS_COMPILE="$CROSS_COMPILE" \
    KERNEL_DIR="$KERNEL_SRC" \
    KERNEL_VERSION="$TARGET_KERNEL" \
    KBUILD_MODPOST_WARN=1 \
    SKIP_INSTALL=1 \
    "${SCRIPT_DIR}/build-dsi-modules.sh" "$target"
}

# ── 收集输出 ──────────────────────────────────────────────────────────────────

collect_modules() {
    step "收集 .ko 文件"

    find /tmp/dsi-modules-build -name "*.ko" -exec cp {} "$OUTPUT_DIR/" \; 2>/dev/null || true

    if ls "$OUTPUT_DIR/"*.ko &>/dev/null; then
        info "模块已收集到：$OUTPUT_DIR"
        ls -lh "$OUTPUT_DIR/"*.ko
    else
        warn "输出目录中未找到 .ko 文件。"
    fi
}

# ── 安装说明 ──────────────────────────────────────────────────────────────────

print_deploy_instructions() {
    local target_ip="${TARGET_IP:-<uno-q-ip>}"

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  交叉编译完成！"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "  模块构建目录：${OUTPUT_DIR}/"
    echo ""
    echo "  部署到 UNO Q："
    echo ""
    echo "    # 将模块复制到目标设备"
    echo "    scp ${OUTPUT_DIR}/*.ko user@${target_ip}:/tmp/"
    echo ""
    echo "    # 在 UNO Q 上安装模块"
    echo "    ssh user@${target_ip} bash << 'EOF'"
    echo "    KVER=\$(uname -r)"
    echo "    # 桥接驱动"
    echo "    sudo mkdir -p /lib/modules/\$KVER/kernel/drivers/gpu/drm/bridge"
    echo "    sudo cp /tmp/tc358762.ko /lib/modules/\$KVER/kernel/drivers/gpu/drm/bridge/"
    echo "    # 面板驱动"
    echo "    sudo mkdir -p /lib/modules/\$KVER/kernel/drivers/gpu/drm/panel"
    echo "    for ko in ili9881c st7701 hx8394 otm8009a; do"
    echo "      [ -f /tmp/\${ko}.ko ] && sudo cp /tmp/\${ko}.ko /lib/modules/\$KVER/kernel/drivers/gpu/drm/panel/"
    echo "    done"
    echo "    sudo depmod -a"
    echo "    sudo modprobe tc358762 || echo '需要先配置设备树'"
    echo "    EOF"
    echo ""
    echo "  然后应用设备树并重启。"
    echo ""
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

TARGET="${1:-all}"

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Arduino UNO Q DSI 交叉构建（主机：$(uname -m)）"
echo "════════════════════════════════════════════════════════════"
echo ""

check_host_tools
clone_or_update_kernel
configure_kernel
prepare_kernel_headers
build_all_modules "$TARGET"
collect_modules
print_deploy_instructions
