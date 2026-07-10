import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

enum AlsamosLogoSize { sm, md, lg, xl }

/// Ported from web `AlsamosLogo.tsx`.
class AlsamosLogo extends StatelessWidget {
  final AlsamosLogoSize size;
  final bool showText;
  const AlsamosLogo({super.key, this.size = AlsamosLogoSize.md, this.showText = true});

  double get _imgSize => switch (size) {
        AlsamosLogoSize.sm => 32,
        AlsamosLogoSize.md => 40,
        AlsamosLogoSize.lg => 56,
        AlsamosLogoSize.xl => 64,
      };

  double get _textSize => switch (size) {
        AlsamosLogoSize.sm => 18,
        AlsamosLogoSize.md => 20,
        AlsamosLogoSize.lg => 24,
        AlsamosLogoSize.xl => 30,
      };

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset(
            'assets/images/alsamos-logo.png',
            width: _imgSize,
            height: _imgSize,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => Container(
              width: _imgSize,
              height: _imgSize,
              decoration: BoxDecoration(
                gradient: AppColors.gradientPrimary,
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: const Text('A', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
        if (showText) ...[
          const SizedBox(width: 10),
          ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [AppColors.alsamosOrangeLight, AppColors.alsamosOrangeDark],
            ).createShader(bounds),
            child: Text(
              'Alsamos',
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: TextStyle(
                fontFamily: 'SpaceGrotesk',
                fontWeight: FontWeight.bold,
                fontSize: _textSize,
                color: Colors.white,
                letterSpacing: -0.5,
                height: 1.0,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
