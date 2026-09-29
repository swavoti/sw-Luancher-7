import re
with open('lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

# Fix homescreen grid item tap
replacement = """                                              child: GestureDetector(
                                                onTap: () {
                                                  if (item.type == 'app') {
                                                    LauncherService.startApp(item.packageName);
                                                  }
                                                },
                                                onLongPress: () =>
                                                    _showItemContextMenu(item),"""

content = re.sub(r'                                              child: GestureDetector\(\n                                                onLongPress: \(\) =>\n                                                    _showItemContextMenu\(item\),', replacement, content)

with open('lib/screens/home_screen.dart', 'w') as f:
    f.write(content)
