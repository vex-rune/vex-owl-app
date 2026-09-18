/// MiniMax 文件上传目的枚举
///
/// 用于 MiniMax Files API 的 purpose 参数
///
/// 文档：https://api.minimax.cn/document/file
enum MiniMaxFilePurpose {
  /// 快速复刻原始音频文件（支持 mp3、m4a、wav）
  voiceClone('voice_clone'),

  /// 音色复刻的示例音频（支持 mp3、m4a、wav）
  promptAudio('prompt_audio'),

  /// 异步长文本语音生成合成中，请求体中的文本文件（支持 text、zip）
  t2aAsyncInput('t2a_async_input'),

  /// 多模态理解使用的视频文件（支持 MP4、AVI、MOV、MKV），有效期 7 天
  videoUnderstanding('video_understanding'),

  /// 视频生成的输入素材（图片/参考视频/参考音频），有效期 7 天
  videoGenerationInput('video_generation_input');

  const MiniMaxFilePurpose(this.value);
  final String value;
}

/// MiniMax 文件限制常量
class MiniMaxFileLimits {
  MiniMaxFileLimits._();

  /// 文件大小限制（字节）
  static const Map<MiniMaxFilePurpose, int> sizeLimits = {
    MiniMaxFilePurpose.videoGenerationInput: 50 * 1024 * 1024, // 50MB
    MiniMaxFilePurpose.videoUnderstanding: 100 * 1024 * 1024, // 100MB
    MiniMaxFilePurpose.t2aAsyncInput: 10 * 1024 * 1024, // 10MB
    MiniMaxFilePurpose.voiceClone: 30 * 1024 * 1024, // 30MB
    MiniMaxFilePurpose.promptAudio: 10 * 1024 * 1024, // 10MB
  };

  /// 支持的文件扩展名
  static const Map<MiniMaxFilePurpose, List<String>> supportedExtensions = {
    MiniMaxFilePurpose.voiceClone: ['mp3', 'm4a', 'wav'],
    MiniMaxFilePurpose.promptAudio: ['mp3', 'm4a', 'wav'],
    MiniMaxFilePurpose.t2aAsyncInput: ['txt', 'zip'],
    MiniMaxFilePurpose.videoUnderstanding: ['mp4', 'avi', 'mov', 'mkv'],
    MiniMaxFilePurpose.videoGenerationInput: [
      'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif', // 图片 30MB
      'mp4', 'mov', // 视频 50MB
      'wav', 'mp3', // 音频 15MB
    ],
  };
}
