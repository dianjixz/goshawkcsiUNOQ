#!/bin/bash
#
# 构建可跳过缺失传感器的补丁版 qcom-camss.ko
#
# 原版 CAMSS 驱动会等待设备树中声明的所有传感器完成绑定，之后才注册
# 媒体设备。如果有任何摄像头接口未连接，整个摄像头子系统都会被阻塞。
#
# 此脚本会修改 camss.c，在将传感器加入 v4l2 异步通知器之前探测 I2C
# 总线。未连接的传感器会被静默跳过。
#
# 用法（在设备上）：
#   ./build-camss-patched.sh [KERNEL_SRC_DIR]
#
# 用法（交叉编译）：
#   ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
#     ./build-camss-patched.sh /tmp/dsi-modules-cross/linux-qcom
#
# 交叉编译后，将 qcom-camss.ko 复制到开发板并安装：
#   scp /tmp/camss-patched/qcom-camss.ko user@uno-q:/tmp/
#   ssh user@uno-q 'KVER=$(uname -r); \
#     sudo cp /lib/modules/$KVER/kernel/drivers/media/platform/qcom/camss/qcom-camss.ko{,.orig}; \
#     sudo cp /tmp/qcom-camss.ko /lib/modules/$KVER/kernel/drivers/media/platform/qcom/camss/; \
#     sudo depmod -a && sudo reboot'
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 内核源码，与 build-dsi-ondevice.sh / cross-build-dsi-modules.sh 使用的相同
KERNEL_SRC="${1:-${KERNEL_SRC_DIR:-/opt/arduino-linux-qcom}}"
CAMSS_SRC="${KERNEL_SRC}/drivers/media/platform/qcom/camss"
CAMSS_C="${CAMSS_SRC}/camss.c"

ARCH="${ARCH:-arm64}"
CROSS_COMPILE="${CROSS_COMPILE:-}"
WORK_DIR="/tmp/camss-patched"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

echo ""
echo "════════════════════════════════════════════════════════════"
echo "  CAMSS 可选传感器补丁构建工具"
echo "════════════════════════════════════════════════════════════"
echo ""

# ── Validate ─────────────────────────────────────────────────────────────

[ -f "$CAMSS_C" ] || error "未找到 CAMSS 源码：${CAMSS_C}\n  请设置 KERNEL_SRC_DIR 或将路径作为参数传入。"
[ -f "${KERNEL_SRC}/Makefile" ] || error "${KERNEL_SRC} 中没有内核源码。"

# ── Patch camss.c ────────────────────────────────────────────────────────

step "正在修补 camss.c"

if grep -q 'camss_sensor_is_present' "$CAMSS_C"; then
    info "已应用补丁，跳过。"
else
    # 备份原文件
    cp "$CAMSS_C" "${CAMSS_C}.orig"
    info "已备份 ${CAMSS_C} → ${CAMSS_C}.orig"

    # --- 1. Add #include <linux/i2c.h> ---
    sed -i '/#include <linux\/interconnect.h>/a #include <linux/i2c.h>' "$CAMSS_C"

    # --- 2. Insert camss_sensor_is_present() before camss_of_parse_ports() ---
    # 创建包含该函数的临时文件
    TMPFUNC=$(mktemp)
    cat > "$TMPFUNC" << 'ENDFUNC'
/*
 * camss_sensor_is_present - Check if a sensor responds on its I2C bus
 * @dev:         CAMSS device (for logging)
 * @sensor_node: DT node of the sensor (e.g. sensor@10)
 *
 * Probes the sensor I2C address to check physical presence.  If the I2C
 * adapter is not yet available (e.g. CCI not probed), returns true to
 * preserve the original behavior.
 *
 * Return: true  if sensor answered or detection was not possible
 *         false if bus was accessible and no device answered
 */
static bool camss_sensor_is_present(struct device *dev,
				    struct device_node *sensor_node)
{
	struct device_node *bus_node;
	struct i2c_adapter *adap;
	u32 reg;
	union i2c_smbus_data dummy;
	int ret;

	if (of_property_read_u32(sensor_node, "reg", &reg))
		return true;

	bus_node = of_get_parent(sensor_node);
	if (!bus_node)
		return true;

	adap = of_find_i2c_adapter_by_node(bus_node);
	of_node_put(bus_node);
	if (!adap)
		return true;

	ret = i2c_smbus_xfer(adap, reg, 0, I2C_SMBUS_READ, 0,
			     I2C_SMBUS_BYTE, &dummy);
	put_device(&adap->dev);

	if (ret < 0) {
		dev_info(dev,
			 "sensor %pOFn @0x%02x not detected (err %d), skipping\n",
			 sensor_node, reg, ret);
		return false;
	}

	dev_info(dev, "sensor %pOFn @0x%02x detected\n", sensor_node, reg);
	return true;
}

