import 'dart:convert';
import 'package:http/http.dart' as http;

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
  final double windSpeed;
  final String locationName;
  final String country;
  final List<HourlyForecast> hourly;
  final List<DailyForecast> daily;

  FullWeatherData({
    required this.currentTemperature,
    required this.currentWeatherCode,
    required this.windSpeed,
    required this.locationName,
    required this.country,
    required this.hourly,
    required this.daily,
  });
}

class WeatherService {
  static const _ipApiUrl = 'https://ipinfo.io/json';
  static const _weatherApiUrl = 'https://api.open-meteo.com/v1/forecast';

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
  static Future<FullWeatherData?> getFullWeather() async {
    try {
      final locationRes = await http.get(Uri.parse(_ipApiUrl));
      if (locationRes.statusCode != 200) return null;

      final locationData = jsonDecode(locationRes.body);
      final String? loc = locationData['loc'];
      if (loc == null) return null;

      final parts = loc.split(',');
      if (parts.length != 2) return null;

      final double? lat = double.tryParse(parts[0]);
      final double? lon = double.tryParse(parts[1]);
      if (lat == null || lon == null) return null;

      final cityName = (locationData['city'] as String?) ?? '';
      final country = (locationData['country'] as String?) ?? '';

      final weatherUrl = Uri.parse(
        '$_weatherApiUrl'
        '?latitude=$lat'
        '&longitude=$lon'
        '&current_weather=true'
        '&hourly=temperature_2m,precipitation_probability,weathercode'
        '&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=auto'
        '&forecast_days=7',
      );

      final res = await http.get(weatherUrl);
      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body);

      // Current
      final current = data['current_weather'];
      final currentTemp = (current['temperature'] as num).toDouble();
      final currentCode = (current['weathercode'] as num).toInt();
      final windSpeed = (current['windspeed'] as num).toDouble();

      // Hourly — next 24 entries from now
      final hourlyTimes = List<String>.from(data['hourly']['time']);
      final hourlyTemps = List<num>.from(data['hourly']['temperature_2m']);
      final hourlyPrecip = List<num>.from(data['hourly']['precipitation_probability']);
      final hourlyCodes = List<num>.from(data['hourly']['weathercode']);

      final now = DateTime.now();
      final List<HourlyForecast> hourlyForecasts = [];
      for (int i = 0; i < hourlyTimes.length; i++) {
        final t = DateTime.tryParse(hourlyTimes[i]);
        if (t == null) continue;
        if (t.isBefore(now)) continue;
        hourlyForecasts.add(HourlyForecast(
          time: t,
          temperature: hourlyTemps[i].toDouble(),
          weatherCode: hourlyCodes[i].toInt(),
          precipitationProbability: hourlyPrecip[i].toDouble(),
        ));
        if (hourlyForecasts.length >= 24) break;
      }

      // Daily — 7 days
      final dailyDates = List<String>.from(data['daily']['time']);
      final dailyMax = List<num>.from(data['daily']['temperature_2m_max']);
      final dailyMin = List<num>.from(data['daily']['temperature_2m_min']);
      final dailyCodes = List<num>.from(data['daily']['weathercode']);
      final dailyPrecip = List<num>.from(data['daily']['precipitation_probability_max']);

      final List<DailyForecast> dailyForecasts = [];
      for (int i = 0; i < dailyDates.length; i++) {
        final d = DateTime.tryParse(dailyDates[i]);
        if (d == null) continue;
        dailyForecasts.add(DailyForecast(
          date: d,
          tempMax: dailyMax[i].toDouble(),
          tempMin: dailyMin[i].toDouble(),
          weatherCode: dailyCodes[i].toInt(),
          precipitationProbabilityMax: dailyPrecip[i].toDouble(),
        ));
      }

      return FullWeatherData(
        currentTemperature: currentTemp,
        currentWeatherCode: currentCode,
        windSpeed: windSpeed,
        locationName: cityName,
        country: country,
        hourly: hourlyForecasts,
        daily: dailyForecasts,
      );
    } catch (e) {
      return null;
    }
  }

  /// Cached coords helper.
  static Future<(double, double)?> _getLocation() async {
    try {
      final res = await http.get(Uri.parse(_ipApiUrl));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body);
      final String? loc = data['loc'];
      if (loc == null) return null;
      final parts = loc.split(',');
      if (parts.length != 2) return null;
      final lat = double.tryParse(parts[0]);
      final lon = double.tryParse(parts[1]);
      if (lat == null || lon == null) return null;
      return (lat, lon);
    } catch (_) {
      return null;
    }
  }
}
