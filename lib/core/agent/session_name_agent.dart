import 'package:langchain/langchain.dart' as lc;
import 'package:langchain_openai/langchain_openai.dart';

import '../agent/agent.dart';
import '../model/owl_config.dart';

/// 会话起名 Agent。
///
/// 行为:接收用户首条原始输入 [userInput](纯字符串,不接触 DB 模型),
/// 用一次非流式模型调用生成 ≤12 字的中文标题。**不做任何持久化**,
/// 调用方负责把返回值写回 Session.title。
///
/// 仍遵守 [Agent] 的契约([run] 抛 UnsupportedError),但**起名能力不再
/// 走 Agent 抽象类入口** —— 由调用方直接调 [SessionNameAgent.generateTitle]。
class SessionNameAgent implements Agent {
  SessionNameAgent({required this.chat, this.maxLength = 12});

  final ChatOpenAI chat;

  /// 标题最大字符数(粗略按字符算,实际是模型的硬约束之一)。
  final int maxLength;

  @override
  AgentRun run({required AgentHandle handle, required OwlConfig config}) {
    throw UnsupportedError('SessionNameAgent does not support run()');
  }

  /// 一次性为会话生成一个短标题。
  ///
  /// 输入:用户首条原始文本 [userInput] + 模型配置 [config]。
  /// 返回:经过清洗(去引号 / 去编号 / 截断到 [maxLength])后的最终标题。
  /// **此方法不捕获异常** —— 调用方负责错误处理与日志。
  Future<String> generateTitle({
    required String userInput,
    required OwlConfig config,
  }) async {
    final messages = <lc.ChatMessage>[
      lc.ChatMessage.system('''你是会话标题生成器。
              ## 任务
              依据用户的对话输入，生成一条会话短标题。**请严格使用用户输入所使用的语言生成标题，用户输入是中文就输出中文，用户输入是英文就输出英文，其他语言对应输出同种语言。**
              
              ## ⚠️强制规则（最高优先级，必须遵守）
              你**禁止直接把标题输出成文本回复**。生成完成后，**必须调用工具 save_title，把生成好的标题填入该工具的 title 参数中交付结果，不允许直接输出标题、不允许输出任何自然语言回答**。
              不要输出解释、不要输出说明，所有结果全部交给 save_title 工具。
              
              ## 输出约束（生成标题内容时严格遵守）
              1. 标题字符长度不超过$maxLength个字符，超出直接截断；
              2. 标题本身只保留标题文字，禁止引号、序号、markdown、注释、思考过程、标签以及任何推理内容；
              3. 抓取对话核心主题，去除冗余修饰、语气词、无关铺垫；
              4. 用户输入内容极短时，直接复用原文，做长度截断即可；
              5. 不要反问，不要补充说明。
              
              ## ✅正确示例（工具入参参考，不是直接输出）
              输入：怎么解析图片文件格式
              调用save_title，title参数值：图片格式解析
              输入：聊聊面试需要注意哪些技巧
              调用save_title，title参数值：面试技巧的讨论
              输入：怎么在家做面条
              调用save_title，title参数值：做面条的技巧
              输入：帮我写代码
              调用save_title，title参数值：写代码需求
              输入：你好
              调用save_title，title参数值：你好
              输入：How to debug flutter app
              调用save_title，title参数值：Flutter应用调试方法
              输入：Bonjour
              调用save_title，title参数值：Bonjour
              
              ## ❌错误示例（禁止这样做）
              输入：怎么解析图片文件格式
              错误行为1：直接回复文本：图片格式解析（不调用工具，严重错误）
              错误行为2：调用工具但title带引号："图片格式解析"（错误）
              错误行为3：title带编号：1.图片格式解析（错误）
              错误行为4：输出思考文本再调用工具：我先理解用户需求...（错误）
              错误行为5：title是长句子：这是一个关于图片格式解析的问题（错误）
              错误行为6：强行翻译语言，输入英文输出中文标题（错误）
              
              ## 输出边界
              - 最大字符：$maxLength，超过强制截断；
              - 语言规则：**跟随用户输入语言，禁止强行翻译为中文**；
              - 输入为空/乱码：title参数填入“新会话”；
              - 输入极短（1‑3个字）：直接使用原文，不做改写；
              - 全程不要输出任何自然语言回复，**唯一允许的行为就是调用save_title工具**。
            '''),
      lc.ChatMessage.humanText(userInput),
    ];

    var title = "新会话";

    final tool = lc.Tool.fromFunction(
      name: "save_title",
      description: "保存会话标题，输入为生成好的会话短标题文本",
      inputJsonSchema: <String, dynamic>{
        "type": "object",
        "properties": {
          "title": {"type": "string", "description": "生成的会话短标题"},
        },
        "required": ["title"],
      },
      func: (Map<String, dynamic> input) async {
        // ✅这里 input 是 Map<String,dynamic>，可以用 []
        final raw = input['title'] as String? ?? "";
        final finalTitle = raw.isEmpty ? "新会话" : raw;
        print("save_title tool: $finalTitle");
        title = finalTitle;
        return "success:$finalTitle";
      },
    );

    final options = ChatOpenAIOptions(
      model: config.model,
      temperature: 0.3,
      tools: <lc.Tool>[tool],
      toolChoice: lc.ChatToolChoice.forced(name: "save_title"), //强制必须调用save_title
    );

    final result = await chat.call(messages, options: options);

    return result.toolCalls[0].arguments['title'];
  }
}
