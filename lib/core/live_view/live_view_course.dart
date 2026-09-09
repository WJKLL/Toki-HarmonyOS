// === 文件: lib/core/live_view/live_view_course.dart ===
// 编号:LIVEVIEW-01 课程时段计时 → 实况窗规格映射(镜像独有)
// 说明:把课表状态(当前课 / 下一节课 / 节次时间)映射为 LiveViewSpec,
//   供 course_reminder_bridge 驱动 start/update/stop。纯函数,不依赖 presentation 层。
//
// 官方限制(来源:D:\Projects\design_refs\liveview-guide.md):
//   - 胶囊主文本 1-3 个中文、副文本 1-6 个中文;仅右侧支持跑马灯;
//   - 卡片固定区(有辅助区)主文本 ≤13 中文、副文本 ≤15 中文;超长直接截断;
//   - 计时场景「辅助区须明确展示当前处于计时中状态」;
//   - 生命周期 ≤8h;>2h 未更新隐藏胶囊/锁屏,>4h 未更新系统清除。
import '../platform/contract/plat_live_view.dart';

/// 课程实况窗输入(纯数据)。
class LiveViewCourseInput {
  const LiveViewCourseInput({
    required this.courseName,
    required this.startAt,
    required this.endAt,
    this.room,
    this.periodLabel = '',
    this.nextCourseName,
    this.nextStartAt,
    this.nextRoom,
  });

  /// 当前(或即将开始)的课程名。
  final String courseName;

  final DateTime startAt;
  final DateTime endAt;

  /// 上课地点。
  final String? room;

  /// 「第 3 节」文本。
  final String periodLabel;

  /// 下一节课(课间衔接节点用;null = 今日无更多课)。
  final String? nextCourseName;
  final DateTime? nextStartAt;
  final String? nextRoom;
}

/// 课程实况窗构建器。
abstract final class LiveViewCourse {
  /// 课前提醒窗口(分钟)。
  static const int preWindowMinutes = 30;

  /// 胶囊主文本上限(中文)。
  static const int capsuleTitleMax = 3;

  /// 卡片主文本上限(有辅助区时,中文)。
  static const int cardTitleMax = 13;

  /// 卡片副文本上限(中文)。
  static const int cardSubtitleMax = 15;

  /// 生成规格;null = 当前不该展示(调用方应 stop)。
  static LiveViewSpec? build(LiveViewCourseInput input, {DateTime? at}) {
    final DateTime now = at ?? DateTime.now();
    if (now.isBefore(input.startAt)) {
      final int leftMin = input.startAt.difference(now).inMinutes;
      if (leftMin > preWindowMinutes) {
        return null;
      }
      return _preClass(input, leftMin);
    }
    if (now.isBefore(input.endAt)) {
      return _inClass(input, now);
    }
    if (input.nextStartAt != null) {
      return _breakTime(input, now);
    }
    return null;
  }

  /// 下一个节点切换时刻(供单次 Timer 精确排程,避免周期轮询)。
  static DateTime? nextBoundary(LiveViewCourseInput input, {DateTime? at}) {
    final DateTime now = at ?? DateTime.now();
    if (now.isBefore(input.startAt)) {
      final DateTime windowStart = input.startAt.subtract(
        const Duration(minutes: preWindowMinutes),
      );
      return now.isBefore(windowStart) ? windowStart : input.startAt;
    }
    if (now.isBefore(input.endAt)) {
      return input.endAt;
    }
    return input.nextStartAt;
  }

  // ── 节点一:课前提醒(距上课 ≤30 分钟)────────────────────────
  static LiveViewSpec _preClass(LiveViewCourseInput input, int leftMin) {
    final int totalMs = input.startAt.difference(DateTime.now()).inMilliseconds
        .clamp(0, 1 << 62);
    return LiveViewSpec(
      id: LiveViewIds.course,
      event: 'TIMER',
      isMute: true,
      timer: LiveViewTimerSpec(
        timeMs: totalMs,
        isCountdown: true,
        presetTitle: '上课时间到',
        presetContent: '课程已开始',
      ),
      capsule: LiveViewCapsuleSpec(
        type: LiveViewCapsuleType.text,
        title: shortName(input.courseName),
        content: '距上课 $leftMin 分',
        timeMs: totalMs,
        isCountdown: true,
      ),
      primary: LiveViewPrimarySpec(
        title: _clip(input.courseName, cardTitleMax),
        content: <LiveViewRichText>[
          LiveViewRichText(
            _clip('${_roomPrefix(input.room)}距上课 $leftMin 分钟', cardSubtitleMax),
          ),
        ],
        keepTimeMinutes: 5,
        layoutType: LiveViewLayoutType.none,
      ),
    );
  }

