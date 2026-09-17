/// Owl 设计系统 - 间距 & 尺寸规范
///
/// 基于 8px 基础网格，所有间距必须为 8 的倍数
abstract final class AppSpacing {
  // ── 基础间距（8px 网格） ──
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double base = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;

  // ── 页面级间距 ──
  /// 页面左右边距
  static const double pageHorizontal = 16;
  /// 页面顶部安全区 + 导航栏
  static const double pageTop = 16;
  /// 页面底部安全区 + 导航栏
  static const double pageBottom = 16;

  // ── 组件级间距 ──
  /// 卡片内边距
  static const double cardPadding = 16;
  /// 列表项上下间距
  static const double listItemSpacing = 12;
  /// 分区标题与内容间距
  static const double sectionGap = 16;
  /// 按钮与输入框间距
  static const double buttonInputGap = 16;
  /// 消息气泡与页面边缘间距
  static const double messagePadding = 8;

  // ── 圆角 ──
  /// 小圆角（按钮、Chip）
  static const double radiusSm = 8;
  /// 中圆角（卡片、输入框）
  static const double radiusMd = 12;
  /// 大圆角（气泡、弹窗）
  static const double radiusLg = 16;
  /// 全圆角（头像、FAB）
  static const double radiusFull = 999;

  // ── 组件尺寸 ──
  /// 图标尺寸 - Material Icons outlined 24x24
  static const double iconSize = 24;
  /// 小图标尺寸
  static const double iconSizeSm = 20;
  /// 大图标尺寸
  static const double iconSizeLg = 32;
  /// 底部导航栏高度
  static const double bottomNavBarHeight = 64;
  /// 顶部导航栏高度
  static const double topNavBarHeight = 56;
  /// 输入框最小高度
  static const double inputMinHeight = 48;
  /// 浮动按钮尺寸
  static const double fabSize = 56;
  /// 小浮动按钮尺寸
  static const double fabSizeSmall = 40;

  // ── 动效时长（毫秒） ──
  /// 快速点击反馈
  static const int durationFast = 100;
  /// 页面切换
  static const int durationNormal = 200;
  /// 页面过渡
  static const int durationSlow = 300;
}
