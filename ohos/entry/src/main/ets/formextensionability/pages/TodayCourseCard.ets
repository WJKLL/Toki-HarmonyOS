/*
 * TodayCourseCard — Toki 桌面「今日课程」服务卡片(首页小课表排布 + 鸿蒙深浅色)。
 * 布局(2*4):标题行(今日课程/周次 + 课中右上圆环倒计时+结束时刻)→
 *   当前课程标签 → 课程名大字 → 教室行 → 分隔线 → 下一节课行。
 * 视觉:系统资源色($r('sys.color.*'))随深浅色自动翻转;卡面由系统默认
 *   卡片材质承担(不自定义背景);圆环/标签主色。
 * 数据键契约 v3:weekText/curTag/curName/curRoom/nextLine + countdownTitle|
 *   countdownText(不变式:含结束时刻,进程被杀仍准确)|countdownPct/Remain。
 */
@Entry
@Component
struct TodayCourseCard {
  @LocalStorageProp('weekText') weekText: string = '暂无课表';
  @LocalStorageProp('curTag') curTag: string = '';
  @LocalStorageProp('curName') curName: string = '';
  @LocalStorageProp('curRoom') curRoom: string = '';
  @LocalStorageProp('nextLine') nextLine: string = '';
  @LocalStorageProp('countdownActive') countdownActive: number = 0;
  @LocalStorageProp('countdownTitle') countdownTitle: string = '';
  @LocalStorageProp('countdownText') countdownText: string = '';
  @LocalStorageProp('countdownPct') countdownPct: number = 0;
  @LocalStorageProp('countdownRemain') countdownRemain: number = 0;

  build() {
    Column({ space: 4 }) {
      // ── 标题行:今日课程/周次 + 课中右上小圆环 ──
      Row({ space: 8 }) {
        Column({ space: 2 }) {
          Text('今日课程')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('sys.color.ohos_id_color_text_primary'))
            .maxLines(1)
          Text(this.weekText)
            .fontSize(11)
            .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            .maxLines(1)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        if (this.countdownActive === 1) {
          Stack() {
            Progress({ value: this.countdownPct, total: 100, type: ProgressType.Ring })
              .width(36)
              .height(36)
              .color($r('sys.color.ohos_id_color_primary'))
              .style({ strokeWidth: 4 })
            Text(this.countdownRemain > 0 ? this.countdownRemain.toString() : '')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)

      // ── 课中:课程名 + 剩余(短文本,小卡不挤)──
      if (this.countdownActive === 1) {
        Text(this.countdownTitle)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text('剩余 ' + this.countdownRemain + ' 分钟')
          .fontSize(11)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .width('100%')
      }

      // ── 当前/下一节课块(首页小课表排布)──
      if (this.curTag.length > 0) {
        Text(this.curTag)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_primary'))
          .width('100%')
      }
      if (this.curName.length > 0) {
        Text(this.curName)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
      if (this.curRoom.length > 0) {
        Text(this.curRoom)
          .fontSize(13)
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .maxLines(1)
          .width('100%')
      }

      // ── 下一节行 ──
      Divider()
        .color($r('sys.color.ohos_id_color_text_secondary'))
        .opacity(0.3)
        .strokeWidth(0.5)
        .margin({ top: 6, bottom: 4 })
      Text(this.nextLine)
        .fontSize(13)
        .fontColor($r('sys.color.ohos_id_color_text_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .justifyContent(FlexAlign.SpaceBetween)
  }
}
