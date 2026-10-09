#!/bin/bash
#
# 为 Arduino UNO Q (QRB2210 / QCM2290) 构建 DSI 显示内核模块
#
# 为树莓派生态中常见的 DSI 面板驱动构建树外可加载模块 (.ko)。
# 无需替换内核。
#
# 支持的模块：
#   tc358762  - DSI 转 DPI 桥接器（树莓派 7 英寸、Freenove 4.3 英寸、微雪 DSI）
#   ili9881c  - ILITEK ILI9881C 面板（微雪 5/7/10.1 英寸）
#   st7701    - Sitronix ST7701 面板（Arduino GigaDisplay、HyperPixel 4）
#   hx8394    - Himax HX8394 面板（各种入门级 720p 显示器）
#   otm8009a  - Orise OTM8009A 面板（STM32 Discovery、评估板）
#   goodix_ts - Goodix GT911/GT9xx 触摸屏（轮询模式，无需 IRQ）
#
# 用法：
#   ./build-dsi-modules.sh [module|all]
#
#   ./build-dsi-modules.sh all          # 构建所有模块
#   ./build-dsi-modules.sh tc358762     # 仅构建 tc358762
#   ./build-dsi-modules.sh ili9881c     # 仅构建 ili9881c
#
# 在 Arduino UNO Q 目标设备上运行，或进行交叉编译：
#   ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- KERNEL_DIR=/path/to/kernel \
#     ./build-dsi-modules.sh all
#

set -e

# ── 配置 ──────────────────────────────────────────────────────────────────────
#
# 目标内核信息：
#   版本：6.16.7-g0dd6551ae96b
#   仓库：https://github.com/arduino/linux-qcom
#   分支：与 6.16.7 构建匹配的标签

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

WORK_DIR="/tmp/dsi-modules-build"
KERNEL_VERSION="${KERNEL_VERSION:-$(uname -r 2>/dev/null || echo "unknown")}"
KERNEL_DIR="${KERNEL_DIR:-/lib/modules/${KERNEL_VERSION}/build}"
ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-}"

# 获取源码：从 Arduino linux-qcom 仓库拉取驱动文件。
# 设备运行的内核为 6.16.7-g0dd6551ae96b，构建自
# https://github.com/arduino/linux-qcom
# 默认分支为 "main"；若存在特定标签，可通过 LINUX_TAG 覆盖。
LINUX_REPO_RAW="${LINUX_REPO_RAW:-https://raw.githubusercontent.com/arduino/linux-qcom/main}"

# 后备来源：从版本匹配的 Linus 上游源码树获取驱动源码
#（arduino/linux-qcom 可能不含面板驱动；后备来源可确保获取这些驱动）
LINUX_TAG="${LINUX_TAG:-v6.16}"
LINUX_UPSTREAM_RAW="https://raw.githubusercontent.com/torvalds/linux/${LINUX_TAG}"

# fetch_url：先尝试 Arduino 仓库，失败后改用 torvalds 上游源码树
fetch_url() {
    local path="$1"
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

    if curl -fsSL "${LINUX_REPO_RAW}/${path}" -o "$dest" 2>/dev/null; then
        return 0
    fi
    curl -fsSL "${LINUX_UPSTREAM_RAW}/${path}" -o "$dest"
}

# ── 彩色输出 ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ── 模块定义 ──────────────────────────────────────────────────────────────────
#
# 格式：MODULE_SOURCES_<name>="src1.c[:dest1.c] src2.c[:dest2.c] ..."
# 格式：MODULE_INSTALL_<name>="kernel/drivers/gpu/drm/..."
# 格式：MODULE_DEPENDS_<name>="drm drm_mipi_dsi panel_simple"（modprobe 依赖项）
#
# tc358762 - DSI 转 DPI 桥接器（东芝）
MODULE_SOURCES_tc358762="drivers/gpu/drm/bridge/tc358762.c"
MODULE_INSTALL_tc358762="kernel/drivers/gpu/drm/bridge"
MODULE_DEPENDS_tc358762="drm drm_kms_helper"

# ili9881c - ILITEK ILI9881C 面板驱动
MODULE_SOURCES_ili9881c="drivers/gpu/drm/panel/panel-ilitek-ili9881c.c:ili9881c.c"
MODULE_INSTALL_ili9881c="kernel/drivers/gpu/drm/panel"
MODULE_DEPENDS_ili9881c="drm drm_kms_helper drm_mipi_dsi backlight"

# st7701 - Sitronix ST7701 面板驱动
MODULE_SOURCES_st7701="drivers/gpu/drm/panel/panel-sitronix-st7701.c:st7701.c"
MODULE_INSTALL_st7701="kernel/drivers/gpu/drm/panel"
MODULE_DEPENDS_st7701="drm drm_kms_helper drm_mipi_dsi backlight"

