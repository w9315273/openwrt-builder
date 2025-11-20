#!/usr/bin/env bash
set -euo pipefail


# ========== 🔧 必须修改为宿主机实际路径 ===============
WORKSPACE_HOST="/home/tk/workspace/openwrt-workspace"
# ==================================================


# ========== 配置区域 ==========
CONTAINER_NAME="Menuconfig"
CONTAINER_IMAGE="ghcr.io/w9315273/openwrt-builder:latest"
WORKSPACE="/openwrt-workspace"
# ==============================

C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_GRAY='\033[0;90m'

CONTAINER_STARTED_BY_SCRIPT=false

require() {
  command -v "$1" >/dev/null 2>&1 || return 1
}

die() {
  echo -e "${C_RED}❌ Error: $*${C_RESET}" >&2
  exit 1
}

# 启动临时容器
start_temp_container() {
  if docker ps -q -f name="^${CONTAINER_NAME}$" 2>/dev/null | grep -q .; then
    echo -e "${C_GREEN}✅ 容器已在运行${C_RESET}\n"
    return 0
  fi
  
  echo -e "${C_YELLOW}⏳ 正在启动临时容器...${C_RESET}"
  
  # 检查宿主机目录配置
  if [[ "${WORKSPACE_HOST}" == "PLEASE_SET_YOUR_WORKSPACE_PATH_HERE" ]]; then
    die "请先修改脚本中的 WORKSPACE_HOST 变量为实际的宿主机目录路径"
  fi
  
  # 检查宿主机目录是否存在
  if [[ ! -d "${WORKSPACE_HOST}" ]]; then
    die "宿主机工作目录不存在: ${WORKSPACE_HOST}\n请确认路径是否正确"
  fi
  
  # 清理可能存在的同名stopped容器
  docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
  
  # 启动容器
  if docker run -d --rm \
    --name "${CONTAINER_NAME}" \
    -v "${WORKSPACE_HOST}:${WORKSPACE}" \
    "${CONTAINER_IMAGE}" \
    sleep infinity >/dev/null 2>&1; then
    
    CONTAINER_STARTED_BY_SCRIPT=true
    sleep 2  # 等待容器完全启动
    echo -e "${C_GREEN}✅ 容器已启动${C_RESET}\n"
  else
    die "启动容器失败, 请检查镜像 ${CONTAINER_IMAGE} 是否存在"
  fi
}

# 清理函数
cleanup() {
  if [[ "$CONTAINER_STARTED_BY_SCRIPT" == "true" ]]; then
    echo -e "\n${C_YELLOW}🔄 正在停止临时容器...${C_RESET}"
    docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    echo -e "${C_GREEN}✅ 容器已清理${C_RESET}"
  fi
}

# 设置退出时清理
trap cleanup EXIT

