#!/bin/bash
# NodeQuality-GB5: Minimal Geekbench 5 & Basic Hardware Info Benchmark Script
#
# Derived and trimmed from:
#   - NodeQuality (https://github.com/LloydAsp/NodeQuality) - BenchOs chroot architecture
#   - HardwareQuality (https://github.com/xykt/HardwareQuality) - Hardware info & GB5 visual benchmark
#
# Repository: https://github.com/amourxiao/NodeQuality-GB5
# License: GNU Affero General Public License v3.0 (AGPL-3.0)

script_version="v1.0.0"
repo_url="https://github.com/amourxiao/NodeQuality-GB5"
run_cmd="bash <(curl -sL https://github.com/amourxiao/NodeQuality-GB5/raw/main/gb5.sh)"

current_time="$(date +%Y_%m_%d_%H_%M_%S)"
work_dir=".nodequality_gb5_${current_time}"
orig_dir="$(pwd)"
bench_os_url="https://github.com/LloydAsp/NodeQuality/releases/download/v0.0.2/BenchOs.tar.gz"

if uname -m | grep -Eq 'arm|aarch64'; then
    bench_os_url="https://github.com/LloydAsp/NodeQuality/releases/download/v0.0.2/BenchOs-arm.tar.gz"
fi

lang="cn"
opt_ipv=""
opt_lang=""
opt_verbose=""
opt_fullinfo=""
output_file=""
show_help_flag=0
cleanup_done=0
work_dir_ready=0

function _red() { echo -e "\033[0;31m$1\033[0m"; }
function _yellow() { echo -e "\033[0;33m$1\033[0m"; }
function _blue() { echo -e "\033[0;36m$1\033[0m"; }
function _green() { echo -e "\033[0;32m$1\033[0m"; }
function _red_bold() { echo -e "\033[1;31m$1\033[0m"; }
function _yellow_bold() { echo -e "\033[1;33m$1\033[0m"; }
function _blue_bold() { echo -e "\033[1;36m$1\033[0m"; }
function _green_bold() { echo -e "\033[1;32m$1\033[0m"; }

function show_help() {
    cat <<EOF
NodeQuality-GB5 (${script_version}) - 精简版设备基础信息 + Geekbench 5 测评脚本
Repository: ${repo_url}

Usage / 用法:
  ${run_cmd}
  bash gb5.sh [-E] [-V] [-f] [-4|-6] [-d <dir>] [-o <file>] [-h]

Options / 参数:
  -E, -e          English output / 使用英文输出（默认中文）
  -V, -v          Verbose GB5 mode (show per-subtest breakdown) / 深度模式（展示 GB5 分项详情）
  -f              Show full unmasked IP in report header / 报告不隐藏 IP 地址
  -4              Prefer IPv4 for header IP detection / 仅使用 IPv4 检测公网 IP
  -6              Prefer IPv6 for header IP detection / 仅使用 IPv6 检测公网 IP
  -D, -d <dir>    Specify temporary working directory for BenchOs / 指定 BenchOs 临时目录
  -o <file>       Save report to file (.ansi keeps colors, others plain text) / 保存报告至文件
  -h              Show this help message / 显示帮助信息
EOF
}

function parse_args() {
    local opt
    while getopts ":D:d:o:46EeVvfh" opt; do
        case "$opt" in
            4)
                if [[ "$opt_ipv" == "-6" ]]; then
                    opt_ipv=""
                else
                    opt_ipv="-4"
                fi
                ;;
            6)
                if [[ "$opt_ipv" == "-4" ]]; then
                    opt_ipv=""
                else
                    opt_ipv="-6"
                fi
                ;;
            D|d)
                local opt_dir="${OPTARG%/}"
                if [[ ! -d "$opt_dir" || ! -r "$opt_dir" || ! -w "$opt_dir" ]]; then
                    _red_bold "Error / 错误：指定的工作目录不存在或不可读写 (${opt_dir})！"
                    exit 1
                fi
                work_dir="${opt_dir}/${work_dir}"
                ;;
            o)
                local raw_out="$OPTARG"
                if [[ -z "$raw_out" ]]; then
                    _red_bold "Error / 错误：-o 需要指定输出文件路径！"
                    exit 1
                fi
                if [[ "$raw_out" == /* ]]; then
                    output_file="$raw_out"
                else
                    output_file="${orig_dir}/${raw_out}"
                fi
                if [[ -e "$output_file" ]]; then
                    _red_bold "Error / 错误：输出文件已存在 (${output_file})！"
                    exit 1
                fi
                if ! touch "$output_file" 2>/dev/null; then
                    _red_bold "Error / 错误：输出文件不可写 (${output_file})！"
                    exit 1
                fi
                ;;
            E|e)
                lang="en"
                opt_lang="-E"
                ;;
            V|v)
                opt_verbose="-V"
                ;;
            f)
                opt_fullinfo="-f"
                ;;
            h)
                show_help_flag=1
                ;;
            :)
                _red_bold "Error / 错误：参数 -${OPTARG} 缺少必要的值！"
                exit 1
                ;;
            \?)
                _red_bold "Error / 错误：不支持的参数 -${OPTARG}！使用 -h 查看帮助。"
                exit 1
                ;;
        esac
    done
}

parse_args "$@"

if [[ "$show_help_flag" -eq 1 ]]; then
    show_help
    exit 0
fi

# Pre-flight checks
if [[ "$(uname -s)" != "Linux" ]]; then
    _red_bold "Error / 错误：此脚本依赖 Linux chroot/BenchOs，仅支持在 Linux 系统上运行！"
    exit 1
fi

if [[ -z "${BASH_VERSINFO[0]}" || "${BASH_VERSINFO[0]}" -lt 4 ]]; then
    _red_bold "Error / 错误：需要 Bash 4.0 及以上版本！(Current: ${BASH_VERSION:-unknown})"
    exit 1
fi

if [[ "$EUID" -ne 0 ]]; then
    if [[ "$lang" == "en" ]]; then
        _red_bold "Error: BenchOs chroot mode requires root privileges. Please run as root (or with sudo)."
    else
        _red_bold "错误：BenchOs 临时系统模式需要 root 权限，请使用 root 用户或 sudo 运行此脚本。"
    fi
    exit 1
fi

for req_cmd in curl tar mount umount chroot; do
    if ! command -v "$req_cmd" >/dev/null 2>&1; then
        _red_bold "Error / 错误：缺少必要的系统命令：${req_cmd}"
        exit 1
    fi
done

declare -A LANG
# ===== English =====
LANG[en.err01]="Error: work_dir does not contain 'nodequality'!"
LANG[en.err_dl]="Error: Failed to download BenchOs archive. Please check network connectivity."
LANG[en.err_tar]="Error: Failed to extract BenchOs archive. Please check available disk space."
LANG[en.err_mount]="Error: Failed to mount proc/sys/dev for BenchOs (some unprivileged containers disallow mount)."
LANG[en.cleanup]="Cleaning up temporary BenchOs environment, please wait..."
LANG[en.clean_fail]="Unexpected error: BenchOs mount points were not fully unmounted. For safety, please reboot before deleting this directory."
LANG[en.cleanup_before]="Preparing temporary workspace..."
LANG[en.loadbench]="Loading BenchOs temporary system..."
LANG[en.run_gb5]="Running Basic Device Info & Geekbench 5 Test..."
LANG[en.cleanup_after]="Cleaning up BenchOs temporary system..."
LANG[en.saved]="Report saved to: "
# ===== Chinese =====
LANG[cn.err01]="错误：work_dir 不包含 'nodequality'！"
LANG[cn.err_dl]="错误：BenchOs 下载失败，请检查网络连接。"
LANG[cn.err_tar]="错误：BenchOs 解压失败，请检查当前目录可用磁盘空间（建议至少预留 1.5GB）。"
LANG[cn.err_mount]="错误：BenchOs 挂载 proc/sys/dev 失败（部分无特权容器环境不支持 mount/chroot）。"
LANG[cn.cleanup]="清理临时 BenchOs 环境中，请稍候..."
LANG[cn.clean_fail]="出现了预料之外的情况，BenchOS 目录的挂载未被清理干净，保险起见请重启后删除该目录。"
LANG[cn.cleanup_before]="准备临时工作目录..."
LANG[cn.loadbench]="加载 BenchOs 临时系统..."
LANG[cn.run_gb5]="正在运行设备基本信息采集与 Geekbench 5 测试..."
LANG[cn.cleanup_after]="清理 BenchOs 临时系统..."
LANG[cn.saved]="报告已保存至："

function L() {
    local key="${lang}.${1}"
    echo "${LANG[$key]:-${LANG[en.$1]}}"
}

function start_ascii() {
    echo -e "\033[1;36m"
    cat <<'EOF'
 _   _           _       ___              _ _ _           ____ ____  ____
| \ | | ___   __| | ___ / _ \ _   _  __ _| (_) |_ _   _  / ___| __ )| ___|
|  \| |/ _ \ / _` |/ _ \ | | | | | |/ _` | | | __| | | || |  _|  _ \|___ \
| |\  | (_) | (_| |  __/ |_| | |_| | (_| | | | |_| |_| || |_| | |_) |___) |
|_| \_|\___/ \__,_|\___|\__\_\\__,_|\__,_|_|_|\__|\__, | \____|____/|____/
                                                  |___/
EOF
    if [[ "$lang" == "en" ]]; then
        cat <<EOF
Trimmed benchmark script: Basic Device Info + Geekbench 5 (with common device comparison)

Executed inside a temporary BenchOs chroot environment; all traces are deleted afterwards.
Repo:    ${repo_url}
Credits: LloydAsp/NodeQuality & xykt/HardwareQuality (AGPL-3.0)
EOF
    else
        cat <<EOF
精简版测评脚本：仅保留设备基本信息 + Geekbench 5 性能测试（含常见设备分数对比）

脚本在 BenchOs 临时系统中纯净执行，测试完成后自动卸载并删除所有痕迹
仓库：${repo_url}
致谢：LloydAsp/NodeQuality & xykt/HardwareQuality (AGPL-3.0)
EOF
    fi
    echo -e "\033[0m"
}

function pre_init() {
    mkdir -p "$work_dir" || exit 1
    cd "$work_dir" || exit 1
    work_dir="$(pwd)"
    work_dir_ready=1
}

function clear_mount() {
    swapoff "$work_dir/swap" 2>/dev/null
    swapoff "$work_dir/BenchOs/.gb5_tmp.swap" 2>/dev/null

    umount "$work_dir/BenchOs/proc/" 2>/dev/null
    umount "$work_dir/BenchOs/sys/" 2>/dev/null
    umount -R "$work_dir/BenchOs/dev/" 2>/dev/null
}

function pre_cleanup() {
    clear_mount
    if [[ "$work_dir" == *"nodequality"* ]]; then
        rm -rf "${work_dir:?}"/*
    else
        echo "$(L err01)"
        exit 1
    fi
}

function load_bench_os() {
    cd "$work_dir" || exit 1
    rm -rf BenchOs

    if ! curl -fL#o BenchOs.tar.gz "$bench_os_url"; then
        _red_bold "$(L err_dl)"
        post_cleanup 1
    fi
    if ! tar -xzf BenchOs.tar.gz; then
        _red_bold "$(L err_tar)"
        post_cleanup 1
    fi
    rm -f BenchOs.tar.gz

    cd "$work_dir/BenchOs" || post_cleanup 1

    if ! mount -t proc /proc proc/ || ! mount --bind /sys sys/ || ! mount --rbind /dev dev/; then
        _red_bold "$(L err_mount)"
        post_cleanup 1
    fi
    mount --make-rslave dev 2>/dev/null || true

    rm -f etc/resolv.conf 2>/dev/null
    cp /etc/resolv.conf etc/resolv.conf 2>/dev/null || true
}

function post_check_mount() {
    if mount | grep -Fq "$work_dir/BenchOs"; then
        _red_bold "$(L clean_fail)" | tee "$work_dir/error.log" >&2
        exit 1
    fi
}

function post_cleanup() {
    local code="${1:-0}"
    if [[ "$cleanup_done" -eq 1 ]]; then
        exit "$code"
    fi
    cleanup_done=1
    trap - INT TERM SIGHUP EXIT

    cd "$orig_dir" 2>/dev/null || cd /

    if [[ "$work_dir_ready" -eq 1 ]]; then
        if [[ -d "$work_dir/BenchOs" ]]; then
            chroot "$work_dir/BenchOs" /bin/bash -c "umount -R /dev" &>/dev/null
            clear_mount
            post_check_mount
            rm -rf "$work_dir/BenchOs"
        fi

        if [[ "$work_dir" == *"nodequality"* ]]; then
            rm -rf "${work_dir:?}"/
        else
            echo "$(L err01)"
            exit 1
        fi
    fi

    if [[ "$code" -ne 0 && -n "$output_file" && ! -s "$output_file" ]]; then
        rm -f "$output_file" 2>/dev/null
    fi

    exit "$code"
}

function sig_cleanup() {
    local sig_code="${1:-130}"
    trap '' INT TERM SIGHUP EXIT
    echo "" >&2
    _yellow_bold "$(L cleanup)" >&2
    post_cleanup "$sig_code"
}

############ Host pre-fetch helpers (accurate host info before entering chroot) ############
function host_detect_virt() {
    local dv_sdv dv_env1 _pn
    [[ -f /.dockerenv ]] && { echo "docker"; return 0; }
    [[ -f /run/.containerenv ]] && { echo "podman"; return 0; }
    if [[ -f /run/systemd/container ]]; then
        local ctype
        ctype="$(cat /run/systemd/container 2>/dev/null)"
        [[ -n "$ctype" ]] && { echo "$ctype"; return 0; }
    fi
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        dv_sdv="$(systemd-detect-virt 2>/dev/null)"
        case "$dv_sdv" in
            none|""|chroot) ;;
            *) echo "$dv_sdv"; return 0 ;;
        esac
    fi
    if [[ -r /proc/1/environ ]]; then
        dv_env1="$(tr '\0' '\n' </proc/1/environ 2>/dev/null)"
        case "$dv_env1" in
            *container=lxc*) echo "lxc"; return 0 ;;
            *container=lxd*) echo "lxd"; return 0 ;;
            *container=systemd-nspawn*) echo "systemd-nspawn"; return 0 ;;
        esac
    fi
    if grep -qa 'lxc' /proc/1/cgroup 2>/dev/null; then
        echo "lxc"
        return 0
    fi
    if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
        if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
            _pn="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)"
            case "$_pn" in
                *VMware*) echo "vmware"; return 0 ;;
                *VirtualBox*) echo "oracle"; return 0 ;;
                *Parallels*) echo "parallels"; return 0 ;;
                *HVM*domU*|*Xen*) echo "xen"; return 0 ;;
                *Amazon*EC2*) echo "amazon"; return 0 ;;
                *Google*Compute*Engine*) echo "google"; return 0 ;;
                *KVM*|*Standard\ PC*|*Q35*|*i440FX*) echo "kvm"; return 0 ;;
                *Microsoft*|*Virtual\ Machine*) echo "microsoft"; return 0 ;;
                *BHYVE*) echo "bhve"; return 0 ;;
                *Bochs*) echo "bochs"; return 0 ;;
            esac
        fi
        echo "virtual-machine"
        return 0
    fi
    echo "physical-machine"
}

function host_get_md_mount() {
    local md="$1"
    local mp=""
    mp="$(findmnt -n -o TARGET "/dev/$md" 2>/dev/null)"
    [[ -n "$mp" ]] && { echo "$mp"; return; }
    mp="$(
        lsblk -o NAME,PKNAME,TYPE,MOUNTPOINT -r 2>/dev/null \
        | awk -v md="$md" '$2==md && $4!="" {print $4}' \
        | sort -u | paste -sd "," -
    )"
    [[ -n "$mp" ]] && echo "$mp"
}

function pre_fetch_info() {
    local virt_type
    virt_type="$(host_detect_virt)"

    declare -gA osinfo
    osinfo[virt]="$virt_type"
    osinfo[os]="$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
    osinfo[proc]="$(ps -e 2>/dev/null | wc -l | tr -d ' ')"

    local tmpuc=""
    if command -v loginctl >/dev/null 2>&1; then
        tmpuc="$(loginctl list-users 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
        [[ "$tmpuc" =~ ^[0-9]+$ && "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
    else
        tmpuc="$(who 2>/dev/null | wc -l | tr -d ' ')"
        [[ "$tmpuc" =~ ^[0-9]+$ && "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
    fi

    if [[ "$virt_type" =~ ^(docker|podman|lxc|lxd|container)$ ]] && [[ "$(ps -p 1 -o comm= 2>/dev/null)" != "systemd" ]]; then
        osinfo[svcr]=""
        osinfo[svct]=""
    elif command -v systemctl >/dev/null 2>&1; then
        osinfo[svcr]="$(systemctl list-units --type=service --state=running 2>/dev/null | grep -c '\.service' | tr -d ' ')"
        osinfo[svct]="$(systemctl list-unit-files --type=service 2>/dev/null | grep -c '\.service' | tr -d ' ')"
        if [[ "${osinfo[svcr]}" == "0" && "${osinfo[svct]}" == "0" ]]; then
            osinfo[svcr]=""
            osinfo[svct]=""
        fi
    elif command -v rc-service >/dev/null 2>&1; then
        osinfo[svcr]="$(rc-service -r 2>/dev/null | wc -l | tr -d ' ')"
        osinfo[svct]="$(rc-service -l 2>/dev/null | wc -l | tr -d ' ')"
    fi

    local osloc=""
    if command -v localectl >/dev/null 2>&1; then
        osloc="$(timeout 2 localectl status 2>/dev/null | awk -F= '/System Locale/ {print $2}' | head -n1)"
    fi
    if [[ -z "$osloc" && -r /etc/locale.conf ]]; then
        osloc="$(grep -E '^(LANG|LC_CTYPE)=' /etc/locale.conf | head -n1 | cut -d= -f2)"
    fi
    if [[ -z "$osloc" ]]; then
        osloc="$(locale 2>/dev/null | awk -F= '/^LANG=/ {print $2}')"
    fi
    osloc="${osloc%\"}"
    osloc="${osloc#\"}"
    if [[ -z "$osloc" || "$osloc" == "C" || "$osloc" == "POSIX" ]]; then
        osinfo[lang]="C"
        osinfo[charset]="UTF-8"
    else
        osinfo[lang]="${osloc%%.*}"
        osinfo[charset]="${osloc#*.}"
        [[ "${osinfo[charset]}" == "$osloc" ]] && osinfo[charset]="UTF-8"
    fi

    osinfo[tz]=""
    if command -v timedatectl >/dev/null 2>&1; then
        local tmptz
        tmptz="$(timeout 2 timedatectl show -p Timezone --value 2>/dev/null)"
        [[ -n "$tmptz" ]] && osinfo[tz]="$tmptz "
    fi
    if [[ -z "${osinfo[tz]}" && -r /etc/timezone ]]; then
        osinfo[tz]="$(cat /etc/timezone) "
    fi
    if [[ -z "${osinfo[tz]}" && -L /etc/localtime ]]; then
        osinfo[tz]="$(readlink /etc/localtime | sed 's|.*/zoneinfo/||') "
    fi
    osinfo[tz_abbr]="$(date +%Z 2>/dev/null)"
    osinfo[tz_offset]="$(date +%z 2>/dev/null)"

    declare -gA meminfo
    case "$virt_type" in
        kvm)
            if lsmod 2>/dev/null | grep -q '^virtio_balloon'; then
                meminfo[balloon]=1
            else
                meminfo[balloon]=0
            fi
            if [[ -r /sys/kernel/mm/ksm/run ]] && [[ "$(cat /sys/kernel/mm/ksm/run)" == "1" ]]; then
                meminfo[ksm]=1
            else
                meminfo[ksm]=0
            fi
            ;;
        lxc|lxd)
            meminfo[neighbor]="$(ls /sys/devices/virtual/block 2>/dev/null | grep -c '^dm')"
            ;;
    esac

    declare -gA diskinfo
    local total used avail p_used p_avail
    read -r total used avail p_used p_avail < <(df -B1 -P 2>/dev/null | awk '
        BEGIN {
            skip["tmpfs"]; skip["devtmpfs"]; skip["udev"]; skip["overlay"]
            skip["shm"]; skip["cgroup"]; skip["cgroup2"]; skip["proc"]
            skip["sysfs"]; skip["debugfs"]; skip["tracefs"]; skip["securityfs"]
            skip["pstore"]; skip["autofs"]; skip["mqueue"]; skip["hugetlbfs"]
            skip["configfs"]; skip["rpc_pipefs"]; skip["binfmt_misc"]
        }
        NR > 1 {
            fs = $1
            if (fs in skip || fs ~ /^fuse\./) next
            size = $2 + 0; used = $3 + 0; avail = $4 + 0
            if (!(fs in seen)) {
                seen[fs] = 1
                T += size; U += used; A += avail
            }
        }
        END {
            if (T > 0)
                printf "%.0f %.0f %.0f %d %d\n", T, U, A, int(U*100/T), int(A*100/T)
        }
    ')
    if [[ -z "$total" || "$total" -le 0 ]]; then
        read -r total used avail p_used < <(df -B1 / 2>/dev/null | awk 'NR==2{print $2,$3,$4,int($3*100/$2)}')
        [[ -n "$p_used" ]] && p_avail=$((100 - p_used))
    fi
    diskinfo[total]="$total"
    diskinfo[used]="$used"
    diskinfo[avail]="$avail"
    diskinfo[p_used]="$p_used"
    diskinfo[p_avail]="$p_avail"

    local ridx=0
    if [[ -r /proc/mdstat ]]; then
        while read -r line; do
            if [[ "$line" =~ ^(md[0-9]+)[[:space:]]*:[[:space:]]*active[[:space:]]+([a-z0-9]+)[[:space:]]+(.*)$ ]]; then
                ((ridx++))
                local rname="${BASH_REMATCH[1]}"
                local rlevel="${BASH_REMATCH[2]}"
                local rdevs="${BASH_REMATCH[3]}"
                rlevel="${rlevel^^}"
                rdevs="$(awk '{for(i=1;i<=NF;i++) if ($i ~ /\[[0-9]+\]/) printf "%s ", $i}' <<<"$rdevs")"
                rdevs="${rdevs% }"
                diskinfo["raid${ridx}.name"]="$rname"
                diskinfo["raid${ridx}.level"]="$rlevel"
                diskinfo["raid${ridx}.devs"]="$rdevs"
                diskinfo["raid${ridx}.mount"]="$(host_get_md_mount "$rname")"
            fi
        done </proc/mdstat
    fi
    diskinfo[raid_count]="$ridx"
}

