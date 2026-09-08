/*
 * EntryFormAbility — Toki 桌面「今日课程」服务卡片(HarmonyOS Form Kit)。
 * 数据流(Dart → entry 进程插件 → 本卡):
 *   1. Flutter 侧 CourseCardSync 经 xiangjugong/cards 通道传「今日课程快照」;
 *   2. 插件写沙箱 filesDir/course_card.json(课表字段 + 倒计时字段);
 *   3. 本 Ability 读同一文件 → formBindingData 下发卡片;
 *   4. 课中:插件 startCountdown 每分钟 updateForm(圆环进度,见 XiangJuGongChannelsPlugin),
 *      进程被杀时依赖 onUpdateForm 兜底重算(文件内持久化 endAt/total)。
 *   5. 卡片进程与 entry 共享同一应用沙箱(filesDir 同目录,文件即契约)。
 */
import { FormExtensionAbility, formBindingData, formProvider } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'XJForm';
const CARD_FILE = 'course_card.json';
const IDS_FILE = 'card_form_ids.json';

/** 卡片数据契约(与 XiangJuGongChannelsPlugin / Dart CourseCardSync 对齐,v2)。 */
interface CardData {
  weekText: string;
  curTag: string;
  curName: string;
  curRoom: string;
  curStart: number;
  curEnd: number;
  nextLine: string;
  countdownActive: number;
  countdownTitle: string;
  countdownText: string;
  countdownPct: number;
  countdownRemain: number;
  countdownEndAt: number;
  countdownTotal: number;
}

/** 卡片绑定键(与 TodayCourseCard 的 @LocalStorageProp 一一对应)。 */
interface CardBindingData {
  weekText: string;
  curTag: string;
  curName: string;
  curRoom: string;
  nextLine: string;
  countdownActive: number;
  countdownTitle: string;
  countdownText: string;
  countdownPct: number;
  countdownRemain: number;
}

function emptyCard(): CardData {
  return {
    weekText: '暂无课表',
    curTag: '', curName: '', curRoom: '', curStart: 0, curEnd: 0, nextLine: '',
    countdownActive: 0, countdownTitle: '', countdownText: '', countdownPct: 0,
    countdownRemain: 0, countdownEndAt: 0, countdownTotal: 0
  };
}

export default class EntryFormAbility extends FormExtensionAbility {

  private cardPath(): string {
    return this.context.filesDir + '/' + CARD_FILE;
  }

  private idsPath(): string {
    return this.context.filesDir + '/' + IDS_FILE;
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    const data = this.readCard();
    // 记录本卡 formId,供 entry 进程 updateForm(与插件协同)。
    const wantParams: Record<string, Object> = want.parameters as Record<string, Object>;
    let formId: string = '';
    if (wantParams !== undefined && wantParams !== null) {
      const maybe = wantParams['ohos.extra.param.key.form_identity'];
      if (typeof maybe === 'string') {
        formId = maybe;
      }
    }
    this.addFormId(formId);
    return formBindingData.createFormBindingData(this.toBinding(data));
  }

  onCastToNormalForm(formId: string): void {
    // 自用:保留(暂无降级差异)。
  }

  onUpdateForm(formId: string): void {
    // 系统定时刷新兜底:若文件内存在 countdown,按墙钟重算剩余再下发。
    const data = this.refreshCountdown(this.readCard());
    formProvider.updateForm(formId, formBindingData.createFormBindingData(this.toBinding(data)));
  }

  onRemoveForm(formId: string): void {
    this.removeFormId(formId);
  }

  onFormEvent(formId: string, message: string): void {
    console.info('[' + TAG + '] formEvent ' + formId + ' ' + message);
  }

  // ── 数据读写 ─────────────────────────────────────────────

  private s(obj: Record<string, Object>, key: string): string {
    const v = obj[key];
    return typeof v === 'string' ? v : '';
  }

  private n(obj: Record<string, Object>, key: string, fb: number): number {
    const v = obj[key];
    return typeof v === 'number' ? v : fb;
  }

