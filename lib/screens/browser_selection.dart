import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:swavoti/services/launcher_service.dart';

class BrowserSelectionScreen extends StatefulWidget {
  const BrowserSelectionScreen({super.key});

  @override
  State<BrowserSelectionScreen> createState() => _BrowserSelectionScreenState();
}

class _BrowserSelectionScreenState extends State<BrowserSelectionScreen> {
  List<Map<String, dynamic>> _browsers = [];
  bool _isLoading = true;
  String? _selectedPackage;

  @override
  void initState() {
    super.initState();
    _loadBrowsers();
  }

  Future<void> _loadBrowsers() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPackage = prefs.getString('search_browser_package');
    final browsers = await LauncherService.getInstalledBrowsers();

    if (mounted) {
      setState(() {
        _browsers = browsers;
        _selectedPackage = savedPackage;
        _isLoading = false;
      });
    }
  }

  Future<void> _selectBrowser(String packageName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('search_browser_package', packageName);
    setState(() => _selectedPackage = packageName);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Default Browser'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _browsers.isEmpty
              ? const Center(child: Text('No browsers found.'))
              : ListView.builder(
                  itemCount: _browsers.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.transparent,
                          child: Icon(Icons.language),
                        ),
                        title: const Text('System Default'),
                        trailing: _selectedPackage == null || _selectedPackage!.isEmpty
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => _selectBrowser(''),
                      );
                    }
                    
                    final browser = _browsers[index - 1];
                    final isSelected = _selectedPackage == browser['packageName'];
                    final iconBytes = browser['icon'] as Uint8List?;

                    return ListTile(
                      leading: iconBytes != null
                          ? Image.memory(iconBytes, width: 40, height: 40)
                          : const Icon(Icons.android, size: 40),
                      title: Text(browser['label'] ?? 'Unknown Browser'),
                      trailing: isSelected ? const Icon(Icons.check) : null,
                      onTap: () => _selectBrowser(browser['packageName']),
                    );
                  },
                ),
    );
  }
}
