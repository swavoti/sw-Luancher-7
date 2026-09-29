import re
with open('lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

content = re.sub(r'Navigator\.push\(\s*context,\s*MaterialPageRoute\(builder: \(_\) => HomeSettings\([\s\S]*?\)\),\s*\)\.then\(\(_\) async \{', 'LauncherService.openRoute(\'/settings\');\n                      Future.value().then((_) async {', content)

content = re.sub(r'Navigator\.push\(\s*context,\s*MaterialPageRoute\(\s*builder: \(_\) => const WallpaperPage\(\),\s*\),\s*\);', 'LauncherService.openRoute(\'/wallpaper\');', content)

with open('lib/screens/home_screen.dart', 'w') as f:
    f.write(content)
