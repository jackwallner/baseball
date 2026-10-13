# Instrumentation shares these APIs with the optimized target APK.
-keep,allowoptimization class kotlin.** { *; }
-keep,allowoptimization class kotlinx.coroutines.** { *; }
-keep,allowoptimization class androidx.** { *; }
