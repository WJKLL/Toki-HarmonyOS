// === 文件: lib/core/platform/impl/ohos/secure_store_ohos.dart ===
// 编号:PLAT-02 OH 敏感值加密存储(HUKS AES-256-GCM,镜像专属)
// 说明:xiangjugong/secure 通道 → 原生 HUKS 加密后偏好持久化(密文不可导出);
//   供 steam_auth_service 等原用 flutter_secure_storage 的调用点替换。
import 'package:flutter/services.dart' show MethodChannel;

/// OH 侧加密存储(全静态三方法;Android/Web 主工程保持 flutter_secure_storage)。
abstract final class OhosSecureStore {
  static const MethodChannel _channel = MethodChannel('xiangjugong/secure');

  /// 读取;未配置/解密失败 → null。
  static Future<String?> read(String key) async {
    try {
      return await _channel.invokeMethod<String>('read', <String, Object?>{
        'key': key,
      });
    } catch (_) {
      return null; // 通道缺失(异常/降级)静默。
    }
  }

  /// 写入(空串等价于清除)。
  static Future<bool> write(String key, String value) async {
    try {
      await _channel.invokeMethod<void>('write', <String, Object?>{
        'key': key,
        'value': value,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 删除。
  static Future<void> delete(String key) async {
    try {
      await _channel.invokeMethod<void>('delete', <String, Object?>{'key': key});
    } catch (_) {}
  }
}
