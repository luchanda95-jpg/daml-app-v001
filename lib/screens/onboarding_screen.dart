// lib/screens/onboarding_screen.dart
// Monochrome (black / white / grey) onboarding for the Direct Access loan app.
// - Strict B&W palette: solid black CTA, black active dot, greyscale art
// - Uses illustration images when present, with a clean greyscale fallback so it
//   looks good right now (even before you add real artwork).
//
// ADDING REAL ILLUSTRATIONS (free, keep them monochrome):
//   1. Go to https://undraw.co
//   2. Set the brand colour to  111111  (near-black) so they match this theme
//   3. Search e.g. "savings", "calculator", "team" / "buildings"
//   4. Save PNGs to:
//        assets/onboarding/manage_loans.png
//        assets/onboarding/calculator.png
//        assets/onboarding/branch_tools.png
//   5. In pubspec.yaml under  flutter: -> assets:  add:
//        - assets/onboarding/
//   Missing files automatically show the greyscale icon fallback.

// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Monochrome palette (kept local so this screen is self-contained)
const Color _kInk = Color(0xFF0F0F0F); // near-black: titles, button, active dot
const Color _kBody = Color(0xFF6B7280); // grey: body text, skip
const Color _kMuted = Color(0xFFD4D4D4); // light grey: inactive dots
const Color _kArtOuter = Color(0xFFF1F1F1); // fallback art outer ring
const Color _kArtInner = Color(0xFFE4E4E4); // fallback art inner circle

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, this.onFinish});

  final VoidCallback? onFinish;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _currentIndex = 0;

  late final List<_OnboardingItem> _items;

  @override
  void initState() {
    super.initState();
    _items = const [
      _OnboardingItem(
        image: 'assets/onboarding/manage_loans.png',
        fallbackIcon: Icons.account_balance_wallet_rounded,
        title: 'Manage your loans',
        subtitle:
            'See credit amounts, due dates and outstanding balances — all in one place.',
      ),
      _OnboardingItem(
        image: 'assets/onboarding/calculator.png',
        fallbackIcon: Icons.calculate_rounded,
        title: 'Quick loan calculator',
        subtitle:
            'Estimate payments and plan ahead with a fast, easy calculator.',
      ),
      _OnboardingItem(
        image: 'assets/onboarding/branch_tools.png',
        fallbackIcon: Icons.apartment_rounded,
        title: 'Branch & admin tools',
        subtitle:
            'Branches send reports while admins manage branches and users with ease.',
      ),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _isLast => _currentIndex == _items.length - 1;

  void _skipToLast() {
    _controller.animateToPage(
      _items.length - 1,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('seenOnboarding', true);
    if (!mounted) return;
    if (widget.onFinish != null) {
      widget.onFinish!();
    } else {
      Navigator.of(context).pushReplacementNamed('/signin');
    }
  }

  void _nextOrFinish() {
    if (!_isLast) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOut,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Header: logo + Skip
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
              child: Row(
                children: [
                  Image.asset(
                    'assets/logo.png',
                    height: 28,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Text(
                      'Direct Access',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: _kInk,
                      ),
                    ),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: _isLast ? 0 : 1,
                    duration: const Duration(milliseconds: 250),
                    child: TextButton(
                      onPressed: _isLast ? null : _skipToLast,
                      style: TextButton.styleFrom(foregroundColor: _kBody),
                      child: const Text('Skip'),
                    ),
                  ),
                ],
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _items.length,
                onPageChanged: (i) => setState(() => _currentIndex = i),
                itemBuilder: (context, index) =>
                    _OnboardingPage(item: _items[index]),
              ),
            ),

            // Page indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_items.length, (index) {
                final active = _currentIndex == index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? _kInk : _kMuted,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),

            const SizedBox(height: 28),

            // CTA button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kInk,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _nextOrFinish,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _isLast ? 'Get Started' : 'Next',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        _isLast
                            ? Icons.check_rounded
                            : Icons.arrow_forward_rounded,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _OnboardingItem {
  final String image;
  final IconData fallbackIcon;
  final String title;
  final String subtitle;

  const _OnboardingItem({
    required this.image,
    required this.fallbackIcon,
    required this.title,
    required this.subtitle,
  });
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingItem item;
  const _OnboardingPage({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        children: [
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset(
                item.image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _FallbackArt(item: item),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              children: [
                Text(
                  item.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  item.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _kBody,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Greyscale placeholder shown until a real illustration is added.
class _FallbackArt extends StatelessWidget {
  final _OnboardingItem item;
  const _FallbackArt({required this.item});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: LayoutBuilder(
          builder: (context, c) {
            final s = c.biggest.shortestSide;
            return Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: s,
                  height: s,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kArtOuter,
                  ),
                ),
                Container(
                  width: s * 0.68,
                  height: s * 0.68,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _kArtInner,
                  ),
                ),
                Icon(item.fallbackIcon, size: s * 0.30, color: _kInk),
                Positioned(
                  top: s * 0.12,
                  right: s * 0.16,
                  child: _dot(s * 0.09, _kInk),
                ),
                Positioned(
                  bottom: s * 0.16,
                  left: s * 0.12,
                  child: _dot(s * 0.06, _kMuted),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _dot(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}
