# NATIVE_FEATURES.md — 鸿蒙原生能力实现登记(2026-09)

> 与 PATCHES.md(引擎补丁)互补:本文件登记 **应用侧原生能力**(插件通道 + Form 卡片)。
> 基线:Flutter-OH 3.44.9 canary1 / API 24 工具链(release 严格 ArkTS)。

## 1. 通道总览(plugins/xiangjugong_ohos → XiangJuGongChannelsPlugin.ets)

| 通道 | 方法 | 实现 | 状态 |
| --- | --- | --- | --- |
| `xiangjugong/media` | saveImage | 相册(photoAccessHelper) | S1 已有 |
| `xiangjugong/log` | exportLog/saveToDownloads | DocumentViewPicker | S1 已有 |
| `xiangjugong/refresh` | setHigh/setNormal | 空(系统自适应) | S1 已有 |
| `xiangjugong/picker` | pickImage/pickExcel/saveFile | PLAT-01 文件操作 | S1 已有 |
| `xiangjugong/reminder` | scheduleAlert/cancelAlert/cancelAllAlarms/startCountdown/stopCountdown/requestNotificationPermission/… | **S2 落地**(↓ 2.1) | 本期 |
| `xiangjugong/cards` | syncToday | 今日课程快照 → course_card.json → 卡片 updateForm(↓ 2.2) | 本期 |
| `xiangjugong/secure` | write/read/delete | **HUKS AES-256-GCM**(↓ 2.3) | 本期 |
| `xiangjugong/diag` | log | 诊断(hilog) | 开发用 |
| `xiangjugong/liveview` | probe/start/update/stop/isActive | **实况窗 LiveView Kit**(↓ 2.4) | S1 本期 |

## 2. 本期实现

### 2.1 课程提醒(替代 Android AlarmManager/前台服务)
- `scheduleAlert`:ReminderAgentManager `REMINDER_TYPE_TIMER`(剩余秒数,`notificationId`=Dart id,`tapDismissed`);同 id 先 cancel 再 publish(覆盖语义)。`dartId→reminderId` 映射持久化于 preferences(`xjug_reminder`),进程重启可取消。
- `startCountdown`:常驻通知(`isOngoing`,id=9000)+ 每 `updateIntervalMs`(默认 60s,下限 10s)自算剩余重发;**同时回写实况卡片圆环**(formProvider.updateForm,↓ 2.2)。下课自动停。
- `requestNotificationPermission` → `notificationManager.requestEnableNotification`(用户拒绝静默)。
- `canScheduleExactAlarm`=true(OH 无精确闹钟限制);`getDiagnostics` 返回 {scheduled,lastAtMillis}。

### 2.2 桌面「今日课程」服务卡片(Form Kit)+ 实况卡片圆环倒计时
- 文件:`entry/src/main/ets/formextensionability/EntryFormAbility.ets` + `pages/TodayCourseCard.ets` + `resources/base/profile/form_config.json`(2*2/2*4,默认 2*4,updateDuration 60 分钟兜底)。
- 数据管线:Dart `CourseCardSync`(lib/core/cards/course_card_sync.dart)算今日快照(周次过滤/时段状态/时间文本)→ cards 通道 → 插件写 `filesDir/course_card.json`(课表字段 + countdown 字段)→ FormExtensionAbility 读同一文件 → formBindingData 下发。
- **圆环倒计时**:课中 `startCountdown` 每分钟 updateForm(countdownActive/Title/Text/Pct/Remain);进程被杀时 `onUpdateForm` 按墙钟从文件内 `countdownEndAt/countdownTotal` 重算(兜底精度=定时刷新周期)。
- formId 登记:`filesDir/card_form_ids.json`(卡片 Ability 写,插件读 → updateForm)。
- 卡片 ArkTS 明细:Progress Ring 48dp + 3 课程行(当前节高亮);字段契约见 `CardData`/`CardBindingData`。
- **已知限制**:卡片仅桌面(主屏);锁屏实况窗需 API 26+ Live View Kit(↓ 3)。

