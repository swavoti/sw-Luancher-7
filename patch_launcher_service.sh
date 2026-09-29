awk '/static Future<void> shareApp/ {
    print "  static Future<void> openRoute(String route) async {"
    print "    try {"
    print "      await _systemChannel.invokeMethod('\''openRoute'\'', {"
    print "        '\''route'\'': route,"
    print "      });"
    print "    } catch (e) {"
    print "      print('\''Error opening route: $e'\'');"
    print "    }"
    print "  }"
    print ""
}
{print}' lib/services/launcher_service.dart > temp.dart && mv temp.dart lib/services/launcher_service.dart
