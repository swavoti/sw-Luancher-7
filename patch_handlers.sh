awk '/"uninstallApp" -> \{/ {
    print "                \"getAvailableIconPacks\" -> {"
    print "                    backgroundExecutor.execute {"
    print "                        val packs = iconPackManager.getAvailableIconPacks()"
    print "                        Handler(Looper.getMainLooper()).post { result.success(packs) }"
    print "                    }"
    print "                }"
    print "                \"getThemedIcon\" -> {"
    print "                    val appPackage = call.argument<String>(\"appPackage\") ?: \"\""
    print "                    val iconPackPackage = call.argument<String>(\"iconPackPackage\") ?: \"\""
    print "                    backgroundExecutor.execute {"
    print "                        val bytes = iconPackManager.getThemedIcon(appPackage, iconPackPackage)"
    print "                        Handler(Looper.getMainLooper()).post { result.success(bytes) }"
    print "                    }"
    print "                }"
}
{print}' android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt > temp.kt && mv temp.kt android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt
