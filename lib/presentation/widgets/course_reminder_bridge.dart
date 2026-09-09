// === 文件: lib/presentation/widgets/course_reminder_bridge.dart ===
// 编号：v1.36.0 课程提醒 · 常驻桥（挂在 App 顶层 MaterialApp 内，整机生命周期）
// 说明：把真实课表数据驱动到原生提醒（Android；Web 直接空转）：
//   - **到点提醒**：课表/节次/周次变化 → 排「今天剩余 + 明天全部」课程开始
//     闹钟（AlarmManager，App 不在也弹）；闹钟清单持久化 → 开机/兜底重排；
//   - **常驻通知（上课中）**：监听 currentClassProvider —— 上课(非空) →
//     原生前台服务**自治倒计时**（传 endAt + total，原生按墙钟自己刷新）；
//     下课 → 停止；
//   - v1.36.0 定稿：桌面小组件因 MIUI 桌面 RemoteViews 兼容性问题已移除，
//     本桥只服务「到点通知 + 上课常驻通知」。
//   - 本桥自身零 Timer、零周期占用；跨周日次以当前周次近似（打开即重排修正）。
import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cards/course_card_sync.dart';
import '../../core/live_view/live_view_course.dart';
import '../../core/platform/contract/plat_live_view.dart';
import '../../core/reminder/reminder_service.dart';
import '../../domain/entities/class_period.dart';
import '../../domain/entities/course.dart';
import '../providers/course_provider.dart';
import '../providers/settings_providers.dart';

