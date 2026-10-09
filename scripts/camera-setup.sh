#!/bin/bash
#
# 检测并配置 Arduino UNO Q 上的 IMX219 摄像头，以及从中采集图像
#
# 自动识别已连接的摄像头，追踪媒体管线以找到各摄像头对应的
# /dev/videoX 设备，并配置管线格式。
#
# 用法：
#   ./camera-setup.sh              # 检测并配置摄像头
#   ./camera-setup.sh capture      # 配置并从每个摄像头采集一帧
#   ./camera-setup.sh stream CAM1  # 配置并从 CAM1 连续传输
#
# 脚本分配固定名称：
#   CAM0 = CCI I2C 总线 0 上的传感器（J4 接口）
#   CAM1 = CCI I2C 总线 1 上的传感器（J3 接口）
#

set -e

MEDIA_DEV="/dev/media0"
FORMAT="SRGGB10_1X10"
WIDTH=1920
HEIGHT=1080
PIX_FMT="pRAA"   # 10 位打包 Bayer（MIPI）
FRAME_COUNT=1
TIMEOUT=10

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── 检查前置条件 ────────────────────────────────────────────────────────

[ -e "$MEDIA_DEV" ] || error "未找到 /dev/media0。qcom-camss 是否已加载？"
command -v media-ctl &>/dev/null || error "未找到 media-ctl。请安装 v4l-utils。"
command -v v4l2-ctl &>/dev/null || error "未找到 v4l2-ctl。请安装 v4l-utils。"

# ── 发现传感器 ──────────────────────────────────────────────────────────

# 解析 media-ctl -p，查找所有 imx219 传感器实体。
# 每个传感器实体名形如 "imx219 N-0010"，其中 N 为 I2C 适配器。
# CCI 总线 0 注册为 i2c 适配器 1（或类似编号），CCI 总线 1 注册为适配器 2。
# 按适配器编号排序，将其映射为 CAM0/CAM1。

declare -A SENSOR_ENTITY    # CAM0 => "imx219 1-0010"
declare -A SENSOR_SUBDEV    # CAM0 => "/dev/v4l-subdev12"
declare -A SENSOR_I2C_BUS   # CAM0 => "1"
declare -A CAM_CSIPHY       # CAM0 => "msm_csiphy0"
declare -A CAM_CSID         # CAM0 => "msm_csid0"
declare -A CAM_VFE          # CAM0 => "msm_vfe0_rdi0"
declare -A CAM_VIDEO        # CAM0 => "/dev/video0"
declare -a CAM_LIST         # ("CAM0" "CAM1")

MEDIA_OUTPUT="$(media-ctl -d "$MEDIA_DEV" -p)"

