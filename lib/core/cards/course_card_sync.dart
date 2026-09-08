// === 文件: lib/core/cards/course_card_sync.dart ===
// 编号:卡-01(镜像独有:OH 桌面「今日课程」服务卡片数据同步)
// 说明:Dart 侧计算今日课程快照(周次过滤 / 时段状态 / 时间文本),
//   经通道 xiangjugong/cards 交给原生插件 → 写沙箱 course_card.json →
//   FormExtensionAbility 读取渲染(契约键见 TodayCourseCard.ets)。
//   v2 契约:首页小课表排布(curTag/curName/curRoom/nextLine;替代 c1..c3)。
//   主工程(Android/Web)无此通道:invoke 静默失败,零副作用。
import 'dart:convert';

import 'package:flutter/services.dart' show MethodChannel;

import '../../domain/entities/class_period.dart';
import '../../domain/entities/course.dart';

/// 今日课程卡片同步(全静态;每次课程/周次/节次变更后调用)。
abstract final class CourseCardSync {
  static const MethodChannel _channel = MethodChannel('xiangjugong/cards');

  /// 推送今日快照;OH 原生缺失时静默(主工程/沙箱外无副作用)。
  static Future<void> syncToday({
    required List<Course> courses,
    required ScheduleMeta meta,
    required List<ClassPeriod> periods,
    DateTime? at,
  }) async {
    try {
      final String json = jsonEncode(
        _buildPayload(courses, meta, periods, at ?? DateTime.now()),
      );
      await _channel.invokeMethod<void>(
        'syncToday',
        <String, Object?>{'json': json},
      );
    } catch (_) {
      // 通道未注册(主工程/Web):静默。
    }
  }

  /// 构造卡片绑定 JSON(v2:首页小课表排布字段)。
  static Map<String, Object?> _buildPayload(
    List<Course> courses,
    ScheduleMeta meta,
    List<ClassPeriod> periods,
    DateTime now,
  ) {
    final int weekday = now.weekday;
    final int week = meta.effectiveWeek(now);
    final int nowMin = now.hour * 60 + now.minute;
    final List<_Row> rows = <_Row>[];
    for (final Course c in courses) {
      if (c.day != weekday) continue;
      if (!c.showsOn(week)) continue;
      if (c.start < 1 || c.start > periods.length) continue;
      final int start = periods[c.start - 1].startMinutes;
      final int? end = _endOf(c, periods);
      if (end == null || end <= start) continue;
      rows.add(
        _Row(
          name: c.name,
          start: start,
          end: end,
          room: c.location ?? '',
          periodLabel: Course.periodLabel(c.start, c.len),
          timeLabel: '${_fmt(start)}-${_fmt(end)}',
        ),
      );
    }
    rows.sort((_Row a, _Row b) => a.start.compareTo(b.start));

    final Map<String, Object?> out = <String, Object?>{
      'weekText': '第 $week 周 · 第 ${meta.term} 学期',
      'curTag': '',
      'curName': '',
      'curRoom': '',
      'curStart': 0,
      'curEnd': 0,
      'nextLine': '',
    };

    if (rows.isEmpty) {
      out['curName'] = '暂无课程';
      out['nextLine'] = '点击卡片去添加';
      return out;
    }

    // 进行中课程(整段 [start,end) 内)。
    _Row? current;
    _Row? next;
    for (final _Row r in rows) {
      if (nowMin >= r.start && nowMin < r.end) {
        current = r;
      } else if (r.end > nowMin && next == null) {
        next = r;
      }
    }
    if (current != null) {
      out['curTag'] = '当前课程';
      out['curName'] = current.name;
      out['curRoom'] = current.room.isNotEmpty ? '教室:${current.room}' : '';
      out['curStart'] = current.start;
      out['curEnd'] = current.end;
      out['nextLine'] = next != null
          ? '下一节课是:${next.name} ${_fmt(next.start)}'
          : '今天没有更多课了';
    } else if (next != null) {
      out['curTag'] = '下一节课';
      out['curName'] = next.name;
      out['curStart'] = next.start;
      out['curEnd'] = next.end;
      // 次一节。
      _Row? next2;
      for (final _Row r in rows) {
        if (r.start > next.start) {
          next2 = r;
          break;
        }
      }
      out['nextLine'] = next2 != null
          ? '再下一节:${next2.name} ${_fmt(next2.start)}'
          : '今天没有更多课了';
    } else {
      out['curTag'] = '全天课程结束';
      out['curName'] = '休息中';
      out['nextLine'] = '明天也要好好上课 ✨';
    }
    return out;
  }

  /// 该课覆盖节次的整段结束分钟(与 course_reminder_bridge._spanOf 同算法)。
  static int? _endOf(Course c, List<ClassPeriod> periods) {
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
    return end;
  }

  static String _fmt(int minutes) {
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    String two(int x) => x < 10 ? '0$x' : '$x';
    return '${two(h)}:${two(m)}';
  }
}

class _Row {
  const _Row({
    required this.name,
    required this.start,
    required this.end,
    required this.room,
    required this.periodLabel,
    required this.timeLabel,
  });

  final String name;
  final int start;
  final int end;
  final String room;
  final String periodLabel;
  final String timeLabel;
}
