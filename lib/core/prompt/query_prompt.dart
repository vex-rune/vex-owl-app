/// Wiki 查询提示词模板。
///
/// 提供用于从 Wiki 索引中检索相关页面的提示词常量和构建方法。
/// AI 助手会根据用户问题，从索引中挑选需要加载的 Wiki 页面文件名。
library;

/// 查询系统提示词。
///
/// 指导 AI 助手从 Wiki 索引中挑选相关页面，输出 JSON 数组格式的文件名列表。
const String querySystemPrompt =
    '你是Wiki知识检索助手';

/// 构建查询用户提示词。
///
/// [indexContent] Wiki 索引内容（包含文件名、摘要、标签等信息）。
/// [userQuestion] 用户提出的问题。
///
/// 返回格式化的用户提示词字符串，包含索引和问题两个部分。
String buildQueryUserPrompt(String indexContent, String userQuestion) {
  return '''
## Wiki 索引
$indexContent

## 用户问题
$userQuestion
''';
}
