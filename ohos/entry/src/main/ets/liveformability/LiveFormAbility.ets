/*
 * LiveFormAbility — 课中「实况表单」(HarmonyOS Live Form,API 20+)。
 * 触发:系统按进行中状态拉起(应用注册 type "liveForm" + profile:live_form_config);
 * 页面:LiveCoursePage(完整 ArkUI;圆环倒计时自运行,读沙箱 course_card.json)。
 * 数据流与桌面卡片同源(EntryFormAbility 写 course_card.json);
 * 实况表单与桌面卡片可同时存在(实况 = 常驻可交互面板,卡片 = 桌面快照)。
 */
import { LiveFormExtensionAbility, LiveFormInfo } from '@kit.FormKit';
import { UIExtensionContentSession } from '@kit.AbilityKit';

export default class LiveFormAbility extends LiveFormExtensionAbility {

  onLiveFormCreate(liveFormInfo: LiveFormInfo, session: UIExtensionContentSession): void {
    console.info('[XJLiveForm] create formId=' + liveFormInfo.formId +
      ' rect=' + JSON.stringify(liveFormInfo.rect) +
      ' radius=' + liveFormInfo.borderRadius);
    session.loadContent('pages/LiveCoursePage');
  }

  onLiveFormDestroy(liveFormInfo: LiveFormInfo): void {
    console.info('[XJLiveForm] destroy formId=' + liveFormInfo.formId);
  }
}
