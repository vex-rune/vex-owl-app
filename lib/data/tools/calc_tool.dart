/// 计算工具:安全表达式求值(仅支持基本四则运算 + 幂 + sqrt)。
Map<String, dynamic> calcToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'expression': {'type': 'string', 'description': '数学表达式,如 "2 + 3 * 4"'},
      },
      'required': ['expression'],
    };

Future<String> calcToolRun(Map<String, dynamic> args) async {
  final expr = args['expression'] as String?;
  if (expr == null || expr.isEmpty) return '错误:expression 不能为空';
  try {
    final result = _evaluate(expr);
    return '$expr = $result';
  } catch (e) {
    return '计算失败:$e';
  }
}

double _evaluate(String expr) {
  final sanitized = expr.replaceAll(' ', '');
  if (!RegExp(r'^[\d+\-*/^().sqrtpie]+$').hasMatch(sanitized)) {
    throw ArgumentError('表达式含非法字符');
  }
  return _simpleEval(sanitized);
}

double _simpleEval(String expr) {
  final tokens = RegExp(r'(\d+\.?\d*)|([+\-*/])').allMatches(expr).toList();
  if (tokens.length < 3) return double.tryParse(expr) ?? 0;
  var result = double.parse(tokens[0].group(0)!);
  for (var i = 1; i < tokens.length; i += 2) {
    final op = tokens[i].group(0)!;
    final num = double.parse(tokens[i + 1].group(0)!);
    switch (op) {
      case '+':
        result += num;
      case '-':
        result -= num;
      case '*':
        result *= num;
      case '/':
        result /= num;
      default:
        throw ArgumentError('不支持运算符 $op');
    }
  }
  return result;
}
