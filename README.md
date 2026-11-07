# eXTMonitor

macOS 与 Android TV 扩展屏控制工具。提供 Sunshine + Moonlight、OpenDisplay 和 HDMI 三种入口，以及毛玻璃控制面板、桌面实时卡片和 WidgetKit 扩展。

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

## 安装与连接

1. 将 `eXTMonitor.app` 放入“应用程序”，安装所选方案依赖。
2. 电视开启 ADB 网络调试，首次连接时在电视上批准；安装 eXTMonitor TV、Moonlight 或电视版 OpenDisplay。
3. 在控制面板设置中填写电视 IP。仓库中的 `192.168.1.100` 仅为占位地址。
4. 为 Sunshine / OpenDisplay 授予屏幕录制权限。选择方案并开启扩展。
5. Sunshine 首次连接需在 Moonlight 中选择电脑，将电视显示的 PIN 填入 Mac 控制面板。
6. Moonlight 中手动设置 3840×2160、60fps 和适合网络的码率。桌面 4K 不等于视频流自动为 4K。
7. 选择电视音频前安装 [BlackHole 2ch](https://existential.audio/blackhole/)。必要时批准 Sunshine 的音频采集权限；具体音频链路仍需在你的设备上验收。

WidgetKit 由系统调度刷新，不用于持续实时监测；桌面卡片与控制面板约每 5 秒读取一次状态。OpenDisplay 的低帧率可能来自静态桌面减少采样；持续运动场景的结果才适合比较性能。

## 源码与许可

- `macos/`、`android/src/`、构建脚本和测试：自研代码使用 [MIT License](LICENSE)。
- `android/receiver/opendisplay-tv.patch` 基于 OpenDisplay，按 GPL-3.0 分发，**不属于 MIT 授权范围**。
- 第三方程序独立安装，许可证见 [开源声明](NOTICE.md)。仓库不包含第三方安装包、私钥、凭据、运行状态或用户截图。

[实现与验收状态](docs/status.md)
