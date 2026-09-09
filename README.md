# Toki · HarmonyOS NEXT 移植版

> [WJKLL/Toki](https://github.com/WJKLL/Toki) 的 **HarmonyOS NEXT 移植版**独立仓库。
> 以 Flutter-OH(**3.44.9 ohos-canary1 / API 24**)镜像维护;与主工程**同代码线**(应用 UI/数据/测试共享),平台能力由本镜像侧插件与引擎补丁承接。

## 鸿蒙能力
| 能力 | 说明 |
| --- | --- |
| 桌面「今日课程」实况卡片 | 系统服务卡片(Form Kit):今日课程 + 上课圆环倒计时,深浅色自适应,杀进程 30 分钟兜底刷新 |
| **实况窗(Live View Kit)** | 课程时段计时三节点(课前 ≤30min / 课中 / 课间);胶囊 + 卡片态;归零自动切文案。参数校验已全通,**待正式权益**;不可用时自动降级到常驻通知 + 卡片 |
| **沉浸光感** | 卡片 / 底栏液态指示器 / 宽屏侧边栏指示框 / 分段选择器选中项的边缘光感 + 按压光圈;**档位可配**(设置 → 外观 → 沉浸光感:关 / 标准 / 丰富);纯 Canvas 绘制,零额外模糊 pass |
| 课程提醒 | ReminderAgent 精确到点通知 + 课中常驻通知(每分钟更新) |
| Steam 凭证 | HUKS AES-256-GCM 加密存储(替代 flutter_secure_storage) |
| 平台文件操作 | 选图/选 Excel/保存文件/存相册(原生 Picker;主工程抽象 `PlatFileOps` 反哺) |
| 渲染性能 | 引擎 render-scale 0.8(120Hz 预算内)+ LTPO 帧率投票 |
| 应用内字体 | HarmonyOS Sans(不打包本地字体,HAP -17MB);字体跟随系统缩放 |

## 更新日志

### v1.49.3 · 2026-09-09
**沉浸光感二期**
- 新增**按压光圈**:卡片按下时白色柔光从触点扩散(180ms),松手 260ms 回收;仅按压期间有 Ticker。
- 新增**指示框光感**:窄屏底栏液态指示器、宽屏侧边栏选中项、分段选择器选中块(形状分别对齐系统 `StadiumBorder` / `Squircle 16` / `Squircle 12`)。
- 新增**光感档位**:设置 → 外观 → 沉浸光感 → **关 / 标准 / 丰富**(持久化,默认标准);档位强度系数 0 / 1.0 / 1.7。
- 按观感要求**移除彩色光源**,保留边缘层次(深色白描边 / 浅色上白高光+下淡黑线)与顶高光线。
- 性能:浅色模式**卡片不画光感**(大面积混合是掉帧主因),仅保留导航组件;深色不变。全部绘制为纯 Canvas,无 `BackdropFilter`/`ImageFilter`/`MaskFilter`,静止零重绘。
- 修复:浅色掉帧、丰富档边缘色斑、按压残留。

### v1.49.2 · 2026-09-09
- **实况窗(Live View Kit)接入**:新增 `xiangjugong/liveview` 通道(probe/start/update/stop/isActive)+ `PlatLiveView` 契约 + `OhosLiveView` 实现;课程时段计时三节点。真机实测参数校验全部通过,`startLiveView` 返回 `1003500005`(权益未开通)→ 权益通过后**零代码改动**即可生效。
- 版本号规则:大版本与主项目同步,**鸿蒙本地能力增删改只动小版本**。

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
**完整操作演示(2026-09-09,含声音)**:[GitHub 页面内播放](https://github.com/WJKLL/Toki/blob/main/docs/demo/toki-demo-20260909.mp4) · [直接下载 MP4](https://github.com/WJKLL/Toki/raw/main/docs/demo/toki-demo-20260909.mp4)(存于主仓库文档区;HarmonyOS 版 UI 与主工程同源)

## 已知边界(详见 NATIVE_FEATURES.md §3)
- 锁屏「通知实况窗」:API 24 仅系统应用(Live View Kit 属 API 26 预览);
- 实况表单(liveForm):代码就绪,官方工具链(6.1.1.300 CLI / DevEco 26)PreBuild 均不支持,升级后加回注册;
- 卡片「杀后台持续更新」:系统服务卡片刷新上限 30 分钟(App 活着每分钟,结束时刻恒准确)。

## 重放/重打补丁
见 `PATCHES.md`(引擎升级 / `flutter update-engine` / clean 后按 P1b 方法重打 HAR;备份链 .orig/.orig2/.orig3)。
