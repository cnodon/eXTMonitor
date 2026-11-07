# eXTMonitor

macOS 与 Android TV 扩展屏控制工具。提供 Sunshine + Moonlight、OpenDisplay 和 HDMI 三种入口，全部日常操作集中在一个毛玻璃桌面面板。

**当前为实验版本。4K60 是目标配置，尚未完成持续 60fps 验收。**

## 功能

- 一键连接、断开、切换方案；管理自己创建的虚拟屏。
- 显示实际桌面像素尺寸、接收端解码帧率、网络往返和码率；未采集的指标显示 `—`。
- Mac / 电视音频选项。Sunshine 电视音频需要 BlackHole 2ch；OpenDisplay 当前仅支持 Mac 输出。
- Android TV 接收入口与 4K Surface 适配；电视视频画面默认不显示统计叠层。
- 关闭或切换会话时恢复应用管理的音频输出，保留用户随后手动选择的输出设备。
- 桌面实时卡片随应用运行；WidgetKit 小组件需在 macOS 小组件图库中手动添加。

## 三种方案

| 方案 | Mac 端 | 电视端 | 当前限制 |
| --- | --- | --- | --- |
| Sunshine | SimpleDisplay、Sunshine | Moonlight | 首次配对；电视音频需要 BlackHole；本版本不承诺 HDR |
| OpenDisplay | OpenDisplay | 本仓库提供的 GPL 电视适配 | Android Beta；不传音频；本机动态测试约 30fps，未达持续 60fps |
| HDMI | 支持 4K60 的接口与线材 | HDMI 输入 | 必须实际接线；目前只自动匹配 Sony / BRAVIA 设备 |

独立安装的依赖及固定版本见 [dependencies-lock.json](macos/dependencies-lock.json)。视频通过局域网传输，ADB 用于启动和停止电视接收端。请只在可信局域网内开启电视调试。

## 构建

需要 Apple Silicon Mac、Xcode/Command Line Tools、Python 3、Android SDK 36 / Build Tools 36.0.0，以及 JDK 17 或更高版本。

```bash
python3 -m unittest discover -s tests -v
bash tools/build-android.sh
bash tools/build-tv-receiver.sh
EXTMONITOR_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' bash tools/build-macos.sh
```

- Android 产物：`output/android/eXTMonitor-TV-0.1.0.apk`。
- OpenDisplay 电视接收端：`output/connect/DDMM-OpenDisplay-1.30.2-ddmm.1.apk`，历史包名为 `local.ddmm.opendisplay`。
- macOS 产物：`output/connect/macos/eXTMonitor.app`。
- `ANDROID_SDK_ROOT`、`DDMM_JAVA_HOME` 可覆盖 SDK/JDK 路径。
- Android 开发签名保存在本机 `~/.android/`，不会加入仓库。电视接收端默认复用 DDMM 开发签名；可使用 `EXTMONITOR_TV_KEYSTORE` 覆盖。
- macOS 未指定签名身份时使用 ad-hoc 签名，仅供本机构建。要使用 WidgetKit 共享容器，需在 `macos/Shared.swift` 和两个 entitlement 文件中配置自己的 Team ID 与 App Group，并使用有效开发者签名。当前值保留首台开发机的标识以兼容已安装数据。

## 从零安装：普通用户

支持 Apple Silicon Mac、macOS 14+ 和 Android TV 8+。当前接收端主要在 Sony XR-75X95EK 上验证。

