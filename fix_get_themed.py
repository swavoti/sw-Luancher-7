import re
with open('android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt', 'r') as f:
    content = f.read()

replacement = """                "getThemedIcon" -> {
                    val appPackage = call.argument<String>("appPackage") ?: ""
                    val iconPackPackage = call.argument<String>("iconPackPackage") ?: ""
                    backgroundExecutor.execute {
                        try {
                            val bytes = iconPackManager.getThemedIcon(appPackage, iconPackPackage)
                            Handler(Looper.getMainLooper()).post { result.success(bytes) }
                        } catch (e: Throwable) {
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        }
                    }
                }"""

content = re.sub(r'                "getThemedIcon" -> \{.*?\n                \}', replacement, content, flags=re.DOTALL)

with open('android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt', 'w') as f:
    f.write(content)
