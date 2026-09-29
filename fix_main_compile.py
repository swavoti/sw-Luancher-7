import re
with open('lib/main.dart', 'r') as f:
    content = f.read()

content = content.replace("Workspace(appCache: _appCache)", "Workspace(prefs: _prefs ?? SharedPreferencesAsync() as dynamic, appCache: _appCache)")

# I should use the proper `prefs` variable from build method!
# Wait, looking at lines 170 and 200, let's see what is on those lines.