function write_worker_script() {
    mkdir -p "$work_dir/BenchOs/tmp"
    declare -p osinfo meminfo diskinfo > "$work_dir/BenchOs/tmp/nqenv.sh"

    cat <<'__GB5_WORKER_EOF__' > "$work_dir/BenchOs/tmp/gb5_worker.sh"
#!/bin/bash
script_version="v1.0.0"

Font_B="\033[1m"
Font_I="\033[3m"
Font_U="\033[4m"
Font_Black="\033[30m"
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Cyan="\033[36m"
Font_White="\033[37m"
Back_Red="\033[41m"
Back_Green="\033[42m"
Back_Yellow="\033[43m"
Back_Cyan="\033[46m"
Back_White="\033[47m"
Font_Suffix="\033[0m"
Font_LineClear="\033[2K"

declare IP=""
declare IPhide=""
declare IPdisp=""
declare fullinfo=0
declare YY="cn"
declare IPV4=""
declare IPV6=""
declare opt_ipv=""
declare mode_verbose=0
declare mode_output=0
declare outputfile=""
declare workdir="/"
declare ibar=0
declare bar_pid=""
declare ibar_step=0
declare main_pid=$$
declare PADDING=""
declare rawgithub="https://github.com/xykt/HardwareQuality/raw/"

declare -A osinfo
declare -A cpuinfo
declare -A meminfo
declare -A diskinfo
declare -A sinfo
declare -A shead
declare -A sos
declare -A scpu
declare -A smem
declare -A sdisk
declare -A stail

# Load host pre-fetched environment if present
if [[ -r /tmp/nqenv.sh ]]; then
    source /tmp/nqenv.sh
fi

set_language() {
    case "$YY" in
        "en")
            sinfo[virt]="Detecting Virtualization Information "
            sinfo[os]="Detecting OS Information "
            sinfo[cpu]="Detecting CPU Information "
            sinfo[cpumark]="Geekbench5 CPU "
            sinfo[mem]="Detecting Memory Information "
            sinfo[disk]="Detecting Disk Information "
            sinfo[lvirt]=37
            sinfo[los]=25
            sinfo[lcpu]=26
            sinfo[lcpumark]=15
            sinfo[lmem]=29
            sinfo[ldisk]=27
            shead[title]="GB5 HARDWARE BENCHMARK REPORT: "
            shead[ver]="Version: $script_version"
            shead[bash]="bash <(curl -sL https://github.com/amourxiao/NodeQuality-GB5/raw/main/gb5.sh)"
            shead[git]="https://github.com/amourxiao/NodeQuality-GB5"
            shead[time_raw]="$(date -u +"%Y-%m-%d %H:%M:%S UTC")"
            shead[time]="Report Time: ${shead[time_raw]}"
            shead[ltitle]=31
            shead[ptime]="$(printf '%13s' '')"
            sos[docker]="Docker container"
            sos[podman]="Podman container"
            sos[lxc]="LXC container"
            sos[lxd]="LXD container"
            sos[lxc-libvirt]="LXC (libvirt) container"
            sos[systemd-nspawn]="systemd-nspawn container"
            sos[openvz]="OpenVZ container"
            sos[rkt]="rkt container"
            sos[proot]="proot container"
            sos[pouch]="Pouch container"
            sos[kvm]="KVM virtual machine"
            sos[qemu]="QEMU virtual machine"
            sos[amazon]="Amazon EC2 (Nitro/KVM)"
            sos[vmware]="VMware virtual machine"
            sos[microsoft]="Hyper-V virtual machine"
            sos[xen]="Xen virtual machine"
            sos[oracle]="VirtualBox virtual machine"
            sos[parallels]="Parallels virtual machine"
            sos[bhve]="bhyve virtual machine"
            sos[uml]="User-Mode Linux"
            sos[bochs]="Bochs emulator"
            sos[zvm]="IBM z/VM"
            sos[powervm]="IBM PowerVM"
            sos[qnx]="QNX hypervisor"
            sos[acrn]="ACRN hypervisor"
            sos[apple]="Apple virtualization framework"
            sos[sre]="LMHS SRE hypervisor"
            sos[google]="Google Compute Engine"
            sos[wsl]="Windows Subsystem for Linux (WSL)"
            sos[virtual-machine]="Virtual machine"
            sos[physical-machine]="Physical machine"
            sos[unknown]="Unknown environment"
            sos[title]="1. Operating System Information"
            sos[virt]="Virt type:             "
            sos[arch]="Architecture:          "
            sos[os]="OS / Kernel:           "
            sos[uptime]="Uptime:                "
            sos[load]="Load:                  "
            sos[status]="Processes:             "
            sos[loc]="Regional setting:      "
            sos[d]="days"
            sos[h]="hours"
            sos[m]="minutes"
            sos[q]=", "
            sos[user]="Users"
            sos[proc]="Procs"
            sos[svc]="Run/All services"
            scpu[title]="2. CPU & Geekbench 5 Benchmark"
            scpu[cpu]="CPU:      "
            scpu[cache]="Cache:    "
            scpu[flag]="Features: "
            scpu[temp]="Temp:     "
            scpu[base]="GB5 Base: "
            scpu[single]="Single:   "
            scpu[multi]="Multi:    "
            scpu[url]="Details:  "
            scpu[gb_status]="GB5 Info: "
            scpu[gb_lowmem_ct]="Insufficient memory (<1200MB RAM+Swap) in container; Geekbench 5 skipped."
            scpu[gb_lowdisk]="Insufficient memory and disk space to create temp swap; Geekbench 5 skipped."
            scpu[gb_swapfail]="Insufficient memory and failed to enable temp swap; Geekbench 5 skipped."
            scpu[gb_nobin]="Geekbench 5 binary unavailable on this platform."
            scpu[gb_fail]="Geekbench 5 failed to return valid scores."
            scpu[num]=""
            scpu[step]="Step "
            scpu[gen]=" Gen"
            scpu[core]=" Core"
            scpu[thread]=" Thread"
            scpu[limit1]=" Limit "
            scpu[limit2]=" Procs"
            scpu[usage]="Usage "
            scpu[min]="Idle "
            scpu[max]="Load "
            scpu[lnum]=0
            scpu[lstep]=0
            scpu[lgen]=0
            scpu[lcore]=0
            scpu[lthread]=0
            scpu[llimit]=0
            scpu[lusage]=0
            smem[title]="3. Memory Information"
            smem[mem]="Memory:   "
            smem[swap]="Swap:     "
            smem[reuse]="Overcmmt: "
            smem[nb]="Neighbor: "
            smem[total]="Total"
            smem[used]="Used"
            smem[avail]="Available"
            smem[balloon]="Balloon"
            smem[ksm]="KSM Reuse"
            smem[nbnum]="Containers"
            smem[ltotal]=0
            sdisk[title]="4. Disk Information"
            sdisk[disk]="Disks:    "
            sdisk[count]="Count "
            sdisk[total]="Total "
            sdisk[used]="Used "
            sdisk[avail]="Available "
            sdisk[po]="PwrOn "
            sdisk[times]=""
            sdisk[lf]="Lf"
            sdisk[sp]="Sp"
            sdisk[lcount]=0
            sdisk[ltotal]=0
            sdisk[lused]=0
            sdisk[lavail]=0
            sdisk[lpo]=0
            sdisk[llf]=0
            sdisk[lsp]=0
            stail[note]="Trimmed from NodeQuality & HardwareQuality: Basic Info & Geekbench 5 Only"
            ;;
        *)
            sinfo[virt]="正在获取虚拟化信息"
            sinfo[os]="正在获取操作系统信息"
            sinfo[cpu]="正在获取CPU信息"
            sinfo[cpumark]="Geekbench5 CPU "
            sinfo[mem]="正在获取内存信息"
            sinfo[disk]="正在获取硬盘信息"
            sinfo[lvirt]=18
            sinfo[los]=20
            sinfo[lcpu]=15
            sinfo[lcpumark]=15
            sinfo[lmem]=16
            sinfo[ldisk]=16
            shead[title]="GB5 硬件体检报告："
            shead[ver]="脚本版本：$script_version"
            shead[bash]="bash <(curl -sL https://github.com/amourxiao/NodeQuality-GB5/raw/main/gb5.sh)"
            shead[git]="https://github.com/amourxiao/NodeQuality-GB5"
            shead[time_raw]="$(TZ="Asia/Shanghai" date +"%Y-%m-%d %H:%M:%S CST")"
            shead[time]="报告时间：${shead[time_raw]}"
            shead[ltitle]=18
            shead[ptime]="$(printf '%14s' '')"
            sos[virt]="容器/虚拟化：          "
            sos[arch]="架构：                 "
            sos[os]="操作系统/内核：        "
            sos[uptime]="运行时间：             "
            sos[load]="负载：                 "
            sos[status]="进程：                 "
            sos[loc]="区域设置：             "
            sos[docker]="Docker 容器"
            sos[podman]="Podman 容器"
            sos[lxc]="LXC 容器"
            sos[lxd]="LXD 容器"
            sos[lxc-libvirt]="LXC(libvirt) 容器"
            sos[systemd-nspawn]="systemd-nspawn 容器"
            sos[openvz]="OpenVZ 容器"
            sos[rkt]="rkt 容器"
            sos[proot]="proot 容器"
            sos[pouch]="Pouch 容器"
            sos[kvm]="KVM 虚拟机"
            sos[qemu]="QEMU 虚拟机"
            sos[amazon]="Amazon EC2（Nitro/KVM）"
            sos[vmware]="VMware 虚拟机"
            sos[microsoft]="Hyper-V 虚拟机"
            sos[xen]="Xen 虚拟机"
            sos[oracle]="VirtualBox 虚拟机"
            sos[parallels]="Parallels 虚拟机"
            sos[bhve]="bhyve 虚拟机"
            sos[uml]="User-Mode Linux"
            sos[bochs]="Bochs 模拟器"
            sos[zvm]="IBM z/VM"
            sos[powervm]="IBM PowerVM"
            sos[qnx]="QNX Hypervisor"
            sos[acrn]="ACRN Hypervisor"
            sos[apple]="Apple Virtualization"
            sos[sre]="LMHS SRE Hypervisor"
            sos[google]="Google Compute Engine"
            sos[wsl]="WSL（Windows Subsystem for Linux）"
            sos[virtual-machine]="虚拟机"
            sos[physical-machine]="物理机"
            sos[unknown]="未知环境"
            sos[title]="一、操作系统信息"
            sos[d]="天"
            sos[h]="小时"
            sos[m]="分钟"
            sos[q]="，"
            sos[user]="用户"
            sos[proc]="进程"
            sos[svc]="活跃/总服务"
            scpu[title]="二、CPU与GB5测评"
            scpu[cpu]="CPU：     "
            scpu[cache]="缓存：    "
            scpu[flag]="指令集：  "
            scpu[temp]="温度：    "
            scpu[url]="详细结果："
            scpu[base]="GB5基准： "
            scpu[single]="GB5单核： "
            scpu[multi]="GB5多核： "
            scpu[gb_status]="GB5状态： "
            scpu[gb_lowmem_ct]="可用内存+Swap 小于 1200MB 且容器环境无法挂载临时 Swap，已跳过 GB5 测试"
            scpu[gb_lowdisk]="内存不足且磁盘剩余空间不足以创建临时 Swap，已跳过 GB5 测试"
            scpu[gb_swapfail]="内存不足且临时 Swap 创建失败，已跳过 GB5 测试"
            scpu[gb_nobin]="当前架构不支持或未能安装 Geekbench 5"
            scpu[gb_fail]="Geekbench 5 测试未返回有效分数（请检查网络连通性）"
            scpu[num]="颗"
            scpu[step]="步进"
            scpu[gen]="代"
            scpu[core]="核心"
            scpu[thread]="线程"
            scpu[limit1]="限制"
            scpu[limit2]="进程"
            scpu[usage]="利用率"
            scpu[min]="待机 "
            scpu[max]="负载 "
            scpu[lnum]=1
            scpu[lstep]=2
            scpu[lgen]=1
            scpu[lcore]=2
            scpu[lthread]=2
            scpu[llimit]=4
            scpu[lusage]=3
            smem[title]="三、内存信息"
            smem[mem]="内存：    "
            smem[swap]="交换：    "
            smem[reuse]="超开指标："
            smem[nb]="邻居数量："
            smem[total]="总容量"
            smem[used]="已用"
            smem[avail]="可用"
            smem[balloon]="气球回收"
            smem[ksm]="KSM 复用"
            smem[nbnum]="个容器"
            smem[ltotal]=7
            sdisk[title]="四、硬盘信息"
            sdisk[disk]="硬盘：    "
            sdisk[count]="数量 "
            sdisk[total]="总容量 "
            sdisk[used]="已用容量 "
            sdisk[avail]="可用容量 "
            sdisk[po]="通电"
            sdisk[times]="次"
            sdisk[lf]="寿"
            sdisk[sp]="备"
            sdisk[lcount]=2
            sdisk[ltotal]=3
            sdisk[lused]=4
            sdisk[lavail]=4
            sdisk[lpo]=3
            sdisk[llf]=1
            sdisk[lsp]=1
            stail[note]="基于 NodeQuality & HardwareQuality 裁切，仅保留设备基础信息与 GB5 测试"
            ;;
    esac
}

