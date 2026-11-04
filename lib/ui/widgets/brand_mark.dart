/// 品牌标识：直接使用与启动图标同一份设计稿（assets/brand/logo.png）。
library;

import 'package:flutter/material.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 34});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Flutter 网测',
      image: true,
      child: Image.asset(
        'assets/brand/logo.png',
        width: size,
        height: size,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
      ),
    );
  }
}
