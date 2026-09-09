// === 文件: lib/core/platform/impl/ohos/live_view_ohos.dart ===
// 编号:PLAT-03-OH 实况窗平台实现(镜像独有;主工程无此文件)
// 说明:PLAT-03 契约的鸿蒙实现 —— 通道 xiangjugong/liveview
//   → XiangJuGongChannelsPlugin.handleLiveView → @kit.LiveViewKit 的 liveViewManager。
//   原生侧负责:canIUse 能力判定、isLiveViewEnabled 权益判定、sequence 自增持久化、
//   同 id 先 stop 再 start、全局节流;Dart 侧只做参数组装与结果映射。
// 降级:任何异常都不抛给业务层,统一返回 degraded(业务继续走常驻通知 + 桌面卡片)。
import 'dart:convert' show jsonEncode;

import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException, PlatformException;

import '../../contract/plat_live_view.dart';

/// 鸿蒙实况窗实现。
class OhosLiveView implements PlatLiveView {
  const OhosLiveView();

  static const MethodChannel _channel = MethodChannel('xiangjugong/liveview');

  @override
  Future<LiveViewProbe> probe() async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('probe');
      if (raw == null) {
        return const LiveViewProbe(
          supported: false,
          enabled: false,
          message: 'probe 返回空',
        );
      }
      return LiveViewProbe(
        supported: raw['supported'] == true,
        enabled: raw['enabled'] == true,
        code: _intOf(raw['code']),
        message: _strOf(raw['message']),
      );
    } on PlatformException catch (e) {
      return LiveViewProbe(
        supported: false,
        enabled: false,
        code: e.code.hashCode,
        message: '${e.code}: ${e.message ?? ''}',
      );
    } on MissingPluginException catch (e) {
      return LiveViewProbe(
        supported: false,
        enabled: false,
        message: '通道未注册: ${e.message ?? ''}',
      );
    }
  }

  @override
  Future<LiveViewOutcome> start(LiveViewSpec spec) => _invoke('start', spec);

  @override
  Future<LiveViewOutcome> update(LiveViewSpec spec) => _invoke('update', spec);

  @override
  Future<LiveViewOutcome> stop(int id) =>
      _invoke('stop', null, idOverride: id);

  @override
  Future<bool> isActive(int id) async {
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('isActive', <String, Object?>{
            'id': id,
          });
      return raw?['active'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 统一调用 + 结果映射(异常一律降级,不打断业务)。
  /// 嵌套规格以 **JSON 字符串**传递:项目惯例 —— 嵌套 Map 在 ArkTS 侧
  /// 以 interface 断言后属性访问会失效(实测 primary.title 恒为空)。
  Future<LiveViewOutcome> _invoke(
    String method,
    LiveViewSpec? spec, {
    int? idOverride,
  }) async {
    final Map<String, Object?> args = <String, Object?>{
      'id': idOverride ?? spec?.id ?? 0,
      if (spec != null) 'json': jsonEncode(spec.toMap()),
    };
    try {
      final Map<Object?, Object?>? raw = await _channel
          .invokeMethod<Map<Object?, Object?>>(method, args);
      if (raw == null) {
        return const LiveViewOutcome.degraded('原生返回空');
      }
      return LiveViewOutcome(
        ok: raw['ok'] == true,
        resultCode: _intOf(raw['resultCode']),
        message: _strOf(raw['message']),
        degraded: raw['degraded'] == true,
      );
    } on PlatformException catch (e) {
      return LiveViewOutcome(
        ok: false,
        message: '${e.code}: ${e.message ?? ''}',
        degraded: true,
      );
    } on MissingPluginException catch (e) {
      return LiveViewOutcome(
        ok: false,
        message: '通道未注册: ${e.message ?? ''}',
        degraded: true,
      );
    } catch (e) {
      return LiveViewOutcome(ok: false, message: '$e', degraded: true);
    }
  }

  static int _intOf(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static String _strOf(Object? v) => v is String ? v : (v?.toString() ?? '');
}
