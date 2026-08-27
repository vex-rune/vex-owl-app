/// 流式解析 `<think>...</think>` 标签的状态机。
///
/// **目的**:DeepSeek / Qwen 等模型把 Chain-of-Thought 直接写在 `<think>XXX`
/// 标签里、混入 `content`。调用方需要在流式过程中把这两部分拆开:
///
/// * 标签内 → 累积为 `thinkSoFar`,产生 [ThinkChunk.thinking]
/// * 标签外 → 累积为 `textSoFar`,产生 [ThinkChunk.text]
///
/// **用法**(典型):
/// ```dart
/// final parser = ThinkParser();
/// await for (final chunk in llmStream) {
///   final chunks = parser.feed(chunk.output.content);
///   for (final c in chunks) {
///     switch (c) {
///       case ThinkThinking(:final content): emitAgentThinking(content);
///       case ThinkText(:final content):     emitAgentText(content);
///     }
///   }
/// }
/// ```
///
/// **partial token 处理**:标签可能跨多个 chunk 出现,状态机用 `_pending`
/// 缓存可能的不完整起始符,直到下一个 chunk 到来再判断。
///
/// **标签未闭合**:若流结束仍处于 `_inThink = true`,调用 [close] 会产生一条
/// 收尾的 [ThinkChunk.thinking](把残留内容视为 thinking —— 多数模型不会这样,
/// 但保证不会出现"内容丢失")。
library;

/// 解析器产出的片段。
///
/// **不耦合** [AgentResponse] / `Message`:本类只描述"这是 think 文本还是
/// 普通文本",由调用方决定落到哪一层。
sealed class ThinkChunk {
  const ThinkChunk(this.content);
  final String content;
}

/// 思考片段(在 `<think>...</think>` 内累积的文本)。
final class ThinkThinking extends ThinkChunk {
  const ThinkThinking(super.content);
}

/// 文本片段(标签外的文本)。
final class ThinkText extends ThinkChunk {
  const ThinkText(super.content);
}

/// 流式状态机。
///
/// **状态**:
/// * `_inThink == false`:在标签外 / 普通文本流
/// * `_inThink == true`:在 `<think>...</think>` 内
///
/// **为什么叫 "Think" 而不是 "Reasoning"**:沿用 DeepSeek 公开命名的标签
/// `<think>`,避免和 OpenAI o-series 的 `reasoning_content` 概念混淆。
class ThinkParser {
  ThinkParser({
    this.openTag = '<think>',
    this.closeTag = '</think>',
  });

  /// 起始标签(默认 `<think>`)。
  final String openTag;

  /// 结束标签(默认 `</think>`)。
  final String closeTag;

  bool _inThink = false;

  /// 截至当前累积的全部 think 文本(含尚未 emit 的部分)。
  String _thinkSoFar = '';

  /// 截至当前累积的全部普通文本(含尚未 emit 的部分)。
  String _textSoFar = '';

  /// 已经 emit 出去的 think 文本长度(cursor)。
  int _thinkEmitted = 0;

  /// 已经 emit 出去的普通文本长度(cursor)。
  int _textEmitted = 0;

  /// 缓存可能跨 chunk 的标签字符。
  /// 长度始终 < `_openTag.length`(起始侧)和 `< _closeTag.length`(结束侧)。
  String _pending = '';

  /// 喂入一段 delta 文本,返回该段产出的 [ThinkChunk] 列表。
  ///
  /// **delta 是本 chunk 增量**(不是累积全文),否则会重复 emit。
  ///
  /// **emit 策略**:每次只 emit 截至当前"还没 emit 过"的那段子串,
  /// cursor 随 emit 推进 —— UI 拼接即可拿到完整文本,无需自行去重。
  ///
  /// **返回可能为空**:若 delta 仅含不完整标签字符(缓存起来等下段),不会产出。
  List<ThinkChunk> feed(String delta) {
    if (delta.isEmpty) return const [];

    var input = _pending + delta;
    _pending = '';

    final out = <ThinkChunk>[];

    void emitThink() {
      if (_thinkSoFar.length > _thinkEmitted) {
        final deltaText = _thinkSoFar.substring(_thinkEmitted);
        _thinkEmitted = _thinkSoFar.length;
        out.add(ThinkThinking(deltaText));
      }
    }

    void emitText() {
      if (_textSoFar.length > _textEmitted) {
        final deltaText = _textSoFar.substring(_textEmitted);
        _textEmitted = _textSoFar.length;
        out.add(ThinkText(deltaText));
      }
    }

    while (input.isNotEmpty) {
      if (_inThink) {
        final closeIdx = input.indexOf(closeTag);
        if (closeIdx >= 0) {
          _thinkSoFar += input.substring(0, closeIdx);
          emitThink();
          input = input.substring(closeIdx + closeTag.length);
          _inThink = false;
        } else {
          // 没找到关闭符,缓存可能的不完整后缀
          if (input.length >= closeTag.length) {
            _thinkSoFar += input.substring(0, input.length - (closeTag.length - 1));
            emitThink();
            input = input.substring(input.length - (closeTag.length - 1));
            _pending = input;
            input = '';
          } else {
            _thinkSoFar += input;
            emitThink();
            input = '';
          }
        }
      } else {
        // 在标签外
        final openIdx = input.indexOf(openTag);
        if (openIdx >= 0) {
          _textSoFar += input.substring(0, openIdx);
          emitText();
          input = input.substring(openIdx + openTag.length);
          _inThink = true;
        } else {
          // 没找到开启符,缓存可能的不完整前缀
          if (input.length >= openTag.length) {
            _textSoFar += input.substring(0, input.length - (openTag.length - 1));
            emitText();
            input = input.substring(input.length - (openTag.length - 1));
            _pending = input;
            input = '';
          } else {
            _textSoFar += input;
            emitText();
            input = '';
          }
        }
      }
    }

    return out;
  }

  /// 流结束时调用。若处于 `_inThink = true`,把残留 thinking 内容 flush 出来。
  ///
  /// 调用后,解析器进入"终态" —— 后续 [feed] 调用将按全新解析器对待。
  List<ThinkChunk> close() {
    final out = <ThinkChunk>[];
    // 把 _pending 视为 thinking 末段(若处于 think 内)
    if (_inThink && _pending.isNotEmpty) {
      _thinkSoFar += _pending;
      _pending = '';
    }
    if (_inThink && _thinkSoFar.length > _thinkEmitted) {
      out.add(ThinkThinking(_thinkSoFar.substring(_thinkEmitted)));
    } else if (!_inThink && _textSoFar.length > _textEmitted) {
      out.add(ThinkText(_textSoFar.substring(_textEmitted)));
    }
    _reset();
    return out;
  }

  void _reset() {
    _inThink = false;
    _thinkSoFar = '';
    _textSoFar = '';
    _thinkEmitted = 0;
    _textEmitted = 0;
    _pending = '';
  }
}