awk '/"getAvailableIconPacks" -> \{/ {
    print "                \"openRoute\" -> {"
    print "                    val route = call.argument<String>(\"route\") ?: \"/\""
    print "                    val title = call.argument<String>(\"title\") ?: \"Settings\""
    print "                    val intent = io.flutter.embedding.android.FlutterActivity"
    print "                        .withNewEngine()"
    print "                        .initialRoute(route)"
    print "                        .build(context)"
    print "                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)"
    print "                    startActivity(intent)"
    print "                    result.success(null)"
    print "                }"
}
{print}' android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt > temp.kt && mv temp.kt android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt
