// lib/core/tools/steam_auth_service.dart
// 编号：P-08 Steam 用户查询 · 凭证存储服务（v1.34.0 新增）
// 说明：UAPI 访问凭证(key)的本机存储 —— 决策记录:v1.34.0 新增
//   flutter_secure_storage(Android Keystore 加密;唯一新增第三方依赖)。
//   - Android/桌面:FlutterSecureStorage(加密持久化,明文不可导出);
//   - Web:降级 shared_preferences(localStorage —— WebCrypto 方案受
//     部署环境限制,浏览器明文容器,注明仅匿名可用的建议);
//   - OH(DSH):HUKS 加密存储(OhosSecureStore;flutter_secure_storage 无
//     OH 实现,主版插件在 OH 上不可用 —— 镜像专属分支);
//   - 接口抽象:查询页/设置页只依赖 [SteamAuthService],单测可替换。
//   安全:key 只进内存/加密存储,绝不写入日志与普通设置(S-02)。
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../platform/impl/ohos/secure_store_ohos.dart';
import '../utils/u04_platform_utils.dart';

/// 凭证存储接口(读/写/清)。
abstract interface class SteamAuthService {
  /// 读取已保存的 UAPI key;未配置 → null。
  Future<String?> readApiKey();

  /// 保存 key(空串/纯空白 → 视为清除)。
  Future<void> saveApiKey(String key);

  /// 清除已保存的 key。
  Future<void> clearApiKey();
}

/// 平台工厂:Web 走 localStorage 降级;OH 走 HUKS;其余走加密存储。
SteamAuthService createSteamAuthService() {
  if (kIsWeb) return const WebSteamAuthService();
  if (U04PlatformUtils.isOhos) return const OhosSteamAuthService();
  return const SecureSteamAuthService();
}

/// OH 实现:HUKS AES-256-GCM 加密后经通道持久化(密文不可导出)。
class OhosSteamAuthService implements SteamAuthService {
  const OhosSteamAuthService();

  static const String _kKey = 'steam_api_key';

  @override
  Future<String?> readApiKey() async {
    final String? v = await OhosSecureStore.read(_kKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  @override
  Future<void> saveApiKey(String key) async {
    final String k = key.trim();
    if (k.isEmpty) {
      await OhosSecureStore.delete(_kKey);
    } else {
      await OhosSecureStore.write(_kKey, k);
    }
  }

  @override
  Future<void> clearApiKey() => OhosSecureStore.delete(_kKey);
}

/// Android/桌面实现:FlutterSecureStorage(Keystore 加密)。
class SecureSteamAuthService implements SteamAuthService {
  const SecureSteamAuthService();

  static const String _kKey = 'steam_api_key';
  // v11:AndroidOptions 不再需要 encryptedSharedPreferences(默认加密)。
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<String?> readApiKey() => _storage.read(key: _kKey);

  @override
  Future<void> saveApiKey(String key) async {
    final String k = key.trim();
    if (k.isEmpty) {
      await _storage.delete(key: _kKey);
    } else {
      await _storage.write(key: _kKey, value: k);
    }
  }

  @override
  Future<void> clearApiKey() => _storage.delete(key: _kKey);
}

/// Web 降级实现(shared_preferences;注释见文件头)。
class WebSteamAuthService implements SteamAuthService {
  const WebSteamAuthService();

  static const String _kKey = 'settings.steamApiKey';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> readApiKey() async {
    final SharedPreferences prefs = await _prefs;
    final String? v = prefs.getString(_kKey);
    return (v == null || v.isEmpty) ? null : v;
  }

  @override
  Future<void> saveApiKey(String key) async {
    final SharedPreferences prefs = await _prefs;
    final String k = key.trim();
    if (k.isEmpty) {
      await prefs.remove(_kKey);
    } else {
      await prefs.setString(_kKey, k);
    }
  }

  @override
  Future<void> clearApiKey() async {
    final SharedPreferences prefs = await _prefs;
    await prefs.remove(_kKey);
  }
}
