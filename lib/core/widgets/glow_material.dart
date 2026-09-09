// === 文件: lib/presentation/widgets/kernel/glow_material.dart ===
// 编号:GLOW-02 光感材质层(2026-09-09 一期:静态光感)
// 说明:在子内容**之上**叠加一层纯 Canvas 光感(彩色柔光 + 边缘层次 + 顶高光线),
//   不改动子内容布局与命中测试。
//
// 深浅两套参数(不可共用):
//   - 深色:白描边(顶亮底暗)+ 顶高光线 + 彩色柔光(BlendMode.plus, alpha ×0.16);
//   - 浅色:上缘白高光 / 下缘淡黑线 + 彩色柔光(BlendMode.srcOver, alpha ×0.07, 光池 2 个);
//     浅底上用 plus 会迅速推向过曝白;而 softLight 虽保色相但属**非分离式**混合,
//     GPU 需读取目标像素并打断批处理 → 平板宽屏多卡片时掉帧,故用分离式的 srcOver;
//     顶高光线在浅底不可见 → 不画。
//
// 形态自适应:
//   - 卡片(宽高比 ≤2.5):三色沿上/右/下三边外侧渗入;
//   - 长条(宽高比 >2.5,如宽屏侧边栏):两色沿**短边两侧**渗入,半径按短边放大,
//     避免长条形上出现被拉伸的色带。
//
// 性能约定(不可违背):
//   1. **零额外模糊 pass** —— 只用 gradient,不用 BackdropFilter / ImageFilter / MaskFilter.blur;
//   2. **静态零重绘** —— shouldRepaint 仅在参数变化时返回 true,不注册任何 Ticker;
//   3. 浅色模式绘制量更小(不画顶光线、alpha 更低);
//   4. 光池强度上限来自 GlowTokens(gentle 档 glowOpacity=0.28),不做叠加放大。
import 'package:flutter/widgets.dart';
import 'package:flutter_miuix/miuix.dart';

import 'glow_tokens.dart';

/// 光感材质层(overlay)。
class GlowMaterial extends StatelessWidget {
  const GlowMaterial({
    super.key,
    required this.child,
    this.level = GlowLevel.gentle,
    this.enabled = true,
    this.radius = 18,
  });

  final Widget child;

  /// 光感档位(默认 gentle;可用 [GlowTokens.adaptive] 按系统减弱动画裁决)。
  final GlowLevel level;

  /// false → 直接透传 child(零绘制)。
  final bool enabled;

  /// 圆角(必须与内层卡片/容器圆角一致,避免描边露角)。
  final double radius;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return child;
    }
    // 深浅判定与 CardShadow / CardDarkGlow 同源(Miuix 实际取色 luminance)。
    final MiuixColors colors = MiuixTheme.of(context).colors;
    final bool dark = colors.surface.computeLuminance() < 0.5;
    return CustomPaint(
      // 用 foregroundPainter:光感需叠在卡片背景**之上**才可见
      // (卡片背景不透明,画在下方会被完全遮住,只剩边缘漏光 → 视觉上像色斑)。
      foregroundPainter: _GlowMaterialPainter(
        tokens: GlowTokens.of(level),
        radius: radius,
        dark: dark,
        // Monet 取色下背景色随壁纸变化,固定三色会显得跳 → 光色向主题表面色靠拢。
        tint: colors.surface,
      ),
      child: child,
    );
  }
}

class _GlowMaterialPainter extends CustomPainter {
  const _GlowMaterialPainter({
    required this.tokens,
    required this.radius,
    required this.dark,
    required this.tint,
  });

  final GlowTokens tokens;
  final double radius;
  final bool dark;

  /// 主题表面色(用于把固定光色向当前主题拉近,降低 Monet 下的突兀感)。
  final Color tint;

  /// 光色与主题表面色的混合比例(0 = 原色,1 = 完全等于表面色)。
  static const double _tintMix = 0.42;

