// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

class LogoLoader extends StatefulWidget {
  final String message;
  final double logoSize;

  const LogoLoader({
    super.key,
    required this.message,
    this.logoSize = 80, // Slightly larger, but feels smaller without the box
  });

  @override
  State<LogoLoader> createState() => _LogoLoaderState();
}

class _LogoLoaderState extends State<LogoLoader> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // The Logo - Clean, no container
              Image.asset(
                "assets/logo.png",
                width: widget.logoSize,
                height: widget.logoSize,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 48), // Large breathy whitespace
              
              // Google-style Linear Progress
              SizedBox(
                width: 140,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: LinearProgressIndicator(
                        backgroundColor: cs.primary.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                        minHeight: 3, // Very thin and modern
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      widget.message.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}