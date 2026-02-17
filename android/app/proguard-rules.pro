# Retrofit 3
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation

# kotlinx.serialization
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt
-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.tofustash.app.**$$serializer { *; }
-keepclassmembers class com.tofustash.app.** {
    *** Companion;
}
-keepclasseswithmembers class com.tofustash.app.** {
    kotlinx.serialization.KSerializer serializer(...);
}
