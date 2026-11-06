// flutter_linux.h — SYNTAX-CHECK STUB (not shipped; local verification only).
// Mirrors the Fl* API surface of the pinned flutter_linux.h (Flutter 3.47.9,
// linux/flutter/ephemeral) signature-for-signature, so a g++ -fsyntax-only
// pass of linux/runner/engine_channel_linux.cc catches every name-resolution,
// overload, hiding and type error the real header would. The GObject type
// macros (G_DECLARE_*) reproduce the real header's cast macros and autoptr
// support; FlValue keeps its real, non-GObject refcounted shape.
#pragma once

#include <glib-object.h>
#include <gio/gio.h>

G_BEGIN_DECLS

// ---- fl_value.h (FlValue is NOT a GObject) -------------------------------
typedef struct _FlValue FlValue;

typedef enum {
  FL_VALUE_TYPE_NULL,
  FL_VALUE_TYPE_BOOL,
  FL_VALUE_TYPE_INT,
  FL_VALUE_TYPE_INT32,
  FL_VALUE_TYPE_INT64,
  FL_VALUE_TYPE_FLOAT32,
  FL_VALUE_TYPE_FLOAT,
  FL_VALUE_TYPE_STRING,
  FL_VALUE_TYPE_UINT8_LIST,
  FL_VALUE_TYPE_INT32_LIST,
  FL_VALUE_TYPE_INT64_LIST,
  FL_VALUE_TYPE_FLOAT32_LIST,
  FL_VALUE_TYPE_FLOAT_LIST,
  FL_VALUE_TYPE_LIST,
  FL_VALUE_TYPE_MAP,
  FL_VALUE_TYPE_CUSTOM_CODEC,
} FlValueType;

FlValue* fl_value_ref(FlValue* value);
void fl_value_unref(FlValue* value);
FlValue* fl_value_new_null(void);
FlValue* fl_value_new_bool(bool value);
FlValue* fl_value_new_int(int64_t value);
FlValue* fl_value_new_string(const char* value);
FlValue* fl_value_new_map(void);
FlValueType fl_value_get_type(FlValue* self);
bool fl_value_get_bool(FlValue* self);
int64_t fl_value_get_int(FlValue* self);
const char* fl_value_get_string(FlValue* self);
FlValue* fl_value_lookup_string(FlValue* self, const char* key);
void fl_value_set_string_take(FlValue* self, const char* key, FlValue* value);

G_DEFINE_AUTOPTR_CLEANUP_FUNC(FlValue, fl_value_unref)

// ---- fl_binary_messenger.h -----------------------------------------------
G_DECLARE_INTERFACE(FlBinaryMessenger, fl_binary_messenger, FL,
                    BINARY_MESSENGER, GObject)

// ---- fl_method_codec.h ----------------------------------------------------
G_DECLARE_INTERFACE(FlMethodCodec, fl_method_codec, FL, METHOD_CODEC, GObject)

// ---- fl_method_response.h -------------------------------------------------
G_DECLARE_DERIVABLE_TYPE(FlMethodResponse, fl_method_response, FL,
                         METHOD_RESPONSE, GObject)
// the derivable-type contract: the class struct body follows the macro
// (G_DECLARE_DERIVABLE_TYPE only forward-declares it; the FINAL subclasses
// below embed it as parent_class and need it complete).
struct _FlMethodResponseClass {
  GObjectClass parent_class;
};

G_DECLARE_FINAL_TYPE(FlMethodSuccessResponse, fl_method_success_response, FL,
                     METHOD_SUCCESS_RESPONSE, FlMethodResponse)
G_DECLARE_FINAL_TYPE(FlMethodErrorResponse, fl_method_error_response, FL,
                     METHOD_ERROR_RESPONSE, FlMethodResponse)
G_DECLARE_FINAL_TYPE(FlMethodNotImplementedResponse,
                     fl_method_not_implemented_response, FL,
                     METHOD_NOT_IMPLEMENTED_RESPONSE, FlMethodResponse)

FlMethodSuccessResponse* fl_method_success_response_new(FlValue* result);
FlMethodErrorResponse* fl_method_error_response_new(const gchar* code,
                                                    const gchar* message,
                                                    FlValue* details);
FlMethodNotImplementedResponse* fl_method_not_implemented_response_new(void);

// ---- fl_method_call.h ------------------------------------------------------
G_DECLARE_FINAL_TYPE(FlMethodCall, fl_method_call, FL, METHOD_CALL, GObject)

const gchar* fl_method_call_get_name(FlMethodCall* self);
FlValue* fl_method_call_get_args(FlMethodCall* self);
gboolean fl_method_call_respond(FlMethodCall* self,
                                FlMethodResponse* response, GError** error);

// ---- fl_method_channel.h ---------------------------------------------------
G_DECLARE_FINAL_TYPE(FlMethodChannel, fl_method_channel, FL, METHOD_CHANNEL,
                     GObject)

typedef void (*FlMethodCallHandler)(FlMethodChannel* channel,
                                    FlMethodCall* call, gpointer user_data);

FlMethodChannel* fl_method_channel_new(FlBinaryMessenger* messenger,
                                       const gchar* name,
                                       FlMethodCodec* codec);
void fl_method_channel_set_method_call_handler(
    FlMethodChannel* self, FlMethodCallHandler handler, gpointer user_data,
    GDestroyNotify destroy_notify);
void fl_method_channel_invoke_method(FlMethodChannel* self,
                                     const gchar* method, FlValue* args,
                                     GCancellable* cancellable,
                                     GAsyncReadyCallback callback,
                                     gpointer user_data);

// ---- fl_standard_method_codec.h ---------------------------------------------
G_DECLARE_FINAL_TYPE(FlStandardMethodCodec, fl_standard_method_codec, FL,
                     STANDARD_METHOD_CODEC, GObject)

FlStandardMethodCodec* fl_standard_method_codec_new(void);

// ---- fl_engine.h --------------------------------------------------------------
G_DECLARE_FINAL_TYPE(FlEngine, fl_engine, FL, ENGINE, GObject)

FlBinaryMessenger* fl_engine_get_binary_messenger(FlEngine* self);

G_END_DECLS
