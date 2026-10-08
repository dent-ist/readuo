import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const inviteHost = 'readuo-b2f24.web.app';

String inviteLink(String code) {
  if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
    throw ArgumentError.value(code, 'code', 'Expected a six-character code');
  }
  return Uri.https(inviteHost, '/invite/$code').toString();
}

String? inviteCodeFromLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != inviteHost ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.hasQuery ||
      uri.hasFragment)
    return null;
  final match = RegExp(r'^/invite/([A-Z0-9]{6})$').firstMatch(uri.path);
  return match?.group(1);
}

class InviteLinks extends ChangeNotifier {
  InviteLinks({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.zipdosa.readuo/invites');

  final MethodChannel _channel;
  String? _pendingCode;
  String? get pendingCode => _pendingCode;

  Future<void> initialize() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openInvite' && call.arguments is String) {
        accept(call.arguments as String);
      }
    });
    try {
      final initial = await _channel.invokeMethod<String>('initialInvite');
      if (initial != null) accept(initial);
    } on MissingPluginException {
      return;
    }
  }

  void accept(String link) {
    final code = inviteCodeFromLink(link);
    if (code == null || code == _pendingCode) return;
    _pendingCode = code;
    notifyListeners();
  }

  void consume(String code) {
    if (_pendingCode == code) _pendingCode = null;
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }
}
