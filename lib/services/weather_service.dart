import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WeatherData {
  final double temperature;
  final int weatherCode;

  WeatherData({required this.temperature, required this.weatherCode});
}

class HourlyForecast {
  final DateTime time;
  final double temperature;
  final int weatherCode;
  final double precipitationProbability;

  HourlyForecast({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.precipitationProbability,
  });
}

class DailyForecast {
  final DateTime date;
  final double tempMax;
  final double tempMin;
  final int weatherCode;
  final double precipitationProbabilityMax;

  DailyForecast({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.weatherCode,
    required this.precipitationProbabilityMax,
  });
}

class FullWeatherData {
  final double currentTemperature;
  final int currentWeatherCode;
  final double feelsLikeTemperature;
  final int relativeHumidity;
  final double uvIndex;
  final double windSpeed;
  final int windDirection;
  final double windGusts;
  final double pressure;
  final double visibility;
  final DateTime updatedAt;
  final String locationName;
  final String country;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;

  FullWeatherData({
    required this.currentTemperature,
    required this.currentWeatherCode,
    required this.feelsLikeTemperature,
    required this.relativeHumidity,
    required this.uvIndex,
    required this.windSpeed,
    required this.windDirection,
    required this.windGusts,
    required this.pressure,
    required this.visibility,
    required this.updatedAt,
    required this.locationName,
    required this.country,
    required this.hourly,
    required this.daily,
  });
}

class WeatherService {
  static const _ipApiUrl = 'https://ipinfo.io/json';
  static const _weatherApiUrl = 'https://api.open-meteo.com/v1/forecast';
  static const _geocodingApiUrl =
      'https://geocoding-api.open-meteo.com/v1/search';

