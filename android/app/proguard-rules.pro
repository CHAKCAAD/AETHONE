# v1.1.0 — hybrid routing. libzeptun-jni.so calls back into the JVM BY NAME:
#   FindClass("dev/zeptun/Zeptun") + GetStaticMethodID("route",
#   "(II[BI[BILjava/lang/String;)I")
# Nothing in Kotlin calls Zeptun.route(), so R8 (on by default for Flutter
# release builds) removed it and nativeStartRouted returned
# ZEPTUN_ERR_INVALID_ARGUMENT (-1) -> "zeptun-start-failed:rc=-1" on every
# hybrid connect. Keep the whole bridge class verbatim.
-keep class dev.zeptun.Zeptun { *; }
-keep class com.chakcaad.aethone.routing.HybridRouter { *; }
# Family Shield (phase 1): libzeptun-jni also resolves BY NAME
#   routeShield (II[BI[BILjava/lang/String;I)I   — route callback + shield verdict
#   revalidate  (II[BI[BILjava/lang/String;I)I   — zeptun_revalidate_flows answer
# and RegisterNatives binds nativeShieldSnapshot / nativeShieldValidate /
# nativeRevalidateFlows / nativeShieldCounter on dev.zeptun.Zeptun (a missing
# native makes the WHOLE RegisterNatives call fail). The keep rule above
# covers the whole class; the targets of the callbacks are kept explicitly
# too so R8 can never inline them away. The CI dexdump gate checks all of it.
-keep class com.chakcaad.aethone.shield.FamilyShield { *; }