1. 到 [Releases](https://github.com/cnodon/eXTMonitor/releases) 下载 `eXTMonitor-0.2.0-macos-arm64.zip` 并解压。
2. 将 `eXTMonitor.app` 拖入“应用程序”；或运行同目录的 `Install eXTMonitor.command` 自动复制到个人“应用程序”目录。
3. 启动后仅出现一个桌面面板，没有独立主窗口或 Dock 图标。点击右上角设置，所有设置都在原面板内展开。
4. 电视和 Mac 接入同一局域网。电视“关于”中连续点击版本号开启开发者选项，再开启 USB / 网络调试（菜单名称由厂商决定），查到电视的 IP。
5. 在面板内填写电视 IP，选择方案，点击 **一键安装与检查**。仓库的 `192.168.1.100` 是占位地址。
6. 首次连接时，在电视上批准来自这台 Mac 的 ADB 授权。若安装暂停，批准后再次点击检查即可续接；已安装的组件不会重新安装或清除设置。
7. 按系统提示允许所选 Mac 串流程序“录屏与系统录音”。Sunshine 首次使用还需在电视 Moonlight 中选择电脑，将四位 PIN 填入同一桌面面板。
8. Moonlight 中设置 **3840×2160 / 60fps**，建议先以 40Mbps 测试，再按实际网络调整。OpenDisplay 电视适配会自动上报 4K 面板。

### 一键流程会安装什么

| 组件 | Sunshine 方案 | OpenDisplay 方案 | HDMI |
| --- | --- | --- | --- |
| eXTMonitor 桌面程序 | 必需 | 必需 | 必需 |
| 独立 Python 运行环境 | 自动下载；不改系统 Python / PATH | 同左 | 控制程序需要，首次检查时初始化 |
| Android platform-tools / ADB | 未找到时自动下载 | 未找到时自动下载 | 不需要 |
| SimpleDisplay | 自动下载、校验、安装到 `~/Applications` | 不需要 | 不需要 |
| Sunshine | 自动下载、校验、安装到 `~/Applications` | 不需要 | 不需要 |
| OpenDisplay Mac | 不需要 | 自动下载、校验、安装到 `~/Applications` | 不需要 |
| eXTMonitor TV | 自动安装 APK | 自动安装 APK | 不需要 |
| Moonlight TV | 自动安装官方 APK | 不需要 | 不需要 |
| OpenDisplay TV 适配 | 不需要 | 自动安装本项目 GPL 接收端 APK | 不需要 |
| BlackHole 2ch | 仅“电视音频”需要 | 不支持电视音频 | 不需要 |

普通用户**无需安装 Xcode、Android SDK 或 JDK**。依赖使用固定版本和 SHA-256 校验，下载失败可重试；已有接收端会保留。开发构建的要求与上表不同，见前文“构建”。

系统调试、录屏权限、首次 PIN 配对、管理员安装音频驱动不能静默代替用户批准。程序将这些操作保留为明确的首次设置步骤；完成后正常连接使用面板中的一个开关。

### 音频

- **Mac**：保留本机输出；Sunshine 配置为不传系统音频。
- **电视 / Sunshine**：选择“电视”后，点击面板内“安装电视音频组件”，自动下载并校验官方 [BlackHole 2ch](https://existential.audio/blackhole/) 安装包；在系统安装器中完成确认。串流建立后将输出路由至 BlackHole，Sunshine 从该设备采集；必要时在系统设置中批准音频采集权限。断开时恢复原输出，用户中途手动选择的新设备不会被覆盖。该端到端音频路径尚待完整实测。
- **电视 / HDMI**：实际连接 Sony 的 HDMI 音频设备后可选择；没有设备时不会假装切换成功。
- **OpenDisplay**：上游当前没有音频传输，面板保留 Mac 输出；若需要电视出声，请选择 Sunshine 或 HDMI。

音频驱动安装需要系统管理员确认，安装程序可能提示重启。安装与许可确认完成前，不会声称电视音频已可用。

### 桌面面板与 WidgetKit

默认启动仅显示 **一个桌面面板**：方案、连接开关、音频选择及指标直接显示；IP、PIN、安装检查、权限入口与开源声明在面板内展开。点击菜单栏图标只会显示这一面板，不创建第二个窗口。面板由后台进程维持，约每 5 秒读取状态。

另保留 WidgetKit 扩展，可在 macOS“编辑小组件”图库手动添加。它由系统调度刷新，不承担连续实时监测；本机图库放置尚未验证，不能与已经运行的桌面面板混称。

### 更新、退出与卸载

- 更新：在面板设置中退出，替换 eXTMonitor.app，再启动。数据与配对留在本机，不写入仓库。
- 退出：面板设置中的“退出”先结束自有会话并恢复音频，再关闭后台进程与桌面面板。
- 卸载：退出后将 eXTMonitor.app 移至废纸篓。独立依赖按需单独卸载；BlackHole 使用官方卸载程序。电视端可在应用管理中卸载 eXTMonitor 和不再需要的接收端。
- 本机数据兼容历史路径：`~/Library/Application Support/DDMM Connect`，含下载缓存、独立运行环境和会话配置；Widget 共享容器与 App Group 标识也保留历史名字。确认不再需要配对和配置后再移除这些数据。
- 当前安装包已进行开发者签名，但未完成 Apple 公证。首次打开可能需要在系统界面确认；安装程序不会关闭 Gatekeeper 或修改系统安全策略。

## 源码与许可

- `macos/`、`android/src/`、构建脚本和测试：自研代码使用 [MIT License](LICENSE)。
- `android/receiver/opendisplay-tv.patch` 基于 OpenDisplay，按 GPL-3.0 分发，**不属于 MIT 授权范围**。
- 第三方程序独立安装，许可证见 [开源声明](NOTICE.md)。仓库不包含第三方安装包、私钥、凭据、运行状态或用户截图。

[实现与验收状态](docs/status.md)
