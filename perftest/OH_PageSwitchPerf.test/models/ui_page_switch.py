# -*- coding: utf-8 -*-
'''
@原子用例
一级页面横滑/点击切换(待办-首页-工具)
@预置条件
App 已安装;设备横屏(平板);底栏标签:待办/首页/工具
@用例步骤
1. 冷启动 App(poc_ohos)
2. 等待界面稳定(3s)
3. 横滑 首页→工具(LEFT)
4. 横滑 工具→首页→待办(RIGHT x2)
5. 横滑 待办→首页(LEFT)
6. 点击底栏「工具」
7. 点击底栏「首页」
8. 复切:横滑 首页→工具→首页
9. 静止 2s(基线采样)
'''
from hypium import BY
from hypium.advance.perf.application_model.model_base import ModelBase
from hypium.advance.perf.driver_perf.idriver_perf import IDriverPerf
from hypium.advance.perf.driver_perf.tag import SceneType
from hypium.model import UiParam

APP_NAME = "poc_ohos"
PKG = "com.example.poc_ohos"


class UiPageSwitch(ModelBase):
    def __init__(self, uidriver: IDriverPerf, case_id):
        ModelBase.__init__(self, uidriver, case_id)
        self.scene_no = "ui_page_switch"
        self.scene_name = "一级页面切换"
        self.scene_type = "页面切换性能"
        self.scene_path = "日常高频操作-页面导航-一级页面切换"
        self.driver = uidriver

    def setup(self):
        self.driver.stop_app(PKG)
        self.driver.go_home()

    @ModelBase.scene_recover
    def execute(self):
        # 1. 冷启动(poc_ohos,含冷启动性能采样)
        self.driver.start_application_perf(APP_NAME, SceneType.COLD_START)
        self.driver.wait(3)

        # 3. 首页 → 工具
        self.driver.swipe_perf(
            UiParam.LEFT,
            tag=self.create_tag("横滑 首页→工具", SceneType.WITH_PAGE_SWITCH))
        self.driver.wait(1)

        # 4. 工具 → 首页 → 待办
        self.driver.swipe_perf(
            UiParam.RIGHT,
            tag=self.create_tag("横滑 工具→首页", SceneType.WITH_PAGE_SWITCH))
        self.driver.wait(1)
        self.driver.swipe_perf(
            UiParam.RIGHT,
            tag=self.create_tag("横滑 首页→待办", SceneType.WITH_PAGE_SWITCH))
        self.driver.wait(1)

        # 5. 待办 → 首页
        self.driver.swipe_perf(
            UiParam.LEFT,
            tag=self.create_tag("横滑 待办→首页", SceneType.WITH_PAGE_SWITCH))
        self.driver.wait(1)

        # 6-7. 点击底栏(按文本找组件;找不到则跳过,不影响后续)
        try:
            tools_btn = self.driver.find_component(BY.text("工具"))
            self.driver.touch_perf(
                tools_btn,
                tag=self.create_tag("点击底栏 工具", SceneType.WITH_PAGE_SWITCH))
            self.driver.wait(1)
            home_btn = self.driver.find_component(BY.text("首页"))
            self.driver.touch_perf(
                home_btn,
                tag=self.create_tag("点击底栏 首页", SceneType.WITH_PAGE_SWITCH))
            self.driver.wait(1)
        except Exception:
            self.driver.wait(2)

        # 8. 复切(已访问页重复切换 = 稳定态性能)
        self.driver.swipe_perf(
            UiParam.LEFT,
            tag=self.create_tag("复切 首页→工具", SceneType.WITH_PAGE_SWITCH))
        self.driver.wait(1)
        self.driver.swipe_perf(
            UiParam.RIGHT,
            tag=self.create_tag("复切 工具→首页", SceneType.WITH_PAGE_SWITCH))

        # 9. 静止基线
        self.driver.wait(2)

    def teardown(self):
        self.driver.stop_app(PKG)
