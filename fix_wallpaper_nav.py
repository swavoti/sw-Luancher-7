import re
with open('lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

content = re.sub(r'Navigator\.push\(\s*context,\s*MaterialPageRoute\(\s*builder: \(_\) =>\s*const WallpaperPage\(homeScreenScreenshot: null\),\s*\),\s*\);', 'LauncherService.openRoute(\'/wallpaper\');', content)

with open('lib/screens/home_screen.dart', 'w') as f:
    f.write(content)
