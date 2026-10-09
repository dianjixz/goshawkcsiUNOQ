#!/bin/bash
#
# 安装 Zephyria Shield systemd 服务
#
# 复制 zephyria-setup.sh 并启用服务，使所有外设
#（显示、音频和摄像头）在启动时完成配置。
#
# 用法：
#   sudo ./install-service.sh
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'

[ "$(id -u)" -eq 0 ] || { echo -e "${RED}请以 root 身份运行：sudo $0${NC}"; exit 1; }

echo "正在安装 Zephyria Shield 服务..."

# 复制设置脚本
cp "$SCRIPT_DIR/zephyria-setup.sh" /usr/local/bin/zephyria-setup.sh
chmod +x /usr/local/bin/zephyria-setup.sh
echo -e "  ${GREEN}✓${NC}  /usr/local/bin/zephyria-setup.sh"

# 复制并启用 systemd 服务
cp "$SCRIPT_DIR/zephyria-setup.service" /etc/systemd/system/zephyria-setup.service
systemctl daemon-reload
systemctl enable zephyria-setup.service
echo -e "  ${GREEN}✓${NC}  zephyria-setup.service 已启用"

echo ""
echo "完成。该服务将在每次启动时运行。"
echo ""
echo "  手动命令："
echo "    sudo zephyria-setup.sh setup    # 立即运行"
echo "    sudo zephyria-setup.sh status   # 检查设备"
echo "    journalctl -u zephyria-setup    # 查看启动日志"
echo "    sudo systemctl disable zephyria-setup  # 禁用"
echo ""
