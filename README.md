# 弹跳足球 · Banjoball Godot

Godot 4.6.1 的 3D 足球游戏工程，当前工程版本 **0.4.41**。包含 PC 鼠标操作、Android 虚拟摇杆与拖动施法、角色技能、AI、房间大厅和权威服务器联机实现。

本仓库保留现有工程使用的魔兽模型、贴图、音效以及运行所需地图数据。**这些第三方资源不因出现在公开仓库中而获得 MIT 或其他开源授权。** 请先阅读 [NOTICE.md](NOTICE.md) 和 [THIRD_PARTY.txt](THIRD_PARTY.txt)。本次先公开工程，没有为整个工程授予统一的开源许可证。

## 在电脑上运行

1. 安装 Godot **4.6.1 Standard**（不需要 .NET）。当前包含 Windows x86_64 和 Android 原生加速库；其他平台需要自行编译 `native/`。
2. 克隆仓库，将 `project.godot` 导入 Godot。首次打开需要等待资源导入。
3. 按 F6/F5 运行主场景，体验单机。默认联网目标为本机，不连接原作者的正式服务器。

如果需要联机，先按下文生成自己的证书。仓库不附带原服务器证书、密钥、用户或比赛记录。

## 本地联机开发

需要 Python 3.11+、Godot 4.6.1。以下命令在仓库根目录执行：

```sh
python -m pip install cryptography
python tools/init_local.py
```

初始化只补齐不存在的示例配置和新证书。`server/data/` 是私有数据目录，已加入忽略规则。随后在两个终端分别启动：

```sh
python server/accounts.py
godot --headless --path . --script res://scripts/net_server.gd
```

运行客户端，进入联机大厅。账号服务只监听 `127.0.0.1:27890`，游戏客户端连接 **UDP 27888**。同局域网或公网部署时，把 `assets/network/endpoints.json` 的地址改成自己的服务器地址；所有客户端需要同一服务器的公开证书 `assets/network/server.crt`，不能复制私钥。云平台防火墙和主机防火墙需要放行游戏 UDP 端口。

`server/config.json` 可配置注册截止时间、同时房间数和掉线接管等待时间。示例 `max_rooms=2` 是可修改的初始设置，不是协议容量保证。公网运行前请自行验证负载、带宽、备份和账户安全。此处命令是开发启动方式，不包含生产环境进程守护。

## Android

`tools/build_android.py` 保留现有 Windows 打包流程，但工具链根目录改为环境变量 `BANJO_TOOLCHAIN`，缺省为 `.local/toolchain`。脚本需要该目录中存在 Godot 4.6.1 console、Android SDK（`android-build/sdk`）、JDK（`jdk/jdk-21.0.12.1+1`），以及与 Godot 版本匹配的导出模板。它会修改当前用户 Godot 编辑器的 Android 工具链设置，首次修改前在工具链目录保存备份。

先运行本地联机初始化，再执行打包脚本。签名密钥在本地生成，不包含原项目的发布密钥，因此自行构建的 APK 不能覆盖不同签名的已有安装。第三方转换工具用 `cd tools` 后 `npm ci` 安装；资源转换脚本保留了原开发环境的部分路径，需要按自己的安装位置调整。已有转换资源可直接用于当前 Windows 工程，不必重新提取。

## 代码结构

| 目录 | 内容 |
| --- | --- |
| `scripts/` | 确定性玩法模拟、碰撞与寻路、技能、3D 表现、手机操作和大厅 |
| `server/` | Python 账号与比赛记录服务、配置样例及测试 |
| `native/` | C++ 加速源码、godot-cpp 构建配置 |
| `assets/` | 当前工程资源和转换前素材；第三方资源权利另见说明 |
| `research/` | 运行需要的场地、角色、碰撞和数值数据 |
| `tests/` | 玩法、UI 和联机回归脚本 |
| `tools/` | 本地初始化、资源转换及部分构建工具 |

中文、英文、俄文界面已包含。旧 WebRTC / EasyTier 客户端适配代码仍保留，但本仓库的本地联机说明使用直接连接游戏服务器，不包含旧公共接头服务的部署。

## 验证

```sh
python -m unittest discover -s server -p "test_*.py"
python tools/audit_public.py
godot --headless --path . --script res://tests/network_endpoint_test.gd
```

其他测试中部分依赖资源导入、窗口渲染或原开发工具链；并非全部都适合无图形环境。本次发布验证结果见 [docs/RELEASE_CHECK.md](docs/RELEASE_CHECK.md)。

公开副本排除了导入缓存、历史日志、旧安装包、部署备份、签名密钥、账号数据库和针对原作者线上服务的探针。游戏内容保留，个人部署状态不随仓库分发。
