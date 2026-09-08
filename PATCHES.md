# PATCHES.md — Flutter-OH embedding 的 API 26 适配补丁登记

> 目的:阶段 0 遇到的引擎侧编译缺陷与手工补丁的**可重放记录**。任何覆盖(引擎升级/ohpm 重装/clean)后需按此重放。

## P1:autoFillManager API 26 重构适配(2026-09)

### 背景(实测)
- Flutter-OH `3.44.9+ohos-0.0.1-canary1` 的 `flutter_embedding_debug.har`(版本 `1.0.0-7c82f544833`,由引擎自举产物提供,`flutter/bin/cache/artifacts/engine/ohos-arm64/flutter_embedding_debug.har`)按 **API ≤25** 的 autoFillManager API 编写。
- 本机 DevEco **26.0.0.461(API 26)** SDK 已删除: `AutoFillType / ViewData / FillRequest / AutoFillCallback / FillFailureResult / SaveRequest / AutoFillTriggerType / requestAutoFill`;`requestAutoSave` 签名改为 `(context: UIContext, callback?: AutoSaveCallback)`。
- 后果:`flutter build hap --debug` 报 **15 个 ArkTS 编译错误**,全部集中在 `OhosAutoFillHelper.ets`。

### 目标文件(oh_modules 生成物,路径含内容 hash)
```
<project>/ohos/oh_modules/.ohpm/@ohos+flutter_ohos@<content-hash>=/
  oh_modules/@ohos/flutter_ohos/src/main/ets/plugin/editing/OhosAutoFillHelper.ets
```

### 改动清单(7 处,均标注 `DSH-POC patch` 注释)
1. `AutoFillManagerPageNodeInfo.autoFillType` 类型:`autoFillManager.AutoFillType` → `number`
2. 删除 `toSdkAutoFillType()`(SDK 枚举已删,数字直通)
3. `toManagerPageNodeInfo()` 内调用点改为 `node.autoFillType`
4. `toManagerViewData()` 降级为类型保形直通(返回 `OhosViewData`;SDK ViewData 已删,不再构造)
5. `parseFillResult(viewData)` 参数:`autoFillManager.ViewData` → `OhosViewData`
6. `requestAutoFill()` **stub 降级**:函数签名保留(TextInputPlugin 调用面),函数体不再触碰 SDK,直接 `onFailure(-2)` —— **password-manager FILL 在 API 26 不可用,降级登记**
7. `requestAutoSave()`:删除 `SaveRequest` 构造,改调 `autoFillManager.requestAutoSave(uiContext, napiCallback)`(API 26 两参版,系统自行从 UIContext 收集表单)—— SAVE 保持可用

### 行为影响(CAPABILITY_MATRIX 登记)
- 自动填充(密码管理器"填写")在 API 26 上降级为不可用(引擎上游适配后可恢复)
- 自动保存仍触发(走 API 26 新签名)

### 重放方法
- 触发点:升级 Flutter-OH 引擎、`ohpm install` 重装、删除 oh_modules 后重建 → 覆盖补丁
- 重放:解包/定位 `flutter_embedding_debug.har` 对应解包目录后重做上述 7 处修改
- 正式化建议(阶段 1):flutter_flutter 引擎源码树中 patch embedding ets 源并自维护补丁分支,构建时输出 har 即含补丁

---

## 环境约束登记(实测)

