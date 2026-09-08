# Toki · HarmonyOS NEXT 移植版

> [WJKLL/Toki](https://github.com/WJKLL/Toki) 的 **HarmonyOS NEXT 移植版**独立仓库。
> 以 Flutter-OH(**3.44.9 ohos-canary1 / API 24**)镜像维护;与主工程**同代码线**(应用 UI/数据/测试共享),平台能力由本镜像侧插件与引擎补丁承接。

## 鸿蒙能力
| 能力 | 说明 |
| --- | --- |
| 桌面「今日课程」实况卡片 | 系统服务卡片(Form Kit):今日课程 + 上课圆环倒计时,深浅色自适应,杀进程 30 分钟兜底刷新 |
| 课程提醒 | ReminderAgent 精确到点通知 + 课中常驻通知(每分钟更新) |
| Steam 凭证 | HUKS AES-256-GCM 加密存储(替代 flutter_secure_storage) |
| 平台文件操作 | 选图/选 Excel/保存文件/存相册(原生 Picker;主工程抽象 `PlatFileOps` 反哺) |
| 渲染性能 | 引擎 render-scale 0.8(120Hz 预算内)+ LTPO 帧率投票 |
| 应用内字体 | HarmonyOS Sans(不打包本地字体,HAP -17MB);字体跟随系统缩放 |

## 目录
| 项 | 说明 |
| --- | --- |
| `lib/` | Flutter 应用镜像(`lib/core/platform/impl/ohos/` 为 OH 平台实现) |
| `plugins/xiangjugong_ohos/` | 自研通道插件:media/log/refresh/reminder/cards/secure/diag(ArkTS) |
| `ohos/entry/.../formextensionability/` | 桌面「今日课程」服务卡片;`liveformability/`(实况表单代码就绪,工具链拦截未启用) |
| `PATCHES.md` | 引擎补丁登记(P1b autoFill / P2 渲染缩放 0.8;HAR 重放方法) |
| `NATIVE_FEATURES.md` | 原生功能实现档案(通道/卡片/HUKS/验证清单/API26 待办) |
| `framesconfig.json` | LTPO 帧率投票开关(SWITCH 1) |

## 构建(Windows,API 24 CLI)
```powershell
pwsh ohos-flutter-api24.ps1 build hap --release --target-platform=ohos-arm64
```
产物:`ohos/build/...`;**安装包(HAP)发布在 [Releases](https://github.com/WJKLL/Toki-HarmonyOS/releases)**。

## 演示
HarmonyOS 适配版完整演示(2026-09-08):[GitHub 页面内播放](https://github.com/WJKLL/Toki/blob/main/docs/demo/9月8日.mp4) · [直接下载 MP4](https://github.com/WJKLL/Toki/raw/main/docs/demo/9月8日.mp4)(存于主仓库文档区)

## 已知边界(详见 NATIVE_FEATURES.md §3)
- 锁屏「通知实况窗」:API 24 仅系统应用(Live View Kit 属 API 26 预览);
- 实况表单(liveForm):代码就绪,官方工具链(6.1.1.300 CLI / DevEco 26)PreBuild 均不支持,升级后加回注册;
- 卡片「杀后台持续更新」:系统服务卡片刷新上限 30 分钟(App 活着每分钟,结束时刻恒准确)。

## 重放/重打补丁
见 `PATCHES.md`(引擎升级 / `flutter update-engine` / clean 后按 P1b 方法重打 HAR;备份链 .orig/.orig2/.orig3)。