show_progress_bar() {
    show_progress_bar_ "$@" 1>&2
}

show_progress_bar_() {
    local bar="\u280B\u2819\u2839\u2838\u283C\u2834\u2826\u2827\u2807\u280F"
    local n=${#bar}
    local tmpinfo=""
    local tmplen=$(($2))
    local last_stage=""
    local upload_seen=0
    while sleep 0.1; do
        if ! kill -0 "$main_pid" 2>/dev/null; then
            exit
        fi
        if ((upload_seen == 0)) && [[ -n $3 ]]; then
            while IFS= read -r -t 0.05 line; do
                [[ -z $line ]] && continue
                if [[ $3 -eq 1 ]]; then
                    if [[ $line == *"Uploading results"* ]]; then
                        upload_seen=1
                        break
                    fi
                    case "$line" in
                        *"Running"*) last_stage="${line#"${line%%[![:space:]]*}"}" ;;
                    esac
                fi
            done
        fi
        if ((upload_seen == 0)) && [[ -n $last_stage ]]; then
            tmpinfo="$last_stage"
        else
            tmpinfo=""
        fi
        tmplen=$(($2 - ${#tmpinfo}))
        ((tmplen < 0)) && tmplen=0
        echo -ne "\r${Font_Cyan}${Font_B}[${IPdisp}]# $1$tmpinfo${Font_Cyan}${Font_B}$(printf '%*s' "$tmplen" '' | tr ' ' '.') ${bar:ibar++*6%n:6} $(printf '%02d%%' "$ibar_step") ${Font_Suffix}"
    done
}

kill_progress_bar() {
    kill "$bar_pid" 2>/dev/null && echo -ne "\r${Font_LineClear}" 1>&2
}

adaptoslocale() {
    local ifunicode
    ifunicode=$(printf '\u2800')
    [[ ${#ifunicode} -gt 3 ]] && export LC_CTYPE=en_US.UTF-8 2>/dev/null
}

check_connectivity() {
    local url="https://www.google.com/generate_204"
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "$url" 2>/dev/null)
    if [[ $http_code == "204" ]]; then
        rawgithub="https://github.com/xykt/HardwareQuality/raw/"
        return 0
    else
        rawgithub="https://testingcf.jsdelivr.net/gh/xykt/HardwareQuality@"
        return 1
    fi
}

install_geekbench5() {
    local GB_VER="5.5.1"
    local GB_BASE_URL="https://cdn.geekbench.com"
    local tmpdir arch pkg_arch pkg url
    case "$(uname -m)" in
        x86_64|amd64|i386|i486|i586|i686)
            arch="x86_64/i386"
            pkg_arch="Linux"
            ;;
        aarch64|arm64|armv7l|armv6l)
            arch="ARM"
            pkg_arch="LinuxARMPreview"
            ;;
        *)
            echo "Unsupported architecture for Geekbench 5: $(uname -m)" 1>&2
            return 1
            ;;
    esac
    pkg="Geekbench-${GB_VER}-${pkg_arch}.tar.gz"
    url="${GB_BASE_URL}/${pkg}"
    echo "Downloading Geekbench 5 (${arch})..." 1>&2
    tmpdir="$(mktemp -d)" || return 1
    if ! curl -L --fail -o "$tmpdir/$pkg" "$url"; then
        rm -rf "$tmpdir"
        echo "Failed to download Geekbench 5." 1>&2
        return 1
    fi
    if ! tar -xf "$tmpdir/$pkg" -C /usr/local/bin; then
        rm -rf "$tmpdir"
        echo "Failed to extract Geekbench 5." 1>&2
        return 1
    fi
    rm -rf "$tmpdir"
    local dst_dir="/usr/local/bin/Geekbench-${GB_VER}-${pkg_arch}"
    if [[ ! -d "$dst_dir" ]]; then
        echo "Geekbench 5 directory not found after extraction." 1>&2
        return 1
    fi
    case "$(uname -m)" in
        aarch64|arm64) rm -f "$dst_dir/geekbench_armv7" ;;
        armv7l|armv6l) rm -f "$dst_dir/geekbench_aarch64" ;;
    esac
    chmod +x "$dst_dir/geekbench5"
    ln -sf "$dst_dir/geekbench5" /usr/local/bin/geekbench5
}

install_curl_impersonate() {
    local arch sys_type
    arch="$(uname -m)"
    case "$arch" in
        x86_64)
            if [[ "$(getconf LONG_BIT)" == "32" ]]; then
                sys_type="i386"
            else
                sys_type="x86_64"
            fi
            ;;
        aarch64|arm64) sys_type="aarch64" ;;
        i386|i486|i586|i686) sys_type="i386" ;;
        riscv64) sys_type="riscv64" ;;
        *) return 1 ;;
    esac
    curl -fsL --max-time 30 -o /usr/local/bin/curl-impersonate "${rawgithub}main/ref/curl-impersonate/curl-impersonate-${sys_type}" || return 1
    chmod +x /usr/local/bin/curl-impersonate
}

install_dependencies() {
    local need_pkgs=()
    command -v tar >/dev/null 2>&1 || need_pkgs+=(tar)
    command -v curl >/dev/null 2>&1 || need_pkgs+=(curl)
    command -v lscpu >/dev/null 2>&1 || need_pkgs+=(util-linux)
    command -v dmidecode >/dev/null 2>&1 || need_pkgs+=(dmidecode)
    command -v sensors >/dev/null 2>&1 || need_pkgs+=(lm-sensors)
    command -v smartctl >/dev/null 2>&1 || need_pkgs+=(smartmontools)
    if [[ "$mode_verbose" -eq 1 ]] && ! command -v update-ca-certificates >/dev/null 2>&1; then
        need_pkgs+=(ca-certificates)
    fi

    if ((${#need_pkgs[@]} > 0)) && command -v apt-get >/dev/null 2>&1; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >/dev/null 2>&1 || true
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${need_pkgs[@]}" >/dev/null 2>&1 || true
    fi

    if ! command -v geekbench5 >/dev/null 2>&1; then
        install_geekbench5
    fi

    if [[ "$mode_verbose" -eq 1 ]] && ! command -v curl-impersonate >/dev/null 2>&1; then
        check_connectivity
        install_curl_impersonate || true
    fi
}

get_ipv4() {
    local response p
    IPV4=""
    local API_NET=("myip.check.place" "ip.sb" "icanhazip.com" "api64.ipify.org" "ifconfig.co" "ident.me")
    for p in "${API_NET[@]}"; do
        response="$(curl -s4 --max-time 2 "$p" 2>/dev/null | tr -d '[:space:]')"
        if [[ -n "$response" && "$response" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            IPV4="$response"
            break
        fi
    done
}

hide_ipv4() {
    if [[ -n $1 ]]; then
        IFS='.' read -r -a ip_parts <<<"$1"
        IPhide="${ip_parts[0]}.${ip_parts[1]}.*.*"
    else
        IPhide=""
    fi
}

get_ipv6() {
    local response p
    IPV6=""
    local API_NET=("myip.check.place" "ip.sb" "icanhazip.com" "api64.ipify.org" "ifconfig.co" "ident.me")
    for p in "${API_NET[@]}"; do
        response="$(curl -s6k --max-time 2 "$p" 2>/dev/null | tr -d '[:space:]')"
        if [[ -n "$response" && "$response" == *:* && ! "$response" =~ error ]]; then
            IPV6="$response"
            break
        fi
    done
}

hide_ipv6() {
    if [[ -n $1 ]]; then
        local expanded_ip
        expanded_ip="$(echo "$1" | sed 's/::/:0000:0000:0000:0000:0000:0000:0000:0000:/g' | cut -d ':' -f1-8)"
        IFS=':' read -r -a ip_parts <<<"$expanded_ip"
        while [[ ${#ip_parts[@]} -lt 8 ]]; do
            ip_parts+=(0000)
        done
        IPhide="${ip_parts[0]:-0}:${ip_parts[1]:-0}:${ip_parts[2]:-0}:*:*:*:*:*"
        IPhide="$(echo "$IPhide" | sed 's/:0\{1,\}/:/g' | sed 's/::\+/:/g')"
    else
        IPhide=""
    fi
}

calc_padding() {
    local input_text="$1"
    local total_width=$2
    local title_length=${#input_text}
    local left_padding=$(((total_width - title_length) / 2))
    if [[ $left_padding -gt 0 ]]; then
        PADDING="$(printf '%*s' "$left_padding" '')"
    else
        PADDING=""
    fi
}

detect_virt() {
    local dv_sdv dv_env1 _pn
    [[ -f /.dockerenv ]] && { echo "docker"; return 0; }
    [[ -f /run/.containerenv ]] && { echo "podman"; return 0; }
    if command -v systemd-detect-virt >/dev/null 2>&1; then
        dv_sdv="$(systemd-detect-virt 2>/dev/null)"
        case "$dv_sdv" in
            none|""|chroot) ;;
            *) echo "$dv_sdv"; return 0 ;;
        esac
    fi
    if [[ -r /proc/1/environ ]]; then
        dv_env1="$(tr '\0' '\n' </proc/1/environ 2>/dev/null)"
        case "$dv_env1" in
            *container=lxc*) echo "lxc"; return 0 ;;
            *container=lxd*) echo "lxd"; return 0 ;;
            *container=systemd-nspawn*) echo "systemd-nspawn"; return 0 ;;
        esac
    fi
    if grep -qw hypervisor /proc/cpuinfo 2>/dev/null; then
        if [[ -r /sys/devices/virtual/dmi/id/product_name ]]; then
            _pn="$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)"
            case "$_pn" in
                *VMware*) echo "vmware"; return 0 ;;
                *VirtualBox*) echo "oracle"; return 0 ;;
                *Parallels*) echo "parallels"; return 0 ;;
                *HVM*domU*|*Xen*) echo "xen"; return 0 ;;
                *Amazon*EC2*) echo "amazon"; return 0 ;;
                *Google*Compute*Engine*) echo "google"; return 0 ;;
                *KVM*|*Standard\ PC*|*Q35*|*i440FX*) echo "kvm"; return 0 ;;
                *Microsoft*|*Virtual\ Machine*) echo "microsoft"; return 0 ;;
                *BHYVE*) echo "bhve"; return 0 ;;
                *Bochs*) echo "bochs"; return 0 ;;
            esac
        fi
        echo "virtual-machine"
        return 0
    fi
    echo "physical-machine"
}

classify_virt_kind() {
    case "$1" in
        docker|podman|lxc|lxd|systemd-nspawn|openvz|rkt|proot|pouch) echo "container" ;;
        kvm|qemu|vmware|wsl|microsoft|xen|oracle|parallels|bhve|bochs|amazon|google|virtual-machine) echo "virtual-machine" ;;
        physical-machine) echo "physical-machine" ;;
        *) echo "unknown" ;;
    esac
}

get_virt() {
    local temp_info="${Font_Cyan}${Font_B}${sinfo[virt]}${Font_Suffix}"
    ibar_step=5
    show_progress_bar "$temp_info" $((55 - sinfo[lvirt])) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN
    [[ -z "${osinfo[virt]}" ]] && osinfo[virt]="$(detect_virt)"
    osinfo[virt_kind]="$(classify_virt_kind "${osinfo[virt]}")"
}

calc_uptime() {
    local total_sec
    total_sec="$(awk '{print int($1)}' /proc/uptime 2>/dev/null)"
    [[ -z "$total_sec" ]] && total_sec=0
    osinfo[d]=$((total_sec / 86400))
    osinfo[h]=$(((total_sec % 86400) / 3600))
    osinfo[m]=$(((total_sec % 3600) / 60))
}

colorize_load() {
    local lv="$1"
    local cores="$2"
    awk -v l="$lv" -v c="$cores" \
        -v R="$Font_Red" -v Y="$Font_Yellow" -v G="$Font_Green" -v S="$Font_Suffix" '
        BEGIN {
            if (l < c)
                printf "%s%.2f%s", G, l, S
            else if (l < 2*c)
                printf "%s%.2f%s", Y, l, S
            else
                printf "%s%.2f%s", R, l, S
        }'
}

