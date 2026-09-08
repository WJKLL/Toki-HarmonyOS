// === 文件: lib/core/platform/impl/ohos/file_ops_ohos.dart ===
// 编号：PLAT-01（OH 实现，仅镜像）—— 原生选择器通道 + media 通道存相册。
// 说明：注册制。镜像 main() 启动时注册本实现 → PlatFileOpsRegistry.instance
//   返回 OH 原生（否则默认 file_picker 逻辑，OH 上无实现会抛 UnimplementedError）。
// 通道契约：xiangjugong/picker（pickImage/pickExcel/saveFile，插件侧
//   PhotoViewPicker / DocumentViewPicker）；xiangjugong/media（saveImage 复用，
//   已实现 photoAccessHelper 存系统相册）。
import 'package:flutter/services.dart';

import '../../contract/plat_file_ops.dart';

/// OH 原生文件操作实现。
class OhosFileOps implements PlatFileOps {
  static const MethodChannel _picker = MethodChannel('xiangjugong/picker');
  static const MethodChannel _media = MethodChannel('xiangjugong/media');

  @override
  Future<PlatPickedFile?> pickImage() => _pick('pickImage');

  @override
  Future<PlatPickedFile?> pickExcel() => _pick('pickExcel');

  Future<PlatPickedFile?> _pick(String method) async {
    // 用户取消 → 插件 success(null) → 返回 null。
    final Map<Object?, Object?>? r = await _picker.invokeMapMethod(
      method,
    );
    if (r == null) return null;
    final Object? bytes = r['bytes'];
    final Object? name = r['name'];
    if (bytes is! Uint8List || bytes.isEmpty) return null;
    return PlatPickedFile(
      name: name is String ? name : 'picked_file',
      bytes: bytes,
    );
  }

  @override
  Future<String?> saveFile({
    required String fileName,
    required Uint8List bytes,
  }) async {
    try {
      final Object? saved = await _picker.invokeMethod<Object?>(
        'saveFile',
        <String, Object?>{'fileName': fileName, 'bytes': bytes},
      );
      return saved?.toString();
    } on PlatformException catch (e) {
      return e.code == 'canceled' ? null : (e.message ?? '保存失败');
    }
  }

  @override
  Future<String?> saveImageToGallery({
    required Uint8List bytes,
    required String fileName,
  }) async {
    try {
      final Object? path = await _media.invokeMethod<Object?>(
        'saveImage',
        <String, Object?>{
          'bytes': bytes,
          'fileName': fileName,
        },
      );
      return path is String ? path : fileName;
    } on PlatformException catch (e) {
      return e.message ?? '保存失败';
    }
  }
}
