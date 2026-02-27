openclaw-cachyos-secure-podman.sh Documentation
 
中文说明
 
项目信息
 
- 脚本名称：openclaw-cachyos-secure-podman.sh
- 适用系统：CachyOS (Arch Linux 系)
- 运行方式：Podman 无根模式（rootless）
- 功能：安全、隔离、一键启动 OpenClaw 容器环境
 
 
 
功能概述
 
本脚本用于在 CachyOS 上以 Podman rootless 安全模式启动 OpenClaw 容器。
特点：
 
- 无根容器，无 root 权限风险
- 主机网络模式，保证本地服务互通
- 配置文件挂载，外部可修改
- 自动后台运行
- 干净、安全、可重复执行
 
 
 
前置要求
 
1. 已安装 Podman
2. 已构建 OpenClaw 镜像
3. 已生成配置文件（如  config.json ）
 
 
 
使用方法
 
bash
  
# 赋予执行权限
chmod +x openclaw-cachyos-secure-podman.sh

# 运行
./openclaw-cachyos-secure-podman.sh
 
 
 
 
容器启动参数说明
 
-  --name openclaw ：容器名称
-  -d ：后台运行
-  --network host ：使用主机网络，便于 Ollama / 本地模型互通
-  -v ./config.json:/app/config.json ：挂载外部配置文件
- 自动使用当前用户构建的 rootless 镜像
 
 
 
常见操作
 
bash
  
# 查看容器运行状态
podman ps

# 查看日志
podman logs openclaw

# 停止容器
podman stop openclaw

# 重启容器
podman start openclaw
 
 
 
 
注意事项
 
- 本脚本仅用于测试/开发环境
- 必须使用 Podman 无根模式，不推荐 root 运行
- 配置文件  config.json  必须在脚本同一目录
- 若端口冲突，请停止占用端口的服务后再启动
 
 
 
 
 
English Documentation
 
Project Info
 
- Script Name: openclaw-cachyos-secure-podman.sh
- OS Support: CachyOS (Arch-based)
- Runtime: Podman rootless mode
- Purpose: Secure, isolated one-click start for OpenClaw container
 
 
 
Overview
 
This script starts the OpenClaw container in secure Podman rootless mode on CachyOS.
 
Features:
 
- Rootless container, no privilege risks
- Host network for better local service connectivity
- External config file mount
- Run in background
- Clean, safe, repeatable
 
 
 
Prerequisites
 
1. Podman installed
2. OpenClaw image already built
3. Config file ( config.json ) ready
 
 
 
Usage
 
bash
  
chmod +x openclaw-cachyos-secure-podman.sh
./openclaw-cachyos-secure-podman.sh
 
 
 
 
Key Podman Flags
 
-  --name openclaw : Set container name
-  -d : Run in background
-  --network host : Use host network
-  -v ./config.json:/app/config.json : Mount external config
 
 
 
Common Commands
 
bash
  
podman ps
podman logs openclaw
podman stop openclaw
podman start openclaw
 
 
 
 
Notes
 
- For test/development use only
- Must run in Podman rootless mode
-  config.json  must exist in the same directory
- If port conflict occurs, stop conflicting services first
 
 
 
需要我再帮你把三个脚本的总 README 也写好吗？直接一套完整仓库说明丢上去就能用。
