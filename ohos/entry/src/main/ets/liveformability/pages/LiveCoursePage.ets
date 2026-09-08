/*
 * LiveCoursePage — 课中实况表单页面(完整 ArkUI)。
 * 自治刷新:aboutToAppear 起每 30s 读沙箱 course_card.json(EntryFormAbility/
 *   插件同源写入)按墙钟重算圆环与剩余;进程无关,无需插件推送。
 * 视觉:HarmonyOS Design —— 大圆环 + 课程层 + 剩余分钟 + 下课时间。
 */
import { fileIo as fs } from '@kit.CoreFileKit';

const CARD_FILE = 'course_card.json';

@Entry
@Component
struct LiveCoursePage {
  @State title: string = '课程进行中';
  @State remainMin: number = 0;
  @State pct: number = 0;
  @State endLabel: string = '';
  @State active: boolean = false;
  private timer: number = 0;

  aboutToAppear(): void {
    this.refresh();
    this.timer = setInterval(() => {
      this.refresh();
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.timer > 0) {
      clearInterval(this.timer);
      this.timer = 0;
    }
  }

  private refresh(): void {
    try {
      const p = getContext(this).filesDir + '/' + CARD_FILE;
      if (!fs.accessSync(p)) {
        this.active = false;
        return;
      }
      const raw = fs.readTextSync(p);
      if (raw.length === 0) {
        this.active = false;
        return;
      }
      const obj = JSON.parse(raw) as Record<string, Object>;
      const num = (k: string): number => {
        const v = obj[k];
        return typeof v === 'number' ? v : 0;
      };
      const str = (k: string): string => {
        const v = obj[k];
        return typeof v === 'string' ? v : '';
      };
      const active = num('countdownActive') === 1;
      const endAt = num('countdownEndAt');
      const total = num('countdownTotal');
      this.title = str('countdownTitle').length > 0 ? str('countdownTitle') : '课程进行中';
      if (!active || endAt <= 0) {
        this.active = false;
        return;
      }
      const remainMs = endAt - Date.now();
      if (remainMs <= 0) {
        this.active = false;
        this.remainMin = 0;
        this.pct = 100;
        return;
      }
      const remain = Math.ceil(remainMs / 60000);
      const done = total > 0 ? 1.0 - remainMs / (total * 60000) : 0.0;
      const pct = Math.max(0, Math.min(100, Math.round(done * 100)));
      const end = new Date(endAt);
      const two = (x: number): string => x < 10 ? '0' + x : '' + x;
      this.active = true;
      this.remainMin = remain;
      this.pct = pct;
      this.endLabel = two(end.getHours()) + ':' + two(end.getMinutes()) + ' 结束';
    } catch (e) {
      this.active = false;
    }
  }

  build() {
    Column({ space: 10 }) {
      // 大圆环 + 中心剩余分钟
      Stack() {
        Progress({ value: this.pct, total: 100, type: ProgressType.Ring })
          .width(120)
          .height(120)
          .color('#0A6CFF')
          .style({ strokeWidth: 8 })
        Column({ space: 2 }) {
          Text(this.remainMin > 0 ? this.remainMin.toString() : '')
            .fontSize(32)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E5000000')
          Text('分钟')
            .fontSize(12)
            .fontColor('#99000000')
        }
      }

      Text(this.title)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#E5000000')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })

      Text(this.endLabel)
        .fontSize(13)
        .fontColor('#99000000')
    }
    .width('100%')
    .height('100%')
    .padding(16)
    .justifyContent(FlexAlign.Center)
  }
}
