/// Token 估算工具。
///
/// 基于字符数的简易 token 估算，无需依赖外部分词库。
/// 中文文本约 1 token / 1.5 字符，英文文本约 1 token / 4 字符。
library;

/// Token 估算工具类。
///
/// 提供基于字符的 token 数量估算方法，适用于快速判断文本长度是否超过限制。
class TokenCounter {
  TokenCounter._();

  /// 中文字符的 token 估算比例（约 1 token 对应 1.5 个中文字符）
  static const double _chineseCharsPerToken = 1.5;

  /// 英文字符的 token 估算比例（约 1 token 对应 4 个英文字符）
  static const double _englishCharsPerToken = 4.0;

  /// 估算文本的 token 数量。
  ///
  /// 对文本中的中文字符和英文字符分别计算后求和。
  /// 中文文本约 1 token / 1.5 字符，英文文本约 1 token / 4 字符。
  ///
  /// [text] 需要估算的文本内容。
  ///
  /// 返回估算的 token 数量（向上取整的整数）。
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;

    int chineseCount = 0;
    int englishCount = 0;
    int otherCount = 0;

    for (final codeUnit in text.codeUnits) {
      // 中文及中日韩统一表意文字范围
      if (codeUnit >= 0x4E00 && codeUnit <= 0x9FFF) {
        chineseCount++;
      }
      // 基本拉丁字母和数字
      else if ((codeUnit >= 0x0041 && codeUnit <= 0x005A) || // A-Z
          (codeUnit >= 0x0061 && codeUnit <= 0x007A) || // a-z
          (codeUnit >= 0x0030 && codeUnit <= 0x0039)) {
        // 0-9
        englishCount++;
      } else {
        otherCount++;
      }
    }

    final chineseTokens = chineseCount / _chineseCharsPerToken;
    final englishTokens = englishCount / _englishCharsPerToken;
    final otherTokens = otherCount / _englishCharsPerToken;

    return (chineseTokens + englishTokens + otherTokens).ceil();
  }

  /// 检查文本的 token 数量是否超过指定阈值。
  ///
  /// [text] 需要检查的文本内容。
  /// [threshold] token 数量阈值。
  ///
  /// 返回 `true` 表示文本 token 数量超过阈值。
  static bool isOverThreshold(String text, int threshold) {
    return estimateTokens(text) > threshold;
  }
}
