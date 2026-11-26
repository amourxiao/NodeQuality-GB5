# NodeQuality-GB5

基于 [NodeQuality](https://github.com/LloydAsp/NodeQuality) 与 [HardwareQuality](https://github.com/xykt/HardwareQuality) 裁切的精简版服务器测评脚本，**仅保留设备基本信息与 Geekbench 5 CPU 性能测试**，完整保留原版终端视觉排版及常见设备 GB5 分数基准对比条（`J1900 ~ 7995WX`）。

## 特性

- **纯净无残留**：保留 NodeQuality 的 `BenchOs` 临时系统 chroot 模式，测试所需依赖与 Geekbench 5 均在临时根文件系统内运行，完成后自动卸载并彻底删除，不污染宿主机环境。
- **精简聚焦**：移除 IP 质量、网络质量、回程路由、Sysbench（CPU/内存）、Fio（硬盘）、主板/显卡检测、广告、访问计数与第三方报告上传。
- **保留原版结果形式**：
  - `一、操作系统信息`：虚拟化类型、架构、宿主机系统与内核、运行时间、负载、进程/服务数、区域与时区
  - `二、CPU与GB5测评`：CPU 型号/步进/核心线程/频率/利用率、缓存、指令集、测试温度、**GB5 常见设备基准对比条（`J1900 N5105 N100 6700K 9900K 5900X 12900K 14900K 7713 7995WX`）**、GB5 单核/多核可视化进度条与官方详情链接
  - `三、内存信息`：内存总容量/已用/可用、物理内存条（物理机）、Swap、KVM 气球回收/KSM 或 LXC 邻居数
  - `四、硬盘信息`：硬盘数量、总容量/已用/可用、物理盘型号与 SMART 健康状态、RAID 信息
- **低内存自动适配**：可用内存不足 950MB 且内存+Swap 不足 1200MB 时（非容器环境）自动创建临时 Swap 并在测试结束后清理。
- **架构支持**：支持 `x86_64` 与 `ARM / aarch64` Linux 系统（需 `root` 权限）。

## 一键运行

### 默认中文输出
```bash
bash <(curl -sL https://github.com/amourxiao/NodeQuality-GB5/raw/main/gb5.sh)
```
或使用 raw 地址：
```bash
bash <(curl -sL https://raw.githubusercontent.com/amourxiao/NodeQuality-GB5/main/gb5.sh)
```

### 常用参数

| 参数 | 说明 |
| --- | --- |
| `-E` / `-e` | 使用英文输出（默认中文） |
| `-V` / `-v` | 深度模式，额外展示 Geekbench 5 各子项分数对比表 |
| `-f` | 报告头部显示完整公网 IP（默认打码为 `x.x.*.*`） |
| `-4` / `-6` | 仅使用 IPv4 或 IPv6 获取头部展示 IP |
| `-d <dir>` | 指定 `BenchOs` 临时工作目录（默认当前目录，建议预留 ≥1.5GB 空间） |
| `-o <file>` | 将报告保存到文件（`.ansi` 后缀保留彩色 ANSI 码，其他后缀输出纯文本） |
| `-h` | 显示帮助信息 |

示例（英文 + 深度模式 + 保存纯文本报告）：
```bash
bash <(curl -sL https://github.com/amourxiao/NodeQuality-GB5/raw/main/gb5.sh) -E -V -o gb5_report.txt
```

## 致谢与协议

本项目基于以下开源项目修改裁切，遵循原项目协议以 **AGPL-3.0** 开源：
- [LloydAsp/NodeQuality](https://github.com/LloydAsp/NodeQuality)
- [xykt/HardwareQuality](https://github.com/xykt/HardwareQuality)
