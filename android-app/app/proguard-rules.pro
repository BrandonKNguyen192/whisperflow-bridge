# Whisper Bridge ProGuard rules

# Keep ZXing / JourneyApps
-keep class com.google.zxing.** { *; }
-keep class com.journeyapps.barcodescanner.** { *; }
-dontwarn com.google.zxing.**

# Keep Material Components
-keep class com.google.android.material.** { *; }
-dontwarn com.google.android.material.**

# Keep data classes used by Gson/JSON
-keep class com.whisperbridge.Pairing$Parsed { *; }
-keep class com.whisperbridge.ProfileManager$Profile { *; }
-keep class com.whisperbridge.BridgeClient$Result { *; }

# Keep view binding generated classes
-keep class com.whisperbridge.databinding.** { *; }
