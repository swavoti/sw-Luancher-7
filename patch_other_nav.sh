cat << 'INNER_EOF' > fix_other_nav.py
import re
with open('lib/screens/home_settings.dart', 'r') as f:
    content = f.read()

content = re.sub(r'Navigator.push\(\s*context,\s*MaterialPageRoute\(\s*builder: \(_\) =>\s*const EditIconsPage\(backgroundWallpaperPath: \'\'\),\s*\),\s*\);', 'LauncherService.openRoute(\'/edit_icons\');', content)
with open('lib/screens/home_settings.dart', 'w') as f:
    f.write(content)


with open('lib/screens/wallpaper_page.dart', 'r') as f:
    content2 = f.read()

content2 = re.sub(r'Navigator.push\(\s*context,\s*MaterialPageRoute\(\s*builder: \(_\) => EditIconsPage\([^)]*\),\s*\),\s*\);', 'LauncherService.openRoute(\'/edit_icons\');', content2)
with open('lib/screens/wallpaper_page.dart', 'w') as f:
    f.write(content2)
INNER_EOF
python3 fix_other_nav.py