  /// Light fetch — current weather only (used by home screen widget).
  static Future<WeatherData?> getCurrentWeather() async {
    try {
      final loc = await _getLocation();
      if (loc == null) return null;

      final weatherUrl = Uri.parse(
        '$_weatherApiUrl'
        '?latitude=${loc.$1}'
        '&longitude=${loc.$2}'
        '&current_weather=true',
      );
      final res = await http.get(weatherUrl);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);
      final current = data['current_weather'];
      return WeatherData(
        temperature: (current['temperature'] as num).toDouble(),
        weatherCode: (current['weathercode'] as num).toInt(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Full fetch — current + hourly (next 24 h) + 7-day daily + location name.
  static Future<FullWeatherData?> getFullWeather({String? city}) async {
    try {
      late final double latitude;
      late final double longitude;
      late final String cityName;
      late final String country;

      if (city != null) {
        final trimmedCity = city.trim();
        if (trimmedCity.isEmpty) return null;
        final geocodingUri = Uri.parse(_geocodingApiUrl).replace(
          queryParameters: {
            'name': trimmedCity,
            'count': '1',
            'language': 'en',
            'format': 'json',
          },
        );
        final geocodingRes = await http.get(geocodingUri);
        if (geocodingRes.statusCode != 200) return null;

        final results =
            (jsonDecode(geocodingRes.body) as Map<String, dynamic>)['results']
                as List<dynamic>?;
        if (results == null || results.isEmpty) return null;
        final location = results.first as Map<String, dynamic>;
        latitude = (location['latitude'] as num).toDouble();
        longitude = (location['longitude'] as num).toDouble();
        cityName = location['name'] as String? ?? trimmedCity;
        country = location['country'] as String? ?? '';
      } else {
        final details = await _resolveLocationDetails();
        if (details == null) return null;
        latitude = details.$1;
        longitude = details.$2;
        cityName = details.$3;
        country = details.$4;
      }

      final weatherUrl = Uri.parse(
        '$_weatherApiUrl'
        '?latitude=$latitude'
        '&longitude=$longitude'
        '&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index,visibility'
        '&hourly=temperature_2m,precipitation_probability,weather_code'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=auto'
        '&forecast_days=7',
      );

      final res = await http.get(weatherUrl);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);

      // Current
      final current = data['current'] as Map<String, dynamic>;
      double currentValue(String key) =>
          (current[key] as num?)?.toDouble() ?? 0;
      int currentInt(String key) => (current[key] as num?)?.toInt() ?? 0;
      final currentTemp = currentValue('temperature_2m');
      final currentCode = currentInt('weather_code');
      final windSpeed = currentValue('wind_speed_10m');
      final windDirection = currentInt('wind_direction_10m');
      final windGusts = currentValue('wind_gusts_10m');
      final updatedAt =
          DateTime.tryParse(current['time'] as String? ?? '') ?? DateTime.now();

      // Hourly — next 24 entries from now
      final hourlyTimes = List<String>.from(data['hourly']['time']);
      final hourlyTemps = List<num>.from(data['hourly']['temperature_2m']);
      final hourlyPrecip = List<num>.from(
        data['hourly']['precipitation_probability'],
      );
      final hourlyCodes = List<num>.from(data['hourly']['weather_code']);

      final now = DateTime.now();
      final List<HourlyForecast> hourlyForecasts = [];
      for (int i = 0; i < hourlyTimes.length; i++) {
        final t = DateTime.tryParse(hourlyTimes[i]);
        if (t == null) continue;
        if (t.isBefore(now)) continue;
        hourlyForecasts.add(
          HourlyForecast(
            time: t,
            temperature: hourlyTemps[i].toDouble(),
            weatherCode: hourlyCodes[i].toInt(),
            precipitationProbability: hourlyPrecip[i].toDouble(),
          ),
        );
        if (hourlyForecasts.length >= 24) break;
      }

      // Daily — 7 days
      final dailyDates = List<String>.from(data['daily']['time']);
      final dailyMax = List<num>.from(data['daily']['temperature_2m_max']);
      final dailyMin = List<num>.from(data['daily']['temperature_2m_min']);
      final dailyCodes = List<num>.from(data['daily']['weather_code']);
      final dailyPrecip = List<num>.from(
        data['daily']['precipitation_probability_max'],
      );

      final List<DailyForecast> dailyForecasts = [];
      for (int i = 0; i < dailyDates.length; i++) {
        final d = DateTime.tryParse(dailyDates[i]);
        if (d == null) continue;
        dailyForecasts.add(
          DailyForecast(
            date: d,
            tempMax: dailyMax[i].toDouble(),
            tempMin: dailyMin[i].toDouble(),
            weatherCode: dailyCodes[i].toInt(),
            precipitationProbabilityMax: dailyPrecip[i].toDouble(),
          ),
        );
      }

      return FullWeatherData(
        currentTemperature: currentTemp,
        currentWeatherCode: currentCode,
        feelsLikeTemperature: currentValue('apparent_temperature'),
        relativeHumidity: currentInt('relative_humidity_2m'),
        uvIndex: currentValue('uv_index'),
        windSpeed: windSpeed,
        windDirection: windDirection,
        windGusts: windGusts,
        pressure: currentValue('pressure_msl'),
        visibility: currentValue('visibility'),
        updatedAt: updatedAt,
        locationName: cityName,
        country: country,
        hourly: hourlyForecasts,
        daily: dailyForecasts,
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> _cacheLocation(double lat, double lon, String city, String country) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('cached_weather_lat', lat);
      await prefs.setDouble('cached_weather_lon', lon);
      await prefs.setString('cached_weather_city', city);
      await prefs.setString('cached_weather_country', country);
    } catch (_) {}
  }

  static Future<(double, double, String, String)?> _getCachedLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('cached_weather_lat');
      final lon = prefs.getDouble('cached_weather_lon');
      final city = prefs.getString('cached_weather_city') ?? '';
      final country = prefs.getString('cached_weather_country') ?? '';
      if (lat != null && lon != null) {
        return (lat, lon, city, country);
      }
    } catch (_) {}
    return null;
  }

  static Future<(double, double, String, String)?> _resolveLocationDetails() async {
    // 1. Try ipinfo.io
    try {
      final res = await http.get(Uri.parse(_ipApiUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final loc = data['loc'] as String?;
        if (loc != null && loc.contains(',')) {
          final parts = loc.split(',');
          final lat = double.tryParse(parts[0]);
          final lon = double.tryParse(parts[1]);
          if (lat != null && lon != null) {
            final city = data['city'] as String? ?? '';
            final country = data['country'] as String? ?? '';
            unawaited(_cacheLocation(lat, lon, city, country));
            return (lat, lon, city, country);
          }
        }
      }
    } catch (_) {}

    // 2. Try freeipapi.com fallback
    try {
      final res = await http.get(Uri.parse('https://freeipapi.com/api/json')).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final lat = (data['latitude'] as num?)?.toDouble();
        final lon = (data['longitude'] as num?)?.toDouble();
        if (lat != null && lon != null) {
          final city = data['cityName'] as String? ?? '';
          final country = data['countryName'] as String? ?? '';
          unawaited(_cacheLocation(lat, lon, city, country));
          return (lat, lon, city, country);
        }
      }
    } catch (_) {}

    // 3. Try cached location from SharedPreferences
    final cached = await _getCachedLocation();
    if (cached != null) return cached;

    // 4. Fallback defaults to South Africa (Johannesburg: -26.2041, 28.0473)
    return (-26.2041, 28.0473, 'Johannesburg', 'South Africa');
  }

  /// Cached coords helper.
  static Future<(double, double)?> _getLocation() async {
    final details = await _resolveLocationDetails();
    if (details == null) return null;
    return (details.$1, details.$2);
  }
}
