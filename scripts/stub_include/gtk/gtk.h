// gtk/gtk.h — the signature-faithful GTK3/gdk-pixbuf stub for the v4.39
// local syntax gate (scripts/syntax_check_linux_runner.sh). This sandbox
// has real glib-2.0/gio-2.0/gobject dev headers but no GTK dev package:
// everything glib/gobject comes from the REAL system headers pulled in
// below; only the widget/pixbuf surface tray_controller_linux.cc touches
// is mirrored here, declaration-for-declaration as gtk3 pins them.
#pragma once

#include <glib-object.h>  // real: gboolean/guint/gulong/gpointer/GCallback/
                          // g_signal_connect*/g_object_unref/g_error_free

typedef struct _GtkWidget GtkWidget;
typedef struct _GtkWindow GtkWindow;
typedef struct _GtkStatusIcon GtkStatusIcon;
typedef struct _GtkMenu GtkMenu;
typedef struct _GtkMenuItem GtkMenuItem;
typedef struct _GtkMenuShell GtkMenuShell;
typedef struct _GdkPixbuf GdkPixbuf;
typedef struct _GdkEvent GdkEvent;

typedef enum {
  GDK_GRAVITY_NORTH_WEST = 1,
  GDK_GRAVITY_SOUTH_WEST,
} GdkGravity;

typedef enum {
  GDK_INTERP_NEAREST,
  GDK_INTERP_TILES,
  GDK_INTERP_BILINEAR,
  GDK_INTERP_HYPER,
} GdkInterpType;

#define GTK_WIDGET(x) ((GtkWidget*)(x))
#define GTK_WINDOW(x) ((GtkWindow*)(x))
#define GTK_MENU(x) ((GtkMenu*)(x))
#define GTK_MENU_SHELL(x) ((GtkMenuShell*)(x))

GtkStatusIcon* gtk_status_icon_new_from_pixbuf(GdkPixbuf* pixbuf);
void gtk_status_icon_set_title(GtkStatusIcon* icon, const gchar* title);
void gtk_status_icon_set_tooltip_text(GtkStatusIcon* icon, const gchar* text);
gboolean gtk_status_icon_is_embedded(GtkStatusIcon* icon);

void gtk_widget_show(GtkWidget* widget);
void gtk_widget_hide(GtkWidget* widget);
void gtk_widget_destroy(GtkWidget* widget);
void gtk_widget_show_all(GtkWidget* widget);

void gtk_window_present(GtkWindow* window);
void gtk_window_deiconify(GtkWindow* window);
void gtk_window_set_icon_from_file(GtkWindow* window, const gchar* filename,
                                    GError** err);

GtkWidget* gtk_menu_new(void);
GtkWidget* gtk_menu_item_new_with_label(const gchar* label);
void gtk_menu_shell_append(GtkMenuShell* shell, GtkWidget* child);
void gtk_menu_popup_at_widget(GtkMenu* menu, GtkWidget* widget,
                               GdkGravity widget_anchor,
                               GdkGravity menu_anchor,
                               const GdkEvent* trigger_event);

// gdk-pixbuf (the tray face is loaded + scaled from the bundle PNG).
GdkPixbuf* gdk_pixbuf_new_from_file(const char* filename, GError** error);
GdkPixbuf* gdk_pixbuf_scale_simple(const GdkPixbuf* src, int dest_width,
                                   int dest_height, GdkInterpType interp);
