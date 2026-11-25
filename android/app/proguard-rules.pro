# v1.1.0 — hybrid routing. libzeptun-jni.so calls back into the JVM BY NAME:
#   FindClass("dev/zeptun/Zeptun") + GetStaticMethodID("route",
#   "(II[BI[BILjava/lang/String;)I")
# Nothing in Kotlin calls Zeptun.route(), so R8 (on by default for Flutter
# release builds) removed it and nativeStartRouted returned
# ZEPTUN_ERR_INVALID_ARGUMENT (-1) -> "zeptun-start-failed:rc=-1" on every
# hybrid connect. Keep the whole bridge class verbatim.
-keep class dev.zeptun.Zeptun { *; }
-keep class com.chakcaad.aethone.routing.HybridRouter { *; }
