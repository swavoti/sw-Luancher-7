import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  try {
    print('Fetching location...');
    final locationRes = await http.get(Uri.parse('https://ipinfo.io/json'));
    print('Location status: ${locationRes.statusCode}');
    print('Location body: ${locationRes.body}');
  } catch (e) {
    print('Error: $e');
  }
}
