// tray_controller_linux.h — v4.39 close-to-tray for the GTK runner.
//
// The owner's decree («وقتی کاربر روی دکمه بستن کلیک میکنه برنامه به جای
// اینکه کلا بسته بشه آیکونش توی ترای سیستم کوچیک بشه»): clicking the
// window's close button HIDES the window instead of quitting — the tunnel
// and the engines keep running in the background, the tray icon carries
// the owner's mark EXACTLY as delivered (design/brand/aethone-logo.svg,
// transparent face), and the tray menu offers نمایش (show) / خروج (quit).
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

// Wires the close-to-tray behavior onto `window`. Idempotent; safe to call
// once at activate. When the bundle's tray PNG is missing (a broken bundle),
// the controller stays inert and close keeps its default quit semantics —
// never a hidden window with no way back.
void AttachTray(GtkWindow* window);

}  // namespace aethone
