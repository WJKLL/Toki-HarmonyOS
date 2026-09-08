// lib/core/web/web_page_scale.dart
// v1.49.1:Web「页面缩放」跨平台出口。
//   Web 实现调用 index.html 注入的 tokiSetPageScale(布局级 CSS 缩放);
//   其它平台(Android 等)走空实现 stub —— 页面缩放仅 Web 生效。
export 'web_page_scale_stub.dart'
    if (dart.library.js_interop) 'web_page_scale_web.dart';
