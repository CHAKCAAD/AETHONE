// tray_controller_linux.cc — see tray_controller_linux.h for the contract.
//
// Everything GTK is guarded by ONE diagnostic push/pop: GtkStatusIcon is
// annotated deprecated-in-3.14, and the runner compiles with
// -Wall -Werror (apply_standard_settings, linux/runner/CMakeLists.txt) —
// without the guard the deprecation attribute alone would fail the build.
#include <gtk/gtk.h>
#include <gdk-pixbuf/gdk-pixbuf.h>

#include <string>

#include "desktop_shared/desktop_engine.h"
#include "tray_controller_linux.h"

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"

namespace aethone {
namespace {

struct TrayState {
  GtkWindow* window = nullptr;
  GtkStatusIcon* icon = nullptr;
  guint embed_timer = 0;      // the one-shot grace timer, 0 = none armed
  bool tray_usable = true;    // flipped off after the embed check fails
};

TrayState g_tray;

// v4.40 — the engine channel's sink (null until RegisterEngineChannel).
aethone::TrayEventSink g_tray_sink = nullptr;

bool EmitTrayEvent(const char* event) {
  if (g_tray_sink == nullptr) return false;
  g_tray_sink(event);
  return true;
}

void ShowMainWindow() {
  if (g_tray.window == nullptr) return;
  gtk_widget_show(GTK_WIDGET(g_tray.window));
  gtk_window_present(g_tray.window);
  gtk_window_deiconify(g_tray.window);
}

void QuitFromTray() {
  // The real quit path: destroying the window ends the GtkApplication
  // (last window gone) exactly like the default close would have.
  if (g_tray.window == nullptr) return;
  GtkWindow* const window = g_tray.window;
  g_tray.window = nullptr;  // the delete-event handler must not re-hide
  gtk_widget_destroy(GTK_WIDGET(window));
}

// ---- the tray icon's own callbacks (the mark EXACTLY as delivered) ----

void OnTrayActivate(GtkStatusIcon*, gpointer) { ShowMainWindow(); }

void OnTrayPopup(GtkStatusIcon* icon, guint, guint, gpointer) {
  GtkWidget* menu = gtk_menu_new();
  // Persian labels, the app's own language — the strings are plain UTF-8
  // source bytes (GTK expects UTF-8; no codepage games on Linux).
  // v4.40 — the owner's round-15 menu, verbatim order: show the app,
  // disconnect/reconnect the connection, fully close the program.
  GtkWidget* const show = gtk_menu_item_new_with_label("نمایش AETHONE");
  GtkWidget* const toggle = gtk_menu_item_new_with_label("قطع و وصل اتصال");
  GtkWidget* const quit = gtk_menu_item_new_with_label("خروج");
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), show);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), toggle);
  gtk_menu_shell_append(GTK_MENU_SHELL(menu), quit);
  g_signal_connect_swapped(show, "activate",
                           G_CALLBACK(ShowMainWindow), nullptr);
  g_signal_connect_swapped(
      toggle, "activate",
      G_CALLBACK(+[](gpointer) { EmitTrayEvent("toggle_connection"); }),
      nullptr);
  g_signal_connect_swapped(quit, "activate",
                           G_CALLBACK(QuitFromTray), nullptr);
  gtk_widget_show_all(menu);
  gtk_menu_popup_at_widget(GTK_MENU(menu), GTK_WIDGET(icon),
                           GDK_GRAVITY_SOUTH_WEST, GDK_GRAVITY_NORTH_WEST,
                           nullptr);
}

// The grace verdict: if the session has no system tray, the icon never
// embeds — bring the window BACK so the user never loses the app, and
// remember the verdict (the next close quits directly, the honest face).
gboolean EmbedCheckTimeout(gpointer) {
  g_tray.embed_timer = 0;
  if (g_tray.icon != nullptr && gtk_status_icon_is_embedded(g_tray.icon)) {
    return FALSE;  // embedded — stay hidden in the tray
  }
  g_tray.tray_usable = false;
  if (g_tray.window != nullptr) {
    ShowMainWindow();
  }
  return FALSE;  // one-shot either way
}

gboolean OnWindowDelete(GtkWidget*, GdkEvent*, gpointer) {
  // v4.40 — the owner's round-15 decree: the close button never quits
  // directly. With the channel up, the decision belongs to the DART layer
  // (the ask-dialog with the remember checkbox); without it (the split
  // second before the engine registers) the v4.39 direct hide keeps the
  // window recoverable.
  if (g_tray.tray_usable && g_tray.window != nullptr) {
    if (EmitTrayEvent("close_requested")) {
      return TRUE;  // stop the default destroy — Dart answers
    }
    gtk_widget_hide(GTK_WIDGET(g_tray.window));
    if (g_tray.embed_timer == 0) {
      g_tray.embed_timer =
          g_timeout_add_seconds(3, EmbedCheckTimeout, nullptr);
    }
    return TRUE;  // stop the default destroy — the app stays alive
  }
  return FALSE;   // no tray on this session — quit as asked
}

}  // namespace

const char* AppIconFile() {
  static const std::string path = Paths().exeDir + "/aethone-icon.png";
  return path.c_str();
}

const char* TrayIconFile() {
  static const std::string path = Paths().exeDir + "/aethone-tray.png";
  return path.c_str();
}

void AttachTray(GtkWindow* window) {
  if (window == nullptr) return;
  g_tray.window = window;

  GError* err = nullptr;
  GdkPixbuf* full = gdk_pixbuf_new_from_file(TrayIconFile(), &err);
  if (full == nullptr) {
    if (err != nullptr) g_error_free(err);
    // A broken bundle must never strand a hidden window: with no tray
    // face to show, close keeps its default quit semantics.
    g_tray.tray_usable = false;
    g_warning("aethone: %s is missing — close will quit directly",
              TrayIconFile());
  } else {
    const gint edge = 24;  // the standard tray edge size
    GdkPixbuf* scaled =
        gdk_pixbuf_scale_simple(full, edge, edge, GDK_INTERP_BILINEAR);
    g_object_unref(full);
    g_tray.icon = gtk_status_icon_new_from_pixbuf(scaled);
    g_object_unref(scaled);
    gtk_status_icon_set_title(g_tray.icon, "AETHONE");
    gtk_status_icon_set_tooltip_text(g_tray.icon, "AETHONE");
    g_signal_connect(g_tray.icon, "activate", G_CALLBACK(OnTrayActivate),
                     nullptr);
    g_signal_connect(g_tray.icon, "popup-menu", G_CALLBACK(OnTrayPopup),
                     nullptr);
  }

  g_signal_connect(window, "delete-event", G_CALLBACK(OnWindowDelete),
                   nullptr);
}

void SetTrayEventSink(TrayEventSink sink) { g_tray_sink = sink; }

bool HideToTrayFromDart() {
  if (!g_tray.tray_usable || g_tray.window == nullptr) return false;
  gtk_widget_hide(GTK_WIDGET(g_tray.window));
  if (g_tray.embed_timer == 0) {
    g_tray.embed_timer =
        g_timeout_add_seconds(3, EmbedCheckTimeout, nullptr);
  }
  return true;
}

void QuitFromDart() { QuitFromTray(); }

}  // namespace aethone

#pragma GCC diagnostic pop