### 2.3 Steam token HUKS 加密存储
- 通道 `secure`:`write/read/delete`;HUKS AES-256-GCM(alias `xjug_secure_v1`;init 不传 IV → 系统生成 IV 拼在密文前 16B;解密切 IV 回填 `HUKS_TAG_IV`)→ base64 → preferences(`xjug_secure`)。
- Dart:`OhosSecureStore`(lib/core/platform/impl/ohos/secure_store_ohos.dart);`steam_auth_service.dart` 工厂加 OH 分支(`OhosSteamAuthService`,镜像专属,主工程保持 flutter_secure_storage)。

### 2.4 实况窗 LiveView Kit(S1 骨架,2026-09-09)
- 通道 `xiangjugong/liveview`:`probe/start/update/stop/isActive`;实现于 `XiangJuGongChannelsPlugin.ets`(约 330 行)。
- Dart 侧:`PlatLiveView` 契约(`lib/core/platform/contract/plat_live_view.dart`,双端同字)+ 镜像实现 `OhosLiveView`(`impl/ohos/live_view_ohos.dart`,镜像独有);`main.dart` 注册 `PlatLiveViewRegistry.register(const OhosLiveView())`。
- 原生侧收口三件事:**sequence 自增持久化**(`xjug_liveview` preferences,防 1003500011)、**同 id 先 stop 再 start**(防 1003500006)、**全局 1s 节流**(防 1003500008);任何失败都返回 `degraded` 不打断业务。
- 诊断入口:设置页「实况窗诊断(LiveView Kit)」→ 显示 `supported/enabled/resultCode`。
- **实测(2026-09-09,LRT-W30)**:`[LiveView] supported=true enabled=true code=0` —— 设备能力与权益均可用;系统侧存在 `LiveCapsuleListVm`(SystemUI 实况窗胶囊组件)。
- 场景规格与节点设计见 `D:\Projects\LIVEVIEW_PLAN.md`(v3);官方设计文档留档于 `D:\Projects\design_refs\`。
- 待办:start/update/stop 的真机全链路验证放 S2(课程时段计时场景首次接入时)。

#### 2.4.1 平台参数校验约束(2026-09-09 逐项实测踩坑,重要)
`startLiveView` 的参数校验比 d.ts 声明严格得多,以下字段**必填**,缺失均报 `401`:

| 字段 | 说明 |
|---|---|
| `primary.title` | 非空字符串 |
| `primary.clickAction` | 必填 `WantAgent`(d.ts 标可选) |
| `primary.layoutData` | **即使不展开也必须传**(用 `LAYOUT_TYPE_DEFAULT`) |
| `capsule.icon` | 必填;PixelMap 需 **≤36px**,过大判「parameter length exceeds the limit」 |
| `capsule.backgroundColor` | 必填(默认 `#000000`;当前仍被拒,待查格式) |
| `capsule.title` | 必填,但 **TimerCapsule 类型未声明该字段** → 改用 `TextCapsule` |
| `layoutData.nodeIcons` | progress 布局必填(2-5 个节点图标);当前未通过 → 暂用 DEFAULT 布局 |

**两个关键坑**:
1. **嵌套 Map 参数不可用**:Dart 侧传嵌套 Map,ArkTS 侧 `as SomeInterface` 断言后**属性访问恒为空**(报「mustbe string」)。
   → 必须按项目惯例改为 **JSON 字符串 + `JSON.parse`**(`{'id': n, 'json': jsonEncode(spec)}`)。
2. **自动降级**:胶囊参数被拒时,ArkTS 侧自动去掉胶囊重试,保证卡片态可用(`liveview retried without capsule`)。

#### 2.4.2 权益实测结论
参数校验全部通过后,`startLiveView` 返回 **`1003500005 - The right of liveView is not enabled`** ——
即:代码链路已完全打通,**仅差正式权益**;权益通过后无需改代码即可生效。
(`isLiveViewEnabled()` 返回 `true` 只代表系统开关允许,不代表正式权益已开通。)