| 约束 | 值 | 影响 |
| --- | --- | --- |
| 空格路径 | DevEco 工具链(ohpm `--target_path`)不支持含空格路径(`D:\web dev\...` 截断为 `D:\web`) | **鸿蒙工程必须位于无空格路径**;最终单仓双工程若源码在 toki/ 内,命令行构建需镜像到无空格构建目录(如 `D:\ohos_build\`) |
| `HOS_SDK_HOME` | `C:\Program Files\Huawei\DevEco Studio\sdk` | flutter 工具发现 HarmonyOS SDK |
| `DEVECO_SDK_HOME` | `C:\Program Files\Huawei\DevEco Studio\sdk` | hvigor 必需 |
| PATH | 需含 `tools\ohpm\bin`、`tools\hvigor\bin`(node 由 hvigor 自取) | flutter build hap 前置 |
| SDK API | 本机仅 API 26(26.0.0.461);`flutter doctor` 显示 `available api versions [26:default]` | 引擎 3.44.9 canary 以 ≤25 编写 → 本补丁;升级引擎可缓解 |

## 构建状态(2026-09)
- [x] ArkTS 编译通过(15 错清零,assembleHap 23.3s 达签名步骤)
- [ ] 签名配置(DevEco GUI:File → Project Structure → Signing Configs → Automatically generate signature)
- [ ] HAP 产物产出 → 模拟器点亮(门禁 V1)

---

## P1b:API 24 release 编译的 modern autoFill 源码补丁(2026-09,与 P1 互补)

### 背景(实测)
- **release/profile 与 debug 的关键差异:ArkTS 在 release 全量严格校验**(debug 仅 WARN → 能过)。
- `flutter_embedding_release.har` 内 `OhosAutoFillHelper.ets` 使用 modern autoFillManager 面:
  `AutoFillType / ViewData / FillRequest / AutoFillCallback / FillFailureResult / SaveRequest / AutoFillTriggerType / requestAutoFill / requestAutoSave(3参)`。
- **API 26.0.0.461 与 API 6.1.1(24) 的 d.ts 均无上述成员**(仅旧 `AutoSaveCallback{onSuccess,onFailure}` + `requestAutoSave(context, callback?)`)。
- → `flutter build hap --release` 失败 **15× ArkTS 10505001**,API 26 与 API 24 工具链同现;P1 只补丁了 debug 解包副本,release har 从未被补丁。

### 改动(1 个文件)
- `OhosAutoFillHelper.ets`:移除全部 modern autoFillManager 类型/调用;`requestAutoFill` / `requestAutoSave` 保留签名,行为 = API≤25 设备原有运行时语义(直接 `onFailure(-1)` / `napiCallback.onFailure()`)。数据构建类 API(buildViewData/buildViewDataForSave/buildNodeIdMap/…)与所有对外符号不变。
- 注意:P1 的"requestAutoSave 两参版(SAVE 保持可用)"为 **API 26 专属**;API 24 下只能全降级。

### 文件与重打包
- **HAR**:`D:\flutter_ohos\flutter\bin\cache\artifacts\engine\ohos-arm64-release\flutter_embedding_release.har`(原包备份 `.har.orig`)
- **引擎源(已同步)**:`D:\flutter_ohos\flutter\engine\src\flutter\shell\platform\ohos\flutter_embedding\flutter\src\main\ets\plugin\editing\OhosAutoFillHelper.ets`
- HAR 实为 **tar.gz**(魔数 `1F 8B`;`.har` 不可被 zip 工具直接解):`tar -xzf har -C <dir>` 后 `tar -czf out.har -C <dir> package`

### 重放
- 触发点:引擎升级 / `flutter update-engine` 重置 artifacts / `flutter clean` 后重建。
- 重放:重打该 HAR(或改 engine 源后重新构建 engine 产物;源已含补丁)。

---

## P2:渲染分辨率缩放 RENDER_SCALE=0.8(2026-09,性能定制;初版 0.75)

### 背景(实测,横屏滑动卡顿根因)
- 同一画面:normal 全屏 rasterAvg ≈11.5ms,free-window ≈5ms → 根因是**全屏渲染分辨率过高**(MediaQuery.dpr 2.25 vs 1.9125,物理缓冲同为 2800×1840,系统上采样)而非内容成本。
- 结论:引擎侧把逻辑渲染缓冲区缩小到 80%,再经 ArkUI 居中上采样回全屏——**逻辑尺寸、dpr 语义、文本/布局不变**,仅降低 GPU 光栅分辨率。
- 2026-09-08 按用户要求由 0.75 调整为 **0.8**(清晰度与性能折中;0.75 版备份 .orig3)。

### 改动(2 个文件,`DSH-OH perf` 注释)
1. **`embedding\ohos\FlutterPage.ets`**:`const FLUTTER_RENDER_SCALE = 0.8;`,FlutterSurface 的 XComponent 改为 `width('80%').height('80%')` + `.scale({x:1/0.8,y:1/0.8})` 于居中 Stack。
2. **`view\FlutterView.ets`**:`const RENDER_SCALE = 0.8;`,所有 `viewportMetrics.devicePixelRatio` 赋值与 `TextInputChannel.setDevicePixelRatio` 上报均 ×RENDER_SCALE(约 8 处:onDevicePixelRatioChange / reset / updateDensity 等)。

### 效果(真机 LRT-W30 / API 24 实测,用户验收)
- dpr 2.25→1.8(0.8×),逻辑尺寸保持 1244×818;光栅缓冲同比例缩小;rasterAvg 介于 0.75×的 ≈6.5ms 与全屏 11.5ms 之间(120Hz 预算内)。

### 文件与重打包(与 P1b 同包,当前 har = P1b + P2 0.8)
- **HAR**:`D:\flutter_ohos\flutter\bin\cache\artifacts\engine\ohos-arm64-release\flutter_embedding_release.har`(`.orig`=原始、`.orig2`=P1b 后、`.orig3`=P1b+0.75)
- **引擎源(已同步)**:`D:\flutter_ohos\flutter\engine\src\flutter\shell\platform\ohos\flutter_embedding\flutter\src\main\ets\`(`embedding\ohos\FlutterPage.ets`、`view\FlutterView.ets`)

### 重放
- 触发点:引擎升级 / `flutter update-engine` 重置 artifacts / `flutter clean` 后重建 → 按 P1b 方法重打该 HAR(两文件常量与乘法点)。

### 相关(非引擎)
- `framesconfig.json`:`{"SWITCH":1}` LTPO 帧率投票(120Hz 触控投票);宿主导航在 8.33ms 预算内。
