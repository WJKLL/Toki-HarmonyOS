// lib/core/web/web_page_scale_web.dart
// Web 平台:调用 index.html 注入的 window.tokiSetPageScale —— 把 flutter
//   宿主元素的 CSS 布局尺寸设为 视口/scale 并 transform 放大显示回视口,
//   等价浏览器网页缩放(Flutter 真实重排,无几何裁切/白边/错位)。
import 'dart:js_interop';

@JS('tokiSetPageScale')
external void _tokiSetPageScale(double scale);

void applyWebPageScale(double scale) => _tokiSetPageScale(scale);
