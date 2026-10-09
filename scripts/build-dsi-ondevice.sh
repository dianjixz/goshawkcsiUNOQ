#!/bin/bash
#
# 直接在 Arduino UNO Q 上构建并安装 DSI 显示内核模块
#
# 请在开发板本机运行此脚本，无需交叉编译器。
#
# 用法：
#   ./build-dsi-ondevice.sh [MODULE|all] [KERNEL_SRC_DIR]
#
#   ./build-dsi-ondevice.sh tc358762                              # 默认源码目录
#   ./build-dsi-ondevice.sh tc358762 /home/arduino/inspection/arduino-linux-qcom
#   ./build-dsi-ondevice.sh all      /home/arduino/inspection/arduino-linux-qcom
#
# 此脚本将：
#   1. 查找或准备内核头文件（需要时克隆 arduino/linux-qcom）
#   2. 从 arduino/linux-qcom 或 torvalds/linux 下载驱动源码
#   3. 编译 .ko 模块
#   4. 将其安装到 /lib/modules/$(uname -r)/ 下
#   5. 运行 depmod，并可选择运行 modprobe
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 配置 ──────────────────────────────────────────────────────────────────────

KVER="$(uname -r)"
WORK_DIR="/tmp/dsi-ondevice-build"
KERNEL_HEADERS="/lib/modules/${KVER}/build"

# 内核源码目录，可通过第二个参数或 KERNEL_SRC_DIR 环境变量覆盖。
# 默认为 /opt/arduino-linux-qcom；若在其他位置找不到头文件，
# 将自动把仓库克隆到此处。
KERNEL_SRC_DIR="${2:-${KERNEL_SRC_DIR:-/opt/arduino-linux-qcom}}"

ARDUINO_LINUX_REPO="https://github.com/arduino/linux-qcom.git"

# 获取源码：先尝试 arduino/linux-qcom，失败后改用 torvalds/linux v6.16
ARDUINO_RAW="https://raw.githubusercontent.com/arduino/linux-qcom/main"
UPSTREAM_RAW="https://raw.githubusercontent.com/torvalds/linux/v6.16"

# BUILD_DIR 由 find_or_prepare_headers() 设置
BUILD_DIR=""

# BUILT_KO 由 build_module() 设置，不使用标准输出捕获
BUILT_KO=""

# ── 驱动源码路径 ──────────────────────────────────────────────────────────────

SOURCES_tc358762="drivers/gpu/drm/bridge/tc358762.c"
INSTALL_tc358762="kernel/drivers/gpu/drm/bridge"

SOURCES_ili9881c="drivers/gpu/drm/panel/panel-ilitek-ili9881c.c:ili9881c.c"
INSTALL_ili9881c="kernel/drivers/gpu/drm/panel"

SOURCES_st7701="drivers/gpu/drm/panel/panel-sitronix-st7701.c:st7701.c"
INSTALL_st7701="kernel/drivers/gpu/drm/panel"

SOURCES_hx8394="drivers/gpu/drm/panel/panel-himax-hx8394.c:hx8394.c"
INSTALL_hx8394="kernel/drivers/gpu/drm/panel"

SOURCES_otm8009a="drivers/gpu/drm/panel/panel-orisetech-otm8009a.c:otm8009a.c"
INSTALL_otm8009a="kernel/drivers/gpu/drm/panel"


SOURCES_panel_dpi="drivers/gpu/drm/panel/panel-dpi.c:panel_dpi.c"
INSTALL_panel_dpi="kernel/drivers/gpu/drm/panel"

ALL_MODULES="tc358762 panel_dpi ili9881c st7701 hx8394 otm8009a"

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

fetch_file() {
    local src_path="$1"
    local dest="$2"
    local basename
    basename="$(basename "$dest")"

    # 检查 scripts/src/ 中是否有本地源码覆盖
    local local_src="${SCRIPT_DIR}/src/${basename}"
    if [ -f "$local_src" ]; then
        info "  使用本地源码：${local_src}"
        cp "$local_src" "$dest"
        return 0
    fi

    if curl -fsSL "${ARDUINO_RAW}/${src_path}" -o "$dest" 2>/dev/null; then
        return 0
    fi
    curl -fsSL "${UPSTREAM_RAW}/${src_path}" -o "$dest"
}

# ── 第 1 步：前置条件 ─────────────────────────────────────────────────────────

