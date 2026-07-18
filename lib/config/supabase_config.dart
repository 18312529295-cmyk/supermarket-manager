/// Supabase 项目连接配置
/// 可在此处修改项目地址和密钥以接入不同环境的后端
class SupabaseConfig {
  SupabaseConfig._();

  /// Supabase 项目 URL
  static const String projectUrl = 'https://pbdslnpikmxgvxvhxzfx.supabase.co';

  /// Supabase REST API 基础路径
  static const String restBaseUrl = '$projectUrl/rest/v1';

  /// anon 密钥（公开密钥，前端安全）
  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBiZHNsbnBpa214Z3Z4dmh4emZ4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAxNjExNzQsImV4cCI6MjA5NTczNzE3NH0.SZz1VzDVn7elHCcKv49_9pEwQhdX_nwDpDuCCDCyb0w';

  /// ★ v6.31: 将手机号/用户名转换为 Supabase Auth 可用的邮箱格式
  static String authEmail({String? phone, String? username}) {
    if (phone != null && phone.trim().isNotEmpty) {
      return '${phone.trim().replaceAll(RegExp(r'[^\d]'), '')}@xm.local';
    }
    if (username != null && username.trim().isNotEmpty) {
      return '${username.trim().toLowerCase()}@xm.local';
    }
    throw ArgumentError('phone 和 username 不能同时为空');
  }
}
