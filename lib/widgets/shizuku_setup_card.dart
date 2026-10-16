import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/shizuku_service.dart';
import '../theme/app_theme.dart';

class ShizukuSetupCard extends StatelessWidget {
  final VoidCallback onRefresh;

  const ShizukuSetupCard({super.key, required this.onRefresh});

  static void showSetupGuide(BuildContext context) {
    final colors = AppColors.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.isDark ? Colors.white24 : Colors.black26,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.terminal_rounded, color: Color(0xFF38BDF8), size: 26),
                const SizedBox(width: 10),
                Text(
                  'How to Setup Shizuku (30s)',
                  style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildStep('1', 'Install Shizuku', 'Download and install Shizuku from Google Play Store or GitHub.', colors),
            _buildStep('2', 'Enable Wireless Debugging', 'Go to Settings > Developer Options > Enable Wireless Debugging.', colors),
            _buildStep('3', 'Pair & Start', 'Open Shizuku > Tap "Pairing" with Wireless Debugging > Tap "Start".', colors),
            _buildStep('4', 'Authorize RecordMi', 'Return here and tap "Connect". Shizuku will grant privileged shell access.', colors),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.shop_two_rounded),
                label: const Text('Open Shizuku on Play Store'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF38BDF8),
                  foregroundColor: const Color(0xFF0F172A),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Navigator.pop(ctx);
                  ShizukuService().openShizukuPlayStore();
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static Widget _buildStep(String num, String title, String desc, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(
              color: Color(0xFF38BDF8),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              num,
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                Text(desc, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shizukuService = ShizukuService();

    return ValueListenableBuilder<bool>(
      valueListenable: shizukuService.isBound,
      builder: (context, bound, _) {
        if (bound) return const SizedBox.shrink();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.08),
                blurRadius: 14,
                offset: const Offset(0, 3),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Shizuku Not Connected',
                          style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          'Required for 2-way call audio capture',
                          style: TextStyle(color: colors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'RecordMi uses Shizuku (UID 2000 shell) to record both caller and receiver audio without rooting your device.',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  // Play Store Download Button
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.shop_two_rounded, size: 16),
                      label: const Text('Get Shizuku', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF38BDF8),
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        shizukuService.openShizukuPlayStore();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Connect / Retry Button
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text('Connect', style: TextStyle(fontSize: 12, color: colors.textPrimary)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        side: BorderSide(color: colors.border),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        HapticFeedback.lightImpact();
                        await shizukuService.initShizuku();
                        onRefresh();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Info / Guide
                  IconButton(
                    icon: Icon(Icons.help_outline_rounded, color: colors.textMuted, size: 20),
                    tooltip: 'Setup Guide',
                    onPressed: () => showSetupGuide(context),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
