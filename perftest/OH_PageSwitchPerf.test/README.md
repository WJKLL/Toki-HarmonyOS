# OH_PageSwitchPerf.test — 一级页面切换性能用例工程(DevEco Testing 场景化性能测试)

专用模板(基于官方 `appsceneperfmetrics/template` 结构),被测应用 `com.example.poc_ohos`(桌面名 `poc_ohos`)。
场景:**平板横屏下,一级页面(待办 → 首页 → 工具)横滑切换 + 点击底栏切换的性能自动测试**
(冷启动、每次切换均打性能采样 tag,报告区分 WITH_PAGE_SWITCH / NO_PAGE_SWITCH 场景指标)。

## 目录结构
```
OH_PageSwitchPerf.test/
├─ main.py                      # xdevice 入口(run -l OH_PageSwitchPerf)
├─ config/user_config.xml       # 设备连接(usb-hdc,sn 留空=自动)
├─ models/ui_page_switch.py     # 原子用例:横滑/点击切换(可在 models/ 加更多)
└─ testcases/
   ├─ OH_PageSwitchPerf.py      # 场景用例(PerfBaseCase)
   └─ OH_PageSwitchPerf.json    # 用例清单(driver 配置)
```

## 在 DevEco Testing 中使用
1. 打开 **DevEco Testing → 测试服务 → 场景化性能测试**;
2. 第 ④ 步「用例工程路径」→ 选择本**目录**(`OH_PageSwitchPerf.test`,路径若被拒请选其 zip 后再试);
3. 测试设备选平板(MatePad Air);执行轮数 1;指标监控按需勾选(CPU/内存/GPU…);
4. 创建任务 → 执行;完成后「查看报告」看各 tag(如"横滑 首页→工具")下的 FPS/CPU/内存。

## 自测(可选,本机 Python)
需要 DevEco Testing 内置 Python 环境里已装 xdevice + hypium + hypium-perf(pip 安装 dev 目录 wheel):
```bash
cd OH_PageSwitchPerf.test
python main.py        # 需设备已连 hdc
```

## 调整
- 切换次数/等待时间:改 `models/ui_page_switch.py` 的 swipe_perf/touch_perf 序列;
- 新增场景:复制 `testcases/OH_PageSwitchPerf.py(.json)` 改名,并按需加 Model;
- 设备方向:执行前把平板改为横屏(或直接保持当前方向)。
