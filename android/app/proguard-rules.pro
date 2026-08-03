## Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-dontwarn io.flutter.embedding.**

## Shizuku raw input helper.
## The helper class is loaded by name inside a process Shizuku starts, and the
## AIDL stubs are only referenced across that binder, so R8 sees both as unused.
-keep class me.efesser.flauncher.RawInputService { *; }
-keep interface me.efesser.flauncher.IRawInputService { *; }
-keep class me.efesser.flauncher.IRawInputService$* { *; }
-keep interface me.efesser.flauncher.IRawInputCallback { *; }
-keep class me.efesser.flauncher.IRawInputCallback$* { *; }
-keep class rikka.shizuku.** { *; }
-dontwarn rikka.shizuku.**