# 查找所有 imx219 实体
while IFS= read -r line; do
    # 匹配："- entity 131: imx219 2-0010 (1 pad, 1 link, 0 routes)"
    if [[ "$line" =~ entity\ [0-9]+:\ (imx219\ ([0-9]+)-[0-9a-f]+)\ \( ]]; then
        entity="${BASH_REMATCH[1]}"
        i2c_bus="${BASH_REMATCH[2]}"

        # 读取下一行中的子设备路径
        subdev=""
        while IFS= read -r next; do
            if [[ "$next" =~ device\ node\ name\ (/dev/v4l-subdev[0-9]+) ]]; then
                subdev="${BASH_REMATCH[1]}"
                break
            fi
        done

        # 按 I2C 总线编号排序，编号较小者为 CAM0
        cam_idx="${#CAM_LIST[@]}"
        cam_name="CAM${cam_idx}"
        CAM_LIST+=("$cam_name")
        SENSOR_ENTITY[$cam_name]="$entity"
        SENSOR_SUBDEV[$cam_name]="$subdev"
        SENSOR_I2C_BUS[$cam_name]="$i2c_bus"
    fi
done <<< "$MEDIA_OUTPUT"

# 按 I2C 总线编号排序（编号较小者为 CAM0）
if [ ${#CAM_LIST[@]} -gt 1 ]; then
    # 重新排序：找出 I2C 总线编号较小者
    if [ "${SENSOR_I2C_BUS[CAM1]}" -lt "${SENSOR_I2C_BUS[CAM0]}" ]; then
        # 交换
        for key in SENSOR_ENTITY SENSOR_SUBDEV SENSOR_I2C_BUS; do
            declare -n arr="$key"
            tmp="${arr[CAM0]}"
            arr[CAM0]="${arr[CAM1]}"
            arr[CAM1]="$tmp"
        done
    fi
fi

if [ ${#CAM_LIST[@]} -eq 0 ]; then
    error "未找到 IMX219 传感器。请检查摄像头连接和 dmesg。"
fi

# ── 追踪各传感器的管线 ──────────────────────────────────────────────────

# 对每个传感器，沿管线中的 ENABLED 链接追踪：
#   传感器 → csiphy → csid → vfe_rdi → 视频节点
trace_pipeline() {
    local cam="$1"
    local entity="${SENSOR_ENTITY[$cam]}"

    # 查找传感器连接的 csiphy
    local csiphy=""
    csiphy=$(echo "$MEDIA_OUTPUT" | grep -B5 "\"${entity}\".*ENABLED" | \
             grep -oP 'entity \d+: \K(msm_csiphy\d+)' | head -1)
    if [ -z "$csiphy" ]; then
        warn "$cam：无法追踪 csiphy 链接"
        return 1
    fi
    CAM_CSIPHY[$cam]="$csiphy"

    # 查找 csiphy 连接的 csid（ENABLED 链接）
    local csid=""
    # 查找从 csiphy SOURCE pad 引出的 ENABLED 链接
    csid=$(echo "$MEDIA_OUTPUT" | \
           sed -n "/entity.*${csiphy}/,/^$/p" | \
           grep 'pad1: SOURCE' -A20 | \
           grep -oP '"(msm_csid\d+)".*\[ENABLED\]' | \
           grep -oP 'msm_csid\d+' | head -1)
    if [ -z "$csid" ]; then
        # 尝试查找以此 csiphy 为 ENABLED 源的任意 csid
        csid=$(echo "$MEDIA_OUTPUT" | \
               grep -P "\"${csiphy}\".*\[ENABLED\]" | \
               grep -oP 'msm_csid\d+' | head -1)
    fi
    if [ -z "$csid" ]; then
        warn "$cam：无法追踪从 $csiphy 引出的 csid 链接"
        return 1
    fi
    CAM_CSID[$cam]="$csid"

    # 查找 csid 连接的 vfe_rdi（ENABLED 链接）
    local vfe=""
    vfe=$(echo "$MEDIA_OUTPUT" | \
          sed -n "/entity.*${csid} /,/^- entity/p" | \
          grep -oP '"(msm_vfe\d+_rdi\d+)".*\[ENABLED\]' | \
          grep -oP 'msm_vfe\d+_rdi\d+' | head -1)
    if [ -z "$vfe" ]; then
        warn "$cam：无法追踪从 $csid 引出的 VFE 链接"
        return 1
    fi
    CAM_VFE[$cam]="$vfe"

    # 查找连接到此 VFE 的 /dev/videoX 节点
    local video=""
    # msm_vfe0_rdi0 对应的视频节点实体名形如 msm_vfe0_video0
    local video_entity="${vfe/rdi/video}"
    video=$(echo "$MEDIA_OUTPUT" | \
            sed -n "/entity.*${video_entity}/,/^$/p" | \
            grep -oP 'device node name \K/dev/video\d+')
    if [ -z "$video" ]; then
        warn "$cam：找不到 $vfe 对应的视频设备"
        return 1
    fi
    CAM_VIDEO[$cam]="$video"
}

for cam in "${CAM_LIST[@]}"; do
    trace_pipeline "$cam" || true
done

# ── 显示结果 ────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  摄像头检测 - Arduino UNO Q / Zephyria 扩展板${NC}"
echo -e "${BOLD}════════════════════════════════════════════════════════════${NC}"
echo ""

for cam in "${CAM_LIST[@]}"; do
    if [ -n "${CAM_VIDEO[$cam]}" ]; then
        echo -e "  ${GREEN}✓${NC}  ${BOLD}${cam}${NC}"
    else
        echo -e "  ${YELLOW}?${NC}  ${BOLD}${cam}${NC}  （未完整追踪管线）"
    fi
    echo "      传感器：${SENSOR_ENTITY[$cam]}"
    echo "      子设备：${SENSOR_SUBDEV[$cam]}"
    echo "      I2C 总线：${SENSOR_I2C_BUS[$cam]}"
    if [ -n "${CAM_CSIPHY[$cam]}" ]; then
        echo "      管线：${CAM_CSIPHY[$cam]} → ${CAM_CSID[$cam]} → ${CAM_VFE[$cam]}"
        echo "      视频设备：${CAM_VIDEO[$cam]}"
    fi
    echo ""
done

# ── 配置管线 ────────────────────────────────────────────────────────────

configure_camera() {
    local cam="$1"
    local entity="${SENSOR_ENTITY[$cam]}"
    local csiphy="${CAM_CSIPHY[$cam]}"
    local csid="${CAM_CSID[$cam]}"
    local vfe="${CAM_VFE[$cam]}"
    local fmt="${FORMAT}/${WIDTH}x${HEIGHT}"

    if [ -z "$vfe" ]; then
        warn "跳过 $cam，未追踪到管线"
        return 1
    fi

    info "正在配置 $cam 管线：$entity → $csiphy → $csid → $vfe"

    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${entity}\":0[fmt:${fmt}]"
    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${csiphy}\":0[fmt:${fmt}]"
    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${csiphy}\":1[fmt:${fmt}]"
    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${csid}\":0[fmt:${fmt}]"
    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${csid}\":1[fmt:${fmt}]"
    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${vfe}\":0[fmt:${fmt}]"
    media-ctl -d "$MEDIA_DEV" --set-v4l2 "\"${vfe}\":1[fmt:${fmt}]"

    info "$cam 管线配置完成"
}

echo -e "${BOLD}正在配置管线...${NC}"
echo ""

for cam in "${CAM_LIST[@]}"; do
    configure_camera "$cam" || true
done

# ── 设置默认曝光 ────────────────────────────────────────────────────────

for cam in "${CAM_LIST[@]}"; do
    subdev="${SENSOR_SUBDEV[$cam]}"
    if [ -n "$subdev" ]; then
        v4l2-ctl -d "$subdev" --set-ctrl=exposure=5000 2>/dev/null || true
        v4l2-ctl -d "$subdev" --set-ctrl=analogue_gain=400 2>/dev/null || true
    fi
done

# ── 操作：采集或传输 ────────────────────────────────────────────────────

ACTION="${1:-}"

if [ "$ACTION" = "capture" ]; then
    echo ""
    echo -e "${BOLD}正在采集帧...${NC}"
    echo ""

    for cam in "${CAM_LIST[@]}"; do
        video="${CAM_VIDEO[$cam]}"
        [ -z "$video" ] && continue

        outfile="${cam,,}_$(date +%Y%m%d_%H%M%S).raw"
        info "$cam：正在从 $video 采集到 $outfile"

        timeout "$TIMEOUT" v4l2-ctl -d "$video" \
            --set-fmt-video=width=${WIDTH},height=${HEIGHT},pixelformat=${PIX_FMT} \
            --stream-mmap --stream-count=${FRAME_COUNT} \
            --stream-to="$outfile" 2>&1 || {
            warn "$cam：采集失败或超时"
            continue
        }

        if [ -f "$outfile" ] && [ -s "$outfile" ]; then
            size=$(du -sh "$outfile" | cut -f1)
            echo -e "  ${GREEN}✓${NC}  $outfile ($size)"
        else
            echo -e "  ${RED}✗${NC}  $outfile（为空或缺失）"
        fi
    done

elif [ "$ACTION" = "stream" ]; then
    TARGET_CAM="${2:-CAM0}"
    video="${CAM_VIDEO[$TARGET_CAM]}"
    [ -z "$video" ] && error "未找到 $TARGET_CAM，或未追踪到其管线"

    info "正在从 $TARGET_CAM ($video) 传输... 按 Ctrl+C 停止。"
    v4l2-ctl -d "$video" \
        --set-fmt-video=width=${WIDTH},height=${HEIGHT},pixelformat=${PIX_FMT} \
        --stream-mmap --stream-count=0
fi

# ── 摘要 ────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}快速参考：${NC}"
echo ""
for cam in "${CAM_LIST[@]}"; do
    video="${CAM_VIDEO[$cam]}"
    subdev="${SENSOR_SUBDEV[$cam]}"
    [ -z "$video" ] && continue
    echo "  $cam：采集设备 = $video"
    echo "        传感器子设备 = $subdev"
done
echo ""
echo "  采集一帧："
for cam in "${CAM_LIST[@]}"; do
    video="${CAM_VIDEO[$cam]}"
    [ -z "$video" ] && continue
    echo "    v4l2-ctl -d $video --set-fmt-video=width=${WIDTH},height=${HEIGHT},pixelformat=${PIX_FMT} \\"
    echo "        --stream-mmap --stream-count=1 --stream-to=${cam,,}.raw"
done
echo ""
echo "  调整曝光/增益："
for cam in "${CAM_LIST[@]}"; do
    subdev="${SENSOR_SUBDEV[$cam]}"
    [ -z "$subdev" ] && continue
    echo "    v4l2-ctl -d $subdev --set-ctrl=exposure=5000"
    echo "    v4l2-ctl -d $subdev --set-ctrl=analogue_gain=400"
done
echo ""