ENDFUNC

    # 找到 "camss_of_parse_ports" 函数注释并在其前面插入
    PARSE_LINE=$(grep -n 'camss_of_parse_ports - Parse ports node' "$CAMSS_C" | head -1 | cut -d: -f1)
    if [ -z "$PARSE_LINE" ]; then
        rm "$TMPFUNC"
        error "在 camss.c 中找不到 camss_of_parse_ports"
    fi
    # 该注释从上方两行的 "/*" 开始
    INSERT_LINE=$((PARSE_LINE - 2))

    # 拆分文件，并插入该函数后重新组合
    head -n "$INSERT_LINE" "$CAMSS_C" > "${CAMSS_C}.tmp"
    cat "$TMPFUNC" >> "${CAMSS_C}.tmp"
    tail -n "+$((INSERT_LINE + 1))" "$CAMSS_C" >> "${CAMSS_C}.tmp"
    mv "${CAMSS_C}.tmp" "$CAMSS_C"
    rm "$TMPFUNC"
    info "已插入 camss_sensor_is_present()"

    # --- 3. Insert the check in camss_of_parse_ports() ---
    # 在 "Cannot get remote parent" 错误处理块之后，
    # 即调用 v4l2_async_nf_add_fwnode() 之前插入检查。
    TMPCHECK=$(mktemp)
    cat > "$TMPCHECK" << 'ENDCHECK'

		/* Skip sensors that are disabled or physically absent */
		if (!of_device_is_available(remote) ||
		    !camss_sensor_is_present(dev, remote)) {
			of_node_put(remote);
			continue;
		}

ENDCHECK

    # 找到 camss_of_parse_ports 中的 v4l2_async_nf_add_fwnode 行
    ADD_LINE=$(grep -n 'csd = v4l2_async_nf_add_fwnode(&camss->notifier,' "$CAMSS_C" | head -1 | cut -d: -f1)
    if [ -z "$ADD_LINE" ]; then
        rm "$TMPCHECK"
        error "在 camss.c 中找不到 v4l2_async_nf_add_fwnode 调用"
    fi

    head -n "$((ADD_LINE - 1))" "$CAMSS_C" > "${CAMSS_C}.tmp"
    cat "$TMPCHECK" >> "${CAMSS_C}.tmp"
    tail -n "+${ADD_LINE}" "$CAMSS_C" >> "${CAMSS_C}.tmp"
    mv "${CAMSS_C}.tmp" "$CAMSS_C"
    rm "$TMPCHECK"
    info "已在 camss_of_parse_ports() 中插入传感器检查"
fi

# ── Build ────────────────────────────────────────────────────────────────

step "正在构建 qcom-camss.ko"

mkdir -p "$WORK_DIR"

MAKE_ARGS=(
    ARCH="$ARCH"
    KBUILD_MODPOST_WARN=1
    -C "$KERNEL_SRC"
    M="drivers/media/platform/qcom/camss"
)
[ -n "$CROSS_COMPILE" ] && MAKE_ARGS+=(CROSS_COMPILE="$CROSS_COMPILE")

make "${MAKE_ARGS[@]}" clean 2>/dev/null || true
make "${MAKE_ARGS[@]}" -j"$(nproc)" modules

KO="${CAMSS_SRC}/qcom-camss.ko"
if [ ! -f "$KO" ]; then
    error "构建失败，未生成 qcom-camss.ko。"
fi

cp "$KO" "${WORK_DIR}/"
info "已构建：${WORK_DIR}/qcom-camss.ko  ($(du -sh "$KO" | cut -f1))"

# ── Install (on-device only) ─────────────────────────────────────────────

if [ -z "$CROSS_COMPILE" ] && [ "$(uname -m)" = "aarch64" ]; then
    KVER="$(uname -r)"
    DEST="/lib/modules/${KVER}/kernel/drivers/media/platform/qcom/camss"

    step "正在安装 qcom-camss.ko → ${DEST}"
    sudo mkdir -p "$DEST"

    if [ -f "${DEST}/qcom-camss.ko" ] && \
       [ ! -f "${DEST}/qcom-camss.ko.orig" ]; then
        sudo cp "${DEST}/qcom-camss.ko" "${DEST}/qcom-camss.ko.orig"
        info "已备份原文件 → qcom-camss.ko.orig"
    fi

    sudo cp "$KO" "${DEST}/"
    sudo depmod -a
    info "安装完成。"

    step "正在重新加载 qcom-camss"
    if lsmod | grep -q '^qcom_camss'; then
        if sudo modprobe -r qcom-camss 2>/dev/null; then
            info "已卸载旧版 qcom-camss"
        else
            warn "无法卸载 qcom-camss（正在使用）。请重启以激活。"
        fi
    fi
    sudo modprobe qcom-camss 2>/dev/null && info "已加载补丁版 qcom-camss" || \
        warn "modprobe 失败，请重启以激活。"

    echo ""
    echo "  验证："
    echo "    ls /dev/media*"
    echo "    dmesg | grep -i 'sensor.*detected\\|sensor.*skipping\\|camss'"
    echo ""
else
    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  交叉构建完成"
    echo "════════════════════════════════════════════════════════════"
    echo ""
    echo "  模块：${WORK_DIR}/qcom-camss.ko"
    echo ""
    echo "  部署到 UNO Q："
    echo "    scp ${WORK_DIR}/qcom-camss.ko user@<uno-q>:/tmp/"
    echo ""
    echo "    # 在 UNO Q 上："
    echo "    KVER=\$(uname -r)"
    echo "    DEST=/lib/modules/\$KVER/kernel/drivers/media/platform/qcom/camss"
    echo "    sudo cp \$DEST/qcom-camss.ko \$DEST/qcom-camss.ko.orig"
    echo "    sudo cp /tmp/qcom-camss.ko \$DEST/"
    echo "    sudo depmod -a && sudo reboot"
    echo ""
fi
