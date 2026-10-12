import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The DogPack mark from `devdogsuga_sdk`, in the theme's primary colour.
/// Declared as an asset in `pubspec.yaml`.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 72});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'packages/devdogsuga_sdk/assets/brand/dogpack.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.primary,
        BlendMode.srcIn,
      ),
      semanticsLabel: 'DogPack',
    );
  }
}