# hx8394 - Himax HX8394 面板驱动
MODULE_SOURCES_hx8394="drivers/gpu/drm/panel/panel-himax-hx8394.c:hx8394.c"
MODULE_INSTALL_hx8394="kernel/drivers/gpu/drm/panel"
MODULE_DEPENDS_hx8394="drm drm_kms_helper drm_mipi_dsi backlight"

# otm8009a - Orise OTM8009A 面板驱动
MODULE_SOURCES_otm8009a="drivers/gpu/drm/panel/panel-orisetech-otm8009a.c:otm8009a.c"
MODULE_INSTALL_otm8009a="kernel/drivers/gpu/drm/panel"
MODULE_DEPENDS_otm8009a="drm drm_kms_helper drm_mipi_dsi backlight"


# panel_dpi - 使用设备树定义时序的通用 DPI 面板（用于 TC358762 下游 LCD）
MODULE_SOURCES_panel_dpi="drivers/gpu/drm/panel/panel-dpi.c:panel_dpi.c"
MODULE_INSTALL_panel_dpi="kernel/drivers/gpu/drm/panel"
MODULE_DEPENDS_panel_dpi="drm drm_kms_helper"

# goodix_ts - Goodix GT911/GT9xx 触摸屏（已加入轮询模式补丁）
# 原版内核虽有 CONFIG_TOUCHSCREEN_GOODIX=m，但其模块需要 IRQ。
# 此补丁版本在 client->irq == 0 时增加 input_setup_polling() 后备方案
#（例如 INT 引脚连接到 STM32 域而非 Linux GPIO）。
# 注意：goodix.h 作为额外头文件获取（不参与编译）
MODULE_SOURCES_goodix_ts="drivers/input/touchscreen/goodix.c drivers/input/touchscreen/goodix_fwupload.c"
MODULE_HEADERS_goodix_ts="drivers/input/touchscreen/goodix.h"
MODULE_INSTALL_goodix_ts="kernel/drivers/input/touchscreen"
MODULE_DEPENDS_goodix_ts=""

ALL_MODULES="tc358762 panel_dpi ili9881c st7701 hx8394 otm8009a goodix_ts"

# ── 辅助函数 ──────────────────────────────────────────────────────────────────

check_prerequisites() {
    step "检查前置条件"

    if [ "$EUID" -eq 0 ]; then
        error "请勿以 root 身份运行。脚本会在需要时使用 sudo。"
    fi

    # 构建工具
    for tool in make curl; do
        if ! command -v "$tool" &>/dev/null; then
            warn "未找到 $tool，正在尝试安装..."
            sudo apt-get install -y build-essential curl
            break
        fi
    done

    # 内核头文件/构建目录
    if [ ! -d "$KERNEL_DIR" ]; then
        warn "未找到内核构建目录：$KERNEL_DIR"
        info "正在尝试：sudo apt-get install linux-headers-${KERNEL_VERSION}"
        if ! sudo apt-get install -y "linux-headers-${KERNEL_VERSION}" 2>/dev/null; then
            echo ""
            echo "  apt 未提供 ${KERNEL_VERSION} 的内核头文件。"
            echo ""
            echo "  可选方案："
            echo "   A) 在主机 PC 上交叉编译："
            echo "      export ARCH=arm64"
            echo "      export CROSS_COMPILE=aarch64-linux-gnu-"
            echo "      export KERNEL_DIR=/path/to/arduino-linux-source"
            echo "      ./build-dsi-modules.sh all"
            echo ""
            echo "   B) 在设备上使用 Arduino 内核源码构建："
            echo "      git clone --depth=1 https://github.com/arduino/linux-qcom.git"
            echo "      cd linux-qcom && make ARCH=arm64 defconfig"
            echo "      make ARCH=arm64 scripts prepare modules_prepare"
            echo "      KERNEL_DIR=\$(pwd) ./build-dsi-modules.sh all"
            error "缺少内核头文件，无法继续。"
        fi
    fi

    info "内核构建目录：$KERNEL_DIR"
}

fetch_source() {
    local mod="$1"
    local build_dir="$2"
    local sources_var="MODULE_SOURCES_${mod}"
    local sources="${!sources_var}"
    local headers_var="MODULE_HEADERS_${mod}"
    local headers="${!headers_var}"

    info "正在获取 ${mod} 的源码..."

    for entry in $sources $headers; do
        local src="${entry%%:*}"
        local dst="${entry##*:}"
        # 若没有 ':' 分隔符，则 dst 等于 src 的基本名称
        [ "$dst" = "$entry" ] && dst="$(basename "$src")"

        info "  获取 ${src}"
        info "    首次尝试：${LINUX_REPO_RAW}/${src}"
        info "    后备来源：${LINUX_UPSTREAM_RAW}/${src}"

        if ! fetch_url "$src" "${build_dir}/${dst}"; then
            error "从 arduino/linux-qcom 和 torvalds/linux 下载 ${src} 均失败"
        fi
    done
}

