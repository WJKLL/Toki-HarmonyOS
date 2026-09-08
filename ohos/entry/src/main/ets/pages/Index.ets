
import common from '@ohos.app.ability.common';
import { window } from '@kit.ArkUI';
import { FlutterPage } from '@ohos/flutter_ohos'

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'

// DSH-OH fix: feed the system top safe-area height into FlutterPage.paddingTop so the
// engine reports a non-zero physicalViewPaddingTop and Dart SafeArea avoids the status
// bar (landscape top toolbar overlap fix). Updated on avoidAreaChange (rotation etc.).
@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  @State topPaddingPx: number = 0
  private win: window.Window | null = null

  aboutToAppear(): void {
    this.refreshSafeArea()
  }

  aboutToDisappear(): void {
    if (this.win !== null) {
      this.win.off('avoidAreaChange', this.onAvoidAreaChange)
      this.win = null
    }
  }

  private onAvoidAreaChange = (data: window.AvoidAreaOptions): void => {
    this.refreshSafeArea()
  }

  private refreshSafeArea(): void {
    window.getLastWindow(this.context).then((w: window.Window) => {
      this.win = w
      try {
        const avoid = w.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM)
        const top = avoid.topRect.height
        if (this.topPaddingPx !== top) {
          this.topPaddingPx = top
        }
        w.on('avoidAreaChange', this.onAvoidAreaChange)
      } catch (e) {
        // ignore: window may not be ready yet
      }
    }).catch(() => {
      // ignore
    })
  }

  build() {
    Column() {
      FlutterPage({
        viewId: this.viewId,
        paddingTop: this.topPaddingPx,
      })
    }
    .width('100%')
    .height('100%')
  }

  onBackPress(): boolean {
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
