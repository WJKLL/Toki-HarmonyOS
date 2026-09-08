/*
 * XiangJuGongChannelsPlugin — Toki 自研通道的 OHOS 实现(对齐 Android MainActivity.kt)。
 * 通道:
 *   xiangjugong/media    saveImage{bytes,fileName} → 相册(photoAccessHelper,需 WRITE_IMAGEVIDEO)
 *   xiangjugong/log      saveToDownloads{sourcePath,fileName,mimeType} → DocumentViewPicker 保存
 *   xiangjugong/refresh  setHigh/setNormal → OHOS 系统自适应刷新,空实现
 *   xiangjugong/reminder 占位(ensureChannels/canScheduleExactAlarm=true/其余 success;S2 升级 ReminderAgent)
 */
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import MethodChannel, {
  MethodCallHandler,
  MethodResult
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { BinaryMessenger } from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import AbilityAware from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityAware';
import {
  AbilityPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/ability/AbilityPluginBinding';
import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { picker } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { abilityAccessCtrl, common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { reminderAgentManager } from '@kit.BackgroundTasksKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { formProvider, formBindingData } from '@kit.FormKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { util } from '@kit.ArkTS';

const TAG = 'XJChannels';
const MEDIA_PERM = 'ohos.permission.WRITE_IMAGEVIDEO';

/** 卡片绑定键(与 TodayCourseCard 的 @LocalStorageProp 一一对应;全量下发)。 */
interface FormCardBinding {
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

/** getDiagnostics 返回结构。 */
interface ReminderDiag {
  scheduled: number;
  lastAtMillis: number;
}

/** HUKS 密钥材料(常量,与 KeyProperties 一致)。 */
const HUKS_ALIAS = 'xjug_secure_v1';

export default class XiangJuGongChannelsPlugin implements FlutterPlugin, AbilityAware {

  private channels: MethodChannel[] = [];
  private abilityContext: common.UIAbilityContext | null = null;

  getUniqueClassName(): string {
    return 'XiangJuGongChannelsPlugin';
  }

  onAttachedToAbility(binding: AbilityPluginBinding): void {
    this.abilityContext = binding.getAbility().context;
    Log.i(TAG, 'onAttachedToAbility');
  }

  onDetachedFromAbility(): void {
    this.abilityContext = null;
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.register(binding.getBinaryMessenger(), 'xiangjugong/media', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleMedia(call, result);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/log', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleLog(call, result);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/refresh', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        // OHOS 自适应刷新由系统管理,无公开 120Hz 请求 API → 空实现。
        result.success(null);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/reminder', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleReminder(call, result);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/diag', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleDiag(call, result);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/picker', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handlePicker(call, result);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/cards', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleCards(call, result);
      }
    });
    this.register(binding.getBinaryMessenger(), 'xiangjugong/secure', {
      onMethodCall: (call: MethodCall, result: MethodResult) => {
        this.handleSecure(call, result);
      }
    });
    Log.i(TAG, 'all channels registered');
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    for (let i = 0; i < this.channels.length; i++) {
      this.channels[i].setMethodCallHandler(null);
    }
    this.channels = [];
  }

  private register(messenger: BinaryMessenger, name: string, handler: MethodCallHandler): void {
    const channel = new MethodChannel(messenger, name);
    channel.setMethodCallHandler(handler);
    this.channels.push(channel);
    Log.i(TAG, 'registered ' + name);
  }

  // ── media ──────────────────────────────────────────────
  private handleMedia(call: MethodCall, result: MethodResult): void {
    if (call.method === 'saveImage') {
      this.saveImage(call, result);
      return;
    }
    result.notImplemented();
  }

  private async saveImage(call: MethodCall, result: MethodResult): Promise<void> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    try {
      const fileName = call.argument('fileName') as string | undefined;
      const name = fileName !== undefined && fileName.length > 0 ? fileName : 'image.png';
      const raw: ESObject = call.argument('bytes');
      if (raw === null) {
        result.error('no_bytes', 'bytes argument missing', null);
        return;
      }
      const extIdx = name.lastIndexOf('.');
      const ext = extIdx >= 0 ? name.substring(extIdx + 1) : 'png';
      // title 必须为**不含扩展名**的显示名(扩展名经创建参数传入);
      //   含 '.' 会被 photoAccessHelper 判 "display name invalid"。
      const title = extIdx >= 0 ? name.substring(0, extIdx) : name;
      // StandardCodec: Dart Uint8List → Uint8Array
      const bytesArr = raw as Uint8Array;
      const buf: ArrayBuffer = bytesArr.buffer as ArrayBuffer;
      // 1) 权限
      const atManager = abilityAccessCtrl.createAtManager();
      const permResult = await atManager.requestPermissionsFromUser(ctx, [MEDIA_PERM]);
      const granted = permResult.authResults.length > 0 && permResult.authResults[0] === 0;
      if (!granted) {
        result.error('no_permission', '相册写入权限被拒绝(设置中开启后可重试)', null);
        return;
      }
      // 2) API 26:createAsset 建空 asset → 返回 uri → 直接写入
      const helper = photoAccessHelper.getPhotoAccessHelper(ctx);
      const options: photoAccessHelper.CreateOptions = { title: title };
      const assetUri = await helper.createAsset(
        photoAccessHelper.PhotoType.IMAGE, ext, options);
      const dst = fs.openSync(assetUri, fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(dst.fd, buf);
      fs.closeSync(dst);
      Log.i(TAG, 'saved to album: ' + assetUri);
      result.success('已保存到相册(' + name + ')');
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'saveImage failed: ' + err.code + ' ' + err.message);
      result.error('save_failed', '保存失败:' + err.message, err.code);
    }
  }

  // ── log ────────────────────────────────────────────────
  private async handleLog(call: MethodCall, result: MethodResult): Promise<void> {
    if (call.method === 'exportLog') {
      this.exportLog(call, result);
      return;
    }
    if (call.method !== 'saveToDownloads') {
      result.notImplemented();
      return;
    }
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    try {
      const sourcePath = call.argument('sourcePath') as string | undefined;
      const fileName = call.argument('fileName') as string | undefined;
      const fname = fileName !== undefined && fileName.length > 0 ? fileName : 'xiangjugong_log.txt';
      if (sourcePath === undefined || sourcePath.length === 0) {
        result.error('no_source', 'sourcePath missing', null);
        return;
      }
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const destUris = await documentPicker.save({
        newFileNames: [fname]
      });
      if (destUris.length > 0) {
        await fs.copyFile(sourcePath, destUris[0]);
        result.success(fname);
      } else {
        result.error('canceled', '用户取消保存', null);
      }
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'saveToDownloads failed: ' + err.code + ' ' + err.message);
      result.error('save_failed', '导出失败:' + err.message, err.code);
    }
  }

  // 日志导出(鸿蒙路径):Dart 直接传字节 → 写入 picker 目标 URI,
  //   不经沙箱中间文件(沙箱 /tmp 路径原生侧不可读,曾致空白文件)。
  private async exportLog(call: MethodCall, result: MethodResult): Promise<void> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    try {
      const fileName = call.argument('fileName') as string | undefined;
      const fname = fileName !== undefined && fileName.length > 0
        ? fileName
        : 'xiangjugong_log.txt';
      const raw: ESObject = call.argument('bytes');
      if (raw === null) {
        result.error('no_bytes', 'bytes missing', null);
        return;
      }
      const bytesArr = raw as Uint8Array;
      const buf: ArrayBuffer = bytesArr.buffer as ArrayBuffer;
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const destUris = await documentPicker.save({ newFileNames: [fname] });
      if (destUris.length === 0) {
        result.error('canceled', '用户取消保存', null);
        return;
      }
      const dst = fs.openSync(destUris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(dst.fd, buf);
      fs.closeSync(dst);
      Log.i(TAG, 'log exported: ' + fname);
      result.success('已保存:' + fname);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'exportLog failed: ' + err.code + ' ' + err.message);
      result.error('save_failed', '导出失败:' + err.message, err.code);
    }
  }

  // ── reminder(S2:ReminderAgentManager 精确到点提醒 + 倒计时常驻通知;
  //    实况卡片圆环进度见 C2:startCountdown 同步 formProvider.updateForm)──
  private static readonly COUNTDOWN_NOTIFICATION_ID: number = 9000;
  private reminderMap: Record<string, number> = {};
  private _reminderMapLoaded: boolean = false;
  private _scheduledCount: number = 0;
  private _lastScheduleAt: number = 0;
  private countdownTimer: number | undefined = undefined;
  private _countdownEndAt: number = 0;
  private _countdownTitle: string = '';
  private _countdownEndText: string = '';
  private _countdownTotal: number = 0;
  // 卡片倒计时绑定字段(内存态;持久化于 course_card.json)。
  private _cardCountdownActive: number = 0;
  private _cardCountdownTitle: string = '';
  private _cardCountdownText: string = '';
  private _cardCountdownPct: number = 0;
  private _cardCountdownRemain: number = 0;
  // 卡片课程字段(v2:首页小课表排布;内存态;updateForm 全量下发)。
  private _cardWeek: string = '';
  private _cardCurTag: string = '';
  private _cardCurName: string = '';
  private _cardCurRoom: string = '';
  private _cardNextLine: string = '';

  private handleReminder(call: MethodCall, result: MethodResult): void {
    switch (call.method) {
      case 'ensureChannels':
        result.success(null);
        return;
      case 'canScheduleExactAlarm':
        // OHOS ReminderAgent 无"精确闹钟"限制概念 → true。
        result.success(true);
        return;
      case 'scheduleAlert':
        this.scheduleAlert(call, result);
        return;
      case 'cancelAlert':
        this.cancelAlert(call, result);
        return;
      case 'cancelAllAlarms':
        this.cancelAllAlarms(result);
        return;
      case 'startCountdown':
        this.startCountdown(call, result);
        return;
      case 'stopCountdown':
        this.stopCountdown(result);
        return;
      case 'requestNotificationPermission':
        this.requestNotificationPermission(result);
        return;
      case 'openBatteryOptimizationSettings':
        // OHOS 无"电池优化白名单"概念(提醒走 ReminderAgent 系统调度) → 空。
        result.success(null);
        return;
      case 'openAppSettings':
        // 引导通知授权(应用详情页无标准跳转能力) → 顺风车打开授权弹窗。
        this.requestNotificationPermission(result);
        return;
      case 'openExactAlarmSettings':
        result.success(null);
        return;
      case 'getDiagnostics':
        {
          const diag: ReminderDiag = {
            scheduled: this._scheduledCount,
            lastAtMillis: this._lastScheduleAt
          };
          result.success(diag);
        }
        return;
      default:
        result.notImplemented();
    }
  }

  /** 排一个到点提醒:ReminderRequestTimer(剩余秒数倒计时,到点系统通知)。
   *  same dart id → 先 cancel 旧 reminder 再 publish 新的(通知 ID 覆盖语义)。 */
  private async scheduleAlert(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const id = call.argument('id') as number | undefined;
      const atMillis = call.argument('atMillis') as number | undefined;
      const title = call.argument('title') as string | undefined;
      const body = call.argument('body') as string | undefined;
      if (id === undefined || atMillis === undefined) {
        result.error('bad_args', 'id/atMillis missing', null);
        return;
      }
      await this.cancelAlertById(id);
      const secs = Math.floor((atMillis - Date.now()) / 1000);
      if (secs <= 0) {
        // 已过期 → 视为"到点即触发"(Android 端语义:直接弹)。
        Log.i(TAG, 'scheduleAlert id=' + id + ' expired(secs<0), skip');
        result.success(true);
        return;
      }
      const req: reminderAgentManager.ReminderRequestTimer = {
        reminderType: reminderAgentManager.ReminderType.REMINDER_TYPE_TIMER,
        triggerTimeInSeconds: secs,
        title: title !== undefined && title.length > 0 ? title : '课程提醒',
        content: body !== undefined ? body : '',
        notificationId: id,
        tapDismissed: true
      };
      const reminderId = await reminderAgentManager.publishReminder(req);
      this.reminderMap[String(id)] = reminderId;
      this._scheduledCount++;
      this._lastScheduleAt = Date.now();
      await this.persistReminderMap();
      Log.i(TAG, 'scheduleAlert id=' + id + ' reminderId=' + reminderId + ' secs=' + secs);
      result.success(true);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'scheduleAlert failed: ' + err.code + ' ' + err.message);
      result.error('schedule_failed', '提醒注册失败:' + err.message, err.code);
    }
  }

  private async cancelAlert(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const id = call.argument('id') as number | undefined;
      if (id !== undefined) {
        await this.cancelAlertById(id);
      }
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'cancelAlert failed: ' + err.code + ' ' + err.message);
      result.error('cancel_failed', err.message, err.code);
    }
  }

  private async cancelAlertById(dartId: number): Promise<void> {
    await this.loadReminderMap();
    const rid: number | undefined = this.reminderMap[String(dartId)];
    if (rid !== undefined && rid > 0) {
      await reminderAgentManager.cancelReminder(rid);
    }
    this.removeMapKey(String(dartId));
    await this.persistReminderMap();
  }

  /** ArkTS 不支持 delete → 过滤重建(key 不在新对象)。 */
  private removeMapKey(key: string): void {
    const next: Record<string, number> = {};
    const keys: string[] = Object.keys(this.reminderMap);
    for (let i = 0; i < keys.length; i++) {
      if (keys[i] !== key) {
        next[keys[i]] = this.reminderMap[keys[i]] as number;
      }
    }
    this.reminderMap = next;
  }

  private async cancelAllAlarms(result: MethodResult): Promise<void> {
    try {
      await this.loadReminderMap();
      const ids: string[] = Object.keys(this.reminderMap);
      for (let i = 0; i < ids.length; i++) {
        const rid: number | undefined = this.reminderMap[ids[i]];
        if (rid !== undefined && rid > 0) {
          await reminderAgentManager.cancelReminder(rid);
        }
      }
      this.reminderMap = {};
      await this.persistReminderMap();
      Log.i(TAG, 'cancelAllAlarms cleared ' + ids.length);
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'cancelAllAlarms failed: ' + err.code + ' ' + err.message);
      result.error('cancel_failed', err.message, err.code);
    }
  }

  /** 课中倒计时常驻通知:每 updateIntervalMs 自算剩余并重新发布同一 ID 通知。
   *  进程存活期内自治更新;(进程被杀 → 通知停在最后文本,实况卡片侧由
   *  FormExtensionAbility 定时刷新兜底,见 C2。) */
  private async startCountdown(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const title = call.argument('title') as string | undefined;
      const endText = call.argument('endText') as string | undefined;
      const endAtMillis = call.argument('endAtMillis') as number | undefined;
      const totalMinutes = call.argument('totalMinutes') as number | undefined;
      const updateIntervalMs = call.argument('updateIntervalMs') as number | undefined;
      this.stopCountdownTimer();
      this._countdownEndAt = endAtMillis !== undefined ? endAtMillis : 0;
      this._countdownTitle = title !== undefined ? title : '课程进行中';
      this._countdownEndText = endText !== undefined ? endText : '';
      this._countdownTotal = totalMinutes !== undefined ? totalMinutes : 0;
      if (this._countdownEndAt <= 0) {
        result.success(false);
        return;
      }
      await this.publishCountdown();
      const interval: number = Math.max(updateIntervalMs !== undefined ? updateIntervalMs : 60000, 10000);
      this.countdownTimer = setInterval(() => {
        this.publishCountdown();
      }, interval);
      Log.i(TAG, 'startCountdown endAt=' + this._countdownEndAt);
      result.success(true);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'startCountdown failed: ' + err.code + ' ' + err.message);
      result.error('countdown_failed', err.message, err.code);
    }
  }

  private async publishCountdown(): Promise<void> {
    if (this._countdownEndAt <= 0) {
      return;
    }
    const remainMs = this._countdownEndAt - Date.now();
    if (remainMs <= 0) {
      // 已到下课:停止常驻通知(卡片进度由 C2 置 100%)。
      await this.stopCountdownTimer();
      await notificationManager.cancel(XiangJuGongChannelsPlugin.COUNTDOWN_NOTIFICATION_ID);
      return;
    }
    const remainMin = Math.ceil(remainMs / 60000);
    const done = this._countdownTotal > 0
      ? 1.0 - remainMs / (this._countdownTotal * 60000)
      : 0.0;
    const pct: number = Math.max(0, Math.min(100, Math.round(done * 100)));
    const text = '距下课约 ' + remainMin + ' 分钟 · ' + (this._countdownEndText.length > 0 ? this._countdownEndText : '');
    const req: notificationManager.NotificationRequest = {
      id: XiangJuGongChannelsPlugin.COUNTDOWN_NOTIFICATION_ID,
      isOngoing: true,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: this._countdownTitle,
          text: text
        }
      }
    };
    await notificationManager.publish(req);
    // C2:实况卡片圆环同步 —— countdownText 传【不变式】(endText 含结束时刻,
    //  如「第1-2节 · 11:30 结束」):进程被杀后卡片兜底刷新仍显示准确时刻。
    await this.updateCountdownForm(this._countdownTitle, this._countdownEndText, pct, remainMin);
  }

  private stopCountdown(result: MethodResult): void {
    try {
      this.stopCountdownTimer();
      // 异步取消通知 + 清卡片进度,结果不回传(幂等)。
      notificationManager.cancel(XiangJuGongChannelsPlugin.COUNTDOWN_NOTIFICATION_ID)
        .then(() => {
          Log.i(TAG, 'countdown notification canceled');
        })
        .catch((e: BusinessError) => {
          Log.w(TAG, 'cancel countdown failed: ' + e.code + ' ' + e.message);
        });
      this.clearCountdownForm();
      result.success(true);
    } catch (e) {
      const err = e as BusinessError;
      result.error('countdown_stop_failed', err.message, err.code);
    }
  }

  private stopCountdownTimer(): void {
    if (this.countdownTimer !== undefined) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = undefined;
    }
  }

  private requestNotificationPermission(result: MethodResult): void {
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    notificationManager.requestEnableNotification(ctx)
      .then(() => {
        result.success(null);
      })
      .catch((e: BusinessError) => {
        Log.w(TAG, 'requestEnableNotification: ' + e.code + ' ' + e.message);
        result.success(null); // 用户拒绝/弹窗取消 → 静默成功(不阻塞课程功能)。
      });
  }

  /** 倒计时卡片进度回写(C2):合并 countdown 字段落盘 + 更新全部活跃卡片。 */
  private async updateCountdownForm(title: string, text: string, pct: number, remainMin: number): Promise<void> {
    this._cardCountdownActive = 1;
    this._cardCountdownTitle = title;
    this._cardCountdownText = text;
    this._cardCountdownPct = pct;
    this._cardCountdownRemain = remainMin;
    await this.persistCardCountdown();
    await this.updateCourseForms();
  }

  private async clearCountdownForm(): Promise<void> {
    this._cardCountdownActive = 0;
    await this.persistCardCountdown();
    await this.updateCourseForms();
  }

  // ── cards 通道:Flutter 今日课程快照 → filesDir/course_card.json ──
  private handleCards(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'syncToday') {
      result.notImplemented();
      return;
    }
    const json = call.argument('json') as string | undefined;
    if (json === undefined || json.length === 0) {
      result.error('bad_args', 'json missing', null);
      return;
    }
    this.writeCourseSnapshot(json).then(() => {
      result.success(null);
    }).catch((e: BusinessError) => {
      Log.e(TAG, 'cards sync failed: ' + e.code + ' ' + e.message);
      result.error('card_sync_failed', e.message, e.code);
    });
  }

  private cardJsonPath(): string {
    const ctx = this.abilityContext;
    return ctx !== null ? ctx.filesDir + '/course_card.json' : '';
  }

  private formIdsPath(): string {
    const ctx = this.abilityContext;
    return ctx !== null ? ctx.filesDir + '/card_form_ids.json' : '';
  }

  /** 写文本文件(ArkTS 无 writeTextSync;openSync + writeSync 封装)。 */
  private writeText(p: string, text: string): void {
    const f = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(f.fd, text);
    } finally {
      fs.closeSync(f);
    }
  }

  /** 写课表快照:json 为 Dart 全量字段,仅保留原文件 countdown 字段(合并)。 */
  private async writeCourseSnapshot(json: string): Promise<void> {
    const p = this.cardJsonPath();
    if (p.length === 0) {
      return;
    }
    const obj = this.mergeCardJson(json);
    this.writeText(p, JSON.stringify(obj));
    await this.updateCourseForms();
    Log.i(TAG, 'course snapshot written');
  }

  private mergeCardJson(courseJson: string): Record<string, Object> {
    try {
      const parsed = JSON.parse(courseJson) as Record<string, Object>;
      const result: Record<string, Object> = parsed;
      // 内存缓存课程行(全量 updateForm 用)。
      this._cardWeek = this.strOf(parsed, 'weekText');
      this._cardCurTag = this.strOf(parsed, 'curTag');
      this._cardCurName = this.strOf(parsed, 'curName');
      this._cardCurRoom = this.strOf(parsed, 'curRoom');
      this._cardNextLine = this.strOf(parsed, 'nextLine');
      if (this._cardCountdownActive === 1) {
        result['countdownActive'] = 1;
        result['countdownTitle'] = this._cardCountdownTitle;
        result['countdownText'] = this._cardCountdownText;
        result['countdownPct'] = this._cardCountdownPct;
        result['countdownRemain'] = this._cardCountdownRemain;
        result['countdownEndAt'] = this._countdownEndAt;
        result['countdownTotal'] = this._countdownTotal;
      }
      return result;
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'mergeCardJson failed: ' + err.code + ' ' + err.message);
      const empty: Record<string, Object> = {};
      return empty;
    }
  }

  private strOf(obj: Record<string, Object>, key: string): string {
    const v = obj[key];
    return typeof v === 'string' ? v : '';
  }

  /** 倒计时字段单独落盘(进度刷新,不动课表字段)。 */
  private async persistCardCountdown(): Promise<void> {
    const p = this.cardJsonPath();
    if (p.length === 0) {
      return;
    }
    try {
      let obj: Record<string, Object> = {};
      if (fs.accessSync(p)) {
        const raw = fs.readTextSync(p);
        if (raw.length > 0) {
          const parsed = JSON.parse(raw) as Record<string, Object>;
          if (parsed !== undefined && parsed !== null) {
            obj = parsed;
          }
        }
      }
      if (this._cardCountdownActive === 1) {
        obj['countdownActive'] = 1;
        obj['countdownTitle'] = this._cardCountdownTitle;
        obj['countdownText'] = this._cardCountdownText;
        obj['countdownPct'] = this._cardCountdownPct;
        obj['countdownRemain'] = this._cardCountdownRemain;
        obj['countdownEndAt'] = this._countdownEndAt;
        obj['countdownTotal'] = this._countdownTotal;
      } else {
        obj['countdownActive'] = 0;
      }
      this.writeText(p, JSON.stringify(obj));
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'persistCardCountdown failed: ' + err.code + ' ' + err.message);
    }
  }

  /** 推送 countdown 绑定数据到全部活跃服务卡片(有实例才生效)。 */
  private async updateCourseForms(): Promise<void> {
    try {
      const idsPath = this.formIdsPath();
      if (idsPath.length === 0 || !fs.accessSync(idsPath)) {
        return;
      }
      const raw = fs.readTextSync(idsPath);
      const ids = JSON.parse(raw) as string[];
      if (!Array.isArray(ids) || ids.length === 0) {
        return;
      }
      const binding: FormCardBinding = {
        weekText: this._cardWeek,
        curTag: this._cardCurTag,
        curName: this._cardCurName,
        curRoom: this._cardCurRoom,
        nextLine: this._cardNextLine,
        countdownActive: this._cardCountdownActive,
        countdownTitle: this._cardCountdownTitle,
        countdownText: this._cardCountdownText,
        countdownPct: this._cardCountdownPct,
        countdownRemain: this._cardCountdownRemain
      };
      const data = formBindingData.createFormBindingData(binding);
      for (let i = 0; i < ids.length; i++) {
        await formProvider.updateForm(ids[i], data);
      }
    } catch (e) {
      const err = e as BusinessError;
      Log.w(TAG, 'updateCourseForms: ' + err.code + ' ' + err.message);
    }
  }

  // ── reminder 状态持久化(preferences: dartId → reminderId 映射)──
  private async loadReminderMap(): Promise<void> {
    if (this._reminderMapLoaded) {
      return;
    }
    const ctx = this.abilityContext;
    if (ctx === null) {
      return;
    }
    try {
      const prefs = await preferences.getPreferences(ctx, 'xjug_reminder');
      const raw = await prefs.get('map', '');
      if (typeof raw === 'string' && raw.length > 0) {
        const obj = JSON.parse(raw) as Record<string, number>;
        if (obj !== undefined && obj !== null) {
          this.reminderMap = obj;
        }
      }
    } catch (e) {
      const err = e as BusinessError;
      Log.w(TAG, 'loadReminderMap failed: ' + err.code + ' ' + err.message);
    }
    this._reminderMapLoaded = true;
  }

  private async persistReminderMap(): Promise<void> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      return;
    }
    try {
      const prefs = await preferences.getPreferences(ctx, 'xjug_reminder');
      await prefs.put('map', JSON.stringify(this.reminderMap));
      await prefs.flush();
    } catch (e) {
      const err = e as BusinessError;
      Log.w(TAG, 'persistReminderMap failed: ' + err.code + ' ' + err.message);
    }
  }

  // ── diag(把 Flutter 侧导航诊断经 hilog 输出, tag XJChannels;仅开发用)──
  private handleDiag(call: MethodCall, result: MethodResult): void {
    if (call.method !== 'log') {
      result.notImplemented();
      return;
    }
    const msg = call.argument('msg') as string | undefined;
    Log.i(TAG, '[diag] ' + (msg !== undefined ? msg : ''));
    result.success(null);
  }

  // ── picker(PLAT-01:选图/选 Excel/保存文件;PhotoViewPicker 与
  //    DocumentViewPicker 均无需运行时权限)──────────────
  private handlePicker(call: MethodCall, result: MethodResult): void {
    if (call.method === 'pickImage') {
      this.pickImage(result);
      return;
    }
    if (call.method === 'pickExcel') {
      this.pickExcel(result);
      return;
    }
    if (call.method === 'saveFile') {
      this.saveFile(call, result);
      return;
    }
    result.notImplemented();
  }

  private async pickImage(result: MethodResult): Promise<void> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    try {
      const picker = new photoAccessHelper.PhotoViewPicker();
      const res = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      if (res.photoUris.length === 0) {
        result.success(null);
        return;
      }
      const uri = res.photoUris[0];
      const bytes = await readUriBytes(uri);
      result.success({
        name: nameFromUri(uri, 'picked_image.png'),
        bytes: bytes
      });
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'pickImage failed: ' + err.code + ' ' + err.message);
      result.error('pick_failed', '选择图片失败:' + err.message, err.code);
    }
  }

  private async pickExcel(result: MethodResult): Promise<void> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    try {
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const uris = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.xls', '.xlsx']
      });
      if (uris.length === 0) {
        result.success(null);
        return;
      }
      const uri = uris[0];
      const bytes = await readUriBytes(uri);
      result.success({
        name: nameFromUri(uri, 'timetable.xlsx'),
        bytes: bytes
      });
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'pickExcel failed: ' + err.code + ' ' + err.message);
      result.error('pick_failed', '选择文件失败:' + err.message, err.code);
    }
  }

  // 保存任意字节:DocumentViewPicker 让用户选位置 → 直写(与 exportLog 同模式)。
  private async saveFile(call: MethodCall, result: MethodResult): Promise<void> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      result.error('no_context', 'ability context missing', null);
      return;
    }
    try {
      const fileName = call.argument('fileName') as string | undefined;
      const fname = fileName !== undefined && fileName.length > 0
        ? fileName
        : 'export.html';
      const raw: ESObject = call.argument('bytes');
      if (raw === null) {
        result.error('no_bytes', 'bytes missing', null);
        return;
      }
      const bytesArr = raw as Uint8Array;
      const buf: ArrayBuffer = bytesArr.buffer as ArrayBuffer;
      const documentPicker = new picker.DocumentViewPicker(ctx);
      const destUris = await documentPicker.save({ newFileNames: [fname] });
      if (destUris.length === 0) {
        result.error('canceled', '用户取消保存', null);
        return;
      }
      const dst = fs.openSync(destUris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(dst.fd, buf);
      fs.closeSync(dst);
      Log.i(TAG, 'file saved: ' + fname);
      result.success('已保存:' + fname);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'saveFile failed: ' + err.code + ' ' + err.message);
      result.error('save_failed', '保存失败:' + err.message, err.code);
    }
  }
  // ── secure 通道(Steam token 等敏感值:HUKS AES-256-GCM 加密 → 偏好存储)──
  // 加密:init 不传 TAG_IV → 系统随机生成 IV 并与密文拼接返回(前 16 字节);
  // 解密:从存储数据切出 IV 回填 TAG_IV。
  private handleSecure(call: MethodCall, result: MethodResult): void {
    if (call.method === 'write') {
      this.secureWrite(call, result);
      return;
    }
    if (call.method === 'read') {
      this.secureRead(call, result);
      return;
    }
    if (call.method === 'delete') {
      this.secureDelete(call, result);
      return;
    }
    result.notImplemented();
  }

  private secureProps(): huks.HuksParam[] {
    return [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE }
    ];
  }

  private async ensureKey(): Promise<void> {
    try {
      await huks.generateKeyItem(HUKS_ALIAS, { properties: this.secureProps() });
    } catch (e) {
      // 已存在(或重复生成)→ 幂等复用,不视为失败。
      const err = e as BusinessError;
      Log.w(TAG, 'generateKeyItem: ' + err.code + ' ' + err.message);
    }
  }

  private async huksEncryptText(text: string): Promise<Uint8Array> {
    await this.ensureKey();
    const props = this.secureProps();
    const enc = new util.TextEncoder();
    const plain = enc.encodeInto(text);
    const handle = await huks.initSession(HUKS_ALIAS, { properties: props, inData: plain });
    const upd = await huks.updateSession(handle.handle, { properties: props, inData: plain });
    const fin = await huks.finishSession(handle.handle, { properties: props });
    const a = upd.outData !== undefined ? upd.outData : new Uint8Array(0);
    const b = fin.outData !== undefined ? fin.outData : new Uint8Array(0);
    return concatU8(a, b);
  }

  private async huksDecryptText(data: Uint8Array): Promise<string> {
    const base = this.secureProps();
    const iv = data.slice(0, 16);
    const cipher = data.slice(16);
    const props: huks.HuksParam[] = base.slice(0, base.length);
    props.push({ tag: huks.HuksTag.HUKS_TAG_IV, value: iv });
    const handle = await huks.initSession(HUKS_ALIAS, { properties: props, inData: cipher });
    const upd = await huks.updateSession(handle.handle, { properties: props, inData: cipher });
    const fin = await huks.finishSession(handle.handle, { properties: props });
    const a = upd.outData !== undefined ? upd.outData : new Uint8Array(0);
    const b = fin.outData !== undefined ? fin.outData : new Uint8Array(0);
    const dec = new util.TextDecoder();
    return dec.decodeWithStream(concatU8(a, b));
  }

  private async secureStore(): Promise<preferences.Preferences> {
    const ctx = this.abilityContext;
    if (ctx === null) {
      throw new Error('no ability context');
    }
    return preferences.getPreferences(ctx, 'xjug_secure');
  }

  private async secureWrite(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key = call.argument('key') as string | undefined;
      const value = call.argument('value') as string | undefined;
      if (key === undefined || value === undefined || key.length === 0) {
        result.error('bad_args', 'key/value missing', null);
        return;
      }
      const cipher = await this.huksEncryptText(value);
      const b64 = new util.Base64Helper().encodeToStringSync(cipher);
      const pref = await this.secureStore();
      await pref.put(key, b64);
      await pref.flush();
      Log.i(TAG, 'secure.write ok key=' + key);
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'secure.write failed: ' + err.code + ' ' + err.message);
      result.error('secure_failed', err.message, err.code);
    }
  }

  private async secureRead(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key = call.argument('key') as string | undefined;
      if (key === undefined || key.length === 0) {
        result.error('bad_args', 'key missing', null);
        return;
      }
      const pref = await this.secureStore();
      const raw = await pref.get(key, '');
      if (typeof raw !== 'string' || raw.length === 0) {
        result.success(null);
        return;
      }
      const cipher = new util.Base64Helper().decodeSync(raw);
      const plain = await this.huksDecryptText(cipher);
      result.success(plain);
    } catch (e) {
      const err = e as BusinessError;
      Log.e(TAG, 'secure.read failed: ' + err.code + ' ' + err.message);
      result.error('secure_failed', err.message, err.code);
    }
  }

  private async secureDelete(call: MethodCall, result: MethodResult): Promise<void> {
    try {
      const key = call.argument('key') as string | undefined;
      if (key === undefined || key.length === 0) {
        result.error('bad_args', 'key missing', null);
        return;
      }
      const pref = await this.secureStore();
      await pref.delete(key);
      await pref.flush();
      result.success(null);
    } catch (e) {
      const err = e as BusinessError;
      result.error('secure_failed', err.message, err.code);
    }
  }
}

// ── 文件级工具 ─────────────────────────────────────────
// 拼接两个 Uint8Array(ArkTS 数组字面量展开受限 → 手动 set)。
function concatU8(a: Uint8Array, b: Uint8Array): Uint8Array {
  const out = new Uint8Array(a.length + b.length);
  out.set(a, 0);
  out.set(b, a.length);
  return out;
}

// picker URI 末段文件名(picker 不直接返回名字;失败兜底 fallback)。
function nameFromUri(uri: string, fallback: string): string {
  const idx = uri.lastIndexOf('/');
  if (idx < 0 || idx === uri.length - 1) {
    return fallback;
  }
  const raw = uri.substring(idx + 1);
  try {
    return decodeURIComponent(raw);
  } catch (e) {
    return raw;
  }
}

// 读 picker 临时授权 URI 的全部字节(与 saveImage 直写模式对称)。
async function readUriBytes(uri: string): Promise<Uint8Array> {
  const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
  try {
    const stat = fs.statSync(file.fd);
    const buf = new ArrayBuffer(stat.size);
    const len = fs.readSync(file.fd, buf);
    return new Uint8Array(buf, 0, len);
  } finally {
    fs.closeSync(file);
  }
}
