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

### v1.50.3 · 2026-09-09
**应用更名「百工箱」+ 包名正式化（备案）**
- 原「Toki」在阿里云 App 备案未通过,按项目定位(Miuix 风格生活/换算工具箱)更名为**「百工箱」** —— 中文、简短、直白,含「工」呼应包名 `xiangjugong`。
- 全端显示名统一:Android `android:label` / 鸿蒙 `AppScope` `app_name` + `EntryAbility_label`(base/zh_CN/en_US) / Web `<title>` + `manifest.json` / `AppConstants.appName`。
- **鸿蒙 bundleName 正式化**:`com.example.poc_ohos`(模板占位,阿里云必拒)→ `com.xiangjugong.xiangjugong`(与 Android 一致)。已装 HAP 需卸载重装。
- 备案身份信息(供阿里云 App 备案):Android 公钥/MD5、鸿蒙公钥/MD5、包名、域名 omjl.top —— 均从 keystore / 证书提取并核对。
- 版本:`1.50.1+157` → `1.50.3+160`(大版本与主项目同步)。

### v1.50.1 · 2026-09-09
**滚动期禁卡片按压光圈(GLOW-04)**
- 修复**首页纵向滚动掉帧**:`GlowMaterial` 的 `Listener.onPointerDown` 不参与手势竞技场 —— 手指按在卡片上**直接开始滑动**时,按下瞬间卡片仍会跑 180ms 按压光圈动画(每帧 `setState` 重绘整卡,含 `CardShadow` 双层阴影模糊),松手再 260ms 反向回收;滚动起始因此必然掉帧,而滚动场景本不该有按压反馈。
- 新增全局门控 `GlowPressGate.scrollActive`(`main.dart` 根部 `ScrollNotification` 写入,覆盖全部路由含二级页):滚动中按下直接忽略;滚动开始即刻停掉进行中的光圈并把进度归零(零残留、零后续重绘)。
- 非滚动路径(点击、长按)的按压反馈完全不变;纯状态门控,无新增 Ticker / 无额外绘制。
- 版本:`1.50.0+156` → `1.50.1+157`(大版本与主项目同步,鸿蒙本地能力增删改只动小版本)。

### v1.50.0 · 2026-09-09
**记账一级页 + 首页记账卡**
- 新增**记账一级页(P-20)**:底栏 3 → 4 项(待办 / 首页 / 记账 / 工具),宽屏侧边栏同源自动跟随;单月视图 = 月份导航 + 支出/收入/结余汇总卡 + 按日分组流水列表;C-24 毛玻璃 FAB「记一笔」→ 底部 sheet(支出/收入 → 金额 → 分类 → 备注 → 日期),长按流水卡 = 编辑 / 删除。
- 新增**记账领域层(S-25)**:金额一律「分」为单位的 `int`(避免 double 累加误差);内置预设 12 支出 + 购物下 13 二级 + 5 收入;存储沿用 prefs + JSON(`ledger.entries` / `ledger.categories` / `ledger.budgetCents`,与待办同模式);月度统计与按日分组为纯函数。
- 新增**C-45 记账图标集(自绘矢量)**:flutter_miuix 内置图标(basic 7 + extended 124)不含钱包/餐饮/交通/医疗语义,按 miuix 面性图标语言自绘 30 个 24×24 图标(`MiuixVectorIcon` + 纯几何填充路径,与内置图标同管线 tint/缩放,静止零重绘)。
- 新增**首页两张记账卡**:C-51 剩余卡(1×1,本月剩余圆环,默认金黄 `#F5A623`、Monet 开启时跟随取色主色、超支转 error;口径 = 预算 + 本月收入 − 本月支出)+ C-52 支出卡(2×1,本日 / 本周 / 本月 / 本年四档同时展示)。
- 修复**分段按钮(GlowTabRow)背后的大方块**:`MiuixTabRow` 默认整条撑满宽度的直角 surface 底色带,在底部 sheet(底色 `colors.background`)里呈显眼方块 → 改透明底(仅保留选中指示块),并修正光感指示器几何(原未扣除 `itemSpacing` 9)。
- 修复**横屏 + 键盘弹出时 sheet 底部空白**:鸿蒙横屏键盘弹起时 Flutter 视图整体缩小(overlay 高 = 屏幕高 − 键盘高,viewInsets 归零),但 `MiuixOverlayBottomSheet` 会把 viewInsets 加进**卡片背景内部** → 横屏时归零 viewInsets(视图已缩小时为幂等 no-op),内容区保持自然高度。
- 修复**深色 FAB 可见性**:C-24 毛玻璃 FAB 深色下背景不透明度 0.20 → 0.55(降级态 0.88 → 0.94),并叠 GLOW-02 光感材质;待办页自绘 FAB 删除、统一改用 C-24。
- 修复**GLOW-02 顶高光线在窄容器上退化成白点**:原按固定 `inset(12) + radius` 取端点,FAB(56px / radius 18)上起点 30 > 终点 26 → 线长变负、渲染成一个点;改为按宽度比例取 18%~82%,宽卡片观感不变。
- 版本:`1.49.3+155` → `1.50.0+156`(大版本与主项目同步,鸿蒙本地能力增删改只动小版本)。

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