check_tools() {
    step "检查工具"
    local need_install=()
    for t in make curl gcc; do
        command -v "$t" &>/dev/null || need_install+=("$t")
    done
    if [ ${#need_install[@]} -gt 0 ]; then
        info "正在安装：${need_install[*]}"
        sudo apt-get install -y build-essential curl
    fi
    info "工具检查通过（gcc：$(gcc --version | head -1)）"
}

# ── 第 2 步：内核头文件 ───────────────────────────────────────────────────────

find_or_prepare_headers() {
    step "正在查找 ${KVER} 的内核头文件"

    # 最理想情况：符号链接 /lib/modules/<kver>/build 已指向头文件
    if [ -f "${KERNEL_HEADERS}/Makefile" ]; then
        info "已找到头文件：${KERNEL_HEADERS}"
        BUILD_DIR="${KERNEL_HEADERS}"
        return
    fi

    # 尝试 apt
    info "/lib/modules 中没有头文件，正在尝试 apt..."
    if sudo apt-get install -y "linux-headers-${KVER}" 2>/dev/null \
       && [ -f "${KERNEL_HEADERS}/Makefile" ]; then
        info "已通过 apt 安装：${KERNEL_HEADERS}"
        BUILD_DIR="${KERNEL_HEADERS}"
        return
    fi

    # 若现有内核源码目录已准备好，则直接使用
    if [ -f "${KERNEL_SRC_DIR}/Makefile" ] && \
       [ -f "${KERNEL_SRC_DIR}/scripts/mod/modpost" ]; then
        info "使用已准备好的内核源码：${KERNEL_SRC_DIR}"
        BUILD_DIR="${KERNEL_SRC_DIR}"
        return
    fi

    # 克隆 arduino/linux-qcom 并在源码树中准备头文件
    warn "没有 ${KVER} 的预构建头文件。"
    warn "正在从此处的源码准备：${KERNEL_SRC_DIR}"
    warn "此操作只需执行一次，后续运行将复用源码。"
    echo ""

    if [ ! -d "${KERNEL_SRC_DIR}/.git" ]; then
        info "正在将 arduino/linux-qcom 浅克隆到 ${KERNEL_SRC_DIR}..."
        mkdir -p "$(dirname "${KERNEL_SRC_DIR}")"
        git clone --depth=1 "$ARDUINO_LINUX_REPO" "$KERNEL_SRC_DIR"
    else
        info "${KERNEL_SRC_DIR} 中已有内核源码，正在复用。"
    fi

    cd "$KERNEL_SRC_DIR"

    info "正在配置..."
    make ARCH=arm64 defconfig

    local cfgs=(
        CONFIG_DRM_TOSHIBA_TC358762=m
        CONFIG_DRM_PANEL_ILITEK_ILI9881C=m
        CONFIG_DRM_PANEL_SITRONIX_ST7701=m
        CONFIG_DRM_PANEL_HIMAX_HX8394=m
        CONFIG_DRM_PANEL_ORISETECH_OTM8009A=m
        CONFIG_DRM_MIPI_DSI=y
        CONFIG_BACKLIGHT_CLASS_DEVICE=y
    )
    for c in "${cfgs[@]}"; do
        scripts/config --set-val "${c%=*}" "${c#*=}"
    done
    make ARCH=arm64 olddefconfig

    info "正在准备头文件..."
    make ARCH=arm64 -j"$(nproc)" scripts prepare
    make ARCH=arm64 -j"$(nproc)" modules_prepare

    # 创建空的 Module.symvers，以消除 modpost 的文件缺失警告。
    # 未解析符号警告属于预期情况，由 KBUILD_MODPOST_WARN=1 抑制。
    touch "${KERNEL_SRC_DIR}/Module.symvers"

    BUILD_DIR="${KERNEL_SRC_DIR}"
    info "头文件已就绪：${BUILD_DIR}"
}

# ── 第 3 步：构建单个模块 ─────────────────────────────────────────────────────

# 将全局变量 BUILT_KO 设为生成的 .ko 文件路径。
# 不使用标准输出，因此调用方可直接调用 build_module，而无需使用会吞掉
# 所有输出的命令替换 ($(...))。
build_module() {
    local mod="$1"
    local dir="${WORK_DIR}/${mod}"
    local sources_var="SOURCES_${mod}"
    local sources="${!sources_var}"

    step "正在构建：${mod}"
    mkdir -p "$dir"

    for entry in $sources; do
        local src="${entry%%:*}"
        local dst="${entry##*:}"
        [ "$dst" = "$entry" ] && dst="$(basename "$src")"
        info "  正在获取 ${src}"
        fetch_file "$src" "${dir}/${dst}" || error "无法获取 ${src}"
    done

    cat > "${dir}/Kbuild" << EOF
obj-m := ${mod}.o
EOF

    cat > "${dir}/Makefile" << MAKEFILE
ARCH ?= arm64
KDIR ?= ${BUILD_DIR}
PWD  := \$(shell pwd)

all:
	\$(MAKE) ARCH=\$(ARCH) KBUILD_MODPOST_WARN=1 -C \$(KDIR) M=\$(PWD) modules

clean:
	\$(MAKE) ARCH=\$(ARCH) -C \$(KDIR) M=\$(PWD) clean

.PHONY: all clean
MAKEFILE

    make -C "$dir" ARCH=arm64 KDIR="$BUILD_DIR" \
        || error "${mod} 构建失败。"

    BUILT_KO="$(find "$dir" -maxdepth 1 -name "*.ko" | head -1)"
    [ -z "$BUILT_KO" ] && error "${mod} 未生成 .ko 文件"

    info "已构建：${BUILT_KO}  ($(du -sh "$BUILT_KO" | cut -f1))"
}

# ── 第 4 步：安装单个模块 ─────────────────────────────────────────────────────

install_module() {
    local mod="$1"
    local ko="$2"
    local install_var="INSTALL_${mod}"
    local subdir="${!install_var}"
    local dest="/lib/modules/${KVER}/${subdir}"

    step "正在安装：${mod} → ${dest}"
    sudo mkdir -p "$dest"
    sudo cp "$ko" "${dest}/"
    sudo depmod -a
    info "已安装：${dest}/$(basename "$ko")"
}

# ── 第 5 步：加载模块 ─────────────────────────────────────────────────────────

load_module() {
    local mod="$1"
    if sudo modprobe "$mod" 2>/dev/null; then
        info "已加载：${mod}"
    else
        warn "modprobe ${mod} 失败，请先应用设备树再重新加载。"
        info "  sudo modprobe ${mod}"
    fi
}

# ── 摘要 ──────────────────────────────────────────────────────────────────────

show_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  构建完成"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    for mod in "$@"; do
        local ko
        ko=$(find "${WORK_DIR}/${mod}" -maxdepth 1 -name "*.ko" 2>/dev/null | head -1)
        if [ -n "$ko" ]; then
            if lsmod | grep -q "^${mod} "; then
                echo -e "  ${GREEN}✓${NC}  ${mod}.ko  →  已加载"
            else
                echo -e "  ${GREEN}✓${NC}  ${mod}.ko  →  已安装（尚未加载）"
            fi
        else
            echo -e "  ${RED}✗${NC}  ${mod}  （构建失败）"
        fi
    done
    echo ""
    echo "  后续步骤："
    echo "   1. 编译并应用 Freenove 显示覆盖："
    echo "      dtc -@ -I dts -O dtb -o imola-camera-dsi-freenove.dtbo \\"
    echo "          dts/imola-camera-dsi-freenove.dts"
    echo "      fdtoverlay -i /boot/efi/dtb/qcom/imola-camera-shield.dtb \\"
    echo "                 -o /boot/efi/dtb/qcom/imola-camera-dsi-freenove.dtb \\"
    echo "                 imola-camera-dsi-freenove.dtbo"
    echo "   2. 设置启动 DTB 并重启"
    echo "   3. 检查显示管线："
    echo "      dmesg | grep -iE 'dsi|panel|tc358762|display'"
    echo "      ls /dev/dri/"
    echo ""
}

# ── 用法 ──────────────────────────────────────────────────────────────────────

usage() {
    echo "用法：$0 [MODULE|all] [KERNEL_SRC_DIR]"
    echo ""
    echo "  MODULE       可选值：tc358762 panel_dpi ili9881c st7701 hx8394 otm8009a"
    echo "  all          构建并安装所有支持的模块"
    echo "  KERNEL_SRC_DIR  已准备好的内核源码树路径（可选）"
    echo "               默认：/opt/arduino-linux-qcom"
    echo "               覆盖方式：作为第二个参数传入或设置环境变量"
    echo ""
    echo "示例："
    echo "  $0 tc358762"
    echo "  $0 tc358762 /home/arduino/inspection/arduino-linux-qcom"
    echo "  $0 all      /home/arduino/inspection/arduino-linux-qcom"
    echo ""
    echo "  # 或通过环境变量："
    echo "  KERNEL_SRC_DIR=/home/arduino/inspection/arduino-linux-qcom $0 all"
    echo ""
    echo "模块："
    echo "  tc358762   Freenove 4.3 英寸 / 树莓派 7 英寸 / 微雪 DSI"
    echo "  ili9881c   微雪 5/7/10.1 英寸"
    echo "  st7701     Arduino GigaDisplay / HyperPixel 4"
    echo "  hx8394     通用入门级 720p DSI 面板"
    echo "  otm8009a   STM32 Discovery / 评估板"
    echo ""
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

TARGET="${1:-}"
if [ -z "$TARGET" ] || [ "$TARGET" = "-h" ] || [ "$TARGET" = "--help" ]; then
    usage; exit 0
fi

[ "$EUID" -eq 0 ] && error "请勿以 root 身份运行。脚本内部会使用 sudo。"

case "$TARGET" in
    all) MODULES=($ALL_MODULES) ;;
    tc358762|panel_dpi|ili9881c|st7701|hx8394|otm8009a) MODULES=("$TARGET") ;;
    *) error "未知模块 '${TARGET}'。运行 $0 --help 查看选项。" ;;
esac

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  DSI 模块构建工具 - Arduino UNO Q（设备本机）"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  开发板内核：${KVER}"
echo "  内核源码：${KERNEL_SRC_DIR}"
echo "  模块：${MODULES[*]}"
echo ""

check_tools
find_or_prepare_headers
mkdir -p "$WORK_DIR"

BUILT=()
for mod in "${MODULES[@]}"; do
    build_module "$mod"          # sets BUILT_KO
    install_module "$mod" "$BUILT_KO"
    load_module    "$mod"
    BUILT+=("$mod")
done

show_summary "${BUILT[@]}"
