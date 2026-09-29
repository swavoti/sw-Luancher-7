cat << 'INNER_EOF' > fix_observer.py
import re
with open('lib/main.dart', 'r') as f:
    content = f.read()

# Add didChangeAppLifecycleState
lifecycle_method = """  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final savedPack = prefs.getString('icon_pack') ?? '';
      if (AppDatabaseService.currentIconPack != savedPack) {
        AppDatabaseService.currentIconPack = savedPack;
        await AppDatabaseService.clearIconCache();
        setState(() {});
      }
    }
  }

"""

if 'didChangeAppLifecycleState' not in content:
    content = content.replace('  void _startRamChecker() {', lifecycle_method + '  void _startRamChecker() {')

with open('lib/main.dart', 'w') as f:
    f.write(content)
INNER_EOF
python3 fix_observer.py
