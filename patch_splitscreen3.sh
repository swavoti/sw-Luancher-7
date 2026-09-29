sed -i '/if (_apps.isEmpty) {/,/    }/c\
    if (_apps.isEmpty) {\
      _isLoading = true;\
      InstalledApps.getInstalledApps(excludeSystemApps: false, excludeNonLaunchableApps: true, withIcon: false).then((apps) {\
        if (!mounted) return;\
        apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));\
        setState(() {\
          _apps = apps;\
          _filteredApps = List.from(_apps);\
          _isLoading = false;\
        });\
      }).catchError((_) {\
        if (!mounted) return;\
        setState(() => _isLoading = false);\
      });\
    }' lib/screens/home_screen.dart
