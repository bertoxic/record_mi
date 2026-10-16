# Shizuku API and Provider
-keep class rikka.shizuku.** { *; }
-keep interface rikka.shizuku.** { *; }
-keep class moe.shizuku.** { *; }
-keep interface moe.shizuku.** { *; }
-keep class dev.rikka.shizuku.** { *; }
-keep interface dev.rikka.shizuku.** { *; }
-keep class moe.shizuku.api.BinderContainer { *; }

# Preserve class and method names across APK builds to ensure AIDL reflection works seamlessly
-dontobfuscate
-dontoptimize
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod, SourceFile, LineNumberTable

# AIDL and Privileged UserService (instantiated by Shizuku via reflection)
-keep class * implements android.os.IInterface { *; }
-keep class *.I*$Stub { *; }
-keep class *.I*$Stub$Proxy { *; }
-keep class com.example.record_mi.** { *; }
-keepclassmembers class com.example.record_mi.** { *; }

# Hidden API reflection classes
-keep class org.lsposed.hiddenapibypass.** { *; }
-dontwarn org.lsposed.hiddenapibypass.**
-keep class android.media.audiopolicy.** { *; }
-keep class android.media.AudioSystem { *; }
-keep class android.app.ActivityThread { *; }
-keep class android.app.ActivityThread$* { *; }

# Flutter Overlays and Plugins
-keep class flutter.overlay.window.flutter_overlay_window.** { *; }
