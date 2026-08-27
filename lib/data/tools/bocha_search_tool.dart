import 'dart:convert';

import 'package:http/http.dart' as http;

/// 博查 Web Search API 客户端。
///
/// 文档:https://bocha-ai.feishu.cn/wiki/Kv1vwbfzpiyCq3kS9FccNVBvnOh
///
/// **仅负责 HTTP 调用 + 响应解析**,不耦合 LLM tool schema —— 让上层
/// ([bindBochaSearchTool] 等) 自己决定如何包装给 LangChain。
///
/// **鉴权**:Bearer Token(API-KEY);失败统一抛 [BochaSearchException],
/// 由 Tool 层转为用户友好的字符串结果(LLM 不需要 try/catch)。
class BochaSearchClient {
  BochaSearchClient({
    required this.apiKey,
    this.endpoint = 'https://api.bocha.cn/v1/web-search',
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
  })  : _http = httpClient ?? http.Client(),
        _timeout = timeout;

  final String apiKey;
  final String endpoint;
  final http.Client _http;
  final Duration _timeout;

  /// 调用博查 Web Search API。
  ///
  /// **核心字段**(详见博查文档):
  /// * [query]:搜索关键词(必填)
  /// * [summary]:是否返回摘要(`true` 让模型能直接引用)
  /// * [count]:返回条数,1~50,默认 10
  /// * [freshness]:时间过滤(`oneDay` / `oneWeek` / `oneMonth` / `oneYear`
  ///   或 `YYYY-MM-DD..YYYY-MM-DD`)
  Future<List<BochaSearchResult>> search({
    required String query,
    bool summary = true,
    int count = 10,
    String? freshness,
  }) async {
    final body = <String, dynamic>{
      'query': query,
      'summary': summary,
      'count': count,
      if (freshness != null) 'freshness': freshness,
    };
    final resp = await _http
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw BochaSearchException(
        'HTTP ${resp.statusCode}: ${resp.body}',
      );
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw BochaSearchException('响应缺少 data 字段:$json');
    }
    final rawItems = data['webPages']?['value'] as List<dynamic>? ?? const [];
    return rawItems
        .map((e) => BochaSearchResult.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  void dispose() => _http.close();
}

/// 单条搜索结果。
///
/// 字段命名与博查官方响应一致;字段可空(博查文档未保证每个字段都返回)。
class BochaSearchResult {
  const BochaSearchResult({
    required this.id,
    required this.name,
    required this.url,
    required this.snippet,
    this.summary,
    this.datePublished,
    this.siteName,
  });

  final String id;
  final String name;
  final String url;
  final String snippet;
  final String? summary;
  final String? datePublished;
  final String? siteName;

  factory BochaSearchResult.fromJson(Map<String, dynamic> json) {
    return BochaSearchResult(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      url: (json['url'] ?? '') as String,
      snippet: (json['snippet'] ?? '') as String,
      summary: json['summary'] as String?,
      datePublished: json['datePublished'] as String?,
      siteName: (json['siteName'] ?? '') as String,
    );
  }

  /// 格式化为 LLM 友好的文本。
  String toLlmString() {
    final buf = StringBuffer()
      ..writeln('- 标题:$name')
      ..writeln('  URL:$url');
    final published = datePublished;
    if (published != null && published.isNotEmpty) {
      buf.writeln('  发布时间:$published');
    }
    final srcName = siteName;
    if (srcName != null && srcName.isNotEmpty) {
      buf.writeln('  来源:$srcName');
    }
    final summaryText = summary;
    final text = (summaryText != null && summaryText.isNotEmpty)
        ? summaryText
        : snippet;
    if (text.isNotEmpty) {
      buf.writeln('  摘要:$text');
    }
    return buf.toString();
  }
}

/// 搜索失败时抛出。
class BochaSearchException implements Exception {
  BochaSearchException(this.message);
  final String message;
  @override
  String toString() => 'BochaSearchException: $message';
}

/// 博查 Web Search 的 LLM tool schema。
///
/// **给模型看的描述**(写在 description 字段):告诉 LLM 这个工具能查实时
/// 网页 / 中文 / 新闻,以及何时该调用。
Map<String, dynamic> bochaSearchToolSchema() => <String, dynamic>{
      'type': 'object',
      'properties': {
        'query': {
          'type': 'string',
          'description': '搜索关键词,中文 / 自然语言均可;不要包含多余修饰词',
        },
        'count': {
          'type': 'integer',
          'description': '返回条数,1~50,默认 10',
          'default': 10,
        },
        'freshness': {
          'type': 'string',
          'description':
              '可选时间过滤:oneDay / oneWeek / oneMonth / oneYear,或 YYYY-MM-DD..YYYY-MM-DD 区间',
        },
      },
      'required': ['query'],
    };

/// 工厂:绑定 BochaClient 后返回可注册的 tool func。
///
/// **当 apiKey 为空**(用户未在 Settings 配置),返回的 func 会直接返回
/// 友好提示字符串 —— 而不是抛异常,这样 LLM 能据此回复用户"请先配置 API Key"。
Future<String> Function(Map<String, dynamic>) bindBochaSearchTool({
  required String apiKey,
  BochaSearchClient? client,
}) {
  return (args) async {
    final query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) return '错误:query 不能为空';

    if (apiKey.isEmpty) {
      return '错误:博查搜索 API Key 未配置,请在 Settings 中填写 bochaApiKey 后重试';
    }

    final own = client ?? BochaSearchClient(apiKey: apiKey);
    try {
      final results = await own.search(
        query: query,
        summary: true,
        count: (args['count'] as num?)?.toInt().clamp(1, 50) ?? 10,
        freshness: args['freshness'] as String?,
      );
      if (results.isEmpty) return '未找到匹配结果';
      return '搜索结果:\n${results.map((r) => r.toLlmString()).join('\n')}';
    } on BochaSearchException catch (e) {
      return '博查搜索失败:${e.message}';
    } catch (e) {
      return '博查搜索异常:$e';
    }
  };
}