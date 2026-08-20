import 'package:flutter/material.dart';

import 'checkered_flag_strip.dart';

class MenuAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MenuAppBar({required this.title, this.actions, super.key});

  static const logoAsset =
      'android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png';

  final Widget title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 6);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: title,
      actions: [
        ...?actions,
        const Padding(
          padding: EdgeInsetsDirectional.only(end: 16),
          child: _MenuLogo(),
        ),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(6),
        child: CheckeredFlagStrip(),
      ),
    );
  }
}

class _MenuLogo extends StatelessWidget {
  const _MenuLogo();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      key: const ValueKey('menu_app_bar_logo'),
      child: ExcludeSemantics(
        child: SizedBox(
          width: 46,
          height: 40,
          child: Image.asset(MenuAppBar.logoAsset, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