# 1) 列出 <OWNER>/<REPO>
list_repos() {
  docker exec "${CONTAINER_NAME}" bash -lc "
    shopt -s nullglob dotglob
    cd '${WORKSPACE}' || exit 0
    for d in */*; do
      [ -d \"\$d\" ] && echo \"\${d%/}\"
    done
  "
}

# 2) 列出目录
list_builds() {
  local repo="$1"
  docker exec "${CONTAINER_NAME}" bash -lc "
    cd '${WORKSPACE}/${repo}' 2>/dev/null || exit 1
    shopt -s nullglob
    builds=( build-* )
    if [ \${#builds[@]} -eq 0 ]; then
      exit 1
    fi
    ls -1dt build-* 2>/dev/null
  " 2>/dev/null
}

pick_one() {
  local arr=("$@")
  local n=${#arr[@]}
  (( n > 0 )) || die "没有可选项"
  
  local idx
  while true; do
    echo >&2
    for i in "${!arr[@]}"; do
      printf "${C_CYAN}%2d${C_RESET} ${C_GRAY}-->${C_RESET} %s\n" "$((i+1))" "${arr[$i]}" >&2
    done
    echo >&2
    read -rp "$(echo -e "${C_YELLOW}▶ 输入序号: ${C_RESET}")" idx </dev/tty >&2
    [[ -z "${idx:-}" ]] && idx=1
    
    if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
      echo -e "${C_RED}❌ 非法输入, 请输入数字${C_RESET}" >&2
      continue
    fi
    
    if ! (( idx>=1 && idx<=n )); then
      echo -e "${C_RED}❌ 超出范围 (1-${n})${C_RESET}" >&2
      continue
    fi
    
    break
  done
  
  echo "${arr[$((idx-1))]}"
}

echo -e "\n${C_BOLD}${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_BOLD}  OpenWrt Menuconfig 配置工具${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"

# 启动临时容器
start_temp_container

echo -e "${C_GRAY}🔎 容器: ${C_CYAN}${CONTAINER_NAME}${C_GRAY}   工作区: ${C_CYAN}${WORKSPACE_HOST}${C_RESET}\n"

# 选择仓库
mapfile -t repos < <(list_repos)
(( ${#repos[@]} > 0 )) || die "未在 ${WORKSPACE} 下找到任何 <OWNER>/<REPO>"

echo -e "${C_BOLD}📦 请选择仓库:${C_RESET}"
repo_sel="$(pick_one "${repos[@]}")"
[[ -n "$repo_sel" ]] || die "未选择仓库"
echo -e "${C_GREEN}➡  已选择仓库: ${C_BOLD}${repo_sel}${C_RESET}\n"

# 选择版本
echo -e "${C_GRAY}🧬 正在查找可用版本...${C_RESET}"
if ! mapfile -t builds < <(list_builds "${repo_sel}"); then
  die "仓库 ${repo_sel} 下没有 build-* 目录, 请先跑过一次工作流"
fi

if (( ${#builds[@]} == 0 )); then
  die "仓库 ${repo_sel} 下没有 build-* 目录, 请先跑过一次工作流"
fi

echo -e "${C_BOLD}🧬 请选择版本:${C_RESET}"
build_sel="$(pick_one "${builds[@]}")"
[[ -n "$build_sel" ]] || die "未选择版本"
echo -e "${C_GREEN}➡  已选择版本: ${C_BOLD}${build_sel}${C_RESET}\n"

# 进入 menuconfig
echo -e "${C_BOLD}${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
echo -e "${C_BOLD}🛠  正在启动 Menuconfig...${C_RESET}"
echo -e "${C_BOLD}${C_BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"

docker exec -it "${CONTAINER_NAME}" bash -lc "
  export TERM=xterm-256color
  cd '${WORKSPACE}/${repo_sel}/${build_sel}' && make menuconfig
"

# 询问是否导出 diffconfig
echo -e "\n${C_BOLD}${C_YELLOW}❓ 是否导出 diffconfig?${C_RESET}"
echo -e "   ${C_GRAY}1${C_RESET} ${C_GRAY}-->${C_RESET} ${C_GREEN}是${C_RESET}"
echo -e "   ${C_GRAY}2${C_RESET} ${C_GRAY}-->${C_RESET} 否"
echo

export_choice=""
while true; do
  read -rp "$(echo -e "${C_YELLOW}▶ 输入序号: ${C_RESET}")" export_choice </dev/tty
  [[ -z "${export_choice}" ]] && export_choice=1
  
  if [[ ! "$export_choice" =~ ^[0-9]+$ ]]; then
    echo -e "${C_RED}❌ 非法输入, 请输入数字${C_RESET}" >&2
    continue
  fi
  
  if ! (( export_choice>=1 && export_choice<=2 )); then
    echo -e "${C_RED}❌ 超出范围 (1-2)${C_RESET}" >&2
    continue
  fi
  
  break
done

if [[ "$export_choice" != "1" ]]; then
  echo -e "${C_GRAY}❕ 已跳过导出${C_RESET}\n"
  exit 0
fi

# 导出 diffconfig 到容器 /tmp 再拷回本机
echo -e "\n${C_YELLOW}📝 正在导出 diffconfig...${C_RESET}"
docker exec "${CONTAINER_NAME}" bash -lc "
  cd '${WORKSPACE}/${repo_sel}/${build_sel}' &&
  ./scripts/diffconfig.sh > /tmp/diffconfig
"

# 目标文件名: 避免覆盖, 加上 repo 与 tag
ts="$(date +%Y%m%d-%H%M%S)"
repo_name="${repo_sel##*/}"
outfile="diffconfig-${repo_name}-${build_sel}-${ts}"

if docker cp "${CONTAINER_NAME}:/tmp/diffconfig" "./${outfile}"; then
  echo -e "${C_GREEN}${C_BOLD}✅ 配置已保存:${C_RESET} ${C_CYAN}./${outfile}${C_RESET}\n"
else
  die "拷贝 diffconfig 失败"
fi