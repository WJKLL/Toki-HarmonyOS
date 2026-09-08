# -*- coding: utf-8 -*-
'''
@场景用例
一级页面切换性能(横滑/点击)
@预置条件
设备横屏;App 已安装
@原子用例
一级页面横滑/点击切换
'''
import os

from hypium.advance.perf.application_model.perf_basecase import PerfBaseCase
from models.ui_page_switch import UiPageSwitch


class OH_PageSwitchPerf(PerfBaseCase):
    def __init__(self, controllers):
        self.TAG = self.__class__.__name__
        self.tests = ["test_step"]
        self.case_id = os.path.splitext(os.path.basename(__file__))[0]
        self.case_scene_name = '一级页面切换性能'
        case_pkg = 'com.example.poc_ohos'
        PerfBaseCase.__init__(self, controllers, case_pkg)
        self.log.info("Case id is %s" % self.case_id)

    def setup(self):
        self.log.info("预置工作:初始化设备开始................." + self.devices[0].device_sn)

    def test_step(self):
        steps = [
            UiPageSwitch(self.driver, self.case_id)
        ]
        for item in steps:
            item.execute()

    def teardown(self):
        result = self.get_case_result()
        self.log.info("收尾工作................., result is {}".format(result))
        PerfBaseCase.teardown(self)
