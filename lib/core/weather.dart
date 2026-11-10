import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// 天气信息（零配置：IP 定位 + Open-Meteo，不需要 Key、不需要定位权限）
class WeatherInfo {
  final String city;
  final double tempC;
  final int code; // WMO weather code
  final int humidity;
  final double wind;
  final bool isDay;

  WeatherInfo({
    required this.city,
    required this.tempC,
    required this.code,
    required this.humidity,
    required this.wind,
    required this.isDay,
  });

  /// 中文天气描述
  String get label {
    if (code == 0) return isDay ? '晴' : '晴夜';
    if (code == 1) return '晴间多云';
    if (code == 2) return '多云';
    if (code == 3) return '阴';
    if (code == 45 || code == 48) return '有雾';
    if (code >= 51 && code <= 57) return '毛毛雨';
    if (code >= 61 && code <= 67) return '下雨';
    if (code >= 71 && code <= 77) return '下雪';
    if (code >= 80 && code <= 82) return '阵雨';
    if (code >= 85 && code <= 86) return '阵雪';
    if (code >= 95) return '雷雨';
    return '未知';
  }

  String get emoji {
    if (code == 0) return isDay ? '☀️' : '🌙';
    if (code <= 2) return '⛅';
    if (code == 3) return '☁️';
    if (code == 45 || code == 48) return '🌫️';
    if (code >= 51 && code <= 67) return '🌧️';
    if (code >= 71 && code <= 86) return '❄️';
    if (code >= 95) return '⛈️';
    return '🌤️';
  }

  /// 给 AI 看的上下文
  String get forAi =>
      '$city $label ${tempC.toStringAsFixed(0)}℃ 湿度$humidity% 风$wind km/h'
      '${isDay ? '（白天）' : '（夜里）'}';

  String get short =>
      '$emoji $label ${tempC.toStringAsFixed(0)}℃';

  /// 背景色调：随天气和昼夜变化
  Color get tint {
    if (!isDay) return const Color(0xFF10131C); // 夜
    if (code == 0) return const Color(0xFF1A1712); // 晴：暖
    if (code <= 2) return const Color(0xFF161A21); // 多云
    if (code == 3) return const Color(0xFF14181E); // 阴
    if (code == 45 || code == 48) return const Color(0xFF171A1F); // 雾
    if (code >= 51 && code <= 67) return const Color(0xFF101820); // 雨：冷青
    if (code >= 71 && code <= 86) return const Color(0xFF111820); // 雪
    if (code >= 95) return const Color(0xFF12141F); // 雷雨
    return const Color(0xFF12161C);
  }

  /// 背景高光色（用于渐变）
  Color get accent {
    if (!isDay) return const Color(0xFF2A3350);
    if (code == 0) return const Color(0xFF4A3520);
    if (code <= 2) return const Color(0xFF243040);
    if (code == 3) return const Color(0xFF22282F);
    if (code >= 51 && code <= 67) return const Color(0xFF1B3244);
    if (code >= 71 && code <= 86) return const Color(0xFF243A4A);
    return const Color(0xFF242A36);
  }
}

/// 天气服务：IP 定位（ip-api）+ 天气（open-meteo），都不需要 Key
class WeatherService {
  static WeatherInfo? cached;
  static DateTime? cachedAt;
  static String? error;

  /// 正在进行的请求。多个调用方必须等同一个 Future，
  /// 不能各自返回 null —— 否则界面会拿到空值。
  static Future<WeatherInfo?>? _inflight;

  static const _ttl = Duration(minutes: 30);

  static bool get isFresh =>
      cached != null &&
      cachedAt != null &&
      DateTime.now().difference(cachedAt!) < _ttl;

  /// 拉取天气；[force] 忽略缓存
  static Future<WeatherInfo?> load({bool force = false}) {
    if (!force && isFresh) return Future.value(cached);
    final running = _inflight;
    if (running != null) return running;
    final f = _doLoad();
    _inflight = f;
    f.whenComplete(() {
      if (identical(_inflight, f)) _inflight = null;
    });
    return f;
  }

  static Future<WeatherInfo?> _doLoad() async {
    error = null;
    try {
      // 1) IP 定位
      // 必须走 HTTPS —— Android 9+ 默认禁止明文 HTTP，用 http:// 会被系统静默拦掉
      final geo = await http
          .get(Uri.parse('https://ipwho.is/?lang=zh-CN'))
          .timeout(const Duration(seconds: 12));
      if (geo.statusCode != 200) {
        error = '定位失败 ${geo.statusCode}';
        debugPrint('[selfgrow] geo http ${geo.statusCode}');
        return cached;
      }
      final g = jsonDecode(utf8.decode(geo.bodyBytes)) as Map<String, dynamic>;
      if (g['success'] != true) {
        error = '定位失败';
        debugPrint('[selfgrow] geo fail: ${g['message']}');
        return cached;
      }
      final city = (g['city'] ?? g['region'] ?? '').toString();
      final lat = (g['latitude'] as num).toDouble();
      final lon = (g['longitude'] as num).toDouble();
      debugPrint('[selfgrow] geo ok: $city $lat,$lon');

      // 2) 天气
      final w = await http
          .get(Uri.parse(
              'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
              '&current=temperature_2m,relative_humidity_2m,weather_code,is_day,wind_speed_10m'
              '&timezone=auto'))
          .timeout(const Duration(seconds: 15));
      if (w.statusCode != 200) {
        error = '天气获取失败';
        return cached;
      }
      final wj = jsonDecode(utf8.decode(w.bodyBytes)) as Map<String, dynamic>;
      final cur = wj['current'] as Map<String, dynamic>;

      cached = WeatherInfo(
        city: city,
        tempC: (cur['temperature_2m'] as num).toDouble(),
        code: (cur['weather_code'] as num).toInt(),
        humidity: (cur['relative_humidity_2m'] as num?)?.toInt() ?? 0,
        wind: (cur['wind_speed_10m'] as num?)?.toDouble() ?? 0,
        isDay: ((cur['is_day'] as num?)?.toInt() ?? 1) == 1,
      );
      cachedAt = DateTime.now();
      debugPrint(
          '[selfgrow] weather ok: $city ${cached!.label} ${cached!.tempC}℃');
      return cached;
    } catch (e) {
      error = '网络异常';
      debugPrint('[selfgrow] weather failed: $e');
      return cached;
    }
  }
}
