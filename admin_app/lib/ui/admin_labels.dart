/// API 枚举 / 健康检查 key → 中文展示。
class AdminLabels {
  AdminLabels._();

  static String status(Object? raw) {
    switch ('$raw'.toUpperCase()) {
      case 'ACTIVE':
      case 'ENABLED':
        return '正常';
      case 'DISABLED':
        return '已禁用';
      case 'TRIAL':
        return '试用中';
      case 'EXPIRED':
        return '已到期';
      case 'READONLY':
      case 'READ_ONLY':
        return '只读';
      case 'MAINTENANCE':
        return '维护中';
      case 'OK':
        return '正常';
      case 'FAIL':
      case 'ERROR':
        return '异常';
      default:
        final s = '$raw'.trim();
        return s.isEmpty ? '—' : s;
    }
  }

  static String plan(Object? raw) {
    switch ('$raw'.toLowerCase()) {
      case 'trial':
        return '试用';
      case 'paid':
      case 'pro':
      case 'full':
        return '正式';
      case 'free':
        return '免费';
      default:
        final s = '$raw'.trim();
        return s.isEmpty ? '—' : s;
    }
  }

  static String appStatus(Object? raw) {
    switch ('$raw'.toUpperCase()) {
      case 'ACTIVE':
        return '运行中';
      case 'MAINTENANCE':
        return '维护';
      case 'DISABLED':
        return '停用';
      default:
        return status(raw);
    }
  }

  static String healthKey(Object? raw) {
    switch ('$raw') {
      case 'database':
        return '数据库';
      case 'data_dir_writable':
        return '数据目录可写';
      case 'attachments_writable':
        return '附件目录可写';
      case 'jwt_secret':
        return 'JWT 密钥';
      case 'admin_password':
        return '管理员密码';
      case 'push':
        return '推送（极光）';
      case 'push_detail':
        return '推送详情';
      case 'user_count':
        return '用户数';
      case 'websocket':
        return 'WebSocket 实时通道';
      default:
        return '$raw';
    }
  }

  static String healthValue(Object? raw) {
    final s = '$raw'.toLowerCase();
    if (s == 'ok' || s == '1' || s == 'true') return '正常';
    if (s == 'optional') return '未配置（可选）';
    if (s == 'fail' || s == 'error' || s == '0' || s == 'false') return '异常';
    return '$raw';
  }

  static String yesNoFlag(Object? raw) {
    final s = '$raw';
    if (s == '1' || s == 'true') return '是';
    if (s == '0' || s == 'false') return '否';
    return status(raw);
  }
}
