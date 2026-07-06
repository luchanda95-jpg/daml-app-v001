import 'package:flutter/material.dart';
import 'package:daml/theme/app_colors.dart';
import 'package:daml/widgets/app_skeleton.dart';

class LogoLoader extends StatelessWidget {
  final String message;
  final double logoSize;

  const LogoLoader({
    super.key,
    required this.message,
    this.logoSize = 72,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/logo.png',
              width: logoSize,
              height: logoSize,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.GREEN,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Flexible(
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const AppSkeleton(height: 13, width: 220, radius: 7),
            const SizedBox(height: 10),
            const AppSkeleton(height: 13, width: 175, radius: 7),
            const SizedBox(height: 10),
            const AppSkeleton(height: 13, width: 120, radius: 7),
          ],
        ),
      ),
    );
  }
}
