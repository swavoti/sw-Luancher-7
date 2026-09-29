sed -i '/static final Map<String, Uint8List> _iconCache = {};/a \  static String currentIconPack = "";' lib/services/app_database_service.dart

awk '/static Future<Uint8List\?> loadIcon\(String packageName\)/ {
    inLoadIcon = 1;
}
inLoadIcon && /if \(blob == null \|\| blob.isEmpty\) \{/ && !foundBlob {
    print "        if (currentIconPack.isNotEmpty) {"
    print "          try {"
    print "            final themed = await LauncherService.getThemedIcon(packageName, currentIconPack);"
    print "            if (themed != null) blob = themed;"
    print "          } catch (_) {}"
    print "        }"
    print "        if (blob == null || blob.isEmpty) {"
    foundBlob = 1;
    next;
}
{print}' lib/services/app_database_service.dart > temp.dart && mv temp.dart lib/services/app_database_service.dart
