import re
with open('lib/screens/home_screen.dart', 'r') as f:
    content = f.read()

replacement = """    if (_apps.isEmpty) {
      _isLoading = true;
      InstalledApps.getInstalledApps(excludeSystemApps: false, excludeNonLaunchableApps: true, withIcon: false).then((apps) {
        if (!mounted) return;
        apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        setState(() {
          _apps = apps;
          _filteredApps = List.from(_apps);
          _isLoading = false;
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() => _isLoading = false);
      });
    }"""

content = re.sub(r'    if \(_apps\.isEmpty\) \{\n      _isLoading = true;\n      widget\.onFetchApps\(\)\.then\(\(_\) \{\n        if \(!mounted\) return;\n        setState\(\{\n          _apps = List\.from\(widget\.apps\);\n          _filteredApps = List\.from\(_apps\);\n          _isLoading = false;\n        \}\);\n      \}\);\n    \}', replacement, content)

with open('lib/screens/home_screen.dart', 'w') as f:
    f.write(content)