## 3. 待办/升级项
- **实况窗(LiveView Kit)**:✅ 已落地 S1 骨架(见 §2.4)。~~「API 24 SDK 无该 Kit」为误记~~ —— 实际 `@kit.LiveViewKit` 自 4.1.0(11) 起可用,SDK `6.1.1.125` 完整包含,设备实测 `supported=true enabled=true`。
- **API 26+ 锁屏实况窗(沉浸态)**:`LiveViewLockScreenExtensionAbility` 随 Kit 提供(5.0.0(12) 起);`NOTIFICATION_CONTENT_LIVE_VIEW` 仍标注仅系统应用;届时把 2.1/2.2 的倒计时接到锁屏灵动区。
- **实况表单(Live Form,API 20+)(已写代码,注册被工具链限制)**:`liveformability/LiveFormAbility.ets` + `pages/LiveCoursePage.ets`(大圆环 + 剩余分钟 + 下课时间,30s 自治刷新读同源 course_card.json)+ `profile/live_form_config.json` 均已就绪;但 command-line-tools **6.1.1.300 的 PreBuild 不支持 `type:"liveForm"`**(报 `Cannot read properties of undefined (reading 'includes')`,modulecheck schema 有该枚举而 PreBuild 执行器没有)→ module.json5 注册已移除。启用路径:DevEco Studio GUI 工程 / 升级工具链 / API 26 工具链(compatibleSdkVersion 24)后加回注册。
- **壁纸背景(2026-09-08 调研,未落地)**:①自定义壁纸双端可做(主工程 0.5d + 镜像 0.5d);②OH 系统壁纸:`@ohos.wallpaper.getFile(WALLPAPER_SYSTEM)` + `ohos.permission.GET_WALLPAPER`(需真机验证权限级别);③Android 14+(API 34+)官方禁止读系统壁纸 → 主工程只做自定义;④深浅压暗:浅 α≈0.30 / 深 α≈0.60,`BoxFit.cover`;⑤可选壁纸取色 → Monet keyColor。
- 通知栏常驻倒计时(方案 B)未做:进程被杀后通知文本静止,卡片定时刷新兜底(可接受);若要"被杀也跳数字",评估 OH 长时任务白名单后再加。
- 卡片数据刷新在 app 未运行时冻结(课程表变更需打开 app 才同步)——课表低频,可接受。

## 3.5 字体与命名(2026-09-08)
- **应用字体**:镜像**不注册本地字体**(fonts 段移除)→ 引擎 fallback 系统默认 = **HarmonyOS Sans**(与系统界面一致;HAP -17MB);主工程(Android/Web)保留 Noto Sans SC 本地注册(Web 远程字体修复依赖)。
- **字体跟随系统**:镜像 `main.dart` 根 MediaQuery `textScaler` 改为**完全跟随系统**(移除 v1.0.1 的 `noScaling` 强制;大字体下 Miuix 溢出需个案修复,不再锁死)。
- **应用名/图标**:桌面显示名 `poc_ohos` → `Toki`;图标 = 品牌图(`assets/images/app_icon.png` 192×192;入口 icon.png + AppScope app_icon.png)。
- UI 风格化(鸿蒙蓝/轻阴影/标题超粗)同日尝试后**按用户要求全部回档**(主工程 git 基线;镜像同步恢复);后续再试走"不动字体,只改色板+形状"路线。
- 渲染分辨率缩放:0.75 → **0.8**(PATCHES P2 已更新;har 备份 .orig3)。

## 4. 验证清单(真机 API24)
- [ ] 到点提醒:上课前 N 分钟锁屏弹通知
- [ ] 常驻倒计时:课中通知"距下课约 X 分钟"
- [ ] 桌面卡片:长按桌面 → 服务卡片 → 「今日课程」→ 显示今日课程(当前节高亮)
- [ ] 圆环倒计时:课中卡片圆环+剩余分钟每分钟刷新;杀 app 后 60 分钟内兜底刷新
- [ ] Steam key 持久:配置 key → 杀进程 → 重开仍登录(密文在 xjug_secure preferences)
- [ ] #6 系统信息:设置页显示 HarmonyOS

## 5. 重放/重建注意
- 插件/EntryAbility/卡片全部为**工程源码**(非引擎产物),`flutter clean` 后自动重建,无需手动补丁。
- `form_config.json` 的 schema 硬性要求:`isDefault` 必填(单卡 true)、`updateDuration` 为 30 的倍数、`supportDimensions` 仅 1*2/2*1/2*2/2*4/4*4。
- ArkTS 红线(踩坑记录):无 `delete`(用过滤重建)、无对象 spread(手写拷贝)、object literal 必须显式 interface、fileIo 无 `writeTextSync`(用 openSync+writeSync)、卡片扩展无 Log 工具(console.info)。
