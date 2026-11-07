// tray_controller_linux.h — v4.39 close-to-tray for the GTK runner,
// v4.40 the owner's round-15 menu + the Dart-routed close decision.
//
// The owner's decree («وقتی کاربر روی دکمه بستن کلیک میکنه برنامه به جای
// اینکه کلا بسته بشه آیکونش توی ترای سیستم کوچیک بشه»): clicking the
// window's close button HIDES the window instead of quitting — the tunnel
// and the engines keep running in the background, the tray icon carries the
// owner's mark EXACTLY as delivered (design/brand/aethone-logo.svg,
// transparent face), and the tray menu offers the owner's round-15 entries
// verbatim: نمایش اپ (show) / قطع و وصل اتصال (toggle connection) / خروج
// (quit). The v4.40 round moves the CLOSE DECISION into the Dart layer
// (the ask-dialog with the remember checkbox); this controller forwards
// the requests through the registered sink and executes the answers
// (HideToTrayFromDart / QuitFromDart).
//
// GtkStatusIcon is the zero-dependency tray on GTK3 (annotated deprecated
// in 3.14 but the only XEmbed/StatusNotifier surface that needs no extra
// library on the runner); the whole implementation sits under one
// -Wdeprecated-declarations guard so -Wall -Werror (apply_standard_settings)
// stays armed everywhere else.
#pragma once

#include <string>

typedef struct _GtkWindow GtkWindow;

namespace aethone {

// The bundle's icon faces (Paths().exeDir based):
//   AppIconFile()  — aethone-icon.png, the mark on WHITE (window/taskbar face)
//   TrayIconFile() — aethone-tray.png, the mark AS-IS (the tray face)
const char* AppIconFile();
const char* TrayIconFile();

// The tray-side event sink, registered by the engine channel (main thread).
//   "close_requested"   — the window's close button was clicked; Dart shows
//                         the ask-dialog and answers window.hide/window.quit.
//   "toggle_connection" — the «قطع و وصل اتصال» menu entry; Dart toggles the
//                         connection state machine.
using TrayEventSink = void (*)(const char* event);

// Wires the close-to-tray behavior onto `window`. Idempotent; safe to call
// once at activate. When the bundle's tray PNG is missing (a broken bundle),
// the controller stays inert and close keeps its default quit semantics —
// never a hidden window with no way back.
void AttachTray(GtkWindow* window);

// v4.40 — the sink the close-request and the toggle entry forward through.
// May be null (before the channel registers): the close button then keeps
// the direct hide (the v4.39 behavior) so a window can never get stuck.
void SetTrayEventSink(TrayEventSink sink);

// v4.40 — the Dart answers: window.hide lands here (hide + the embed-grace
// timer, exactly the v4.39 close path); window.quit destroys the window
// (the real exit — GtkApplication ends with its last window).
bool HideToTrayFromDart();
void QuitFromDart();

}  // namespace aethone
