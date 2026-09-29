import re
with open('lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

# Replace settings navigation
content = re.sub(r'Navigator.push\(\s*context,\s*MaterialPageRoute\(builder: \(_\) => HomeSettings\([^)]*\)\),\s*\);', 'LauncherService.openRoute(\'/settings\');', content)
# Replace wallpaper navigation
content = re.sub(r'Navigator.push\(\s*context,\s*MaterialPageRoute\(\s*builder: \(_\) => const WallpaperPage\(\),\s*\),\s*\);', 'LauncherService.openRoute(\'/wallpaper\');', content)

with open('lib/screens/home_screen.dart', 'w') as f:
    f.write(content)
