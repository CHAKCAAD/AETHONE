/// Connection state machine — EXACTLY the states of prompt §8:
/// `Disconnected → Starting → WaitingForPermissions (Android/iOS only) →
/// Connecting → Connected → Reconnecting → Disconnecting → Failed`
/// plus the rules: any state may reach `Failed`; retry from `Failed` or
/// `Reconnecting` goes to `Connecting`; only ONE transition in flight;
/// `Connected` is only ever entered after the end-to-end probe succeeded
/// (that gate lives in the service layer — the machine just refuses
/// impossible jumps).
library;

/// The 8 connection states (prompt §8).
enum VpnState {
  disconnected,
  starting,
  waitingForPermissions,
  connecting,
  connected,
  reconnecting,
  disconnecting,
  failed,
}

/// v4.16 — connection mode («حالت اتصال» on the protocol sheet: تونل /
/// پروکسی). The sheet's segmented control binds here. The engine consumes
/// it at M2 (tunnel ⇒ zeptun owns the TUN device; proxy ⇒ the local proxy
/// port) — documented gap: the UI state is real from day one, the sheet
/// frame ships پروکسی selected as the default.
enum ConnectionMode { tunnel, proxy }

/// v4.40 — the desktop close behavior (owner round 15: «وقتی روی دکمه ضربدر
/// کلیک میشه برنامه باید یک پنجره نمایش بده و از کاربر بپرسه که میخواد
/// برنامه کلا بسته بشه یا اینکه بره تو تری سیستم … یه گزینه هم باید باشه
/// که کاربر بتونه تیک بزنه که آیا این انتخابش دفعه بعد هم اعمال بشه
/// مستقیم»). ASK is the default; a remembered pick applies directly (and the
/// general-settings row re-opens the question).
enum CloseBehavior { ask, close, tray }

/// Pure, side-effect-free transition table — fully unit-tested.
class VpnStateMachine {
  VpnState _current = VpnState.disconnected;

  VpnState get current => _current;

  VpnState transition(VpnState next) {
    if (!isValidTransition(_current, next)) {
      throw StateError('invalid transition: $_current → $next');
    }
    _current = next;
    return _current;
  }

  /// Any state → failed is always legal (prompt §8).
  static bool isValidTransition(VpnState from, VpnState to) {
    if (to == VpnState.failed) return true;
    return switch (from) {
      VpnState.disconnected => next(to, {
        VpnState.starting,
        VpnState.disconnecting,
      }),
      VpnState.starting => next(to, {
        VpnState.waitingForPermissions,
        VpnState.connecting,
        // v4.26 — tap-to-cancel must work during the tunnel bring-up too
        // (owner device-test round 4: «وسط حالت در حال اتصال … کلیک میکنی
        // تا اتصال قطع بشه»). The store's canceling disconnect applies
        // exactly this edge; refusing it used to fail the machine into
        // `failed(illegalTransition)` and wedge the UI there.
        VpnState.disconnecting,
      }),
      VpnState.waitingForPermissions => next(to, {
        VpnState.connecting,
        VpnState.disconnecting,
      }),
      VpnState.connecting => next(to, {
        VpnState.connected,
        VpnState.disconnecting,
      }),
      VpnState.connected => next(to, {
        VpnState.reconnecting,
        VpnState.disconnecting,
      }),
      // Retry from Reconnecting goes back to Connecting (prompt §8).
      VpnState.reconnecting => next(to, {
        VpnState.connecting,
        VpnState.disconnecting,
      }),
      VpnState.disconnecting => next(to, {VpnState.disconnected}),
      // Retry from Failed goes to Connecting (prompt §8).
      VpnState.failed => next(to, {
        VpnState.connecting,
        VpnState.disconnecting,
      }),
    };
  }

  static bool next(VpnState to, Set<VpnState> allowed) => allowed.contains(to);
}