  private readCard(): CardData {
    try {
      const p = this.cardPath();
      if (fs.accessSync(p)) {
        const raw = fs.readTextSync(p);
        if (raw.length > 0) {
          const obj = JSON.parse(raw) as Record<string, Object>;
          const out: CardData = emptyCard();
          if (obj !== undefined && obj !== null) {
            const week = this.s(obj, 'weekText');
            out.weekText = week.length > 0 ? week : out.weekText;
            out.curTag = this.s(obj, 'curTag');
            out.curName = this.s(obj, 'curName');
            out.curRoom = this.s(obj, 'curRoom');
            out.curStart = this.n(obj, 'curStart', 0);
            out.curEnd = this.n(obj, 'curEnd', 0);
            out.nextLine = this.s(obj, 'nextLine');
            out.countdownActive = this.n(obj, 'countdownActive', 0);
            out.countdownTitle = this.s(obj, 'countdownTitle');
            out.countdownText = this.s(obj, 'countdownText');
            out.countdownPct = this.n(obj, 'countdownPct', 0);
            out.countdownRemain = this.n(obj, 'countdownRemain', 0);
            out.countdownEndAt = this.n(obj, 'countdownEndAt', 0);
            out.countdownTotal = this.n(obj, 'countdownTotal', 0);
          }
          return out;
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      console.info('[' + TAG + '] readCard failed: ' + err.code + ' ' + err.message);
    }
    return emptyCard();
  }

  /** countdown 字段按当前墙钟重算(进程被杀后定时刷新仍准确)。 */
  private refreshCountdown(data: CardData): CardData {
    if (data.countdownActive !== 1 || data.countdownEndAt <= 0) {
      return data;
    }
    const remainMs = data.countdownEndAt - Date.now();
    const out: CardData = emptyCard();
    out.weekText = data.weekText;
    out.curTag = data.curTag;
    out.curName = data.curName;
    out.curRoom = data.curRoom;
    out.curStart = data.curStart;
    out.curEnd = data.curEnd;
    out.nextLine = data.nextLine;
    out.countdownActive = data.countdownActive;
    out.countdownTitle = data.countdownTitle;
    out.countdownText = data.countdownText;
    out.countdownPct = data.countdownPct;
    out.countdownRemain = data.countdownRemain;
    out.countdownEndAt = data.countdownEndAt;
    out.countdownTotal = data.countdownTotal;
    // 被杀后兜底:所展示课程已过 curEnd → 状态翻转为"休息中"
    // (下一节课行保留原样,粗略可读)。
    const now = new Date();
    const nowMin = now.getHours() * 60 + now.getMinutes();
    if (data.curEnd > 0 && nowMin >= data.curEnd) {
      out.curTag = '今日课程结束';
      out.curName = '休息中';
    }
    if (remainMs <= 0) {
      out.countdownActive = 0;
      out.countdownPct = 100;
      out.countdownText = '课程已结束';
      return out;
    }
    const remain = Math.ceil(remainMs / 60000);
    const done = data.countdownTotal > 0
      ? 1.0 - remainMs / (data.countdownTotal * 60000)
      : 0.0;
    out.countdownPct = Math.max(0, Math.min(100, Math.round(done * 100)));
    out.countdownRemain = remain;
    out.countdownText = '距下课约 ' + remain + ' 分钟';
    return out;
  }

  /** 卡片绑定键(与 TodayCourseCard 的 @LocalStorageProp 一一对应)。 */
  private toBinding(d: CardData): CardBindingData {
    return {
      weekText: d.weekText,
      curTag: d.curTag,
      curName: d.curName,
      curRoom: d.curRoom,
      nextLine: d.nextLine,
      countdownActive: d.countdownActive,
      countdownTitle: d.countdownTitle,
      countdownText: d.countdownText,
      countdownPct: d.countdownPct,
      countdownRemain: d.countdownRemain
    };
  }

  // ── formId 注册表(filesDir/card_form_ids.json;与插件共享)──

  private writeText(p: string, text: string): void {
    const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(f.fd, text);
    } finally {
      fs.closeSync(f);
    }
  }

  private loadIds(): string[] {
    try {
      const p = this.idsPath();
      if (fs.accessSync(p)) {
        const raw = fs.readTextSync(p);
        const arr = JSON.parse(raw) as string[];
        if (Array.isArray(arr)) {
          return arr;
        }
      }
    } catch (e) {
      console.info('[' + TAG + '] loadIds failed');
    }
    return [];
  }

  private saveIds(ids: string[]): void {
    try {
      this.writeText(this.idsPath(), JSON.stringify(ids));
    } catch (e) {
      console.info('[' + TAG + '] saveIds failed');
    }
  }

  private addFormId(formId: string): void {
    if (formId === '' || formId.length === 0) {
      return;
    }
    const ids = this.loadIds();
    if (ids.indexOf(formId) < 0) {
      ids.push(formId);
      this.saveIds(ids);
    }
  }

  private removeFormId(formId: string): void {
    const ids = this.loadIds().filter((id: string) => id !== formId);
    this.saveIds(ids);
  }
}