  // ── 节点二:课中计时(辅助区明确「计时中」)──────────────────
  static LiveViewSpec _inClass(LiveViewCourseInput input, DateTime now) {
    final int remainMs = input.endAt.difference(now).inMilliseconds
        .clamp(0, 1 << 62);
    final int leftMin = (remainMs / 60000).ceil();
    return LiveViewSpec(
      id: LiveViewIds.course,
      event: 'TIMER',
      isMute: true,
      timer: LiveViewTimerSpec(
        timeMs: remainMs,
        isCountdown: true,
        presetTitle: '下课时间到',
        presetContent: '课间休息',
      ),
      capsule: LiveViewCapsuleSpec(
        type: LiveViewCapsuleType.text,
        title: shortName(input.courseName),
        content: '距下课 $leftMin 分',
        timeMs: remainMs,
        isCountdown: true,
      ),
      primary: LiveViewPrimarySpec(
        title: _clip(input.courseName, cardTitleMax),
        content: <LiveViewRichText>[
          LiveViewRichText(
            _clip('${_roomPrefix(input.room)}计时中 · 距下课 $leftMin 分', cardSubtitleMax),
          ),
        ],
        keepTimeMinutes: 5,
        aliveTimeSeconds: (input.endAt.difference(now).inSeconds + 300).clamp(
          60,
          8 * 3600,
        ),
        // 注:进度展开区(layoutType=progress)需 layoutData.nodeIcons(2-5 个节点图标),
        //   当前仍被平台校验拒绝 → 先不展开;节点图标方案确认后再启用。
        layoutType: LiveViewLayoutType.none,
      ),
    );
  }

  // ── 节点三:课间衔接(下课 → 下一节)──────────────────────────
  static LiveViewSpec _breakTime(LiveViewCourseInput input, DateTime now) {
    final DateTime nextStart = input.nextStartAt!;
    final int leftMs = nextStart.difference(now).inMilliseconds
        .clamp(0, 1 << 62);
    final int leftMin = (leftMs / 60000).ceil();
    final String nextName = input.nextCourseName ?? '下一节课';
    return LiveViewSpec(
      id: LiveViewIds.course,
      event: 'TIMER',
      isMute: true,
      timer: LiveViewTimerSpec(
        timeMs: leftMs,
        isCountdown: true,
        presetTitle: '下节课开始',
        presetContent: nextName,
      ),
      capsule: LiveViewCapsuleSpec(
        type: LiveViewCapsuleType.text,
        title: shortName(nextName),
        content: '距下节 $leftMin 分',
        timeMs: leftMs,
        isCountdown: true,
      ),
      primary: LiveViewPrimarySpec(
        title: _clip(nextName, cardTitleMax),
        content: <LiveViewRichText>[
          LiveViewRichText(
            _clip(
              '${_roomPrefix(input.nextRoom)}${_hhmm(nextStart)} 开始 · 距下节 $leftMin 分',
              cardSubtitleMax,
            ),
          ),
        ],
        keepTimeMinutes: 5,
        layoutType: LiveViewLayoutType.none,
      ),
    );
  }

  /// 诊断用测试规格(2 分钟倒计时 + 进度展开区;id=99,与业务场景隔离)。
  static LiveViewSpec testSpec() => const LiveViewSpec(
    id: 99,
    event: 'TIMER',
    isMute: true,
    timer: LiveViewTimerSpec(
      timeMs: 120000,
      isCountdown: true,
      presetTitle: '测试结束',
      presetContent: '实况窗已归零',
    ),
    capsule: LiveViewCapsuleSpec(
      type: LiveViewCapsuleType.text,
      title: '诊断',
      content: '测试中',
      timeMs: 120000,
      isCountdown: true,
    ),
    primary: LiveViewPrimarySpec(
      title: '诊断',
      content: <LiveViewRichText>[LiveViewRichText('计时中 · 2 分钟后结束')],
      keepTimeMinutes: 1,
      aliveTimeSeconds: 180,
      layoutType: LiveViewLayoutType.none,
    ),
  );

  // ── 文本工具 ────────────────────────────────────────────────
  /// 胶囊主文本:去括号内容后截到 3 字(用户可直接把课程名写成简称)。
  static String shortName(String name) {
    String t = name.replaceAll(RegExp(r'[（(][^）)]*[）)]'), '').trim();
    if (t.isEmpty) {
      t = name.trim();
    }
    if (t.isEmpty) {
      return '课程';
    }
    return t.length <= capsuleTitleMax ? t : t.substring(0, capsuleTitleMax);
  }

  static String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

  static String _roomPrefix(String? room) {
    final String r = (room ?? '').trim();
    return r.isEmpty ? '' : '$r · ';
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
