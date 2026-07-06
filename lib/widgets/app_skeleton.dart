import 'package:flutter/material.dart';
import 'package:daml/theme/app_colors.dart';

class AppSkeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const AppSkeleton({
    super.key,
    required this.height,
    this.width,
    this.radius = 12,
  });

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final base = dark ? AppColors.GRAY_900 : AppColors.GRAY_100;
        final glow = dark ? AppColors.GRAY_800 : AppColors.GREEN_SOFT;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            color: Color.lerp(base, glow, t),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

class AppPageSkeleton extends StatelessWidget {
  final int cards;
  final EdgeInsets padding;

  const AppPageSkeleton({
    super.key,
    this.cards = 5,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: padding,
      children: [
        const AppSkeleton(height: 24, width: 170, radius: 8),
        const SizedBox(height: 10),
        const AppSkeleton(height: 12, width: 230, radius: 6),
        const SizedBox(height: 22),
        for (int i = 0; i < cards; i++) ...[
          const AppSkeleton(height: 92, radius: 18),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class AppLoadingOverlay extends StatelessWidget {
  final String message;

  const AppLoadingOverlay({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      // ignore: deprecated_member_use
      color: (dark ? Colors.black : Colors.white).withOpacity(0.82),
      child: SafeArea(
        child: Center(
          child: Container(
            width: 290,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: dark ? AppColors.GRAY_800 : AppColors.GRAY_200,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: AppColors.GREEN,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const AppSkeleton(height: 14, width: 210, radius: 7),
                const SizedBox(height: 10),
                const AppSkeleton(height: 14, width: 245, radius: 7),
                const SizedBox(height: 10),
                const AppSkeleton(height: 14, width: 165, radius: 7),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
