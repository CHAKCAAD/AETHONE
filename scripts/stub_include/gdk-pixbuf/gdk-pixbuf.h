// gdk-pixbuf/gdk-pixbuf.h — v4.39 stub include shim: everything the tray
// controller needs from gdk-pixbuf already lives in the gtk/gtk.h stub
// (same gate tree, scripts/stub_include). This shim only exists so the
// real-world include chain
//   #include <gdk-pixbuf/gdk-pixbuf.h>
// resolves inside the stub tree too.
#pragma once

#include "gtk/gtk.h"
