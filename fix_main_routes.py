import re
with open('lib/main.dart', 'r') as f:
    content = f.read()

# Remove the '/' route, use home instead.
content = content.replace("'/': (context) => Workspace(appCache: _appCache),", "")

with open('lib/main.dart', 'w') as f:
    f.write(content)
