import 'dart:async';

/// Retries one refresh at a time, with a single one-minute failure deadline.
class AccountServiceRetry {
  AccountServiceRetry({required this.refresh, required this.onFailure});

  final Future<void> Function() refresh;
  final void Function() onFailure;
  Timer? _deadline;
  Timer? _retry;
  bool _running = false;
  bool _disposed = false;
  bool _inFlight = false;

  void start() {
    if (_disposed || _running || _inFlight) return;
    _running = true;
    _deadline = Timer(const Duration(minutes: 1), () {
      _running = false;
      _retry?.cancel();
      if (!_disposed) onFailure();
    });
    unawaited(_attempt());
  }

  Future<void> _attempt() async {
    if (_disposed || !_running) return;
    _inFlight = true;
    try {
      await refresh();
      _running = false;
      _deadline?.cancel();
    } catch (_) {
      if (!_disposed && _running) {
        _retry = Timer(const Duration(seconds: 5), () => unawaited(_attempt()));
      }
    } finally {
      _inFlight = false;
    }
  }

  void dispose() {
    _disposed = true;
    _running = false;
    _deadline?.cancel();
    _retry?.cancel();
  }
}
