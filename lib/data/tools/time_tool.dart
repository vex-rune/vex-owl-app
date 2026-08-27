import 'package:intl/intl.dart';

/// 时间工具:返回当前时间。
Map<String, dynamic> timeToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'format': {
          'type': 'string',
          'description': '可选,自定义输出格式(默认 ISO8601)',
        },
      },
    };

Future<String> timeToolRun(Map<String, dynamic> args) async {
  final now = DateTime.now();
  final fmt = args['format'] as String?;
  if (fmt != null) {
    return DateFormat(fmt).format(now);
  }
  final offset = now.timeZoneOffset;
  final sign = offset.inHours >= 0 ? '+' : '';
  return '${now.toIso8601String()} (UTC$sign${offset.inHours})';
}
