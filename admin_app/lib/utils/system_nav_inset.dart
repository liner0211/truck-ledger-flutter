/// 底栏尺寸约定。
///
/// Material3 [NavigationBar] 自带底部 SafeArea（系统 inset 自适应）。
/// 不要再手动垫 viewPadding，否则会叠高或把按键压到屏幕底边。
class SystemNavInset {
  SystemNavInset._();

  /// 按键区高度（图标+文字），不含系统底部安全区。
  static const double contentHeight = 64;
}
