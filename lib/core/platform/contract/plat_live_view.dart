// === 文件: lib/core/platform/contract/plat_live_view.dart ===
// 编号:PLAT-03 实况窗(LiveView)平台抽象(双端同字,主项目为源)
// 说明:把「鸿蒙实况窗」从业务代码中抽出,与 PLAT-01(文件操作)同一注册制模式:
//   - 未注册 → _Default(全部返回 degraded,主项目/Web 零副作用);
//   - 镜像注册 OH 实现(live_view_ohos.dart → 通道 xiangjugong/liveview
//     → @kit.LiveViewKit 的 liveViewManager);
//   - 本文件不引用 TargetPlatform.ohos(标准 Flutter 无该枚举),平台差异全部收敛到 impl/。
//
// 设计依据(官方文档见 D:\Projects\design_refs\):
//   - 实况窗设计规范:生命周期 ≤8h;>2h 未更新隐藏胶囊/锁屏,>4h 未更新系统清除;
//   - 实况窗设计指南:卡片 = 固定区(必选)+ 辅助区(44*44vp)+ 扩展区;
//     胶囊主文本 1-3 中文 / 副文本 1-6 中文;文本超长直接截断(不支持跑马灯);
//   - 计时场景:仅端侧创建与更新,辅助区须明确「计时中」状态。
//
// 场景 ID 与申请材料《实况窗场景节点设计》一一对应。

/// 实况窗场景 ID(与权益申请材料的场景类型对应)。
abstract final class LiveViewIds {
  /// 课程时段计时。
  static const int course = 1;

  /// 待办任务截止计时。
  static const int todo = 2;
}

/// 胶囊类型(对齐 liveViewManager.CapsuleType)。
abstract final class LiveViewCapsuleType {
  static const int text = 1;
  static const int timer = 2;
  static const int progress = 3;
}

/// 展开区布局类型(对齐 liveViewManager.LayoutType)。
abstract final class LiveViewLayoutType {
  /// 不展开。
  static const int none = -1;

  /// 进度可视化(课程课时进度)。
  static const int progress = 3;

  /// 强调文本(取件码式下划线强调)。
  static const int pickup = 4;
}

/// 进度条线型(对齐 liveViewManager.LineType)。
abstract final class LiveViewLineType {
  static const int dashed = 0;
  static const int solid = 1;
  static const int thickSolid = 2;
}

/// 胶囊状态。
abstract final class LiveViewCapsuleStatus {
  static const int normal = 1;
}

/// 富文本段(颜色为 #ARGB 十六进制,如 `#FFFFFFFF`)。
class LiveViewRichText {
  const LiveViewRichText(this.text, {this.textColor});

  final String text;
  final String? textColor;

  Map<String, Object?> toMap() => <String, Object?>{
    'text': text,
    if (textColor != null) 'textColor': textColor,
  };
}

/// 计时器(倒计时/正计时;归零后系统自动显示 preset 文案,无需应用保活)。
class LiveViewTimerSpec {
  const LiveViewTimerSpec({
    required this.timeMs,
    this.isCountdown = true,
    this.isPaused = false,
    this.presetTitle,
    this.presetContent,
  });

  /// 计时初值(毫秒)。
  final int timeMs;

  /// true = 倒计时,false = 正计时。
  final bool isCountdown;

  final bool isPaused;

  /// 归零后展开区标题(系统自动替换,应用不在也可生效)。
  final String? presetTitle;

  /// 归零后展开区内容。
  final String? presetContent;

  Map<String, Object?> toMap() => <String, Object?>{
    'time': timeMs,
    'isCountdown': isCountdown,
    'isPaused': isPaused,
    if (presetTitle != null) 'presetTitle': presetTitle,
    if (presetContent != null) 'presetContent': presetContent,
  };
}

/// 胶囊内容。
class LiveViewCapsuleSpec {
  const LiveViewCapsuleSpec({
    required this.type,
    this.status = LiveViewCapsuleStatus.normal,
    this.title,
    this.content,
    this.timeMs,
    this.isCountdown,
  });

  final int type;
  final int status;

  /// 主文本:官方建议 1-3 个中文。
  final String? title;

  /// 副文本:官方建议 1-6 个中文。
  final String? content;

  /// TIMER 胶囊专用计时值(毫秒)。
  final int? timeMs;

  final bool? isCountdown;

  Map<String, Object?> toMap() => <String, Object?>{
    'type': type,
    'status': status,
    if (title != null) 'title': title,
    if (content != null) 'content': content,
    if (timeMs != null) 'time': timeMs,
    if (isCountdown != null) 'isCountdown': isCountdown,
  };
}

