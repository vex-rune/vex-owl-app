import 'agent_spec.dart';

/// 图片生成 Agent 默认系统提示词
const _imageAgentPrompt = '你是一个图片生成助手。根据用户的描述生成图片。';

/// 创建图片生成 AgentSpec
///
/// 创建一个用于图片生成的 AgentSpec。
/// 该 Agent 接受用户的图片描述，调用图片生成 API 返回生成结果。
AgentSpec createImageAgentSpec({
  required String apiKey,
  required String apiEndpoint,
  String? systemPrompt,
}) {
  return AgentSpec(
    name: 'owl-image',
    instructions: systemPrompt ?? _imageAgentPrompt,
    model: ModelRoute.cloudOnly([
      ModelProvider(
        apiKey: apiKey,
        baseUrl: apiEndpoint,
      ),
    ]),
    tools: const [],
  );
}