get_os() {
    local temp_info="${Font_Cyan}${Font_B}${sinfo[os]}${Font_Suffix}"
    ibar_step=15
    show_progress_bar "$temp_info" $((55 - sinfo[los])) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN

    [[ -z "${osinfo[os]}" ]] && osinfo[os]="$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '"')"
    osinfo[kernel]="$(uname -r)"
    osinfo[arch]="$(uname -m)"
    calc_uptime

    if [[ -r /proc/loadavg ]]; then
        read -r osinfo[load1] osinfo[load5] osinfo[load15] _ </proc/loadavg
    else
        read -r osinfo[load1] osinfo[load5] osinfo[load15] <<<"$(LC_ALL=C uptime | awk -F'load average:' '{gsub(/^[[:space:]]+/, "", $2); gsub(/,/, "", $2); print $2}')"
    fi
    local cpu_cores
    cpu_cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null)"
    [[ -z "$cpu_cores" || ! "$cpu_cores" =~ ^[0-9]+$ ]] && cpu_cores=1
    sos[load1]="$(colorize_load "${osinfo[load1]:-0}" "$cpu_cores")"
    sos[load5]="$(colorize_load "${osinfo[load5]:-0}" "$cpu_cores")"
    sos[load15]="$(colorize_load "${osinfo[load15]:-0}" "$cpu_cores")"

    if [[ -z "${osinfo[user]}" ]]; then
        local tmpuc=""
        if command -v loginctl >/dev/null 2>&1; then
            tmpuc="$(loginctl list-users 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')"
            [[ "$tmpuc" =~ ^[0-9]+$ && "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
        else
            tmpuc="$(who 2>/dev/null | wc -l | tr -d ' ')"
            [[ "$tmpuc" =~ ^[0-9]+$ && "$tmpuc" -gt 0 ]] && osinfo[user]="$tmpuc"
        fi
    fi
    [[ -z "${osinfo[proc]}" ]] && osinfo[proc]="$(ps -e 2>/dev/null | wc -l | tr -d ' ')"
    [[ "${osinfo[proc]}" =~ ^[0-9]+$ && "${osinfo[proc]}" -gt 0 ]] && osinfo[proc]=$((osinfo[proc] - 1))

    if [[ -z "${osinfo[lang]}" ]]; then
        osinfo[lang]="C"
        osinfo[charset]="UTF-8"
    fi
    if [[ -z "${osinfo[tz_abbr]}" ]]; then
        osinfo[tz_abbr]="$(date +%Z 2>/dev/null)"
        osinfo[tz_offset]="$(date +%z 2>/dev/null)"
    fi
}

get_cgroup_cpu_and_pids() {
    local cpuset quota period pids
    if [[ -r /sys/fs/cgroup/cpuset.cpus ]]; then
        cpuset=$(</sys/fs/cgroup/cpuset.cpus)
    elif [[ -r /sys/fs/cgroup/cpuset/cpuset.cpus ]]; then
        cpuset=$(</sys/fs/cgroup/cpuset/cpuset.cpus)
    fi
    if [[ -n "$cpuset" ]]; then
        local total=0 p
        IFS=',' read -ra parts <<<"$cpuset"
        for p in "${parts[@]}"; do
            if [[ "$p" == *-* ]]; then
                total=$((total + ${p#*-} - ${p%-*} + 1))
            elif [[ -n "$p" ]]; then
                total=$((total + 1))
            fi
        done
        echo "$total"
    else
        if [[ -r /sys/fs/cgroup/cpu.max ]]; then
            read -r quota period </sys/fs/cgroup/cpu.max
            [[ "$quota" != "max" && "$period" -gt 0 ]] && printf '%.1f\n' "$(awk "BEGIN{print $quota/$period}")"
        elif [[ -r /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]]; then
            quota=$(</sys/fs/cgroup/cpu/cpu.cfs_quota_us)
            period=$(</sys/fs/cgroup/cpu/cpu.cfs_period_us)
            ((quota > 0 && period > 0)) && printf '%.1f\n' "$(awk "BEGIN{print $quota/$period}")"
        fi
    fi
    if [[ -r /sys/fs/cgroup/pids.max ]]; then
        pids=$(</sys/fs/cgroup/pids.max)
    elif [[ -r /sys/fs/cgroup/pids/pids.max ]]; then
        pids=$(</sys/fs/cgroup/pids/pids.max)
    fi
    [[ -n "$pids" && "$pids" != "max" ]] && echo "pids=$pids"
}

get_cpu() {
    local temp_info="${Font_Cyan}${Font_B}${sinfo[cpu]}${Font_Suffix}"
    ibar_step=25
    show_progress_bar "$temp_info" $((55 - sinfo[lcpu])) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN

    local lscpu_out proc_cpuinfo
    lscpu_out="$(LC_ALL=C lscpu 2>/dev/null)"
    proc_cpuinfo="$(</proc/cpuinfo)"

    cpuinfo[arch]="$(awk -F: '/Architecture/{print $2}' <<<"$lscpu_out" | xargs)"
    [[ -z "${cpuinfo[arch]}" ]] && cpuinfo[arch]="$(uname -m)"

    cpuinfo[name]="$(awk -F: '/^Model name[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    [[ -z "${cpuinfo[name]}" ]] && cpuinfo[name]="$(awk -F': +' '/model name/{print $2; exit}' <<<"$proc_cpuinfo")"
    cpuinfo[name]="${cpuinfo[name]//(R)/}"
    cpuinfo[name]="${cpuinfo[name]//(TM)/}"
    cpuinfo[name]="${cpuinfo[name]//CPU /}"
    cpuinfo[name]="${cpuinfo[name]//w\/ /}"

    cpuinfo[op_mode]="$(awk -F: '/^CPU op-mode\(s\)[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    [[ "${cpuinfo[op_mode]}" == *"32-bit"* && "${cpuinfo[op_mode]}" == *"64-bit"* ]] && cpuinfo[op_mode]="32/64-bit"
    if [[ -z "${cpuinfo[op_mode]}" ]]; then
        case "${cpuinfo[arch]}" in
            x86_64) cpuinfo[op_mode]="32/64-bit" ;;
            aarch64|ppc64*|riscv64) cpuinfo[op_mode]="64-bit" ;;
            i[3-6]86|armv7*|armv6*) cpuinfo[op_mode]="32-bit" ;;
        esac
    fi

    cpuinfo[family]="$(awk -F: '/^CPU family[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    [[ -z "${cpuinfo[family]}" ]] && cpuinfo[family]="$(awk -F': +' '/cpu family/{print $2; exit}' <<<"$proc_cpuinfo")"

    cpuinfo[stepping]="$(awk -F: '/^Stepping[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    [[ -z "${cpuinfo[stepping]}" ]] && cpuinfo[stepping]="$(awk -F': +' '/stepping/{print $2; exit}' <<<"$proc_cpuinfo")"

    cpuinfo[sockets]="$(awk -F: '/^Socket\(s\)[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    if [[ -z "${cpuinfo[sockets]}" || "${cpuinfo[sockets]}" == "0" ]]; then
        cpuinfo[sockets]="$(awk -F': +' '/physical id/{print $2}' <<<"$proc_cpuinfo" | sort -u | wc -l)"
        [[ "${cpuinfo[sockets]}" -eq 0 ]] && cpuinfo[sockets]=1
    fi

    cpuinfo[cores_per_socket]="$(awk -F: '/^Core\(s\) per socket[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    [[ -z "${cpuinfo[cores_per_socket]}" ]] && cpuinfo[cores_per_socket]="$(awk -F': +' '/cpu cores/{print $2; exit}' <<<"$proc_cpuinfo")"

    cpuinfo[threads_per_core]="$(awk -F: '/^Thread\(s\) per core[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    if [[ -z "${cpuinfo[threads_per_core]}" ]]; then
        local logical physical
        logical="$(grep -c '^processor' <<<"$proc_cpuinfo")"
        physical=$((cpuinfo[sockets] * ${cpuinfo[cores_per_socket]:-0}))
        [[ $physical -gt 0 ]] && cpuinfo[threads_per_core]=$((logical / physical))
        [[ -z "${cpuinfo[threads_per_core]}" || "${cpuinfo[threads_per_core]}" -eq 0 ]] && cpuinfo[threads_per_core]=1
    fi

    if [[ -n "${cpuinfo[sockets]}" && -n "${cpuinfo[cores_per_socket]}" ]] && ((cpuinfo[sockets] > 0 && cpuinfo[cores_per_socket] > 0)); then
        cpuinfo[cores]=$((cpuinfo[sockets] * cpuinfo[cores_per_socket]))
    else
        cpuinfo[cores]="$(grep -c '^processor' <<<"$proc_cpuinfo")"
    fi
    if [[ -n "${cpuinfo[cores]}" && -n "${cpuinfo[threads_per_core]}" ]] && ((cpuinfo[cores] > 0 && cpuinfo[threads_per_core] > 0)); then
        cpuinfo[threads]=$((cpuinfo[cores] * cpuinfo[threads_per_core]))
    fi

    local cginfo cgcores
    cginfo="$(get_cgroup_cpu_and_pids)"
    if [[ -n "$cginfo" ]]; then
        cgcores="$(grep -v '^pids=' <<<"$cginfo" | head -n1)"
        [[ -n "$cgcores" ]] && cpuinfo[cores]="$cgcores"
        cpuinfo[cg_threads]="$(grep '^pids=' <<<"$cginfo" | cut -d= -f2)"
    fi

    cpuinfo[mhz]="$(awk -F: '/^CPU MHz[[:space:]]*:/{print $2}' <<<"$lscpu_out" | xargs)"
    cpuinfo[min_mhz]="$(awk -F: '/^CPU min MHz[[:space:]]*:/{printf "%d", $2}' <<<"$lscpu_out")"
    cpuinfo[max_mhz]="$(awk -F: '/^CPU max MHz[[:space:]]*:/{printf "%d", $2}' <<<"$lscpu_out")"
    [[ -z "${cpuinfo[mhz]}" ]] && cpuinfo[mhz]="$(awk -F': +' '/cpu MHz/{print $2; exit}' <<<"$proc_cpuinfo")"

    local _cpu a b c idle rest total1 idle1 total2 idle2
    read -r _cpu a b c idle rest </proc/stat
    total1=$((a + b + c + idle))
    idle1=$idle
    sleep 1
    read -r _cpu a b c idle rest </proc/stat
    total2=$((a + b + c + idle))
    idle2=$idle
    cpuinfo[usage]="$(awk -v t1="$total1" -v t2="$total2" -v i1="$idle1" -v i2="$idle2" '
        BEGIN {
            if (t2 > t1) {
                usage = (1 - (i2 - i1) / (t2 - t1)) * 100
                if (usage < 0) usage = 0
                printf "%d", usage + 0.5
            } else {
                printf "0"
            }
        }')"

    cpuinfo[L1d]="$(awk -F: '/^L1d cache[[:space:]]*:/{print $2}' <<<"$lscpu_out" | sed 's/([^)]*)//g' | xargs)"
    cpuinfo[L1i]="$(awk -F: '/^L1i cache[[:space:]]*:/{print $2}' <<<"$lscpu_out" | sed 's/([^)]*)//g' | xargs)"
    cpuinfo[L2]="$(awk -F: '/^L2 cache[[:space:]]*:/{print $2}' <<<"$lscpu_out" | sed 's/([^)]*)//g' | xargs)"
    cpuinfo[L3]="$(awk -F: '/^L3 cache[[:space:]]*:/{print $2}' <<<"$lscpu_out" | sed 's/([^)]*)//g' | xargs)"
    if [[ -z "${cpuinfo[L1d]}${cpuinfo[L1i]}${cpuinfo[L2]}${cpuinfo[L3]}" ]]; then
        local cache_kb
        cache_kb="$(awk -F': +' '/cache size/{print $2; exit}' <<<"$proc_cpuinfo")"
        if [[ -n "$cache_kb" && -n "${cpuinfo[cores_per_socket]}" ]]; then
            local cores total_kb
            cores=$((cpuinfo[sockets] * cpuinfo[cores_per_socket]))
            total_kb=$((${cache_kb% *} * cores))
            cpuinfo[cache_total]="${total_kb} KB"
            cpuinfo[cache_fallback]=1
        fi
    fi

    cpuinfo[flags]="$(awk -F: '/^Flags[[:space:]]*:/{print $2}' <<<"$lscpu_out")"
    [[ -z "${cpuinfo[flags]}" ]] && cpuinfo[flags]="$(awk -F': +' '/^(flags|Features)/{print $2; exit}' <<<"$proc_cpuinfo")"
    if [[ "${cpuinfo[arch]}" =~ x86_64|i[3-6]86 ]]; then
        cpuinfo[vt]="$([[ "${cpuinfo[flags]}" =~ vmx|svm ]] && echo 1)"
        cpuinfo[aes]="$([[ "${cpuinfo[flags]}" =~ aes ]] && echo 1)"
        cpuinfo[avx2]="$([[ "${cpuinfo[flags]}" =~ avx2 ]] && echo 1)"
        cpuinfo[bmi]="$([[ "${cpuinfo[flags]}" =~ bmi1|bmi2 ]] && echo 1)"
        cpuinfo[ept]="$([[ "${cpuinfo[flags]}" =~ ept|npt ]] && echo 1)"
    else
        cpuinfo[el2]="$([[ "${cpuinfo[flags]}" =~ el2 ]] && echo 1)"
        cpuinfo[neon]="$([[ "${cpuinfo[flags]}" =~ neon|asimd ]] && echo 1)"
        cpuinfo[aes_sha]="$([[ "${cpuinfo[flags]}" =~ aes|sha ]] && echo 1)"
        cpuinfo[atomics]="$([[ "${cpuinfo[flags]}" =~ atomics ]] && echo 1)"
        cpuinfo[sve]="$([[ "${cpuinfo[flags]}" =~ sve ]] && echo 1)"
    fi
}

echo_cpu_temp() {
    declare -A min_temp
    declare -A max_temp
    local interval="${1:-5}"
    while :; do
        local found=0 zone type t
        for zone in /sys/class/thermal/thermal_zone*; do
            [[ -r "$zone/type" && -r "$zone/temp" ]] || continue
            type=$(<"$zone/type")
            [[ "$type" =~ cpu|CPU|pkg|core|soc|x86 ]] || continue
            t=$(($(<"$zone/temp") / 1000))
            [[ $t -le 0 ]] && continue
            ((min_temp[0] == 0 || t < min_temp[0])) && min_temp[0]=$t
            ((t > max_temp[0])) && max_temp[0]=$t
            found=1
        done
        if ((found == 0)) && command -v sensors &>/dev/null; then
            local tctl
            tctl="$(sensors 2>/dev/null | awk '/Tctl:/ {gsub(/[^0-9.]/,"",$2); print int($2); exit}')"
            if [[ -n "$tctl" && "$tctl" -gt 0 ]]; then
                ((min_temp[0] == 0 || tctl < min_temp[0])) && min_temp[0]=$tctl
                ((tctl > max_temp[0])) && max_temp[0]=$tctl
                found=1
            fi
            if ((found == 0)); then
                local max_core=0 v
                while read -r v; do
                    [[ "$v" -gt "$max_core" ]] && max_core="$v"
                done < <(sensors 2>/dev/null | awk '
                    /Core [0-9]+:|Package id/ {
                        if (match($0, /\+[0-9.]+°C/)) {
                            t=$0
                            sub(/.*\+/,"",t)
                            sub(/°C.*/,"",t)
                            print int(t)
                        }
                    }')
                if ((max_core > 0)); then
                    ((min_temp[0] == 0 || max_core < min_temp[0])) && min_temp[0]=$max_core
                    ((max_core > max_temp[0])) && max_temp[0]=$max_core
                    found=1
                fi
            fi
        fi
        local out="[" i
        for i in "${!min_temp[@]}"; do
            out+="$i=${min_temp[$i]}/${max_temp[$i]} "
        done
        out="${out% }]"
        echo "$out"
        sleep "$interval"
    done
}

parse_geekbench_cpu_html() {
    local html="$1"
    [[ -z "$html" ]] && return 1
    _gb_key() {
        echo "$1" | sed -E '
            s/<[^>]+>//g;
            s/^[[:space:]]+|[[:space:]]+$//g;
            s/[[:space:]]+/_/g
        '
    }
    local mode="" name="" score="" desc="" pct="" line name_line l score_line
    while IFS= read -r line; do
        [[ "$line" =~ \<h3\>Single-Core\ Performance\<\/h3\> ]] && { mode="s"; continue; }
        [[ "$line" =~ \<h3\>Multi-Core\ Performance\<\/h3\> ]] && { mode="m"; continue; }
        [[ -z "$mode" ]] && continue
        if [[ "$line" =~ \<td\ class=\'name\'\> ]]; then
            read -r name_line
            name="$(_gb_key "$name_line")"
            desc=""
            pct=""
            continue
        fi
        if [[ "$line" =~ \<td\ class=\'score\'\> ]]; then
            score=""
            desc=""
            while IFS= read -r l; do
                if [[ -z "$score" && "$l" =~ ^[[:space:]]*[0-9]+[[:space:]]*$ ]]; then
                    score="$(sed 's/[^0-9]//g' <<<"$l")"
                fi
                if [[ "$l" =~ \<span\ class=\'description\'\> ]]; then
                    desc="$(sed -E 's/<[^>]+>//g; s/^[[:space:]]+|[[:space:]]+$//g' <<<"$l")"
                fi
                [[ "$l" =~ \<\/td\> ]] && break
            done
            continue
        fi
        if [[ "$line" =~ benchmark-bar ]]; then
            if [[ "$line" =~ width:([0-9]+)% ]]; then
                pct="${BASH_REMATCH[1]}"
            fi
            if [[ -n "$name" && -n "$score" ]]; then
                cpuinfo["gb.$mode.i.$name"]="$score"
                [[ -n "$desc" ]] && cpuinfo["gb.$mode.i.$name.desc"]="$desc"
                [[ -n "$pct" ]] && cpuinfo["gb.$mode.i.$name.pct"]="$pct"
            fi
            name="" score="" desc="" pct=""
            continue
        fi
        if [[ "$line" =~ \<tr\ class=\'stacked-heading\'\> ]]; then
            read -r _
            read -r name_line
            read -r _
            read -r _
            read -r score_line
            local gname gscore
            gname="$(_gb_key "$name_line")"
            gscore="$(sed 's/[^0-9]//g' <<<"$score_line")"
            if [[ "$gname" == "Single-Core_Score" || "$gname" == "Multi-Core_Score" ]]; then
                continue
            fi
            [[ -n "$gname" && -n "$gscore" ]] && cpuinfo["gb.$mode.g.$gname"]="$gscore"
        fi
    done <<<"$html"
}

test_cpu_gb5() {
    if ! command -v geekbench5 &>/dev/null; then
        cpuinfo[gb_err]="${scpu[gb_nobin]}"
        return
    fi

    local mem_avail_mb swap_free_mb
    mem_avail_mb="$(awk '/MemAvailable:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)"
    swap_free_mb="$(awk '/SwapFree:/ {print int($2/1024)}' /proc/meminfo 2>/dev/null)"
    [[ "$mem_avail_mb" =~ ^[0-9]+$ ]] || mem_avail_mb=0
    [[ "$swap_free_mb" =~ ^[0-9]+$ ]] || swap_free_mb=0

    local need_swap=0
    local swap_file=""
    local target_total_mb=1200

    if ((mem_avail_mb < 950 && mem_avail_mb + swap_free_mb < target_total_mb)); then
        if [[ "${osinfo[virt_kind]}" == "container" || "${osinfo[virt_kind]}" == "unknown" ]]; then
            cpuinfo[gb_err]="${scpu[gb_lowmem_ct]}"
            return
        fi
        local create_mb=$((target_total_mb - mem_avail_mb - swap_free_mb))
        ((create_mb < 128)) && create_mb=128
        local avail_disk_mb
        avail_disk_mb="$(df -Pm "$workdir" 2>/dev/null | awk 'NR==2 {print $4}')"
        if ! [[ "$avail_disk_mb" =~ ^[0-9]+$ ]] || ((avail_disk_mb < create_mb + 100)); then
            cpuinfo[gb_err]="${scpu[gb_lowdisk]}"
            return
        fi
        swap_file="${workdir%/}/.gb5_tmp.swap"
        local swap_ok=0
        if fallocate -l "${create_mb}M" "$swap_file" 2>/dev/null; then
            if chmod 600 "$swap_file" && mkswap "$swap_file" >/dev/null 2>&1 && swapon "$swap_file" >/dev/null 2>&1; then
                swap_ok=1
            else
                rm -f "$swap_file"
            fi
        fi
        if ((swap_ok == 0)); then
            if dd if=/dev/zero of="$swap_file" bs=1M count="$create_mb" status=none 2>/dev/null \
                && chmod 600 "$swap_file" \
                && mkswap "$swap_file" >/dev/null 2>&1 \
                && swapon "$swap_file" >/dev/null 2>&1; then
                swap_ok=1
            else
                rm -f "$swap_file"
            fi
        fi
        if ((swap_ok == 1)); then
            need_swap=1
        else
            cpuinfo[gb_err]="${scpu[gb_swapfail]}"
            return
        fi
    fi

    local fd3_open=0 fd4_open=0 test_on=0 test_pid=""
    cleanup_local() {
        [[ -n "$PROG_BAR_PID" ]] && kill "$PROG_BAR_PID" 2>/dev/null
        [[ -n "$test_pid" && "$test_on" -eq 1 ]] && kill "$test_pid" 2>/dev/null
        if [[ "$need_swap" -eq 1 ]]; then
            swapoff "$swap_file" 2>/dev/null
            [[ -n "$swap_file" ]] && rm -f "$swap_file"
        fi
        ((fd3_open)) && exec 3<&-
        ((fd4_open)) && exec 4>&-
        trap - INT TERM
        echo -ne "\r${Font_LineClear}" 1>&2
    }
    on_int() {
        cleanup_local
        exit 130
    }
    on_term() {
        cleanup_local
        exit 143
    }
    trap cleanup_local RETURN
    trap on_int INT
    trap on_term TERM

    local temp_info="${Font_Cyan}${Font_B}${sinfo[cpumark]}"
    ibar_step=40
    coproc PROG_BAR {
        show_progress_bar "$temp_info" $((55 - sinfo[lcpumark])) 1
    }
    exec 4>&"${PROG_BAR[1]}"
    fd4_open=1

    local last_line=""
    exec 3< <(echo_cpu_temp 5)
    fd3_open=1
    test_pid=$!
    test_on=1

    local url="" single_score="" multi_score="" tmpresu="" attempt
    url="$(geekbench5 --cpu 2>&1 | tee >(cat >&4) | grep -oE 'https://browser\.geekbench\.com/v5/cpu/[0-9]+' | head -n 1)"
    if [[ -n "$url" ]]; then
        cpuinfo[url]="$url"
        if [[ "$mode_verbose" -eq 1 ]] && command -v curl-impersonate >/dev/null 2>&1; then
            for ((attempt = 1; attempt <= 5; attempt++)); do
                tmpresu="$(curl-impersonate -s --compressed --impersonate "chrome146" "$url" 2>/dev/null)"
                if [[ -n "$tmpresu" ]] && grep -q "<div class='score'>" <<<"$tmpresu"; then
                    break
                fi
                sleep 1
            done
            if [[ -n "$tmpresu" ]] && grep -q "<div class='score'>" <<<"$tmpresu"; then
                parse_geekbench_cpu_html "$tmpresu"
                local scores=()
                mapfile -t scores < <(echo "$tmpresu" | grep -o "<div class='score'>[0-9]\+</div>" | sed 's/[^0-9]//g')
                single_score="${scores[0]}"
                multi_score="${scores[1]}"
            fi
        fi
        if [[ -z "$single_score" || -z "$multi_score" ]]; then
            for ((attempt = 1; attempt <= 5; attempt++)); do
                tmpresu="$(curl -sL --max-time 15 "${url}.csv" 2>/dev/null | tr -d '\r')"
                single_score="$(awk -F',' '/^Single-Core,/{print $2; exit}' <<<"$tmpresu" | tr -dc '0-9')"
                multi_score="$(awk -F',' '/^Multi-Core,/{print $2; exit}' <<<"$tmpresu" | tr -dc '0-9')"
                if [[ -n "$single_score" && -n "$multi_score" ]]; then
                    break
                fi
                sleep 1
            done
        fi
    fi

    if [[ -n "$single_score" && -n "$multi_score" ]]; then
        cpuinfo[geekbench_single]="$single_score"
        cpuinfo[geekbench_multi]="$multi_score"
    else
        cpuinfo[gb_err]="${scpu[gb_fail]}"
    fi

    [[ -n "$test_pid" ]] && kill "$test_pid" 2>/dev/null && test_on=0
    local line item idx val tmin tmax
    while read -r -t 1 line <&3; do
        last_line="$line"
    done
    cpuinfo[temp_count]=0
    cpuinfo[temp_min]=-1
    cpuinfo[temp_max]=-1
    for item in ${last_line#[}; do
        item="${item%]}"
        idx="${item%%=*}"
        val="${item#*=}"
        tmin="${val%/*}"
        tmax="${val#*/}"
        [[ "$tmin" =~ ^[0-9]+$ ]] || continue
        [[ "$tmax" =~ ^[0-9]+$ ]] || continue
        [[ -z "${cpuinfo[temp${idx}_min]}" || "${cpuinfo[temp${idx}_min]}" -gt "$tmin" ]] && cpuinfo[temp${idx}_min]="$tmin"
        [[ -z "${cpuinfo[temp${idx}_max]}" || "${cpuinfo[temp${idx}_max]}" -lt "$tmax" ]] && cpuinfo[temp${idx}_max]="$tmax"
        ((cpuinfo[temp_count]++))
        if ((cpuinfo[temp_min] < 0 || tmin < cpuinfo[temp_min])); then
            cpuinfo[temp_min]=$tmin
        fi
        if ((cpuinfo[temp_max] < 0 || tmax > cpuinfo[temp_max])); then
            cpuinfo[temp_max]=$tmax
        fi
    done
}

get_mem() {
    local temp_info="${Font_Cyan}${Font_B}${sinfo[mem]}${Font_Suffix}"
    ibar_step=85
    show_progress_bar "$temp_info" $((55 - sinfo[lmem])) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN

    local idx=0 ch line cur size unit val
    meminfo[count]=0
    if command -v lscpu >/dev/null 2>&1; then
        ch="$(lscpu 2>/dev/null | awk -F: 'tolower($1) ~ /channel/ {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | head -n1)"
        [[ "$ch" =~ ^[0-9]+$ ]] && meminfo[mem_channels]="$ch"
    fi
    if command -v dmidecode >/dev/null 2>&1 && [[ $EUID -eq 0 ]] && [[ "${osinfo[virt]}" == "physical-machine" ]]; then
        while IFS= read -r line; do
            case "$line" in
                "Memory Device")
                    cur="mem$idx"
                    ((idx++))
                    ;;
                *"Size:"*)
                    if [[ "$line" =~ ^[[:space:]]*Size:[[:space:]]+([0-9]+)[[:space:]]+(MB|GB)$ ]]; then
                        size="${BASH_REMATCH[1]}"
                        unit="${BASH_REMATCH[2]}"
                        [[ "$size" == "No" || "$size" == "None" ]] && continue
                        meminfo[$cur.size]="${size}${unit}"
                    fi
                    ;;
                *"Bank Locator:"*)
                    val="${line#*: }"
                    val="${val#"${val%%[![:space:]]*}"}"
                    val="${val%"${val##*[![:space:]]}"}"
                    val="$(echo "$val" | tr 'a-z' 'A-Z' | sed -E 's/CPU/p/g; s/NODE/n/g; s/CHANNEL/ch/g; s/DIMM/d/g; s/^[[:space:]]*P([^A-Z])/p\1/; s/\b([A-Z])([A-Z]+)\b/\L\1/g; s/[ _-]//g')"
                    meminfo[$cur.slot]="$val"
                    ;;
                *"Type:"*)
                    val="${line#*: }"
                    val="${val#"${val%%[![:space:]]*}"}"
                    val="${val%"${val##*[![:space:]]}"}"
                    meminfo[$cur.type]="$val"
                    ;;
                *"Manufacturer:"*)
                    val="${line#*: }"
                    val="${val#"${val%%[![:space:]]*}"}"
                    val="${val%"${val##*[![:space:]]}"}"
                    meminfo[$cur.vendor]="$val"
                    ;;
                *"Serial Number:"*)
                    val="${line#*: }"
                    val="${val#"${val%%[![:space:]]*}"}"
                    val="${val%"${val##*[![:space:]]}"}"
                    meminfo[$cur.serial]="$val"
                    ;;
                *"Part Number:"*)
                    val="${line#*: }"
                    val="${val#"${val%%[![:space:]]*}"}"
                    val="${val%"${val##*[![:space:]]}"}"
                    meminfo[$cur.part]="$val"
                    ;;
                *"Configured Memory Speed:"*) : ;;
                *"Speed:"*)
                    val="${line#*: }"
                    meminfo[$cur.speed]="$(echo "$val" | grep -oE '[0-9]+' | head -n1)"
                    ;;
            esac
        done < <(dmidecode -t memory 2>/dev/null)
        meminfo[count]="$idx"
    fi

    if [[ -r /proc/meminfo ]]; then
        local key
        while read -r key val _; do
            case "$key" in
                MemTotal:) meminfo[mem_total_kb]="$val" ;;
                MemAvailable:) meminfo[mem_avail_kb]="$val" ;;
                SwapTotal:) meminfo[swap_total_kb]="$val" ;;
                SwapFree:) meminfo[swap_avail_kb]="$val" ;;
            esac
        done </proc/meminfo
        meminfo[mem_used_kb]=$((meminfo[mem_total_kb] - meminfo[mem_avail_kb]))
        meminfo[total]="$(awk -v t="${meminfo[mem_total_kb]}" 'BEGIN { if (t < 1024*1024) printf "%.0f MB", t/1024; else printf "%.1f GB", t/1024/1024 }')"
        meminfo[used]="$(awk -v u="${meminfo[mem_used_kb]}" -v t="${meminfo[mem_total_kb]}" 'BEGIN { if (t < 1024*1024) printf "%.0f MB", u/1024; else printf "%.1f GB", u/1024/1024 }')"
        meminfo[avail]="$(awk -v a="${meminfo[mem_avail_kb]}" -v t="${meminfo[mem_total_kb]}" 'BEGIN { if (t < 1024*1024) printf "%.0f MB", a/1024; else printf "%.1f GB", a/1024/1024 }')"
        if ((meminfo[mem_total_kb] > 0)); then
            meminfo[mem_used_pct]="$(awk -v u="${meminfo[mem_used_kb]}" -v t="${meminfo[mem_total_kb]}" 'BEGIN{printf "%.0f", u*100/t}')"
            meminfo[mem_avail_pct]=$((100 - meminfo[mem_used_pct]))
        fi
        if ((meminfo[swap_total_kb] > 0)); then
            meminfo[swap_used_kb]=$((meminfo[swap_total_kb] - meminfo[swap_avail_kb]))
            meminfo[swap_total]="$(awk -v t="${meminfo[swap_total_kb]}" 'BEGIN { if (t < 1024*1024) printf "%.0f MB", t/1024; else printf "%.1f GB", t/1024/1024 }')"
            meminfo[swap_used]="$(awk -v u="${meminfo[swap_used_kb]}" -v t="${meminfo[swap_total_kb]}" 'BEGIN { if (t < 1024*1024) printf "%.0f MB", u/1024; else printf "%.1f GB", u/1024/1024 }')"
            meminfo[swap_avail]="$(awk -v a="${meminfo[swap_avail_kb]}" -v t="${meminfo[swap_total_kb]}" 'BEGIN { if (t < 1024*1024) printf "%.0f MB", a/1024; else printf "%.1f GB", a/1024/1024 }')"
            meminfo[swap_used_pct]="$(awk -v u="${meminfo[swap_used_kb]}" -v t="${meminfo[swap_total_kb]}" 'BEGIN{printf "%.0f", u*100/t}')"
            meminfo[swap_avail_pct]=$((100 - meminfo[swap_used_pct]))
        fi
    fi

    if [[ -z "${meminfo[balloon]}" && -z "${meminfo[neighbor]}" ]]; then
        case "${osinfo[virt]}" in
            kvm)
                if lsmod 2>/dev/null | grep -q '^virtio_balloon'; then
                    meminfo[balloon]=1
                else
                    meminfo[balloon]=0
                fi
                if [[ -r /sys/kernel/mm/ksm/run ]] && [[ "$(cat /sys/kernel/mm/ksm/run)" == "1" ]]; then
                    meminfo[ksm]=1
                else
                    meminfo[ksm]=0
                fi
                ;;
            lxc|lxd)
                meminfo[neighbor]="$(ls /sys/devices/virtual/block 2>/dev/null | grep -c '^dm')"
                ;;
        esac
    fi
}

fmt_bytes() {
    local v="$1"
    [[ -z "$v" || "$v" -le 0 ]] && return
    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec "$v"
    else
        awk -v b="$v" '
            BEGIN {
                split("B KB MB GB TB PB EB", u, " ")
                i=1
                while (b>=1024 && i<length(u)) { b/=1024; i++ }
                if (b>=10) printf "%.0f%s", b, u[i]
                else printf "%.1f%s", b, u[i]
            }'
    fi
}

fmt_rw() {
    local b="$1"
    [[ -z "$b" ]] && return
    awk -v b="$b" '
        BEGIN {
            if (b+0 <= 0) exit
            tb = 1024*1024*1024*1024
            gb = 1024*1024*1024
            if (b >= tb) printf "%dTB", int(b/tb + 0.5)
            else printf "%dGB", int(b/gb + 0.5)
        }'
}

parse_sata_rw() {
    local id="$1"
    local smart_all="$2"
    awk -v id="$id" '
        $1==id {
            name=$2; raw=$NF; unit=1
            if (index(name, "_") > 0) {
                split(name, p, "_")
                last=p[length(p)]
                num=""; suf=""
                for (i=1; i<=length(last); i++) {
                    c=substr(last, i, 1)
                    if (c >= "0" && c <= "9") num = num c
                    else { suf = substr(last, i); break }
                }
                if (num != "" && suf != "") {
                    if (suf=="KB" || suf=="KiB") unit = num * 1024
                    else if (suf=="MB" || suf=="MiB") unit = num * 1024 * 1024
                    else if (suf=="GB" || suf=="GiB") unit = num * 1024 * 1024 * 1024
                }
            }
            print raw * unit
        }' <<<"$smart_all"
}

get_md_mount() {
    local md="$1"
    local mp=""
    mp="$(findmnt -n -o TARGET "/dev/$md" 2>/dev/null)"
    [[ -n "$mp" ]] && { echo "$mp"; return; }
    mp="$(lsblk -o NAME,PKNAME,TYPE,MOUNTPOINT -r 2>/dev/null | awk -v md="$md" '$2==md && $4!="" {print $4}' | sort -u | paste -sd "," -)"
    [[ -n "$mp" ]] && echo "$mp"
}

get_disk() {
    local temp_info="${Font_Cyan}${Font_B}${sinfo[disk]}${Font_Suffix}"
    ibar_step=95
    show_progress_bar "$temp_info" $((55 - sinfo[ldisk])) &
    bar_pid="$!" && disown "$bar_pid"
    trap "kill_progress_bar" RETURN

    if [[ -z "${diskinfo[total]}" || "${diskinfo[total]}" -le 0 ]]; then
        local total used avail p_used p_avail
        read -r total used avail p_used p_avail < <(df -B1 -P 2>/dev/null | awk '
            BEGIN {
                skip["tmpfs"]; skip["devtmpfs"]; skip["udev"]; skip["overlay"]
                skip["shm"]; skip["cgroup"]; skip["cgroup2"]; skip["proc"]
                skip["sysfs"]; skip["debugfs"]; skip["tracefs"]; skip["securityfs"]
                skip["pstore"]; skip["autofs"]; skip["mqueue"]; skip["hugetlbfs"]
                skip["configfs"]; skip["rpc_pipefs"]; skip["binfmt_misc"]
            }
            NR > 1 {
                fs = $1
                if (fs in skip || fs ~ /^fuse\./) next
                size = $2 + 0; used = $3 + 0; avail = $4 + 0
                if (!(fs in seen)) {
                    seen[fs] = 1
                    T += size; U += used; A += avail
                }
            }
            END {
                if (T > 0) printf "%.0f %.0f %.0f %d %d\n", T, U, A, int(U*100/T), int(A*100/T)
            }')
        if [[ -z "$total" || "$total" -le 0 ]]; then
            read -r total used avail p_used < <(df -B1 / 2>/dev/null | awk 'NR==2{print $2,$3,$4,int($3*100/$2)}')
            [[ -n "$p_used" ]] && p_avail=$((100 - p_used))
        fi
        diskinfo[total]="$total"
        diskinfo[used]="$used"
        diskinfo[avail]="$avail"
        diskinfo[p_used]="$p_used"
        diskinfo[p_avail]="$p_avail"
    fi

    local name rota size_b type smart_out smart_all smart_j used id
    local idx=0
    if command -v lsblk >/dev/null 2>&1; then
        while read -r name rota size_b; do
            ((idx++))
            local dev="/dev/$name"
            local show_name="$name"
            if [[ "$name" =~ ^(nvme[0-9]+)n[0-9]+$ ]]; then
                show_name="${BASH_REMATCH[1]}"
            fi
            diskinfo["disk${idx}.name"]="$show_name"
            diskinfo["disk${idx}.dev"]="$dev"
            if [[ "$name" == nvme* ]]; then
                type="NVMe"
            elif [[ "$rota" == "1" ]]; then
                type="HDD"
            else
                type="SSD"
            fi
            diskinfo["disk${idx}.type"]="$type"
            command -v smartctl >/dev/null 2>&1 || continue

            smart_out="$(smartctl -i "$dev" 2>/dev/null)"
            diskinfo["disk${idx}.model"]="$(awk '
                /Device Model|Model Number/ {
                    line = $0
                    sub(/^.*:[[:space:]]*/, "", line)
                    n = split(line, a, /[[:space:]]+/)
                    if (n >= 2) print a[1], a[2]
                    else print line
                }' <<<"$smart_out")"
            diskinfo["disk${idx}.serial"]="$(awk -F: '/Serial Number/{print $2}' <<<"$smart_out" | xargs)"
            if [[ "$type" == "NVMe" ]]; then
                diskinfo["disk${idx}.capacity"]="$(sed -n 's/.*Total NVM Capacity:.*\[\(.*\)\].*/\1/p' <<<"$smart_out" | tr -d ' ')"
            else
                diskinfo["disk${idx}.capacity"]="$(sed -n 's/.*User Capacity:.*\[\(.*\)\].*/\1/p' <<<"$smart_out" | tr -d ' ')"
            fi
            if [[ "$type" == "HDD" ]]; then
                diskinfo["disk${idx}.rpm"]="$(sed -n 's/.*Rotation Rate:[[:space:]]*\([0-9]\+\).*/\1rpm/p' <<<"$smart_out")"
            fi
            if [[ "$type" != "NVMe" ]]; then
                diskinfo["disk${idx}.form"]="$(sed -n 's/.*Form Factor:[[:space:]]*\([0-9.]\+\)[[:space:]]*inches/\1"/p' <<<"$smart_out")"
            fi

            smart_all="$(smartctl -A "$dev" 2>/dev/null)"
            smart_j="$(smartctl -H -j "$dev" 2>/dev/null)"
            if grep -q '"passed":[[:space:]]*true' <<<"$smart_j"; then
                diskinfo["disk${idx}.smart_pass"]="PASSED"
            elif grep -q '"passed":[[:space:]]*false' <<<"$smart_j"; then
                diskinfo["disk${idx}.smart_pass"]="FAILED"
            fi

            diskinfo["disk${idx}.pcycle"]="$(awk '$1==12{print $NF}' <<<"$smart_all")"
            diskinfo["disk${idx}.poh"]="$(awk '$1==9{print $NF}' <<<"$smart_all")"
            diskinfo["disk${idx}.temp"]="$(awk '
                ($1==190 || $1==194) {
                    for (i=NF; i>0; i--) {
                        if ($i ~ /^[0-9]+$/) { print $i; exit }
                    }
                }' <<<"$smart_all")"

            if [[ "$type" == "HDD" ]]; then
                for id in 1 5 187 196 197 198; do
                    diskinfo["disk${idx}.smart_${id}"]="$(awk '$1=='"$id"'{print $NF}' <<<"$smart_all")"
                done
            elif [[ "$type" == "SSD" ]]; then
                diskinfo["disk${idx}.write_raw"]="$(parse_sata_rw 241 "$smart_all")"
                diskinfo["disk${idx}.read_raw"]="$(parse_sata_rw 242 "$smart_all")"
                diskinfo["disk${idx}.life"]="$(awk '$1==169{print $NF}' <<<"$smart_all")"
            elif [[ "$type" == "NVMe" ]]; then
                diskinfo["disk${idx}.pcycle"]="$(sed -n 's/.*Power Cycles:[[:space:]]*\([0-9,]\+\).*/\1/p' <<<"$smart_all" | tr -d ',')"
                diskinfo["disk${idx}.poh"]="$(sed -n 's/.*Power On Hours:[[:space:]]*\([0-9,]\+\).*/\1/p' <<<"$smart_all" | tr -d ',')"
                diskinfo["disk${idx}.temp"]="$(sed -n 's/.*Temperature:[[:space:]]*\([0-9]\+\)[[:space:]]*Celsius.*/\1/p' <<<"$smart_all")"
                if [[ -z "${diskinfo[disk${idx}.temp]}" ]]; then
                    diskinfo["disk${idx}.temp"]="$(sed -n 's/.*Temperature Sensor 1:[[:space:]]*\([0-9]\+\)[[:space:]]*Celsius.*/\1/p' <<<"$smart_all")"
                fi
                diskinfo["disk${idx}.read_tb"]="$(sed -n 's/.*Data Units Read:.*\[\([^]]\+\)\].*/\1/p' <<<"$smart_all" | awk '{v=$1; u=$2; if (v+0 == v) printf "%d%s", int(v+0.5), u}')"
                diskinfo["disk${idx}.write_tb"]="$(sed -n 's/.*Data Units Written:.*\[\([^]]\+\)\].*/\1/p' <<<"$smart_all" | awk '{v=$1; u=$2; if (v+0 == v) printf "%d%s", int(v+0.5), u}')"
                used="$(sed -n 's/.*Percentage Used:[[:space:]]*\([0-9]\+\)%.*/\1/p' <<<"$smart_all")"
                [[ -n "$used" ]] && diskinfo["disk${idx}.life"]=$((100 - used))
                diskinfo["disk${idx}.spare"]="$(sed -n 's/.*Available Spare:[[:space:]]*\([0-9]\+\)%.*/\1/p' <<<"$smart_all")"
            fi
        done < <(lsblk -dn -o NAME,ROTA,SIZE,TYPE -b 2>/dev/null | awk '$4=="disk" && $3>0 {print $1,$2,$3}')
    fi
    diskinfo[count]=$idx

    if [[ -z "${diskinfo[raid_count]}" ]]; then
        local ridx=0 line
        if [[ -r /proc/mdstat ]]; then
            while read -r line; do
                if [[ "$line" =~ ^(md[0-9]+)[[:space:]]*:[[:space:]]*active[[:space:]]+([a-z0-9]+)[[:space:]]+(.*)$ ]]; then
                    ((ridx++))
                    local rname="${BASH_REMATCH[1]}"
                    local rlevel="${BASH_REMATCH[2]}"
                    local rdevs="${BASH_REMATCH[3]}"
                    rlevel="${rlevel^^}"
                    rdevs="$(awk '{for(i=1;i<=NF;i++) if ($i ~ /\[[0-9]+\]/) printf "%s ", $i}' <<<"$rdevs")"
                    rdevs="${rdevs% }"
                    diskinfo["raid${ridx}.name"]="$rname"
                    diskinfo["raid${ridx}.level"]="$rlevel"
                    diskinfo["raid${ridx}.devs"]="$rdevs"
                    diskinfo["raid${ridx}.mount"]="$(get_md_mount "$rname")"
                fi
            done </proc/mdstat
        fi
        diskinfo[raid_count]="$ridx"
    fi
}

show_head() {
    echo -ne "\r$(printf '%80s' | tr ' ' '+')\n"
    calc_padding "$(printf '%*s' "${shead[ltitle]}" '')${IPdisp}" 80
    echo -ne "\r${PADDING}${Font_B}${shead[title]}${Font_Cyan}${IPdisp}${Font_Suffix}\n"
    calc_padding "${shead[git]}" 80
    echo -ne "\r${PADDING}${Font_U}${shead[git]}${Font_Suffix}\n"
    calc_padding "${shead[bash]}" 80
    echo -ne "\r${PADDING}${shead[bash]}\n"
    echo -ne "\r${shead[ptime]}${shead[time]}  ${shead[ver]}\n"
    echo -ne "\r$(printf '%80s' | tr ' ' '+')\n"
}

show_os() {
    local virt_label="${sos[${osinfo[virt]}]:-${osinfo[virt]}}"
    echo -ne "\r${sos[title]}\n"
    echo -ne "\r${Font_Cyan}${sos[virt]}${Font_Green}${virt_label}${Font_Suffix}\n"
    echo -ne "\r${Font_Cyan}${sos[arch]}${Font_Green}${osinfo[arch]}${Font_Suffix}\n"
    echo -ne "\r${Font_Cyan}${sos[os]}${Font_Green}${osinfo[os]} ${osinfo[kernel]}${Font_Suffix}\n"
    echo -ne "\r${Font_Cyan}${sos[uptime]}${Font_Green}${osinfo[d]} ${sos[d]} ${osinfo[h]} ${sos[h]} ${osinfo[m]} ${sos[m]}${Font_Suffix}\n"
    echo -ne "\r${Font_Cyan}${sos[load]}${sos[load1]}${Font_Green}, ${sos[load5]}${Font_Green}, ${sos[load15]}${Font_Suffix}\n"
    local svc_part="" user_part=""
    [[ -n "${osinfo[svcr]}" && -n "${osinfo[svct]}" ]] && svc_part="${sos[q]}${osinfo[svcr]}/${osinfo[svct]} ${sos[svc]}"
    [[ -n "${osinfo[user]}" ]] && user_part="${osinfo[user]} ${sos[user]}${sos[q]}"
    echo -ne "\r${Font_Cyan}${sos[status]}${Font_Green}${user_part}${osinfo[proc]} ${sos[proc]}${svc_part}${Font_Suffix}\n"
    echo -ne "\r${Font_Cyan}${sos[loc]}${Font_Green}${osinfo[lang]}, ${osinfo[charset]}, ${osinfo[tz]}${osinfo[tz_abbr]} ${osinfo[tz_offset]}${Font_Suffix}\n"
}

align_lines() {
    local cpuline1="$1"
    local cpuline2="$2"
    local -i cpulen1="$3"
    local -i cpulen2="$4"
    if [[ -z "$cpuline1" || -z "$cpuline2" ]]; then
        [[ -n "$cpuline1" ]] && echo -ne "\r${Font_Cyan}${scpu[cpu]}${Font_B}${Font_U}${Back_White}${Font_Black}${cpuline1}${Font_Suffix}\n"
        [[ -n "$cpuline2" ]] && echo -ne "\r${Font_Cyan}${scpu[cpu]}${Font_B}${Font_U}${Back_White}${Font_Black}${cpuline2}${Font_Suffix}\n"
        return
    fi
    local w1 w2 diff
    w1=$(($(echo -n "$cpuline1" | wc -c) + cpulen2))
    w2=$(($(echo -n "$cpuline2" | wc -c) + cpulen1 + 4))
    if ((w1 < w2)); then
        diff=$((w2 - w1))
        cpuline1+="${Font_Suffix}${Back_White}$(printf '%*s' "$diff" '')"
    elif ((w1 > w2)); then
        diff=$((w1 - w2))
        cpuline2+="${Font_Suffix}${Back_White}$(printf '%*s' "$diff" '')"
    fi
    echo -ne "\r${Font_Cyan}${scpu[cpu]}${Font_B}${Font_U}${Back_White}${Font_Black}${cpuline1}${Font_Suffix}\n"
    echo -ne "\r          ${Font_B}${Back_White}${Font_Black} ╚═ ${cpuline2}${Font_Suffix}\n"
}

score_bar() {
    local score="$1"
    local low_min="$2"
    local mid_low="$3"
    local mid_high="$4"
    local high_max="$5"
    local seg_width=20
    local pos=1
    if ((score <= low_min)); then
        pos=1
    elif ((score < mid_low)); then
        pos=$((1 + (score - low_min) * seg_width / (mid_low - low_min)))
    elif ((score < mid_high)); then
        pos=$((21 + (score - mid_low) * seg_width / (mid_high - mid_low)))
    elif ((score < high_max)); then
        pos=$((41 + (score - mid_high) * seg_width / (high_max - mid_high)))
    else
        pos=60
    fi
    ((pos < 1)) && pos=1
    ((pos > 60)) && pos=60
    local bar="" n
    if ((pos >= 1)); then
        n=$((pos < 20 ? pos : 20))
        if ((n > 0)); then
            bar+="${Back_Red}$(printf "%${n}s" '')${Font_Suffix}"
        fi
    fi
    if ((pos > 20)); then
        n=$((pos - 20 < 20 ? pos - 20 : 20))
        bar+="${Back_Yellow}$(printf "%${n}s" '')${Font_Suffix}"
    fi
    if ((pos > 40)); then
        n=$((pos - 40 < 20 ? pos - 40 : 20))
        bar+="${Back_Green}$(printf "%${n}s" '')${Font_Suffix}"
    fi
    local color bg
    if ((pos <= 20)); then
        color="$Font_Red"
        bg="$Back_Red"
    elif ((pos <= 40)); then
        color="$Font_Yellow"
        bg="$Back_Yellow"
    else
        color="$Font_Green"
        bg="$Back_Green"
    fi
    bar+="\b${bg}${Font_White}${Font_B}|${Font_Suffix}"
    echo -ne "${bar}${Font_B}${color}${score}${Font_Suffix}"
}

cpu_gb_bar() {
    local text="$1"
    local pct="$2"
    local width=$((pct * 20 / 100))
    ((width < 1)) && width=1
    ((width > 20)) && width=20
    text="$(printf "%20s" "$text")"
    local left="${text:0:width}"
    local right="${text:width}"
    local out=""
    ((width > 0)) && out+="${Back_Cyan}${Font_White}${left}${Font_Suffix}"
    ((width < 20)) && out+="${Font_Cyan}${right}${Font_Suffix}"
    printf '%s' "$out"
}

show_geekbench_cpu_table() {
    local key name disp_name
    local s_score m_score s_desc s_pct m_desc m_pct line
    local s_pct_max=0 scaled_s_pct
    declare -A seen
    for key in "${!cpuinfo[@]}"; do
        [[ "$key" =~ ^gb\.[sm]\.[gi]\.(.+)$ ]] || continue
        name="${BASH_REMATCH[1]}"
        name="${name%%.*}"
        seen["$name"]=1
    done
    ((${#seen[@]} == 0)) && return
    for name in "${!seen[@]}"; do
        if [[ -n "${cpuinfo[gb.s.i.$name.pct]}" ]]; then
            ((cpuinfo[gb.s.i.$name.pct] > s_pct_max)) && s_pct_max="${cpuinfo[gb.s.i.$name.pct]}"
        fi
    done
    for name in $(printf "%s\n" "${!seen[@]}" | sort); do
        if [[ -n "${cpuinfo[gb.s.g.$name]}" || -n "${cpuinfo[gb.m.g.$name]}" ]]; then
            s_score="${cpuinfo[gb.s.g.$name]}"
            m_score="${cpuinfo[gb.m.g.$name]}"
            disp_name="${name//_/ }"
            line="${Font_Cyan}$(printf "%-22s" "$disp_name")"
            line+="${Font_Green}${Font_B}$(printf "%7s" "$s_score")${Font_Suffix}"
            line+="${Font_Cyan}    Single-Core Score||"
            line+="${Font_Green}${Font_B}$(printf "%7s" "$m_score")${Font_Suffix}"
            line+="${Font_Cyan}     Multi-Core Score${Font_Suffix}"
            echo -ne "\r${line}\n"
        fi
    done
    for name in $(printf "%s\n" "${!seen[@]}" | sort); do
        if [[ -z "${cpuinfo[gb.s.g.$name]}" && -z "${cpuinfo[gb.m.g.$name]}" ]]; then
            s_score="${cpuinfo[gb.s.i.$name]}"
            m_score="${cpuinfo[gb.m.i.$name]}"
            s_desc="${cpuinfo[gb.s.i.$name.desc]}"
            m_desc="${cpuinfo[gb.m.i.$name.desc]}"
            s_pct="${cpuinfo[gb.s.i.$name.pct]:-0}"
            m_pct="${cpuinfo[gb.m.i.$name.pct]:-0}"
            disp_name="${name//_/ }"
            if ((s_pct_max > 0)); then
                scaled_s_pct=$((s_pct * 100 / s_pct_max))
            else
                scaled_s_pct=0
            fi
            line="${Font_Cyan}$(printf "%-22s" "$disp_name")"
            line+="${Font_Green}${Font_B}$(printf "%7s" "$s_score")"
            line+=" ${Font_Suffix}$(cpu_gb_bar "$s_desc" "$scaled_s_pct")"
            line+="${Font_Cyan}||"
            line+="${Font_Green}${Font_B}$(printf "%7s" "$m_score")"
            line+=" ${Font_Suffix}$(cpu_gb_bar "$m_desc" "$m_pct")"
            echo -ne "\r${line}\n"
        fi
    done
}

temp_color() {
    local t="$1"
    if ((t < 60)); then
        echo -ne "$Font_Green"
    elif ((t < 80)); then
        echo -ne "$Font_Yellow"
    else
        echo -ne "$Font_Red"
    fi
}

show_cpu() {
    local cpuline cpuline1 cpuline2 cpulen1 cpulen2
    echo -ne "\r${scpu[title]}\n"
    cpulen1=0
    cpuline1="${cpuinfo[name]}"
    if [[ -n "${cpuinfo[stepping]}" ]]; then
        cpuline1+=" ${scpu[step]}${cpuinfo[stepping]}"
        ((cpulen1 += scpu[lstep]))
    fi
    if [[ -n "${cpuinfo[family]}" ]]; then
        cpuline1+=" (${cpuinfo[family]}${scpu[gen]})"
        ((cpulen1 += scpu[lgen]))
    fi
    [[ -n "${cpuinfo[op_mode]}" ]] && cpuline1+=" ${cpuinfo[op_mode]}"
    if [[ "${cpuinfo[sockets]:-1}" -gt 1 ]]; then
        cpuline1+=" × ${cpuinfo[sockets]}${scpu[num]}"
        ((cpulen1 += scpu[lnum] + 1))
    fi

    cpuline2=""
    cpulen2=0
    if [[ -n "${cpuinfo[cores]}" && "${cpuinfo[cores]}" != "0" ]]; then
        cpuline2+="${cpuinfo[cores]}${scpu[core]}"
        ((cpulen2 += scpu[lcore]))
    fi
    if [[ -n "${cpuinfo[cg_threads]}" ]]; then
        cpuline2+=", ${scpu[limit1]}${cpuinfo[cg_threads]}${scpu[limit2]}"
        ((cpulen2 += scpu[llimit]))
    fi
    if [[ -n "${cpuinfo[threads]}" && "${cpuinfo[threads]}" -gt 0 && "${osinfo[virt_kind]}" != "container" ]]; then
        [[ -n "$cpuline2" ]] && cpuline2+=", "
        cpuline2+="${cpuinfo[threads]}${scpu[thread]}"
        ((cpulen2 += scpu[lthread]))
    fi
    if [[ -n "${cpuinfo[mhz]}" ]]; then
        [[ -n "$cpuline2" ]] && cpuline2+=", "
        cpuline2+="${cpuinfo[mhz]}MHz"
    fi
    [[ -n "${cpuinfo[min_mhz]}${cpuinfo[max_mhz]}" ]] && cpuline2+=" (${cpuinfo[min_mhz]}MHz ~ ${cpuinfo[max_mhz]}MHz)"
    if [[ -n "${cpuinfo[usage]}" ]]; then
        cpuline2+=", ${scpu[usage]}${cpuinfo[usage]}%"
        ((cpulen2 += scpu[lusage]))
    fi
    align_lines "$cpuline1" "$cpuline2" "$cpulen1" "$cpulen2"

    if [[ "${cpuinfo[cache_fallback]}" == "1" && -n "${cpuinfo[cache_total]}" ]]; then
        echo -ne "\r${Font_Cyan}${scpu[cache]}${Font_Green}${cpuinfo[cache_total]}${Font_Suffix}\n"
    elif [[ -n "${cpuinfo[L1d]}${cpuinfo[L1i]}${cpuinfo[L2]}${cpuinfo[L3]}" ]]; then
        cpuline="${Font_Cyan}${scpu[cache]}${Font_Green}"
        [[ -n "${cpuinfo[L1d]}" ]] && cpuline+="L1d ${cpuinfo[L1d]},"
        [[ -n "${cpuinfo[L1i]}" ]] && cpuline+=" L1i ${cpuinfo[L1i]},"
        [[ -n "${cpuinfo[L2]}" ]] && cpuline+=" L2 ${cpuinfo[L2]},"
        [[ -n "${cpuinfo[L3]}" ]] && cpuline+=" L3 ${cpuinfo[L3]}"
        cpuline="${cpuline%,}"
        cpuline="${cpuline#"${cpuline%%[![:space:]]*}"}"
        echo -ne "\r${cpuline}${Font_Suffix}\n"
    fi

    if [[ "${cpuinfo[arch]}" =~ x86_64|i[3-6]86 ]]; then
        echo -ne "\r${Font_Cyan}${scpu[flag]}${Font_Suffix}"
        echo -ne "$([[ "${cpuinfo[vt]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") VT-x/AMD-V ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[aes]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") AES-NI ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[avx2]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") AVX2 ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[bmi]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") BMI1/2 ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[ept]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") EPT/NPT ${Font_Suffix}\n"
    else
        echo -ne "\r${Font_Cyan}${scpu[flag]}${Font_Suffix}"
        echo -ne "$([[ "${cpuinfo[el2]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") EL2 ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[neon]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") NEON ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[aes_sha]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") AES/SHA ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[atomics]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") Atomics ${Font_Suffix}"
        echo -ne "  $([[ "${cpuinfo[sve]}" ]] && echo "${Back_Green} ✔" || echo "${Back_Red} ✘") SVE ${Font_Suffix}\n"
    fi

    if [[ -n "${cpuinfo[temp_count]}" && "${cpuinfo[temp_count]}" -gt 0 ]] && [[ -n "${cpuinfo[geekbench_single]}" && -n "${cpuinfo[geekbench_multi]}" ]]; then
        local min_list="" max_list="" i
        for ((i = 0; i < cpuinfo[temp_count]; i++)); do
            if [[ -n "${cpuinfo[temp${i}_min]}" ]]; then
                [[ -n "$min_list" ]] && min_list+="${Font_Green}/ "
                min_list+="$(temp_color "${cpuinfo[temp${i}_min]}")${cpuinfo[temp${i}_min]}℃ ${Font_Suffix}"
            fi
            if [[ -n "${cpuinfo[temp${i}_max]}" ]]; then
                [[ -n "$max_list" ]] && max_list+="${Font_Green}/ "
                max_list+="$(temp_color "${cpuinfo[temp${i}_max]}")${cpuinfo[temp${i}_max]}℃ ${Font_Suffix}"
            fi
        done
        if [[ -n "$min_list" || -n "$max_list" ]]; then
            echo -ne "\r${Font_Cyan}${scpu[temp]}${Font_Green}${scpu[min]}${min_list}     ${Font_Green}${scpu[max]}${max_list}${Font_Suffix}\n"
        fi
    fi

    if [[ -n "${cpuinfo[geekbench_single]}" && -n "${cpuinfo[geekbench_multi]}" ]]; then
        echo -ne "\r${Font_Cyan}${scpu[base]}${Font_Suffix}${Font_I}${Back_Red}J1900 N5105 N100 670${Back_Yellow}0K 9900K 5900X 12900${Back_Green}K 14900K 7713 7995WX${Font_Suffix}\n"
        local scoretest
        scoretest="$(score_bar "${cpuinfo[geekbench_single]}" 0 4500 18000 80000)"
        echo -ne "\r${Font_Cyan}${scpu[single]}${Font_Suffix}${scoretest}${Font_Suffix}\n"
        scoretest="$(score_bar "${cpuinfo[geekbench_multi]}" 0 4500 18000 80000)"
        echo -ne "\r${Font_Cyan}${scpu[multi]}${Font_Suffix}${scoretest}${Font_Suffix}\n"
    elif [[ -n "${cpuinfo[gb_err]}" ]]; then
        echo -ne "\r${Font_Cyan}${scpu[gb_status]}${Font_Yellow}${cpuinfo[gb_err]}${Font_Suffix}\n"
    fi

    [[ "$mode_verbose" -eq 1 ]] && show_geekbench_cpu_table

    if [[ -n "${cpuinfo[url]}" ]]; then
        echo -ne "\r${Font_Cyan}${scpu[url]}${Font_Green}${Font_U}${cpuinfo[url]}${Font_Suffix}\n"
    fi
}

show_mem() {
    echo -ne "\r${smem[title]}\n"
    local last=-1 i p prefix
    local -A memlen
    local -A memline
    memline[f]="${smem[total]} ${meminfo[total]},  ${smem[used]} ${meminfo[used]}(${meminfo[mem_used_pct]}%),  ${smem[avail]} ${meminfo[avail]}(${meminfo[mem_avail_pct]}%)"
    memlen[f]=$(($(echo -n "${memline[f]}" | wc -c) - smem[ltotal]))
    local memmax=$((memlen[f]))
    for ((i = 0; i < ${meminfo[count]:-0}; i++)); do
        p="mem$i"
        [[ -z "${meminfo[$p.size]}" ]] && continue
        memline[$i]="[${meminfo[$p.slot]}]${meminfo[$p.vendor]} ${meminfo[$p.size]} ${meminfo[$p.type]} ${meminfo[$p.speed]} ${meminfo[$p.part]} SN:${meminfo[$p.serial]}"
        memlen[$i]=$(($(echo -n "${memline[$i]}" | wc -c) + 4))
        ((memlen[$i] > memmax)) && memmax=$((memlen[$i]))
        last=$i
    done
    local memdiff
    memdiff="$(printf '%*s' "$((memmax - memlen[f]))" '')"
    if [[ -n "${meminfo[total]}" ]]; then
        echo -ne "\r${Font_Cyan}${smem[mem]}${Font_B}${Font_U}${Back_White}${Font_Black}${memline[f]}${Font_Suffix}${Back_White}${memdiff}${Font_Suffix}\n"
    fi
    for ((i = 0; i < ${meminfo[count]:-0}; i++)); do
        p="mem$i"
        [[ -z "${meminfo[$p.size]}" ]] && continue
        memdiff="$(printf '%*s' "$((memmax - memlen[$i]))" '')"
        if [[ $i -eq $last ]]; then
            prefix="          ${Font_B}${Back_White}${Font_Black} ╚═ "
        else
            prefix="          ${Font_B}${Back_White}${Font_Black} ╠═ "
        fi
        echo -ne "\r${prefix}${memline[$i]}${memdiff}${Font_Suffix}\n"
    done
    if [[ -n "${meminfo[swap_total]}" ]]; then
        echo -ne "\r${Font_Cyan}${smem[swap]}${Font_Green}${smem[total]} ${meminfo[swap_total]},  ${smem[used]} ${meminfo[swap_used]}(${meminfo[swap_used_pct]}%),  ${smem[avail]} ${meminfo[swap_avail]}(${meminfo[swap_avail_pct]}%)${Font_Suffix}\n"
    fi
    if [[ "${osinfo[virt]}" == "kvm" ]]; then
        local balloon_flag ksm_flag
        [[ "${meminfo[balloon]}" == "1" ]] && balloon_flag="${Back_Red} ✔" || balloon_flag="${Back_Green} ✘"
        [[ "${meminfo[ksm]}" == "1" ]] && ksm_flag="${Back_Red} ✔" || ksm_flag="${Back_Green} ✘"
        echo -ne "\r${Font_Cyan}${smem[reuse]}${Font_Suffix}${balloon_flag} ${smem[balloon]} ${Font_Suffix}   ${ksm_flag} ${smem[ksm]} ${Font_Suffix}\n"
    fi
    if [[ "${osinfo[virt]}" == "lxc" || "${osinfo[virt]}" == "lxd" ]] && [[ -n "${meminfo[neighbor]}" ]] && ((meminfo[neighbor] > 0)); then
        local ncolor="$Font_Red"
        if ((meminfo[neighbor] <= 200)); then
            ncolor="$Font_Green"
        elif ((meminfo[neighbor] <= 500)); then
            ncolor="$Font_Yellow"
        fi
        echo -ne "\r${Font_Cyan}${smem[nb]}${ncolor}${meminfo[neighbor]} ${smem[nbnum]}${Font_Suffix}\n"
    fi
}

cap_to_bytes() {
    local s="$1"
    [[ -z "$s" ]] && return
    awk '
        {
            if ($0 ~ /TB$/) { sub(/TB$/, "", $0); printf "%.0f", $0 * 1024 * 1024 * 1024 * 1024 }
            else if ($0 ~ /GB$/) { sub(/GB$/, "", $0); printf "%.0f", $0 * 1024 * 1024 * 1024 }
        }' <<<"$s"
}

rw_to_bytes() {
    local s="$1"
    [[ -z "$s" ]] && return
    awk '
        {
            if ($0 ~ /TB$/) { sub(/TB$/, "", $0); printf "%.0f", $0 * 1024 * 1024 * 1024 * 1024 }
            else if ($0 ~ /GB$/) { sub(/GB$/, "", $0); printf "%.0f", $0 * 1024 * 1024 * 1024 }
        }' <<<"$s"
}

show_disk() {
    echo -ne "\r${sdisk[title]}\n"
    local -A disklen
    local -A diskline
    local -A smartlen
    local -A smartline
    disklen[f]=0
    diskline[f]=""
    if [[ -n "${diskinfo[count]}" && "${diskinfo[count]}" -gt 0 ]]; then
        diskline[f]="${sdisk[count]}${diskinfo[count]}"
        disklen[f]=$((disklen[f] - sdisk[lcount]))
    fi
    if [[ -n "${diskinfo[total]}" && "${diskinfo[total]}" -gt 0 ]]; then
        [[ -n "${diskline[f]}" ]] && diskline[f]+=",  "
        diskline[f]+="${sdisk[total]}$(fmt_bytes "${diskinfo[total]}")"
        disklen[f]=$((disklen[f] - sdisk[ltotal]))
    fi
    if [[ -n "${diskinfo[used]}" && "${diskinfo[used]}" -gt 0 && -n "${diskinfo[p_used]}" ]]; then
        [[ -n "${diskline[f]}" ]] && diskline[f]+=",  "
        diskline[f]+="${sdisk[used]}$(fmt_bytes "${diskinfo[used]}")(${diskinfo[p_used]}%)"
        disklen[f]=$((disklen[f] - sdisk[lused]))
    fi
    if [[ -n "${diskinfo[avail]}" && "${diskinfo[avail]}" -gt 0 && -n "${diskinfo[p_avail]}" ]]; then
        [[ -n "${diskline[f]}" ]] && diskline[f]+=",  "
        diskline[f]+="${sdisk[avail]}$(fmt_bytes "${diskinfo[avail]}")(${diskinfo[p_avail]}%)"
        disklen[f]=$((disklen[f] - sdisk[lavail]))
    fi
    disklen[f]=$((disklen[f] + $(echo -n "${diskline[f]}" | wc -c)))
    local diskmax=$((disklen[f]))
    local i last_valid=0
    for ((i = 1; i <= ${diskinfo[count]:-0}; i++)); do
        local name type
        [[ -z "${diskinfo[disk${i}.capacity]}" || -z "${diskinfo[disk${i}.name]}" || -z "${diskinfo[disk${i}.type]}" || -z "${diskinfo[disk${i}.model]}" ]] && continue
        last_valid=$i
        name="${diskinfo[disk${i}.name]}"
        type="${diskinfo[disk${i}.type]}"
        diskline[$i]="[$name"
        [[ "$type" != "NVMe" ]] && diskline[$i]+=" $type"
        diskline[$i]+="]${diskinfo[disk${i}.model]}"
        [[ -n "${diskinfo[disk${i}.serial]}" ]] && diskline[$i]+=" SN:${diskinfo[disk${i}.serial]}"
        [[ -n "${diskinfo[disk${i}.capacity]}" ]] && diskline[$i]+=" ${diskinfo[disk${i}.capacity]}"
        [[ -n "${diskinfo[disk${i}.rpm]}" ]] && diskline[$i]+=" ${diskinfo[disk${i}.rpm]}"
        [[ -n "${diskinfo[disk${i}.form]}" ]] && diskline[$i]+=" ${diskinfo[disk${i}.form]}"
        disklen[$i]=$(($(echo -n "${diskline[$i]}" | wc -c) + 4))
        ((disklen[$i] > diskmax)) && diskmax=$((disklen[$i]))

        smartline[$i]=""
        smartlen[$i]=0
        if [[ -n "${diskinfo[disk${i}.pcycle]}" ]]; then
            local pc="${diskinfo[disk${i}.pcycle]}"
            local pc_color="$Font_Green"
            [[ "$pc" =~ ^[0-9]+$ ]] && ((pc >= 10000)) && pc_color="$Font_Yellow"
            smartline[$i]+="${pc_color}${sdisk[po]}${pc}${sdisk[times]}${Font_Black} "
            smartlen[$i]=$((smartlen[$i] - sdisk[lpo] - 10))
        fi
        if [[ -n "${diskinfo[disk${i}.poh]}" ]]; then
            local poh="${diskinfo[disk${i}.poh]}"
            if [[ "$poh" =~ ^[0-9]+$ ]] && ((poh <= 30000)); then
                smartline[$i]+="${Font_Green}${poh}h${Font_Black} "
            else
                smartline[$i]+="${Font_Yellow}${poh}h${Font_Black} "
            fi
            smartlen[$i]=$((smartlen[$i] - 10))
        fi
        if [[ -n "${diskinfo[disk${i}.temp]}" ]]; then
            local t="${diskinfo[disk${i}.temp]}"
            local tc="$Font_Green"
            case "$type" in
                HDD) ((t > 50)) && tc="$Font_Red"; ((t >= 40 && t <= 50)) && tc="$Font_Yellow" ;;
                SSD) ((t > 65)) && tc="$Font_Red"; ((t >= 50 && t <= 65)) && tc="$Font_Yellow" ;;
                NVMe) ((t > 75)) && tc="$Font_Red"; ((t >= 60 && t <= 75)) && tc="$Font_Yellow" ;;
            esac
            smartline[$i]+="${tc}${t}℃ ${Font_Black} "
            smartlen[$i]=$((smartlen[$i] - 12))
        fi
        if [[ "$type" == "HDD" ]]; then
            local id v
            for id in 1 5 187 196 197 198; do
                v="${diskinfo[disk${i}.smart_${id}]}"
                [[ -z "$v" ]] && continue
                if [[ "$v" == "0" ]]; then
                    smartline[$i]+="${Font_Green}✔$(printf "%02X" "$id")${Font_Black} "
                else
                    smartline[$i]+="${Font_Red}✘$(printf "%02X" "$id")${Font_Black} "
                fi
                smartlen[$i]=$((smartlen[$i] - 12))
            done
        elif [[ "$type" == "SSD" ]]; then
            if [[ -n "${diskinfo[disk${i}.read_raw]}" && -n "${diskinfo[disk${i}.write_raw]}" ]]; then
                local r_disp w_disp cap_b w_b wc="$Font_Green"
                r_disp="$(fmt_rw "${diskinfo[disk${i}.read_raw]}")"
                w_disp="$(fmt_rw "${diskinfo[disk${i}.write_raw]}")"
                cap_b="$(cap_to_bytes "${diskinfo[disk${i}.capacity]}")"
                w_b="${diskinfo[disk${i}.write_raw]}"
                [[ -n "$cap_b" && -n "$w_b" ]] && ((w_b > cap_b * 1000)) && wc="$Font_Yellow"
                smartline[$i]+="${wc}R/W:${r_disp}/${w_disp}${Font_Black} "
                smartlen[$i]=$((smartlen[$i] - 10))
            fi
            if [[ -n "${diskinfo[disk${i}.life]}" ]]; then
                local life="${diskinfo[disk${i}.life]}" lc="$Font_Green"
                ((life < 30)) && lc="$Font_Red"
                ((life >= 30 && life < 80)) && lc="$Font_Yellow"
                smartline[$i]+="${lc}${sdisk[lf]}${life}%${Font_Black} "
                smartlen[$i]=$((smartlen[$i] - sdisk[llf] - 10))
            fi
        elif [[ "$type" == "NVMe" ]]; then
            local nvme_parts=()
            if [[ -n "${diskinfo[disk${i}.read_tb]}" && -n "${diskinfo[disk${i}.write_tb]}" ]]; then
                local cap_b w_b wc="$Font_Green"
                cap_b="$(cap_to_bytes "${diskinfo[disk${i}.capacity]}")"
                w_b="$(rw_to_bytes "${diskinfo[disk${i}.write_tb]}")"
                [[ -n "$cap_b" && -n "$w_b" ]] && ((w_b > cap_b * 1000)) && wc="$Font_Yellow"
                nvme_parts+=("${wc}R/W:${diskinfo[disk${i}.read_tb]}/${diskinfo[disk${i}.write_tb]}${Font_Black}")
                smartlen[$i]=$((smartlen[$i] - 10))
            fi
            if [[ -n "${diskinfo[disk${i}.life]}" ]]; then
                local life="${diskinfo[disk${i}.life]:-0}" lc="$Font_Green"
                if ((life < 30)); then lc="$Font_Red"; elif ((life < 80)); then lc="$Font_Yellow"; fi
                nvme_parts+=("${lc}${sdisk[lf]}${life}%${Font_Black}")
                smartlen[$i]=$((smartlen[$i] - sdisk[llf] - 10))
            fi
            if [[ -n "${diskinfo[disk${i}.spare]}" ]]; then
                local spare="${diskinfo[disk${i}.spare]:-0}" sc="$Font_Green"
                if ((spare < 90)); then sc="$Font_Red"; elif ((spare < 100)); then sc="$Font_Yellow"; fi
                nvme_parts+=("${sc}${sdisk[sp]}${spare}%${Font_Black}")
                smartlen[$i]=$((smartlen[$i] - sdisk[lsp] - 10))
            fi
            ((${#nvme_parts[@]})) && smartline[$i]+="${nvme_parts[*]} "
        fi
        case "${diskinfo[disk${i}.smart_pass]}" in
            PASSED)
                smartline[$i]+="${Back_Green}${Font_White} PASSED ${Font_Suffix}${Back_White}"
                smartlen[$i]=$((smartlen[$i] - 19))
                ;;
            FAILED)
                smartline[$i]+="${Back_Red}${Font_White} FAILED ${Font_Suffix}${Back_White}"
                smartlen[$i]=$((smartlen[$i] - 19))
                ;;
        esac
        smartline[$i]="${smartline[$i]%, }"
        if [[ -n "${smartline[$i]}" ]]; then
            smartlen[$i]=$((smartlen[$i] + $(echo -en "${smartline[$i]}" | wc -c) + 8))
            ((smartlen[$i] > diskmax)) && diskmax=$((smartlen[$i]))
        fi
    done

    local diskdiff
    diskdiff="$(printf '%*s' "$((diskmax - disklen[f]))" '')"
    if [[ -n "${diskline[f]}" ]]; then
        echo -ne "\r${Font_Cyan}${sdisk[disk]}${Font_Suffix}${Back_White}${Font_Black}${Font_B}${Font_U}${diskline[f]}${Font_Suffix}${Back_White}${diskdiff}${Font_Suffix}\n"
    fi
    for ((i = 1; i <= ${diskinfo[count]:-0}; i++)); do
        [[ -z "${diskinfo[disk${i}.capacity]}" || -z "${diskinfo[disk${i}.name]}" || -z "${diskinfo[disk${i}.type]}" || -z "${diskinfo[disk${i}.model]}" ]] && continue
        if ((i == last_valid)); then
            diskline[$i]="          ${Font_B}${Back_White}${Font_Black} ╚═ ${diskline[$i]}"
        else
            diskline[$i]="          ${Font_B}${Back_White}${Font_Black} ╠═ ${diskline[$i]}"
        fi
        diskdiff="$(printf '%*s' "$((diskmax - disklen[$i]))" '')"
        echo -ne "\r${diskline[$i]}${diskdiff}${Font_Suffix}\n"
        if [[ -n "${smartline[$i]}" ]]; then
            diskdiff="$(printf '%*s' "$((diskmax - smartlen[$i]))" '')"
            if ((i == last_valid)); then
                echo -ne "\r          ${Font_B}${Back_White}${Font_Black}     ╚═ ${smartline[$i]}${diskdiff}${Font_Suffix}\n"
            else
                echo -ne "\r          ${Font_B}${Back_White}${Font_Black} ║   ╚═ ${smartline[$i]}${diskdiff}${Font_Suffix}\n"
            fi
        fi
    done

    if [[ "${diskinfo[raid_count]:-0}" -gt 0 ]]; then
        local r rname rlevel rdevs rmount
        for ((r = 1; r <= diskinfo[raid_count]; r++)); do
            rname="${diskinfo[raid${r}.name]}"
            rlevel="${diskinfo[raid${r}.level]}"
            rdevs="${diskinfo[raid${r}.devs]}"
            rmount="${diskinfo[raid${r}.mount]}"
            [[ -n "$rmount" ]] && rmount="($rmount)" || rmount=""
            if ((r == 1)); then
                echo -ne "\r${Font_Cyan}RAID:     ${Font_Green}${rname} -> ${rlevel}${rmount} ${rdevs}${Font_Suffix}\n"
            else
                echo -ne "\r          ${Font_Green}${rname} -> ${rlevel}${rmount} ${rdevs}${Font_Suffix}\n"
            fi
        done
    fi
}

show_tail() {
    echo -ne "\r$(printf '%80s' | tr ' ' '=')\n"
    echo -ne "\r${Font_I}${stail[note]}${Font_Suffix}\n\n"
}

parse_worker_opts() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -E) YY="en"; shift ;;
            -V) mode_verbose=1; shift ;;
            -f) fullinfo=1; shift ;;
            -4) opt_ipv="-4"; shift ;;
            -6) opt_ipv="-6"; shift ;;
            -o) mode_output=1; outputfile="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
}