/// 固定区 + 展开区。
class LiveViewPrimarySpec {
  const LiveViewPrimarySpec({
    required this.title,
    this.content = const <LiveViewRichText>[],
    this.keepTimeMinutes = 5,
    this.aliveTimeSeconds,
    this.layoutType = LiveViewLayoutType.none,
    this.progress,
    this.lineType,
  });

  /// 主文本:卡片固定区有辅助区时 ≤13 中文,无辅助区时 ≤16 中文。
  final String title;

  /// 副文本段落。
  final List<LiveViewRichText> content;

  /// 结束通知中心保留分钟数。
  final int keepTimeMinutes;

  /// 存活时长(秒,API 24 起)。
  final int? aliveTimeSeconds;

  final int layoutType;

  /// 进度可视化模板的进度值(0-100)。
  final int? progress;

  final int? lineType;

  Map<String, Object?> toMap() => <String, Object?>{
    'title': title,
    'content': content.map((LiveViewRichText e) => e.toMap()).toList(),
    'keepTime': keepTimeMinutes,
    if (aliveTimeSeconds != null) 'aliveTime': aliveTimeSeconds,
    'layoutType': layoutType,
    if (progress != null) 'progress': progress,
    if (lineType != null) 'lineType': lineType,
  };
}

/// 一次 start/update 的完整规格。
class LiveViewSpec {
  const LiveViewSpec({
    required this.id,
    required this.primary,
    this.event = 'TIMER',
    this.isMute = true,
    this.timer,
    this.capsule,
  });

  final int id;

  /// 场景标识(官方按场景下发;示例值 'TIMER')。
  final String event;

  /// true = 静默;重要节点应设 false(铃声/振动)。
  final bool isMute;

  final LiveViewTimerSpec? timer;
  final LiveViewCapsuleSpec? capsule;
  final LiveViewPrimarySpec primary;

  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'event': event,
    'isMute': isMute,
    if (timer != null) 'timer': timer!.toMap(),
    if (capsule != null) 'capsule': capsule!.toMap(),
    'primary': primary.toMap(),
  };
}

/// 探测结果。
class LiveViewProbe {
  const LiveViewProbe({
    required this.supported,
    required this.enabled,
    this.code = 0,
    this.message = '',
  });

  /// 设备是否具备 LiveView 系统能力。
  final bool supported;

  /// 本应用实况窗权益是否已开通。
  final bool enabled;

  final int code;
  final String message;

  /// 可用 = 能力具备且权益已开通。
  bool get usable => supported && enabled;
}

/// 操作结果。
class LiveViewOutcome {
  const LiveViewOutcome({
    required this.ok,
    this.resultCode = 0,
    this.message = '',
    this.degraded = false,
  });

  /// 静默降级(实况窗不可用,已回落到常驻通知/桌面卡片)。
  const LiveViewOutcome.degraded(String reason)
    : ok = false,
      resultCode = 0,
      message = reason,
      degraded = true;

  final bool ok;
  final int resultCode;
  final String message;
  final bool degraded;
}

/// 平台实况窗能力。
abstract interface class PlatLiveView {
  /// 探测设备能力与权益状态。
  Future<LiveViewProbe> probe();

  /// 创建实况窗(同 id 已存在时会先结束再创建)。
  Future<LiveViewOutcome> start(LiveViewSpec spec);

  /// 更新实况窗(sequence 由原生侧自增并持久化)。
  Future<LiveViewOutcome> update(LiveViewSpec spec);

  /// 结束实况窗。
  Future<LiveViewOutcome> stop(int id);

  /// 查询某场景是否正在展示。
  Future<bool> isActive(int id);
}

/// 注册表:未注册 → [instance] 返回 Default(主项目/Web 行为零变)。
abstract final class PlatLiveViewRegistry {
  static PlatLiveView? _impl;

  /// 注册平台实现(镜像 main() 启动时注册 OH 实现)。
  static void register(PlatLiveView impl) => _impl = impl;

  static PlatLiveView get instance => _impl ?? const _DefaultPlatLiveView();
}

/// 默认实现:非鸿蒙平台一律静默降级。
class _DefaultPlatLiveView implements PlatLiveView {
  const _DefaultPlatLiveView();

  @override
  Future<LiveViewProbe> probe() async =>
      const LiveViewProbe(supported: false, enabled: false, message: '非鸿蒙平台');

  @override
  Future<LiveViewOutcome> start(LiveViewSpec spec) async =>
      const LiveViewOutcome.degraded('实况窗未注册(非鸿蒙平台)');

  @override
  Future<LiveViewOutcome> update(LiveViewSpec spec) async =>
      const LiveViewOutcome.degraded('实况窗未注册(非鸿蒙平台)');

  @override
  Future<LiveViewOutcome> stop(int id) async =>
      const LiveViewOutcome.degraded('实况窗未注册(非鸿蒙平台)');

  @override
  Future<bool> isActive(int id) async => false;
}
