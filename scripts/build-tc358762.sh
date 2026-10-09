#!/bin/bash
#
# 为 Arduino UNO Q 构建 TC358762 DSI 转 DPI 桥接内核模块
#
# 以下设备需要此模块：
#   - Freenove 4.3 英寸触摸屏
#   - 树莓派官方 7 英寸显示器
#   - 使用 TC358762 的微雪 DSI 显示器
#
# 请在 Arduino UNO Q 本机运行此脚本
#

set -e

echo "=============================================="
echo " UNO Q TC358762 内核模块构建工具"
echo "=============================================="
echo ""

# 配置
WORK_DIR="/tmp/tc358762-build"
KERNEL_VERSION=$(uname -r)
MODULE_NAME="tc358762"

# 彩色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# 检查是否以 root 身份运行
if [ "$EUID" -eq 0 ]; then
    error "请勿以 root 身份运行。脚本会在需要时使用 sudo。"
fi

# 第 1 步：检查前置条件
info "正在检查前置条件..."

if ! command -v make &>/dev/null; then
    warn "正在安装 build-essential..."
    sudo apt update
    sudo apt install -y build-essential bc flex bison
fi

# 第 2 步：检查内核头文件
info "正在检查内核头文件..."

HEADERS_DIR="/lib/modules/${KERNEL_VERSION}/build"
if [ ! -d "$HEADERS_DIR" ]; then
    warn "在 $HEADERS_DIR 中未找到内核头文件"
    echo ""
    echo "正在尝试安装内核头文件..."

    if ! sudo apt install -y linux-headers-${KERNEL_VERSION} 2>/dev/null; then
        echo ""
        error "apt 未提供内核头文件。

请选择以下一种方式：
  1. 使用 Arduino 内核源码构建（参见 RPI-DISPLAY-COMPATIBILITY.md 中的方法 2）
  2. 在主机 PC 上交叉编译（更快，参见方法 3）

仓库中没有 ${KERNEL_VERSION} 的内核头文件包。"
    fi
fi

info "已在 $HEADERS_DIR 中找到内核头文件"

# 第 3 步：创建工作目录
info "正在创建工作目录..."
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 第 4 步：下载 tc358762.c 源码
info "正在下载 tc358762.c 源码..."

# 先尝试 arduino/linux-qcom，失败后改用 torvalds 上游源码树
ARDUINO_URL="https://raw.githubusercontent.com/arduino/linux-qcom/main/drivers/gpu/drm/bridge/tc358762.c"
UPSTREAM_URL="https://raw.githubusercontent.com/torvalds/linux/v6.16/drivers/gpu/drm/bridge/tc358762.c"

if curl -fsSL "$ARDUINO_URL" -o tc358762.c 2>/dev/null; then
    info "  已从 arduino/linux-qcom 获取源码"
elif curl -fsSL "$UPSTREAM_URL" -o tc358762.c; then
    info "  已从 torvalds/linux v6.16 获取源码（后备来源）"
else
    error "从 arduino/linux-qcom 和 torvalds/linux 下载 tc358762.c 均失败"
fi

# 第 5 步：创建 Kbuild 文件
info "正在创建 Kbuild 文件..."

cat > Kbuild << 'EOF'
# tc358762 树外模块的 Kbuild 文件
obj-m := tc358762.o
EOF

# 第 6 步：创建 Makefile
cat > Makefile << 'EOF'
KERNEL_VERSION ?= $(shell uname -r)
KERNEL_DIR ?= /lib/modules/$(KERNEL_VERSION)/build
PWD := $(shell pwd)

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean

install:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules_install
	depmod -a

.PHONY: all clean install
EOF

# 第 7 步：构建模块
info "正在构建 tc358762.ko 模块..."
echo ""

if ! make 2>&1; then
    echo ""
    error "模块构建失败，请检查上方错误消息。

常见问题：
  - 缺少内核头文件：安装 linux-headers-${KERNEL_VERSION}
  - 内核配置不匹配：源码必须与运行中的内核匹配
  - 缺少依赖项：检查 DRM_MIPI_DSI、DRM_KMS_HELPER"
fi

# 第 8 步：检查模块是否已构建
if [ ! -f "tc358762.ko" ]; then
    error "未生成模块 tc358762.ko"
fi

info "模块构建成功！"
echo ""
ls -la tc358762.ko
echo ""

# 第 9 步：安装模块
info "正在安装模块..."

INSTALL_DIR="/lib/modules/${KERNEL_VERSION}/kernel/drivers/gpu/drm/bridge"
sudo mkdir -p "$INSTALL_DIR"
sudo cp tc358762.ko "$INSTALL_DIR/"
sudo depmod -a

# 第 10 步：加载模块
info "正在加载模块..."

if sudo modprobe tc358762; then
    info "模块加载成功！"
else
    warn "模块加载失败，可能需要先配置设备树"
fi

# 第 11 步：验证
echo ""
echo "=============================================="
echo " 构建完成！"
echo "=============================================="
echo ""
echo "模块已安装到：$INSTALL_DIR/tc358762.ko"
echo ""
echo "验证方法："
echo "  lsmod | grep tc358762"
echo "  modinfo tc358762"
echo ""
echo "后续步骤："
echo "  1. 为显示器配置设备树（参见 DSI-DISPLAY-GUIDE.md）"
echo "  2. 重启以应用设备树更改"
echo "  3. 检查 dmesg 中的显示初始化信息"
echo ""
echo "构建文件保存在：$WORK_DIR"
echo ""
