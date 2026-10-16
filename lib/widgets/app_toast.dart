import 'package:flutter/material.dart';

enum ToastType { info, success, warning, error }

class AppToast {
  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration duration = const Duration(milliseconds: 2400),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    Color accentColor;
    IconData icon;

    switch (type) {
      case ToastType.success:
        accentColor = const Color(0xFF2DD4BF); // Teal accent
        icon = Icons.check_circle_rounded;
        break;
      case ToastType.warning:
        accentColor = const Color(0xFFFBBF24); // Amber
        icon = Icons.warning_amber_rounded;
        break;
      case ToastType.error:
        accentColor = const Color(0xFFF87171); // Red accent
        icon = Icons.error_outline_rounded;
        break;
      case ToastType.info:
        accentColor = const Color(0xFF38BDF8); // Cyan
        icon = Icons.info_outline_rounded;
        break;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 28, left: 24, right: 24),
        padding: EdgeInsets.zero,
        duration: duration,
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xF21E293B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: accentColor.withValues(alpha: 0.45),
              width: 1.2,
            ),
            boxShadow: [
              const BoxShadow(
                color: Color(0x77000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: 0.15),
                blurRadius: 14,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    messenger.hideCurrentSnackBar();
                    onAction();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static void showSuccess(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
    show(context, message, type: ToastType.success, actionLabel: actionLabel, onAction: onAction);
  }

  static void showError(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
    show(context, message, type: ToastType.error, actionLabel: actionLabel, onAction: onAction);
  }

  static void showInfo(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
    show(context, message, type: ToastType.info, actionLabel: actionLabel, onAction: onAction);
  }

  static void showWarning(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
    show(context, message, type: ToastType.warning, actionLabel: actionLabel, onAction: onAction);
  }
}