/// 顶层常驻桥：无 UI，纯驱动（return child 透传）。
class CourseReminderBridge extends ConsumerStatefulWidget {
  const CourseReminderBridge({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<CourseReminderBridge> createState() =>
      _CourseReminderBridgeState();
}

class _CourseReminderBridgeState extends ConsumerState<CourseReminderBridge> {
  /// 首次 build 完成监听注册与初始排程（ref.listen 必须在 build 内调用）。
  bool _booted = false;

  /// PLAT-03:实况窗边界 Timer —— 只在「节点切换时刻」触发一次后重排,
  ///   不是周期轮询(保持本桥零周期占用的原设计)。
  Timer? _liveViewTimer;

  @override
  void dispose() {
    _liveViewTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && !_booted) {
      _booted = true;
      // 课表/周次/节次变更 → 重排到点闹钟。
      ref.listen(courseListProvider, (_, _) => _scheduleCourseAlarms());
      ref.listen(scheduleMetaProvider, (_, _) => _scheduleCourseAlarms());
      ref.listen(
        appSettingsProvider.select((s) => s.classPeriods),
        (_, _) => _scheduleCourseAlarms(),
      );
      // 当前课程 → 启停常驻自治通知。
      ref.listen(
        currentClassProvider,
        (_, CurrentClass? next) => _onCurrentClass(next),
      );
      // 课程提醒总开关：关 → 清闹钟 + 停常驻；开 → 重排 + 恢复上课态。
      ref.listen(appSettingsProvider.select((s) => s.courseReminderEnabled), (
        _,
        bool enabled,
      ) {
        if (!enabled) {
          unawaited(ReminderService.cancelAllAlarms());
          unawaited(ReminderService.stopCountdown());
          // PLAT-03:关闭课程提醒 → 同时收起课程实况窗。
          _liveViewTimer?.cancel();
          unawaited(PlatLiveViewRegistry.instance.stop(LiveViewIds.course));
        } else {
          _scheduleCourseAlarms();
          _onCurrentClass(ref.read(currentClassProvider));
        }
      });
      // 首帧后初始排程 + 覆盖「启动即在上课」（非 listen 副作用走 postFrame）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (!ref.read(appSettingsProvider).courseReminderEnabled) return;
        _scheduleCourseAlarms();
        _onCurrentClass(ref.read(currentClassProvider));
      });
    }
    return widget.child;
  }

  // ── 到点提醒排程：今天剩余 + 明天全部 ─────────────────────────

  void _scheduleCourseAlarms() {
    final List<Course> courses =
        ref.read(courseListProvider).value ?? const <Course>[];
    final meta = ref.read(scheduleMetaProvider).value;
    if (courses.isEmpty || meta == null) return;
    final List<ClassPeriod> periods = ref
        .read(appSettingsProvider)
        .classPeriods;
    final DateTime now = DateTime.now();
    // DSH-OH:课表/周次/节次变更 → 同步桌面「今日课程」卡片快照。
    unawaited(
      CourseCardSync.syncToday(
        courses: courses,
        meta: meta,
        periods: periods,
      ),
    );

    for (int dayOffset = 0; dayOffset <= 1; dayOffset++) {
      final DateTime day = now.add(Duration(days: dayOffset));
      final int weekday = day.weekday; // 1=周一..7=周日
      for (final Course c in courses) {
        if (c.day != weekday) continue;
        if (!c.showsOn(meta.effectiveWeek(day))) continue; // 跨周边界以目标日近似。
        if (c.start < 1 || c.start > periods.length) continue;
        final ClassPeriod p = periods[c.start - 1];
        if (!p.enabled) continue;
        final DateTime at = DateTime(
          day.year,
          day.month,
          day.day,
          p.startMinutes ~/ 60,
          p.startMinutes % 60,
        );
        if (dayOffset == 0 && !at.isAfter(now)) continue; // 今天已过/正在不排
        final int id =
            ('course_alarm_${c.id}_${day.year}${day.month}${day.day}')
                .hashCode &
            0x7fffffff;
        // v1.40.1(C 方案):课程闹钟携带结束参数 —— 到点原生直启倒计时
        // 常驻(App 不在也出现);时间未设置(span null)则仅弹到点通知。
        final _Span? span = _spanOf(c, periods);
        unawaited(
          ReminderService.scheduleAlert(
            id: id,
            at: at,
            title: c.name,
            body:
                '${Course.periodLabel(c.start, c.len)} · '
                '${ClassPeriod.formatMinutes(p.startMinutes)} 开始',
            endAtMillis: span == null
                ? null
                : DateTime(
                    day.year,
                    day.month,
                    day.day,
                    span.end ~/ 60,
                    span.end % 60,
                  ).millisecondsSinceEpoch,
            totalMinutes: span == null ? null : span.end - span.start,
            endText: span == null
                ? null
                : '${Course.periodLabel(c.start, c.len)} · '
                      '${ClassPeriod.formatMinutes(span.end)} 结束',
          ),
        );
      }
    }
  }

  // ── 常驻通知（上课中）：启动原生自治倒计时 / 下课停 ────────────

  /// 该课覆盖启用节次的**整段起止分钟**（0 点起；与 currentClassProvider
  /// 首末节次算法一致）。覆盖节次全未启用 → null（时间缺失，无常驻）。
  _Span? _spanOf(Course c, List<ClassPeriod> periods) {
    final int first = (c.start - 1).clamp(0, periods.length - 1);
    final int last = (c.start + c.len - 2).clamp(first, periods.length - 1);
    int? start;
    int end = 0;
    for (int i = first; i <= last; i++) {
      final ClassPeriod p = periods[i];
      if (p.enabled && p.endMinutes > p.startMinutes) {
        start ??= p.startMinutes;
        end = p.endMinutes;
      }
    }
    if (start == null || end <= start) return null;
    return _Span(start, end);
  }

  void _onCurrentClass(CurrentClass? cur) {
    if (cur == null || cur.timeMissing) {
      unawaited(ReminderService.stopCountdown());
    } else {
      final List<ClassPeriod> periods = ref
          .read(appSettingsProvider)
          .classPeriods;
      final _Span? span = _spanOf(cur.course, periods);
      if (span == null) {
        unawaited(ReminderService.stopCountdown());
      } else {
        final DateTime now = DateTime.now();
        final DateTime endAt = DateTime(
          now.year,
          now.month,
          now.day,
          span.end ~/ 60,
          span.end % 60,
        );
        unawaited(
          ReminderService.startCountdown(
            title: cur.course.name,
            endText: '${cur.periodLabel} · ${cur.spanEndLabel} 结束',
            endAtMillis: endAt.millisecondsSinceEpoch,
            totalMinutes: cur.totalMinutes <= 0 ? 1 : cur.totalMinutes,
          ),
        );
      }
    }
    // PLAT-03:课程状态变化 → 同步实况窗,并排下一个节点边界。
    unawaited(_applyLiveView());
    _scheduleLiveViewBoundary();
  }

  // ── PLAT-03:课程实况窗(实况窗 = 实时层;常驻通知/桌面卡片为兜底)────

  /// 组装实况窗输入(当前课优先;无当前课则用下一节课的课前窗口)。
  LiveViewCourseInput? _liveViewInput() {
    final List<ClassPeriod> periods = ref
        .read(appSettingsProvider)
        .classPeriods;
    if (periods.isEmpty) {
      return null;
    }
    final DateTime now = DateTime.now();
    final CurrentClass? cur = ref.read(currentClassProvider);
    final NextClass? next = ref.read(nextClassProvider);
    final DateTime? nextStart = next == null
        ? null
        : _parseHhmm(now, next.startLabel);
    if (cur != null && !cur.timeMissing) {
      final _Span? span = _spanOf(cur.course, periods);
      if (span != null) {
        return LiveViewCourseInput(
          courseName: cur.course.name,
          startAt: _atToday(now, span.start),
          endAt: _atToday(now, span.end),
          room: cur.course.location,
          periodLabel: cur.periodLabel,
          nextCourseName: next?.course.name,
          nextStartAt: nextStart,
          nextRoom: next?.course.location,
        );
      }
    }
    if (next != null) {
      final _Span? span = _spanOf(next.course, periods);
      if (span != null) {
        return LiveViewCourseInput(
          courseName: next.course.name,
          startAt: nextStart ?? now,
          endAt: _atToday(now, span.end),
          room: next.course.location,
          periodLabel: next.periodLabel,
        );
      }
    }
    return null;
  }

  /// 计算并下发实况窗(spec 为 null → 收起)。
  Future<void> _applyLiveView() async {
    if (kIsWeb) {
      return;
    }
    final PlatLiveView lv = PlatLiveViewRegistry.instance;
    final LiveViewCourseInput? input = _liveViewInput();
    final LiveViewSpec? spec = input == null
        ? null
        : LiveViewCourse.build(input);
    if (spec == null) {
      // 无课/不在窗口:仅当确实存在时才收起(避免无谓调用与 401 噪音)。
      if (await lv.isActive(LiveViewIds.course)) {
        final LiveViewOutcome r = await lv.stop(LiveViewIds.course);
        if (!r.ok && !r.degraded) {
          debugPrint('[LiveView] stop ${r.resultCode} ${r.message}');
        }
      }
      return;
    }
    final bool active = await lv.isActive(LiveViewIds.course);
    final LiveViewOutcome r = active
        ? await lv.update(spec)
        : await lv.start(spec);
    if (!r.ok) {
      debugPrint(
        '[LiveView] ${active ? 'update' : 'start'} '
        '${r.resultCode} ${r.message}${r.degraded ? ' (degraded)' : ''}',
      );
    }
  }

  /// 在下一个节点切换时刻排一次单次 Timer(上课/下课/课前窗口)。
  void _scheduleLiveViewBoundary() {
    _liveViewTimer?.cancel();
    final LiveViewCourseInput? input = _liveViewInput();
    if (input == null) {
      return;
    }
    final DateTime? boundary = LiveViewCourse.nextBoundary(input);
    if (boundary == null) {
      return;
    }
    final Duration d = boundary.difference(DateTime.now());
    if (d.isNegative) {
      return;
    }
    _liveViewTimer = Timer(d + const Duration(seconds: 2), () {
      if (!mounted) {
        return;
      }
      unawaited(_applyLiveView());
      _scheduleLiveViewBoundary();
    });
  }

  DateTime _atToday(DateTime day, int minutes) => DateTime(
    day.year,
    day.month,
    day.day,
    minutes ~/ 60,
    minutes % 60,
  );

  DateTime _parseHhmm(DateTime day, String s) {
    final int idx = s.indexOf(':');
    if (idx <= 0) {
      return day;
    }
    final int h = int.tryParse(s.substring(0, idx)) ?? 0;
    final int m = int.tryParse(s.substring(idx + 1)) ?? 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }
}

/// 课程覆盖节次的整段计时（分钟；0 点起）。
class _Span {
  const _Span(this.start, this.end);

  final int start;
  final int end;
}