write_kbuild() {
    local mod="$1"
    local build_dir="$2"
    local sources_var="MODULE_SOURCES_${mod}"
    local sources="${!sources_var}"

    # 收集目标文件名（每个目标 *.c 对应一个 *.o）
    local objs=""
    for entry in $sources; do
        local dst="${entry##*:}"
        [ "$dst" = "$entry" ] && dst="$(basename "${entry%%:*}")"
        objs="${objs} ${dst%.c}.o"
    done

    cat > "${build_dir}/Kbuild" << EOF
# Kbuild - 树外模块：${mod}
obj-m := ${mod}.o
EOF

    # 若有多个源文件，将其列为复合模块的组成部分
    local count
    count=$(echo "$objs" | wc -w)
    if [ "$count" -gt 1 ]; then
        cat >> "${build_dir}/Kbuild" << EOF
${mod}-objs :=${objs}
EOF
    fi
}

write_makefile() {
    local build_dir="$1"

    cat > "${build_dir}/Makefile" << 'MAKEFILE'
ARCH                 ?= arm64
CROSS_COMPILE        ?=
KERNEL_DIR           ?= /lib/modules/$(shell uname -r)/build
# KBUILD_MODPOST_WARN=1 将未解析符号错误转为警告。
# 针对没有 Module.symvers 的源码树进行交叉编译时需要此设置
#（即只准备头文件，未完整运行 'make modules'）。
# 缺失的符号已内置于目标内核中，将在运行时解析。
KBUILD_MODPOST_WARN  ?= 0
PWD                  := $(shell pwd)

all:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	        KBUILD_MODPOST_WARN=$(KBUILD_MODPOST_WARN) \
	        -C $(KERNEL_DIR) M=$(PWD) modules

clean:
	$(MAKE) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) \
	        -C $(KERNEL_DIR) M=$(PWD) clean

.PHONY: all clean
MAKEFILE
}

build_module() {
    local mod="$1"
    local build_dir="${WORK_DIR}/${mod}"

    step "正在构建模块：${mod}"

    mkdir -p "$build_dir"

    fetch_source "$mod" "$build_dir"
    write_kbuild  "$mod" "$build_dir"
    write_makefile       "$build_dir"

    info "正在编译..."
    if ! make -C "$build_dir" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" \
              KERNEL_DIR="$KERNEL_DIR" \
              KBUILD_MODPOST_WARN="${KBUILD_MODPOST_WARN:-0}"; then
        echo ""
        warn "${mod} 构建失败。请查看上方错误。"
        echo ""
        echo "  常见原因："
        echo "    - 内核头文件版本不匹配（源码 != 运行中的内核）"
        echo "    - 缺少内核配置项（检查 DRM_MIPI_DSI=y）"
        echo "    - 源码不兼容（尝试 LINUX_TAG=v<你的内核版本>）"
        return 1
    fi

    local ko="${build_dir}/${mod}.ko"
    if [ ! -f "$ko" ]; then
        warn "构建后未找到 ${mod}.ko（可能使用了其他名称）"
        # 尝试查找该文件
        ko=$(find "$build_dir" -name "*.ko" | head -1)
        [ -z "$ko" ] && return 1
    fi

    info "已构建：$ko"
    ls -lh "$ko"
    return 0
}

install_module() {
    local mod="$1"
    local build_dir="${WORK_DIR}/${mod}"
    local install_var="MODULE_INSTALL_${mod}"
    local install_subdir="${!install_var}"

    local install_dir="/lib/modules/${KERNEL_VERSION}/${install_subdir}"

    step "正在安装模块：${mod} → ${install_dir}"

    local ko
    ko=$(find "$build_dir" -name "${mod}.ko" | head -1)
    [ -z "$ko" ] && ko=$(find "$build_dir" -name "*.ko" | head -1)
    [ -z "$ko" ] && { warn "未找到 ${mod} 的 .ko 文件"; return 1; }

    sudo mkdir -p "$install_dir"
    sudo cp "$ko" "${install_dir}/"
    sudo depmod -a

    info "已安装：${install_dir}/$(basename "$ko")"
}

load_module() {
    local mod="$1"
    local depends_var="MODULE_DEPENDS_${mod}"
    local depends="${!depends_var}"

    step "正在加载模块：${mod}"

    # 先加载依赖项（尽力而为）
    for dep in $depends; do
        sudo modprobe "$dep" 2>/dev/null || true
    done

    if sudo modprobe "$mod"; then
        info "模块 ${mod} 加载成功"
    else
        warn "modprobe ${mod} 失败，可能需要先配置设备树"
        info "应用设备树后可手动加载："
        info "  sudo modprobe ${mod}"
    fi
}

