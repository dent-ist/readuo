class ContentFilterResult {
  const ContentFilterResult({required this.allowed, this.explanation});

  final bool allowed;
  final String? explanation;
}

abstract final class BasicContentFilter {
  static const version = 'basic-threats-v1';
  static const pattern =
      r'(?:^|[^a-z0-9_])(?:i[ \t\r\n]+will[ \t\r\n]+kill[ \t\r\n]+you|kill[ \t\r\n]+yourself)(?:$|[^a-z0-9_])';
  static const explanation =
      'Remove direct threats of violence or encouragement to self-harm before sharing.';

  static ContentFilterResult check(String text) => ContentFilterResult(
    allowed: !RegExp(pattern).hasMatch(text.toLowerCase()),
    explanation: RegExp(pattern).hasMatch(text.toLowerCase())
        ? explanation
        : null,
  );
}
