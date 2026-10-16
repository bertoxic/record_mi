import 'package:flutter/material.dart';
import 'models/app_settings.dart';
import 'screens/main_shell.dart';
import 'screens/onboarding_screen.dart';
import 'services/storage_service.dart';
import 'theme/app_theme.dart';
import 'widgets/micro_recording_pill.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storageService = StorageService();
  await storageService.init();

  runApp(CallRecorderApp(hasCompletedOnboarding: storageService.settings.value.hasCompletedOnboarding));
}

// ============================================================================
// ENTRY POINT FOR THE FLOATING MICRO-POPUP OVERLAY (RUNS IN ISOLATED ENGINE)
// ============================================================================
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MicroRecordingPill(),
  ));
}

// ============================================================================
// MAIN APPLICATION
// ============================================================================
class CallRecorderApp extends StatelessWidget {
  final bool hasCompletedOnboarding;

  const CallRecorderApp({super.key, this.hasCompletedOnboarding = true});

  @override
  Widget build(BuildContext context) {
    final storageService = StorageService();

    return ValueListenableBuilder<AppSettings>(
      valueListenable: storageService.settings,
      builder: (context, settings, _) {
        final themeMode = settings.themeMode == 'light'
            ? ThemeMode.light
            : (settings.themeMode == 'system' ? ThemeMode.system : ThemeMode.dark);

        return MaterialApp(
          title: 'RecordMi Call Recorder',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: themeMode,
          home: hasCompletedOnboarding ? const MainShell() : const OnboardingScreen(),
        );
      },
    );
  }
}