show_summary() {
    local built=("$@")
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  DSI 模块构建摘要"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    for mod in "${built[@]}"; do
        local ko
        ko=$(find "${WORK_DIR}/${mod}" -name "*.ko" 2>/dev/null | head -1)
        if [ -n "$ko" ]; then
            echo -e "  ${GREEN}✓${NC} ${mod}.ko"
        else
            echo -e "  ${RED}✗${NC} ${mod}  （构建失败）"
        fi
    done
    echo ""
    echo "  后续步骤："
    echo "   1. 应用 Freenove 显示设备树覆盖："
    echo "      sudo cp dts/imola-camera-dsi.dts /boot/efi/dtb/qcom/"
    echo "   2. 验证模块是否已加载："
    echo "      lsmod | grep tc358762"
    echo "   3. 检查显示管线："
    echo "      dmesg | grep -iE 'dsi|panel|tc358762|display'"
    echo "   4. 检查 DRM 设备："
    echo "      ls /dev/dri/  &&  cat /sys/class/drm/card*/status"
    echo ""
    echo "  构建产物：${WORK_DIR}/"
    echo ""
}

usage() {
    echo "用法：$0 [MODULE|all]"
    echo ""
    echo "  all          构建所有支持的模块"
    echo "  tc358762     DSI 转 DPI 桥接器（树莓派 7 英寸、Freenove 4.3 英寸）"
    echo "  ili9881c     ILITEK ILI9881C 面板（微雪 5/7/10.1 英寸）"
    echo "  st7701       Sitronix ST7701 面板（Arduino GigaDisplay）"
    echo "  hx8394       Himax HX8394 面板（入门级 720p 显示器）"
    echo "  otm8009a     Orise OTM8009A 面板（STM32 Discovery 开发板）"
    echo "  goodix_ts    Goodix GT911/GT9xx 触摸屏（轮询模式，无 IRQ）"
    echo ""
    echo "  环境变量："
    echo "    KERNEL_DIR            内核构建目录路径（默认：/lib/modules/\$(uname -r)/build）"
    echo "    KERNEL_VERSION        目标内核版本字符串（默认：\$(uname -r)）"
    echo "    ARCH                  目标架构（默认：arm64）"
    echo "    CROSS_COMPILE         交叉编译器前缀（默认：无）"
    echo "    SKIP_INSTALL          设为 1 可跳过安装/modprobe（交叉构建模式）"
    echo "    KBUILD_MODPOST_WARN   设为 1 可在没有 Module.symvers 时构建"
    echo "    LINUX_TAG             获取源码所用的 Linux git 标签（默认：v6.16）"
    echo ""
    echo "  交叉编译示例："
    echo "    ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \\"
    echo "    KERNEL_DIR=/path/to/linux \\"
    echo "    LINUX_TAG=v6.16 \\"
    echo "    ./build-dsi-modules.sh all"
}

# ── 主流程 ────────────────────────────────────────────────────────────────────

TARGET="${1:-}"

if [ -z "$TARGET" ] || [ "$TARGET" = "-h" ] || [ "$TARGET" = "--help" ]; then
    usage
    exit 0
fi

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  Arduino UNO Q DSI 显示模块构建工具"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "  内核：${KERNEL_VERSION}"
echo "  构建目录：${KERNEL_DIR}"
echo "  架构：${ARCH}"
echo "  交叉编译器：${CROSS_COMPILE:-<原生>}"
echo ""

check_prerequisites

mkdir -p "$WORK_DIR"

if [ "$TARGET" = "all" ]; then
    MODULES_TO_BUILD=($ALL_MODULES)
else
    # 验证模块名
    if [[ ! " $ALL_MODULES " =~ " $TARGET " ]]; then
        error "未知模块：'$TARGET'。支持的模块：$ALL_MODULES"
    fi
    MODULES_TO_BUILD=("$TARGET")
fi

BUILT=()
for mod in "${MODULES_TO_BUILD[@]}"; do
    if build_module "$mod"; then
        # 交叉编译时跳过安装/加载；调用方（交叉构建脚本）会收集 .ko 文件，
        # 由用户手动部署到目标设备。
        if [ "${SKIP_INSTALL:-0}" = "1" ]; then
            info "交叉构建模式：跳过 ${mod} 的安装/加载"
        else
            install_module "$mod"
            load_module    "$mod"
        fi
        BUILT+=("$mod")
    else
        warn "模块 ${mod} 构建失败，跳过安装/加载"
        BUILT+=("${mod}-FAILED")
    fi
done

show_summary "${BUILT[@]}"
