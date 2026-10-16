import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/shizuku_service.dart';
import '../services/storage_service.dart';
import 'main_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  final StorageService _storageService = StorageService();
  final ShizukuService _shizukuService = ShizukuService();

  int _currentPage = 0;
  bool _phonePerm = false;
  bool _micPerm = false;
  bool _overlayPerm = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final phone = await Permission.phone.isGranted;
    final mic = await Permission.microphone.isGranted;
    final overlay = await FlutterOverlayWindow.isPermissionGranted();
    if (mounted) {
      setState(() {
        _phonePerm = phone;
        _micPerm = mic;
        _overlayPerm = overlay;
      });
    }
  }

  Future<void> _completeOnboarding() async {
    HapticFeedback.mediumImpact();
    final current = _storageService.settings.value;
    await _storageService.updateSettings(current.copyWith(hasCompletedOnboarding: true));
    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const MainShell(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      );
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bar with Skip Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.mic_external_on_rounded, color: Color(0xFF38BDF8), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'RecordMi',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  if (_currentPage < 3)
                    TextButton(
                      onPressed: _completeOnboarding,
                      child: const Text('Skip', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    )
                  else
                    const SizedBox(height: 48),
                ],
              ),
            ),

            // Main Page Content
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (idx) => setState(() => _currentPage = idx),
                children: [
                  _buildPage(
                    icon: Icons.phone_in_talk_rounded,
                    iconColor: const Color(0xFF38BDF8),
                    title: 'True Two-Way Call Recording',
                    subtitle: 'Capture both sides of every phone conversation crystal clear. Record both the caller (uplink) and receiver (downlink) simultaneously without hardware distortion.',
                    badge: '2-WAY AUDIO',
                  ),
                  _buildShizukuPage(),
                  _buildPage(
                    icon: Icons.picture_in_picture_alt_rounded,
                    iconColor: Colors.tealAccent,
                    title: 'Interactive Floating Call Pill',
                    subtitle: 'A discreet floating pill automatically glides onto your screen during phone and WhatsApp calls. Easily pause, stop, or boost speakerphone with a single tap.',
                    badge: 'SMART OVERLAY',
                  ),
                  _buildPermissionsPage(),
                ],
              ),
            ),

            // Bottom Navigation & Progress Dots
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Dot Indicators
                  Row(
                    children: List.generate(
                      4,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentPage == index ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentPage == index
                              ? const Color(0xFF38BDF8)
                              : Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),

                  // Next / Get Started Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF38BDF8),
                      foregroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (_currentPage < 3) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeInOutCubic,
                        );
                      } else {
                        _completeOnboarding();
                      }
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _currentPage == 3 ? 'Get Started' : 'Next',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          _currentPage == 3 ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: iconColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              badge,
              style: TextStyle(color: iconColor, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 28),
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E293B),
              border: Border.all(color: iconColor.withValues(alpha: 0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: iconColor.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(icon, size: 52, color: iconColor),
          ),
          const SizedBox(height: 36),
          Text(
            title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildShizukuPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.indigoAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'PRIVILEGED ENGINE',
              style: TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1E293B),
              border: Border.all(color: Colors.indigoAccent.withValues(alpha: 0.4), width: 2),
              boxShadow: [
                BoxShadow(
                  color: Colors.indigoAccent.withValues(alpha: 0.25),
                  blurRadius: 30,
                  spreadRadius: 2,
                )
              ],
            ),
            child: const Icon(Icons.security_rounded, size: 48, color: Colors.indigoAccent),
          ),
          const SizedBox(height: 28),
          const Text(
            'Powered by Shizuku',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'RecordMi leverages Android ADB shell (UID 2000) via Shizuku to record internal call audio without root access.',
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7), height: 1.45),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Direct Play Store Button for Shizuku
          ElevatedButton.icon(
            icon: const Icon(Icons.shop_two_rounded, size: 18),
            label: const Text('Download Shizuku on Play Store'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E293B),
              foregroundColor: const Color(0xFF38BDF8),
              side: const BorderSide(color: Color(0xFF38BDF8)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              HapticFeedback.lightImpact();
              _shizukuService.openShizukuPlayStore();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'Permissions Setup',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            'Grant these standard permissions for seamless automatic recording',
            style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          _buildPermTile(
            icon: Icons.phone_rounded,
            title: 'Phone State & Calls',
            desc: 'Detects incoming, outgoing, and conference calls',
            granted: _phonePerm,
            onRequest: () async {
              await Permission.phone.request();
              await _checkPermissions();
            },
          ),
          const SizedBox(height: 10),

          _buildPermTile(
            icon: Icons.mic_rounded,
            title: 'Microphone Access',
            desc: 'Allows capturing your voice during calls',
            granted: _micPerm,
            onRequest: () async {
              await Permission.microphone.request();
              await _checkPermissions();
            },
          ),
          const SizedBox(height: 10),

          _buildPermTile(
            icon: Icons.picture_in_picture_rounded,
            title: 'Floating UI Overlay',
            desc: 'Displays the call pill overlay while inside phone calls',
            granted: _overlayPerm,
            onRequest: () async {
              await FlutterOverlayWindow.requestPermission();
              await _checkPermissions();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPermTile({
    required IconData icon,
    required String title,
    required String desc,
    required bool granted,
    required VoidCallback onRequest,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: granted ? Colors.tealAccent.withValues(alpha: 0.4) : Colors.white12),
      ),
      child: Row(
        children: [
          Icon(icon, color: granted ? Colors.tealAccent : const Color(0xFF38BDF8), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (granted)
            const Icon(Icons.check_circle_rounded, color: Colors.tealAccent, size: 22)
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: const Color(0xFF0F172A),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onRequest,
              child: const Text('Allow', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
        ],
      ),
    );
  }
}