run_benchmark() {
    if [[ "$opt_ipv" == "-4" ]]; then
        get_ipv4
    elif [[ "$opt_ipv" == "-6" ]]; then
        get_ipv6
    else
        get_ipv4
        [[ -z "$IPV4" ]] && get_ipv6
    fi

    if [[ -n "$IPV4" ]]; then
        IP="$IPV4"
        hide_ipv4 "$IP"
    elif [[ -n "$IPV6" ]]; then
        IP="$IPV6"
        hide_ipv6 "$IP"
    fi

    if [[ -n "$IP" ]]; then
        if [[ "$fullinfo" -eq 1 ]]; then
            IPdisp="$IP"
        else
            IPdisp="$IPhide"
        fi
    else
        IPdisp="$(hostname 2>/dev/null || echo 'LocalHost')"
    fi

    get_virt
    get_os
    get_cpu
    test_cpu_gb5
    get_mem
    get_disk

    echo -ne "\r${Font_LineClear}" 1>&2

    local hw_report
    hw_report="$(
        show_head
        show_os
        show_cpu
        show_mem
        show_disk
        show_tail
    )"

    echo -ne "\r${hw_report}\n"

    if [[ "$mode_output" -eq 1 && -n "$outputfile" ]]; then
        printf '%s\n' "$hw_report" >"$outputfile"
    fi
}

