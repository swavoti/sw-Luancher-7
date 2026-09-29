cat << 'INNER_EOF' > fix_routes.py
import re
with open('android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt', 'r') as f:
    content = f.read()

replacement = """                "openRoute" -> {
                    val route = call.argument<String>("route") ?: "/"
                    val intent = when (route) {
                        "/settings" -> Intent(context, SettingsActivity::class.java)
                        "/wallpaper" -> Intent(context, WallpaperActivity::class.java)
                        "/edit_icons" -> Intent(context, EditIconsActivity::class.java)
                        else -> null
                    }
                    if (intent != null) {
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
                        startActivity(intent)
                    }
                    result.success(null)
                }"""

content = re.sub(r'                "openRoute" -> \{.*?\n                \}', replacement, content, flags=re.DOTALL)
with open('android/app/src/main/kotlin/co/za/launcher3/swavoti/MainActivity.kt', 'w') as f:
    f.write(content)
INNER_EOF
python3 fix_routes.py
