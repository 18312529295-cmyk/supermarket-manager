import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

/// 密码安全工具：SHA-256 + 随机盐
///
/// 用法：
///   // 注册/设置密码时
///   final salt = PasswordUtil.generateSalt();
///   final hash = PasswordUtil.hashPassword('1234', salt);
///   // 存 hash + salt 到数据库，不存原始密码
///
///   // 登录验证时
///   final ok = PasswordUtil.verify('1234', storedSalt, storedHash);
class PasswordUtil {
  /// 生成 32 字节安全随机盐（base64url 编码后约 43 字符）
  static String generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64Url.encode(bytes);
  }

  /// 用盐+明文密码计算 SHA-256 哈希（返回 64 位十六进制字符串）
  static String hashPassword(String plainPassword, String salt) {
    final combined = utf8.encode('$salt:$plainPassword');
    final digest = sha256.convert(combined);
    return digest.toString();
  }

  /// 验证密码：比较输入密码+盐的哈希 与 数据库存哈希
  static bool verify(String plainPassword, String salt, String storedHash) {
    return hashPassword(plainPassword, salt) == storedHash;
  }
}
