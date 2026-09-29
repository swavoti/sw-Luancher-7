cat << 'INNER_EOF' > fix_main_routes.py
import re
with open('lib/main.dart', 'r') as f:
    content = f.read()

# Make sure edit_icons_page, home_settings, wallpaper_page are imported
if 'import \'package:swavoti/screens/edit_icons_page.dart\';' not in content:
    content = content.replace('import \'package:swavoti/screens/workspace.dart\';', 
                              'import \'package:swavoti/screens/workspace.dart\';\nimport \'package:swavoti/screens/edit_icons_page.dart\';\nimport \'package:swavoti/screens/home_settings.dart\';\nimport \'package:swavoti/screens/wallpaper_page.dart\';')

replacement = """        return MaterialApp(
          title: 'Go Launcher 7',
          initialRoute: '/',
          routes: {
            '/': (context) => Workspace(appCache: _appCache),
            '/settings': (context) => const HomeSettings(),
            '/wallpaper': (context) => const WallpaperPage(),
            '/edit_icons': (context) => const EditIconsPage(backgroundWallpaperPath: ''),
          },
          theme: ThemeData("""

content = re.sub(r'        return MaterialApp\(\n          title: \'Go Launcher 7\',\n          theme: ThemeData\(', replacement, content)

# Remove the home: Workspace(appCache: _appCache), line
content = re.sub(r'\n\s*home: Workspace\(appCache: _appCache\),', '', content)

with open('lib/main.dart', 'w') as f:
    f.write(content)
INNER_EOF
python3 fix_main_routes.py
