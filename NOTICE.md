# 开源声明

## eXTMonitor

Copyright (c) 2026 eXTMonitor contributors.

本项目原创的 macOS 控制面板、桌面卡片、WidgetKit 扩展、Android TV 入口、控制脚本和测试使用 MIT License，完整许可见根目录 LICENSE。

## OpenDisplay 电视适配

上游：[peetzweg/opendisplay](https://github.com/peetzweg/opendisplay)，v1.30.2，源码提交 `c023ef3e9dfed7497f89b47cd70d0aa420a59f30`。

`android/receiver/opendisplay-tv.patch` 包含上游代码的上下文及修改，遵循 GNU GPL v3；完整许可证见 [LICENSE-OpenDisplay](android/receiver/LICENSE-OpenDisplay)。上游版权属于其原作者。修改包括电视入口、横屏、4K Surface、HiDPI 面板上报、默认关闭统计叠层和简化等待界面。构建脚本固定源码提交并应用补丁，不重写上游工作区。

如分发修改后的接收端二进制，须同时按 GPL 要求提供完整对应源码（包括该固定提交、补丁和构建材料），不能将接收端重新标记为 MIT。从 v0.2.0 起，Release 中的接收端 APK 附有 `OpenDisplay-TV-source-1.30.2-ddmm.1.tar.gz` 完整对应源码及构建说明。

## 独立安装的第三方软件

| 软件 | 用途 | 许可证 / 上游 |
| --- | --- | --- |
| Sunshine | 视频与音频串流服务 | [GPL-3.0](https://github.com/LizardByte/Sunshine/blob/master/LICENSE) |
| Moonlight Android | 电视硬件解码接收端 | [GPL-3.0](https://github.com/moonlight-stream/moonlight-android/blob/master/LICENSE) |
| SimpleDisplay | 虚拟扩展屏 | [GPL-3.0](https://github.com/SamuelRioTz/SimpleDisplay/blob/main/LICENSE) |
| OpenDisplay | 虚拟屏与串流 | [GPL-3.0](https://github.com/peetzweg/opendisplay/blob/main/LICENSE) |
| BlackHole | macOS 虚拟音频环回 | [GPL-3.0](https://github.com/ExistentialAudio/BlackHole/blob/master/LICENSE) |

上述程序通过外部进程、URL 或系统音频接口协作，未作为源码或二进制捆绑进 MIT 应用发布。产品名称和商标属于各自权利人，本项目与这些项目、Apple 或 Sony 无隶属关系。

## 安装工具下载的运行组件

独立 Python 运行环境来自 [astral-sh/python-build-standalone](https://github.com/astral-sh/python-build-standalone)，CPython 使用 PSF 许可证，构建中各依赖的许可证随上游归档提供。安装器只下载并校验，不修改或重新授权这些组件。

ADB 来自 [Google Android Platform Tools](https://developer.android.com/tools/releases/platform-tools)，遵循其附带许可与通知文件。下载归档的 SHA-256 记录在依赖锁中；未将这些工具加入源码仓库。
