/// 仓储层通用业务异常。
///
/// 所有 `*Repository` 实现都应把领域错误映射成 [RepositoryError] 后抛出,
/// 而不是裸露底层异常(Drift `ExpressionError` / 文件 IO `FileSystemException`)等。
/// 上层服务负责按 [RepositoryErrorKind] 转译为面向用户的中文业务错误。
class RepositoryError implements Exception {
  RepositoryError(this.kind, this.message, [this.cause]);

  /// 错误分类。
  final RepositoryErrorKind kind;

  /// 面向开发者的描述(可记日志,但不要直接渲染给最终用户)。
  final String message;

  /// 底层异常,若有。
  final Object? cause;

  @override
  String toString() =>
      'RepositoryError($kind): $message${cause == null ? '' : ' | cause=$cause'}';
}

/// 仓储错误分类。
enum RepositoryErrorKind {
  /// 资源不存在(ID 找不到对应记录)。
  notFound,

  /// 校验失败(空标题、超长等)。
  invalid,

  /// 底层存储不可用(数据库被锁、文件读失败)。
  storage,

  /// 并发冲突(更新行数异常等)。
  conflict,
}
