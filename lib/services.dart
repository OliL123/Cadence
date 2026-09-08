import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// GET with a short retry (the very first request on cold start can race).
Future<http.Response?> _get(Uri uri) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final r = await http.get(uri).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) return r;
    } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 500));
  }
  return null;
}

// ---------------- Weather (Open-Meteo, no API key) ----------------

class DayForecast {
  final DateTime date;
  final int code;
  final double max;
  final double min;
  DayForecast(this.date, this.code, this.max, this.min);
}

class HourForecast {
  final DateTime time;
  final int code;
  final double temp;
  HourForecast(this.time, this.code, this.temp);
}

class WeatherData {
  final double temp;
  final int code;
  final List<DayForecast> days;
  final List<HourForecast> hours;
  WeatherData(this.temp, this.code, this.days, this.hours);
}

class GeoPlace {
  final String name;
  final String admin; // region/country label
  final double lat;
  final double lon;
  GeoPlace(this.name, this.admin, this.lat, this.lon);
}

Future<WeatherData?> fetchWeather(double lat, double lon) async {
  try {
    final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code'
        '&hourly=temperature_2m,weather_code'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min'
        '&timezone=auto&forecast_days=5');
    final r = await _get(uri);
    if (r == null) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final cur = j['current'] as Map<String, dynamic>;
    final d = j['daily'] as Map<String, dynamic>;
    final times = (d['time'] as List).cast<String>();
    final codes = (d['weather_code'] as List);
    final maxs = (d['temperature_2m_max'] as List);
    final mins = (d['temperature_2m_min'] as List);
    final days = <DayForecast>[
      for (var i = 0; i < times.length; i++)
        DayForecast(DateTime.parse(times[i]), (codes[i] as num).toInt(),
            (maxs[i] as num).toDouble(), (mins[i] as num).toDouble()),
    ];
    // hourly: keep from the current hour onward
    final hours = <HourForecast>[];
    final h = j['hourly'] as Map<String, dynamic>?;
    if (h != null) {
      final ht = (h['time'] as List).cast<String>();
      final hc = (h['weather_code'] as List);
      final htemp = (h['temperature_2m'] as List);
      final nowHour = DateTime.now();
      for (var i = 0; i < ht.length; i++) {
        final t = DateTime.parse(ht[i]);
        if (t.isBefore(DateTime(nowHour.year, nowHour.month, nowHour.day, nowHour.hour))) {
          continue;
        }
        hours.add(HourForecast(t, (hc[i] as num).toInt(), (htemp[i] as num).toDouble()));
      }
    }
    return WeatherData((cur['temperature_2m'] as num).toDouble(),
        (cur['weather_code'] as num).toInt(), days, hours);
  } catch (_) {
    return null;
  }
}

Future<List<GeoPlace>> geocode(String name) async {
  try {
    final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(name)}&count=6&language=en&format=json');
    final r = await _get(uri);
    if (r == null) return [];
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final results = (j['results'] ?? []) as List;
    return [
      for (final e in results)
        GeoPlace(
          e['name'] ?? '',
          [e['admin1'], e['country']].where((x) => x != null).join(', '),
          (e['latitude'] as num).toDouble(),
          (e['longitude'] as num).toDouble(),
        ),
    ];
  } catch (_) {
    return [];
  }
}

/// WMO weather code -> (label, icon).
(String, IconData) weatherInfo(int code) {
  if (code == 0) return ('Clear', Icons.wb_sunny_outlined);
  if (code <= 2) return ('Partly cloudy', Icons.wb_cloudy_outlined);
  if (code == 3) return ('Overcast', Icons.cloud_outlined);
  if (code <= 48) return ('Fog', Icons.foggy);
  if (code <= 57) return ('Drizzle', Icons.grain);
  if (code <= 67) return ('Rain', Icons.water_drop_outlined);
  if (code <= 77) return ('Snow', Icons.ac_unit);
  if (code <= 82) return ('Showers', Icons.grain);
  if (code <= 86) return ('Snow showers', Icons.ac_unit);
  return ('Thunderstorm', Icons.thunderstorm_outlined);
}

// ---------------- Holidays (Nager.Date, no API key) ----------------

class Holiday {
  final DateTime date;
  final String name;
  final String country; // ISO code this holiday belongs to
  Holiday(this.date, this.name, this.country);
}

/// A stable colour per holiday region.
const _placeColors = <String, Color>{
  'US': Color(0xFF2C4C7C), // navy
  'HK': Color(0xFFBE3A2B), // red
  'GB': Color(0xFF1F6E4E), // green
  'CA': Color(0xFFD2982E), // mustard
  'AU': Color(0xFF217A6E), // teal
  'CN': Color(0xFFA31545),
  'JP': Color(0xFF7A4E28),
  'SG': Color(0xFF2C7C6E),
  'TW': Color(0xFF126E4E),
  'KR': Color(0xFFC96A1E),
  'DE': Color(0xFF3A3630),
  'FR': Color(0xFF4A4C9C),
};
Color placeColor(String code) => _placeColors[code] ?? const Color(0xFF7C7358);

/// Common places to pick from (ISO-3166 alpha-2 country codes).
const holidayPlaces = <String, String>{
  'US': 'United States',
  'HK': 'Hong Kong',
  'GB': 'United Kingdom',
  'CA': 'Canada',
  'AU': 'Australia',
  'CN': 'China',
  'JP': 'Japan',
  'SG': 'Singapore',
  'TW': 'Taiwan',
  'KR': 'South Korea',
  'DE': 'Germany',
  'FR': 'France',
};

Future<List<Holiday>> fetchHolidays(String country, int year) async {
  try {
    final uri = Uri.parse('https://date.nager.at/api/v3/PublicHolidays/$year/$country');
    final r = await _get(uri);
    if (r == null) return [];
    final list = jsonDecode(r.body) as List;
    return [
      for (final e in list)
        Holiday(DateTime.parse(e['date'] as String),
            (e['localName'] ?? e['name'] ?? '') as String, country),
    ];
  } catch (_) {
    return [];
  }
}
