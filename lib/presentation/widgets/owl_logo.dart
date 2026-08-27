import 'package:flutter/material.dart';

/// vex owl 的猫头鹰 logo 组件。
///
/// 资源: assets/logo/logo.png
/// 该图为用户提供,纯黑/白配色,几何风格,辨识度高。
///
/// 用法:
/// - 大尺寸(启动页主 logo):[OwlLogo.large]
/// - 中尺寸(列表/空状态):[OwlLogo.medium]
/// - 小尺寸(导航栏/AppBar):[OwlLogo.small]
/// - 主题色自适应:由 [color] 决定主色,默认跟随主题
class OwlLogo extends StatelessWidget {
  final double size;

  /// 主题色叠加(通过 [ColorFiltered] 实现),传入 null 表示保留原图色。
  final Color? color;

  const OwlLogo({
    super.key,
    this.size = 48,
    this.color,
  });

  /// 启动页用大 logo(96px)。
  const OwlLogo.large({super.key}) : size = 96, color = null;

  /// 中等尺寸(48px),用于卡片/列表。
  const OwlLogo.medium({super.key}) : size = 48, color = null;

  /// 小尺寸(24px),用于 AppBar leading 等。
  const OwlLogo.small({super.key}) : size = 24, color = null;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/logo/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
    );

    // 透明 PNG 直接显示即可,不需要 ColorFiltered
    return SizedBox(
      width: size,
      height: size,
      child: image,
    );
  }
}