  /// 长条判定阈值(宽高比)。
  static const double _barRatio = 2.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final RRect rr = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    canvas.save();
    canvas.clipRRect(rr);
    _paintGlow(canvas, size);
    _paintEdge(canvas, size, rr);
    if (dark) {
      _paintTopLine(canvas, size);
    }
    canvas.restore();
  }

  // ── 1) 彩色柔光(圆心在容器外侧,只让颜色从边缘向内渗出)──────────
  void _paintGlow(Canvas canvas, Size size) {
    // 再柔化一轮:深色 0.16→0.11、浅色 0.07→0.04(Monet 取色下更含蓄)。
    final double a = tokens.glowOpacity * (dark ? 0.11 : 0.04);
    if (a <= 0.004) {
      return;
    }
    final bool bar =
        size.width / size.height > _barRatio ||
        size.height / size.width > _barRatio;
    final bool vertical = size.height > size.width;
    final double r = bar ? size.shortestSide * 1.5 : size.longestSide * 0.68;
    final List<Offset> anchors = bar
        ? (vertical
              // 纵向长条(宽屏侧边栏):左右两侧渗入。
              ? <Offset>[
                  Offset(-size.width * 0.25, size.height * 0.30),
                  Offset(size.width * 1.25, size.height * 0.70),
                ]
              // 横向长条:上下两侧渗入。
              : <Offset>[
                  Offset(size.width * 0.30, -size.height * 0.25),
                  Offset(size.width * 0.70, size.height * 1.25),
                ])
        // 卡片:上 / 右 / 下三边渗入。
        : <Offset>[
            Offset(size.width * 0.50, -size.height * 0.30),
            Offset(size.width * 1.30, size.height * 0.55),
            Offset(size.width * 0.50, size.height * 1.30),
          ];
    // PERF:混合模式必须是**分离式**的。
    //   深色用 plus(分离式,GPU 直接叠加);
    //   浅色原先用 softLight —— 它是**非分离式**混合,GPU 需读取目标像素、
    //   打断批处理并触发额外离屏合成,平板宽屏多卡片叠加时实测掉帧,
    //   故改为 srcOver(直接叠色,分离式,与默认路径同价)。
    final BlendMode mode = dark ? BlendMode.plus : BlendMode.srcOver;
    // 浅色少画一个光池(2 个)进一步降低光栅化成本;深色保持 3 个。
    final int count = dark
        ? anchors.length
        : (anchors.length > 2 ? 2 : anchors.length);
    for (int i = 0; i < count; i++) {
      final Color raw = GlowTokens.glowColors[i % GlowTokens.glowColors.length];
      // 与主题表面色混合 → 光色随主题/壁纸一起走,Monet 下不再"跳出来"。
      final Color base = Color.lerp(raw, tint, _tintMix)!;
      final Paint p = Paint()
        ..blendMode = mode
        ..shader = RadialGradient(
          colors: <Color>[
            base.withValues(alpha: a),
            base.withValues(alpha: a * 0.35),
            base.withValues(alpha: 0),
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: anchors[i], radius: r));
      canvas.drawCircle(anchors[i], r, p);
    }
  }

  // ── 2) 边缘层次 ─────────────────────────────────────────────
  void _paintEdge(Canvas canvas, Size size, RRect rr) {
    final Paint edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    if (dark) {
      // 深色:白色渐变描边(顶 .9 → 中 .2 → 底 .26,官方参考比例 × 0.46)。
      edge.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: 0.9 * 0.46),
          const Color(0xFFFFFFFF).withValues(alpha: 0.2 * 0.46),
          const Color(0xFFFFFFFF).withValues(alpha: 0.26 * 0.46),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size);
    } else {
      // 浅色:上缘白高光 → 中段透明 → 下缘极淡黑线(内高光 / 外阴影层次)。
      edge.shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          const Color(0xFFFFFFFF).withValues(alpha: 0.55),
          const Color(0x00FFFFFF),
          const Color(0xFF000000).withValues(alpha: 0.06),
        ],
        stops: const <double>[0.0, 0.5, 1.0],
      ).createShader(Offset.zero & size);
    }
    canvas.drawRRect(rr.deflate(0.55), edge);
  }

  // ── 3) 顶高光线(仅深色;浅底白线不可见)──────────────────────
  void _paintTopLine(Canvas canvas, Size size) {
    final double specA = tokens.specularOpacity * 0.7;
    if (specA <= 0.01) {
      return;
    }
    const double inset = 12;
    final Paint topLine = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        colors: <Color>[
          const Color(0x00FFFFFF),
          const Color(0xFFFFFFFF).withValues(alpha: specA),
          const Color(0x00FFFFFF),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 1));
    canvas.drawLine(
      Offset(radius + inset, 0.9),
      Offset(size.width - radius - inset, 0.9),
      topLine,
    );
  }

  @override
  bool shouldRepaint(covariant _GlowMaterialPainter old) =>
      old.tokens != tokens ||
      old.radius != radius ||
      old.dark != dark ||
      old.tint != tint;
}