adaptoslocale
parse_worker_opts "$@"
set_language
install_dependencies
run_benchmark
__GB5_WORKER_EOF__

    chmod +x "$work_dir/BenchOs/tmp/gb5_worker.sh"
}

function main() {
    trap 'sig_cleanup 130' INT
    trap 'sig_cleanup 143' TERM
    trap 'sig_cleanup 129' SIGHUP
    trap 'post_cleanup $?' EXIT

    start_ascii

    _green_bold "$(L cleanup_before)"
    pre_init
    pre_cleanup

    _green_bold "$(L loadbench)"
    load_bench_os

    _green_bold "$(L run_gb5)"
    pre_fetch_info
    write_worker_script

    local worker_args=()
    [[ -n "$opt_lang" ]] && worker_args+=("$opt_lang")
    [[ -n "$opt_verbose" ]] && worker_args+=("$opt_verbose")
    [[ -n "$opt_fullinfo" ]] && worker_args+=("$opt_fullinfo")
    [[ -n "$opt_ipv" ]] && worker_args+=("$opt_ipv")
    [[ -n "$output_file" ]] && worker_args+=("-o" "/tmp/gb5_report.ansi")

    chroot "$work_dir/BenchOs" /bin/bash /tmp/gb5_worker.sh "${worker_args[@]}"
    local rc=$?

    if [[ -n "$output_file" && -f "$work_dir/BenchOs/tmp/gb5_report.ansi" ]]; then
        case "$output_file" in
            *.[aA][nN][sS][iI])
                cp "$work_dir/BenchOs/tmp/gb5_report.ansi" "$output_file"
                ;;
            *)
                sed $'s/\033\\[[0-9;]*[mGKHF]//g; s/ \010//g; s/\010//g; s/\r//g' "$work_dir/BenchOs/tmp/gb5_report.ansi" >"$output_file"
                ;;
        esac
        _green_bold "$(L saved)${output_file}"
    fi

    _green_bold "$(L cleanup_after)"
    post_cleanup "$rc"
}

main
