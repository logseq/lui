/* Desktop shell transport for lui_shell_linux on Linux.

   The OCaml side owns all semantics; this file only carries values to
   and from the platform. Platform libraries are resolved at runtime
   with dlopen/dlsym so the stub links and runs without dev headers:

     libdbus-1                session bus — notifications, the launcher
                              entry, org.freedesktop.Application open-url
     libglib-2.0/libgobject   main-context iteration, signal connect
     libgio-2.0               g_app_info_launch_default_for_uri
     libgdk-3/libgtk-3        clipboard, file dialogs, tray menus
     libayatana-appindicator3 StatusNotifier status items
     (libappindicator3)       (older name, tried second)

   Probing is lazy and cached: lui_shx_probe returns a capability
   bitmask — 1 session bus connected, 2 GTK bound with a display, 4
   indicator library bound. Anything a capability does not cover
   degrades to false/NULL/-1 instead of failing.

   Events never call back into OCaml from C: the transport queues
   (kind, iarg, sarg) triples and lui_shx_pump drains them; the OCaml
   side translates and dispatches. GTK callbacks and the D-Bus object
   vtable all run inside pump (or a nested dialog loop) on the calling
   thread, so queuing is always safe. */

#if defined(__linux__)

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <dlfcn.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/custom.h>
#include <caml/callback.h>
#include <caml/misc.h>

/* ---- Minimal libdbus declarations (no headers required) ---- */

typedef struct DBusConnection DBusConnection;
typedef struct DBusMessage DBusMessage;
typedef struct DBusMessageIter DBusMessageIter;

typedef struct {
  const char *name;
  const char *message;
  unsigned int dummy1 : 1;
  unsigned int dummy2 : 1;
  unsigned int dummy3 : 1;
  unsigned int dummy4 : 1;
  unsigned int dummy5 : 1;
  unsigned int padding1 : 1;
  void *padding2;
} DBusError;

struct DBusMessageIter {
  void *dummy1;
  void *dummy2;
  unsigned int dummy3;
  int dummy4;
  int dummy5;
  int dummy6;
  int dummy7;
  int dummy8;
  int dummy9;
  int dummy10;
  int dummy11;
  int pad1;
  int pad2;
  void *pad3;
};

#define DBUS_TYPE_INVALID      0
#define DBUS_TYPE_BOOLEAN      ((int) 'b')
#define DBUS_TYPE_INT32        ((int) 'i')
#define DBUS_TYPE_UINT32       ((int) 'u')
#define DBUS_TYPE_DOUBLE       ((int) 'd')
#define DBUS_TYPE_STRING       ((int) 's')
#define DBUS_TYPE_OBJECT_PATH  ((int) 'o')
#define DBUS_TYPE_SIGNATURE    ((int) 'g')
#define DBUS_TYPE_ARRAY        ((int) 'a')
#define DBUS_TYPE_VARIANT      ((int) 'v')
#define DBUS_TYPE_STRUCT       ((int) 'r')
#define DBUS_TYPE_DICT_ENTRY   ((int) 'e')

#define DBUS_MESSAGE_TYPE_METHOD_CALL   1
#define DBUS_MESSAGE_TYPE_METHOD_RETURN 2
#define DBUS_MESSAGE_TYPE_ERROR         3
#define DBUS_MESSAGE_TYPE_SIGNAL        4

#define DBUS_HANDLER_RESULT_HANDLED         0
#define DBUS_HANDLER_RESULT_NOT_YET_HANDLED 1

typedef int dbus_bool_t;
typedef unsigned int dbus_uint32_t;
typedef int dbus_int32_t;
typedef unsigned char dbus_bool_wire_t;

typedef int (*DBusObjectPathMessageFunction)(DBusConnection *,
                                             DBusMessage *, void *);
typedef void (*DBusObjectPathUnregisterFunction)(DBusConnection *,
                                                 void *);

typedef struct {
  DBusObjectPathUnregisterFunction unregister_function;
  DBusObjectPathMessageFunction message_function;
  void (*internal_pad1)(void *);
  void (*internal_pad2)(void *);
  void (*internal_pad3)(void *);
  void (*internal_pad4)(void *);
  void *pad1;
  void *pad2;
  void *pad3;
  void *pad4;
} DBusObjectPathVTable;

static DBusConnection *(*p_dbus_connection_open)(const char *,
                                                 DBusError *) = 0;
static dbus_bool_t (*p_dbus_bus_register)(DBusConnection *,
                                          DBusError *) = 0;
static void (*p_dbus_connection_unref)(DBusConnection *) = 0;
static void (*p_dbus_connection_set_exit_on_disconnect)(DBusConnection *,
                                                      dbus_bool_t) = 0;
static dbus_bool_t (*p_dbus_connection_send)(DBusConnection *,
                                             DBusMessage *,
                                             dbus_uint32_t *) = 0;
static void (*p_dbus_connection_flush)(DBusConnection *) = 0;
static dbus_bool_t (*p_dbus_connection_read_write_dispatch)(
    DBusConnection *, int) = 0;
static DBusMessage *(*p_dbus_connection_pop_message)(
    DBusConnection *) = 0;
static DBusMessage *(*p_dbus_connection_send_with_reply_and_block)(
    DBusConnection *, DBusMessage *, int, DBusError *) = 0;
static dbus_bool_t (*p_dbus_connection_register_object_path)(
    DBusConnection *, const char *, const DBusObjectPathVTable *,
    void *) = 0;
static void (*p_dbus_connection_unregister_object_path)(
    DBusConnection *, const char *) = 0;
static dbus_bool_t (*p_dbus_bus_add_match)(DBusConnection *,
                                           const char *, DBusError *) = 0;
static dbus_uint32_t (*p_dbus_bus_request_name)(DBusConnection *,
                                                const char *,
                                                unsigned int,
                                                DBusError *) = 0;
static DBusMessage *(*p_dbus_message_new_method_call)(const char *,
                                                    const char *,
                                                    const char *,
                                                    const char *) = 0;
static DBusMessage *(*p_dbus_message_new_signal)(const char *,
                                               const char *,
                                               const char *) = 0;
static DBusMessage *(*p_dbus_message_new_method_return)(
    DBusMessage *) = 0;
static void (*p_dbus_message_unref)(DBusMessage *) = 0;
static int (*p_dbus_message_get_type)(DBusMessage *) = 0;
static const char *(*p_dbus_message_get_interface)(DBusMessage *) = 0;
static const char *(*p_dbus_message_get_member)(DBusMessage *) = 0;
static dbus_bool_t (*p_dbus_message_iter_init)(DBusMessage *,
                                             DBusMessageIter *) = 0;
static int (*p_dbus_message_iter_get_arg_type)(
    DBusMessageIter *) = 0;
static void (*p_dbus_message_iter_get_basic)(DBusMessageIter *,
                                             void *) = 0;
static dbus_bool_t (*p_dbus_message_iter_next)(DBusMessageIter *) = 0;
static void (*p_dbus_message_iter_recurse)(DBusMessageIter *,
                                           DBusMessageIter *) = 0;
static void (*p_dbus_message_iter_init_append)(DBusMessage *,
                                              DBusMessageIter *) = 0;
static dbus_bool_t (*p_dbus_message_iter_append_basic)(
    DBusMessageIter *, int, const void *) = 0;
static dbus_bool_t (*p_dbus_message_iter_open_container)(
    DBusMessageIter *, int, const char *, DBusMessageIter *) = 0;
static dbus_bool_t (*p_dbus_message_iter_close_container)(
    DBusMessageIter *, DBusMessageIter *) = 0;
static void (*p_dbus_error_init)(DBusError *) = 0;
static void (*p_dbus_error_free)(DBusError *) = 0;
static dbus_bool_t (*p_dbus_error_is_set)(const DBusError *) = 0;

/* ---- Minimal glib/gobject/gio declarations ---- */

typedef struct _GSList { void *data; struct _GSList *next; } GSList;
typedef struct { int domain; int code; char *message; } GError;

static void (*p_g_free)(void *) = 0;
static void (*p_g_slist_free)(GSList *) = 0;
static int (*p_g_main_context_iteration)(void *, int) = 0;
static void (*p_g_object_unref)(void *) = 0;
static void *(*p_g_object_ref_sink)(void *) = 0;
static unsigned long (*p_g_signal_connect_data)(void *, const char *,
                                                void *, void *, void *,
                                                int) = 0;
static void (*p_g_error_free)(GError *) = 0;
static int (*p_g_app_info_launch_default_for_uri)(const char *, void *,
                                                  GError **) = 0;

/* ---- Minimal gtk/gdk declarations ---- */

static int (*p_gtk_init_check)(int *, char ***) = 0;
static void *(*p_gdk_atom_intern)(const char *, int) = 0;
static void *(*p_gtk_clipboard_get)(void *) = 0;
static void (*p_gtk_clipboard_set_text)(void *, const char *, int) = 0;
static char *(*p_gtk_clipboard_wait_for_text)(void *) = 0;
static void (*p_gtk_clipboard_clear)(void *) = 0;
static void *(*p_gtk_file_chooser_native_new)(const char *, void *,
                                              int, const char *,
                                              const char *) = 0;
static int (*p_gtk_native_dialog_run)(void *) = 0;
static void (*p_gtk_native_dialog_destroy)(void *) = 0;
static void (*p_gtk_file_chooser_set_select_multiple)(void *, int) = 0;
static void (*p_gtk_file_chooser_set_current_name)(void *,
                                                   const char *) = 0;
static void (*p_gtk_file_chooser_set_do_overwrite_confirmation)(void *,
                                                                int) = 0;
static void (*p_gtk_file_chooser_add_filter)(void *, void *) = 0;
static char *(*p_gtk_file_chooser_get_filename)(void *) = 0;
static GSList *(*p_gtk_file_chooser_get_filenames)(void *) = 0;
static void *(*p_gtk_file_filter_new)(void) = 0;
static void (*p_gtk_file_filter_set_name)(void *, const char *) = 0;
static void (*p_gtk_file_filter_add_pattern)(void *, const char *) = 0;
static void *(*p_gtk_menu_new)(void) = 0;
static void *(*p_gtk_menu_item_new_with_label)(const char *) = 0;
static void *(*p_gtk_check_menu_item_new_with_label)(const char *) = 0;
static void *(*p_gtk_separator_menu_item_new)(void) = 0;
static void (*p_gtk_menu_item_set_submenu)(void *, void *) = 0;
static void (*p_gtk_menu_shell_append)(void *, void *) = 0;
static void (*p_gtk_widget_set_sensitive)(void *, int) = 0;
static void (*p_gtk_check_menu_item_set_active)(void *, int) = 0;
static void (*p_gtk_widget_show_all)(void *) = 0;

/* ---- Minimal appindicator declarations ---- */

static void *(*p_app_indicator_new)(const char *, const char *,
                                    int) = 0;
static void (*p_app_indicator_set_status)(void *, int) = 0;
static void (*p_app_indicator_set_menu)(void *, void *) = 0;
static void (*p_app_indicator_set_icon_full)(void *, const char *,
                                             const char *) = 0;
static void (*p_app_indicator_set_icon_theme_path)(void *,
                                                   const char *) = 0;
static void (*p_app_indicator_set_title)(void *, const char *) = 0;
static void (*p_app_indicator_set_label)(void *, const char *,
                                         const char *) = 0;
static void (*p_app_indicator_set_secondary_activate_target)(void *,
                                                             void *) = 0;

/* ---- dlopen plumbing ---- */

static int sym(void *h, const char *name, void **out)
{
  *out = dlsym(h, name);
  return *out != 0;
}

static int cap_bits = 0;   /* 1 session bus, 2 gui, 4 indicator lib */
static int did_probe = 0;
static DBusConnection *session = 0;
static int gtk_ready = 0;
static int clip_watch = 0;
static long clip_generation = 0;
static char openurl_path[256];

/* ---- Event queue: (kind, iarg, sarg) drained by lui_shx_pump ---- */

#define EV_NOTIFY_INVOKED 0
#define EV_NOTIFY_CLOSED  1
#define EV_OPEN_URL       2
#define EV_MENU_SELECT    3
#define EV_STATUS_CLICK   4

#define EV_MAX 256

typedef struct {
  int kind;
  int iarg;
  char *sarg;
} ev_t;

static ev_t ev_queue[EV_MAX];
static int ev_head = 0, ev_len = 0;

static void ev_push(int kind, int iarg, const char *sarg)
{
  ev_t *e;
  if (ev_len == EV_MAX) {
    /* Queue full: drop the oldest so newer events still land. */
    free(ev_queue[ev_head].sarg);
    ev_head = (ev_head + 1) % EV_MAX;
    ev_len--;
  }
  e = &ev_queue[(ev_head + ev_len) % EV_MAX];
  e->kind = kind;
  e->iarg = iarg;
  e->sarg = sarg != NULL ? strdup(sarg) : NULL;
  ev_len++;
}

/* ---- D-Bus helpers ---- */

/* Append a {sv} dictionary entry (key -> variant-of-basic) to an
   array iterator opened on a{sv}. */
static void dict_add_sv(DBusMessageIter *arr, const char *key, int ty,
                        const void *val)
{
  DBusMessageIter ent, var;
  p_dbus_message_iter_open_container(arr, DBUS_TYPE_DICT_ENTRY, 0,
                                     &ent);
  p_dbus_message_iter_append_basic(&ent, DBUS_TYPE_STRING, &key);
  {
    char sig[2] = { (char) ty, 0 };
    p_dbus_message_iter_open_container(&ent, DBUS_TYPE_VARIANT, sig,
                                       &var);
    p_dbus_message_iter_append_basic(&var, ty, val);
    p_dbus_message_iter_close_container(&ent, &var);
  }
  p_dbus_message_iter_close_container(arr, &ent);
}

/* A blocking call that returns the reply message or NULL. */
static DBusMessage *bus_call(DBusMessage *call, DBusError *err)
{
  DBusMessage *rep;
  if (session == 0 || call == 0) return 0;
  p_dbus_error_init(err);
  rep = p_dbus_connection_send_with_reply_and_block(session, call,
                                                    3000, err);
  p_dbus_message_unref(call);
  return rep;
}

/* org.freedesktop.Application handler: Open forwards every URI to the
   open-url event; Activate/ActivateAction just answer. Runs inside
   read_write_dispatch on the calling thread. */
static int lui_app_path_call(DBusConnection *conn, DBusMessage *msg,
                             void *data)
{
  const char *member = p_dbus_message_get_member(msg);
  DBusMessage *reply;
  (void) data;
  if (member != 0 && strcmp(member, "Open") == 0) {
    DBusMessageIter it, sub;
    if (p_dbus_message_iter_init(msg, &it)
        && p_dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_ARRAY) {
      p_dbus_message_iter_recurse(&it, &sub);
      do {
        if (p_dbus_message_iter_get_arg_type(&sub)
            == DBUS_TYPE_STRING) {
          const char *uri = "";
          p_dbus_message_iter_get_basic(&sub, &uri);
          ev_push(EV_OPEN_URL, 0, uri);
        }
      } while (p_dbus_message_iter_next(&sub));
    }
    reply = p_dbus_message_new_method_return(msg);
    if (reply != 0) {
      p_dbus_connection_send(conn, reply, 0);
      p_dbus_message_unref(reply);
      p_dbus_connection_flush(conn);
    }
    return DBUS_HANDLER_RESULT_HANDLED;
  }
  if (member != 0 && (strcmp(member, "Activate") == 0
                      || strcmp(member, "ActivateAction") == 0)) {
    reply = p_dbus_message_new_method_return(msg);
    if (reply != 0) {
      p_dbus_connection_send(conn, reply, 0);
      p_dbus_message_unref(reply);
      p_dbus_connection_flush(conn);
    }
    return DBUS_HANDLER_RESULT_HANDLED;
  }
  return DBUS_HANDLER_RESULT_NOT_YET_HANDLED;
}

static DBusObjectPathVTable lui_app_vtable = {
  0, lui_app_path_call, 0, 0, 0, 0, 0, 0, 0, 0
};

/* Drain queued signal messages the bus delivered; method calls on the
   registered object path already ran inside read_write_dispatch. */
static void drain_signals(void)
{
  DBusMessage *m;
  if (session == 0) return;
  while ((m = p_dbus_connection_pop_message(session)) != 0) {
    const char *iface = p_dbus_message_get_interface(m);
    const char *member = p_dbus_message_get_member(m);
    if (p_dbus_message_get_type(m) == DBUS_MESSAGE_TYPE_SIGNAL
        && iface != 0
        && strcmp(iface, "org.freedesktop.Notifications") == 0
        && member != 0) {
      DBusMessageIter it;
      dbus_uint32_t id = 0;
      if (p_dbus_message_iter_init(m, &it)
          && p_dbus_message_iter_get_arg_type(&it)
                 == DBUS_TYPE_UINT32)
        p_dbus_message_iter_get_basic(&it, &id);
      if (strcmp(member, "ActionInvoked") == 0)
        ev_push(EV_NOTIFY_INVOKED, (int) id, "");
      else if (strcmp(member, "NotificationClosed") == 0)
        ev_push(EV_NOTIFY_CLOSED, (int) id, "");
    }
    p_dbus_message_unref(m);
  }
}

/* ---- GTK helpers ---- */

static void on_clip_owner_change(void *board, void *event, void *data)
{
  (void) board; (void) event; (void) data;
  clip_generation++;
}

static void on_menu_activate(void *item, void *data)
{
  (void) item;
  ev_push(EV_MENU_SELECT, (int) (intptr_t) data, "");
}

static void on_status_click(void *item, void *data)
{
  (void) item;
  ev_push(EV_STATUS_CLICK, (int) (intptr_t) data, "");
}

static void *clip_board(void)
{
  static void *atom = 0;
  void *board;
  if (!gtk_ready) return 0;
  if (atom == 0) atom = p_gdk_atom_intern("CLIPBOARD", 0);
  board = p_gtk_clipboard_get(atom);
  if (board != 0 && !clip_watch) {
    clip_watch = 1;
    p_g_signal_connect_data(board, "owner-change",
                            (void *) on_clip_owner_change, 0, 0, 0);
  }
  return board;
}

/* Rows from the OCaml side: (depth, kind, label, id, enabled, checked)
   with kind 0 item, 1 separator, 2 submenu; a submenu's children
   follow it at depth+1. Returns a GtkMenu the caller sinks. */
static void *lui_menu_build(value rows)
{
  void *root = p_gtk_menu_new();
  void *stack[32];
  int top = 0;
  mlsize_t n = Wosize_val(rows);
  mlsize_t i;
  stack[0] = root;
  for (i = 0; i < n; i++) {
    value row = Field(rows, i);
    int depth = Int_val(Field(row, 0));
    int kind = Int_val(Field(row, 1));
    int ident = Int_val(Field(row, 3));
    int enabled = Int_val(Field(row, 4));
    int checked = Int_val(Field(row, 5));
    void *parent;
    if (depth < 0 || depth >= 31) continue;
    while (top > depth) top--;
    if (top != depth) continue;
    parent = stack[top];
    if (kind == 1) {
      p_gtk_menu_shell_append(parent,
                              p_gtk_separator_menu_item_new());
    } else if (kind == 2) {
      char *label = caml_stat_strdup(String_val(Field(row, 2)));
      void *sub = p_gtk_menu_new();
      void *mi = p_gtk_menu_item_new_with_label(label);
      caml_stat_free(label);
      p_gtk_widget_set_sensitive(mi, enabled);
      p_gtk_menu_item_set_submenu(mi, sub);
      p_gtk_menu_shell_append(parent, mi);
      stack[++top] = sub;
    } else {
      char *label = caml_stat_strdup(String_val(Field(row, 2)));
      void *mi = checked
        ? p_gtk_check_menu_item_new_with_label(label)
        : p_gtk_menu_item_new_with_label(label);
      caml_stat_free(label);
      p_gtk_widget_set_sensitive(mi, enabled);
      if (checked) p_gtk_check_menu_item_set_active(mi, 1);
      p_g_signal_connect_data(mi, "activate",
                              (void *) on_menu_activate,
                              (void *) (intptr_t) ident, 0, 0);
      p_gtk_menu_shell_append(parent, mi);
    }
  }
  return root;
}

/* ---- Status item custom block ---- */

typedef struct {
  void *ind;          /* AppIndicator*, NULL when inert */
  void *menu;         /* GtkMenu* (our ref) or NULL */
  void *click_item;   /* GtkMenuItem* for secondary activate */
  int tag;
} si_t;

#define Lui_si_val(v) (*(si_t **)Data_custom_val(v))

static void si_drop_menu(si_t *s)
{
  if (s == 0) return;
  if (s->menu != 0) {
    p_g_object_unref(s->menu);
    s->menu = 0;
  }
  if (s->click_item != 0) {
    p_g_object_unref(s->click_item);
    s->click_item = 0;
  }
}

static void lui_si_finalize(value v)
{
  si_t *s = Lui_si_val(v);
  if (s == 0) return;
  if (s->ind != 0 && gtk_ready) {
    p_app_indicator_set_status(s->ind, 0); /* PASSIVE */
    p_g_object_unref(s->ind);
  }
  si_drop_menu(s);
  free(s);
  Lui_si_val(v) = 0;
}

static struct custom_operations lui_si_ops = {
  "lui_shell_linux.status_item",
  lui_si_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

/* Per-app icon dir the theme-path lookups read from. */
static const char *icon_dir(void)
{
  static char dir[512];
  const char *base;
  if (dir[0] != 0) return dir;
  base = getenv("XDG_CACHE_HOME");
  if (base == 0 || base[0] == 0) {
    const char *home = getenv("HOME");
    if (home == 0) home = "/tmp";
    snprintf(dir, sizeof(dir), "%s/.cache", home);
  } else {
    snprintf(dir, sizeof(dir), "%s", base);
  }
  mkdir(dir, 0755);
  {
    char sub[600];
    snprintf(sub, sizeof(sub), "%s/lui-icons-%d", dir,
             (int) getpid());
    memcpy(dir, sub, strlen(sub) + 1);
  }
  mkdir(dir, 0755);
  return dir;
}

/* ---- Probe ---- */

static int probe_dbus(void)
{
  void *h = dlopen("libdbus-1.so.3", RTLD_NOW | RTLD_GLOBAL);
  int ok = 1;
  if (h == 0) return 0;
  ok &= sym(h, "dbus_connection_open",
            (void **) &p_dbus_connection_open);
  ok &= sym(h, "dbus_bus_register", (void **) &p_dbus_bus_register);
  ok &= sym(h, "dbus_connection_unref",
            (void **) &p_dbus_connection_unref);
  ok &= sym(h, "dbus_connection_set_exit_on_disconnect",
            (void **) &p_dbus_connection_set_exit_on_disconnect);
  ok &= sym(h, "dbus_connection_send",
            (void **) &p_dbus_connection_send);
  ok &= sym(h, "dbus_connection_flush",
            (void **) &p_dbus_connection_flush);
  ok &= sym(h, "dbus_connection_read_write_dispatch",
            (void **) &p_dbus_connection_read_write_dispatch);
  ok &= sym(h, "dbus_connection_pop_message",
            (void **) &p_dbus_connection_pop_message);
  ok &= sym(h, "dbus_connection_send_with_reply_and_block",
            (void **) &p_dbus_connection_send_with_reply_and_block);
  ok &= sym(h, "dbus_connection_register_object_path",
            (void **) &p_dbus_connection_register_object_path);
  ok &= sym(h, "dbus_connection_unregister_object_path",
            (void **) &p_dbus_connection_unregister_object_path);
  ok &= sym(h, "dbus_bus_add_match",
            (void **) &p_dbus_bus_add_match);
  ok &= sym(h, "dbus_bus_request_name",
            (void **) &p_dbus_bus_request_name);
  ok &= sym(h, "dbus_message_new_method_call",
            (void **) &p_dbus_message_new_method_call);
  ok &= sym(h, "dbus_message_new_signal",
            (void **) &p_dbus_message_new_signal);
  ok &= sym(h, "dbus_message_new_method_return",
            (void **) &p_dbus_message_new_method_return);
  ok &= sym(h, "dbus_message_unref", (void **) &p_dbus_message_unref);
  ok &= sym(h, "dbus_message_get_type",
            (void **) &p_dbus_message_get_type);
  ok &= sym(h, "dbus_message_get_interface",
            (void **) &p_dbus_message_get_interface);
  ok &= sym(h, "dbus_message_get_member",
            (void **) &p_dbus_message_get_member);
  ok &= sym(h, "dbus_message_iter_init",
            (void **) &p_dbus_message_iter_init);
  ok &= sym(h, "dbus_message_iter_get_arg_type",
            (void **) &p_dbus_message_iter_get_arg_type);
  ok &= sym(h, "dbus_message_iter_get_basic",
            (void **) &p_dbus_message_iter_get_basic);
  ok &= sym(h, "dbus_message_iter_next",
            (void **) &p_dbus_message_iter_next);
  ok &= sym(h, "dbus_message_iter_recurse",
            (void **) &p_dbus_message_iter_recurse);
  ok &= sym(h, "dbus_message_iter_init_append",
            (void **) &p_dbus_message_iter_init_append);
  ok &= sym(h, "dbus_message_iter_append_basic",
            (void **) &p_dbus_message_iter_append_basic);
  ok &= sym(h, "dbus_message_iter_open_container",
            (void **) &p_dbus_message_iter_open_container);
  ok &= sym(h, "dbus_message_iter_close_container",
            (void **) &p_dbus_message_iter_close_container);
  ok &= sym(h, "dbus_error_init", (void **) &p_dbus_error_init);
  ok &= sym(h, "dbus_error_free", (void **) &p_dbus_error_free);
  ok &= sym(h, "dbus_error_is_set", (void **) &p_dbus_error_is_set);
  return ok;
}

static int probe_glib(void)
{
  void *h;
  int ok = 1;
  h = dlopen("libglib-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (h == 0) return 0;
  ok &= sym(h, "g_free", (void **) &p_g_free);
  ok &= sym(h, "g_slist_free", (void **) &p_g_slist_free);
  ok &= sym(h, "g_main_context_iteration",
            (void **) &p_g_main_context_iteration);
  ok &= sym(h, "g_error_free", (void **) &p_g_error_free);
  if (!ok) return 0;
  h = dlopen("libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (h == 0) return 0;
  ok &= sym(h, "g_object_unref", (void **) &p_g_object_unref);
  ok &= sym(h, "g_object_ref_sink", (void **) &p_g_object_ref_sink);
  ok &= sym(h, "g_signal_connect_data",
            (void **) &p_g_signal_connect_data);
  if (!ok) return 0;
  h = dlopen("libgio-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (h != 0)
    sym(h, "g_app_info_launch_default_for_uri",
        (void **) &p_g_app_info_launch_default_for_uri);
  return 1;
}

static int probe_gtk(void)
{
  void *h;
  int ok = 1;
  h = dlopen("libgdk-3.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (h == 0) return 0;
  ok &= sym(h, "gdk_atom_intern", (void **) &p_gdk_atom_intern);
  h = dlopen("libgtk-3.so.0", RTLD_NOW | RTLD_GLOBAL);
  if (h == 0) return 0;
  ok &= sym(h, "gtk_init_check", (void **) &p_gtk_init_check);
  ok &= sym(h, "gtk_clipboard_get", (void **) &p_gtk_clipboard_get);
  ok &= sym(h, "gtk_clipboard_set_text",
            (void **) &p_gtk_clipboard_set_text);
  ok &= sym(h, "gtk_clipboard_wait_for_text",
            (void **) &p_gtk_clipboard_wait_for_text);
  ok &= sym(h, "gtk_clipboard_clear",
            (void **) &p_gtk_clipboard_clear);
  ok &= sym(h, "gtk_file_chooser_native_new",
            (void **) &p_gtk_file_chooser_native_new);
  ok &= sym(h, "gtk_native_dialog_run",
            (void **) &p_gtk_native_dialog_run);
  ok &= sym(h, "gtk_native_dialog_destroy",
            (void **) &p_gtk_native_dialog_destroy);
  ok &= sym(h, "gtk_file_chooser_set_select_multiple",
            (void **) &p_gtk_file_chooser_set_select_multiple);
  ok &= sym(h, "gtk_file_chooser_set_current_name",
            (void **) &p_gtk_file_chooser_set_current_name);
  ok &= sym(h, "gtk_file_chooser_set_do_overwrite_confirmation",
            (void **) &p_gtk_file_chooser_set_do_overwrite_confirmation);
  ok &= sym(h, "gtk_file_chooser_add_filter",
            (void **) &p_gtk_file_chooser_add_filter);
  ok &= sym(h, "gtk_file_chooser_get_filename",
            (void **) &p_gtk_file_chooser_get_filename);
  ok &= sym(h, "gtk_file_chooser_get_filenames",
            (void **) &p_gtk_file_chooser_get_filenames);
  ok &= sym(h, "gtk_file_filter_new",
            (void **) &p_gtk_file_filter_new);
  ok &= sym(h, "gtk_file_filter_set_name",
            (void **) &p_gtk_file_filter_set_name);
  ok &= sym(h, "gtk_file_filter_add_pattern",
            (void **) &p_gtk_file_filter_add_pattern);
  ok &= sym(h, "gtk_menu_new", (void **) &p_gtk_menu_new);
  ok &= sym(h, "gtk_menu_item_new_with_label",
            (void **) &p_gtk_menu_item_new_with_label);
  ok &= sym(h, "gtk_check_menu_item_new_with_label",
            (void **) &p_gtk_check_menu_item_new_with_label);
  ok &= sym(h, "gtk_separator_menu_item_new",
            (void **) &p_gtk_separator_menu_item_new);
  ok &= sym(h, "gtk_menu_item_set_submenu",
            (void **) &p_gtk_menu_item_set_submenu);
  ok &= sym(h, "gtk_menu_shell_append",
            (void **) &p_gtk_menu_shell_append);
  ok &= sym(h, "gtk_widget_set_sensitive",
            (void **) &p_gtk_widget_set_sensitive);
  ok &= sym(h, "gtk_check_menu_item_set_active",
            (void **) &p_gtk_check_menu_item_set_active);
  ok &= sym(h, "gtk_widget_show_all",
            (void **) &p_gtk_widget_show_all);
  return ok;
}

static int probe_indicator(void)
{
  void *h = dlopen("libayatana-appindicator3.so.1",
                   RTLD_NOW | RTLD_GLOBAL);
  int ok = 1;
  if (h == 0)
    h = dlopen("libappindicator3.so.1", RTLD_NOW | RTLD_GLOBAL);
  if (h == 0) return 0;
  ok &= sym(h, "app_indicator_new", (void **) &p_app_indicator_new);
  ok &= sym(h, "app_indicator_set_status",
            (void **) &p_app_indicator_set_status);
  ok &= sym(h, "app_indicator_set_menu",
            (void **) &p_app_indicator_set_menu);
  ok &= sym(h, "app_indicator_set_icon_full",
            (void **) &p_app_indicator_set_icon_full);
  ok &= sym(h, "app_indicator_set_icon_theme_path",
            (void **) &p_app_indicator_set_icon_theme_path);
  ok &= sym(h, "app_indicator_set_title",
            (void **) &p_app_indicator_set_title);
  ok &= sym(h, "app_indicator_set_label",
            (void **) &p_app_indicator_set_label);
  ok &= sym(h, "app_indicator_set_secondary_activate_target",
            (void **) &p_app_indicator_set_secondary_activate_target);
  return ok;
}

static void do_probe(const char *bus_addr)
{
  if (did_probe) return;
  did_probe = 1;
  if (probe_dbus()) {
    DBusError err;
    p_dbus_error_init(&err);
    if (bus_addr != 0 && bus_addr[0] != 0) {
      session = p_dbus_connection_open(bus_addr, &err);
      if (session != 0 && !p_dbus_error_is_set(&err)
          && p_dbus_bus_register(session, &err)
          && !p_dbus_error_is_set(&err)) {
        p_dbus_connection_set_exit_on_disconnect(session, 0);
        cap_bits |= 1;
        /* One rule covers the whole Notifications interface. */
        p_dbus_bus_add_match(
            session,
            "type='signal',sender='org.freedesktop.Notifications'",
            &err);
      } else {
        if (session != 0) {
          p_dbus_connection_unref(session);
          session = 0;
        }
      }
    }
    if (p_dbus_error_is_set(&err)) p_dbus_error_free(&err);
  }
  if (probe_glib() && probe_gtk() && p_gtk_init_check(0, 0)) {
    gtk_ready = 1;
    cap_bits |= 2;
  }
  if (probe_indicator()) cap_bits |= 4;
}

CAMLprim value lui_shx_probe(value vaddr)
{
  CAMLparam1(vaddr);
  do_probe(String_val(vaddr));
  CAMLreturn(Val_int(cap_bits));
}

CAMLprim value lui_shx_gui(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(gtk_ready));
}

CAMLprim value lui_shx_indicator(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool((cap_bits & 4) != 0));
}

/* ---- Launcher entry (dock badge / attention) ---- */

CAMLprim value lui_shx_launcher(value vpath, value vapp, value vcount,
                                value vvis, value vurgent)
{
  CAMLparam5(vpath, vapp, vcount, vvis, vurgent);
  int ok = 0;
  if (session != 0) {
    DBusMessage *sig =
      p_dbus_message_new_signal(String_val(vpath),
                                "com.canonical.Unity.LauncherEntry",
                                "Update");
    if (sig != 0) {
      DBusMessageIter it, arr;
      const char *app = String_val(vapp);
      dbus_int32_t count = Int_val(vcount);
      dbus_int32_t cv = Bool_val(vvis) ? 1 : 0;
      dbus_int32_t ur = Bool_val(vurgent) ? 1 : 0;
      int ready = 0;
      p_dbus_message_iter_init_append(sig, &it);
      if (p_dbus_message_iter_append_basic(&it, DBUS_TYPE_STRING,
                                           &app)
          && p_dbus_message_iter_open_container(&it, DBUS_TYPE_ARRAY,
                                                "{sv}", &arr)) {
        dict_add_sv(&arr, "count", 'x', &count);
        dict_add_sv(&arr, "count-visible", 'b', &cv);
        dict_add_sv(&arr, "urgent", 'b', &ur);
        ready = p_dbus_message_iter_close_container(&it, &arr);
      }
      if (ready && p_dbus_connection_send(session, sig, 0)) {
        p_dbus_connection_flush(session);
        ok = 1;
      }
      p_dbus_message_unref(sig);
    }
  }
  CAMLreturn(Val_bool(ok));
}

/* ---- Notifications ---- */

CAMLprim value lui_shx_notify(value vapp, value vtitle, value vbody)
{
  CAMLparam3(vapp, vtitle, vbody);
  CAMLlocal2(vres, vdetail);
  DBusMessage *call, *rep = 0;
  DBusError err;
  int err_live = 0;
  const char *detail = "unavailable";
  dbus_uint32_t nid = 0;
  if (session == 0) {
    detail = "no session bus";
    goto done;
  }
  call = p_dbus_message_new_method_call(
      "org.freedesktop.Notifications",
      "/org/freedesktop/Notifications",
      "org.freedesktop.Notifications", "Notify");
  if (call == 0) {
    detail = "no message";
    goto done;
  }
  {
    DBusMessageIter it, arr;
    const char *app = String_val(vapp);
    const char *title = String_val(vtitle);
    const char *body = String_val(vbody);
    const char *icon = "";
    const char *action = "default";
    dbus_uint32_t replaces = 0;
    dbus_int32_t timeout = -1;
    p_dbus_message_iter_init_append(call, &it);
    p_dbus_message_iter_append_basic(&it, DBUS_TYPE_STRING, &app);
    p_dbus_message_iter_append_basic(&it, DBUS_TYPE_UINT32, &replaces);
    p_dbus_message_iter_append_basic(&it, DBUS_TYPE_STRING, &icon);
    p_dbus_message_iter_append_basic(&it, DBUS_TYPE_STRING, &title);
    p_dbus_message_iter_append_basic(&it, DBUS_TYPE_STRING, &body);
    if (p_dbus_message_iter_open_container(&it, DBUS_TYPE_ARRAY,
                                           "s", &arr)) {
      p_dbus_message_iter_append_basic(&arr, DBUS_TYPE_STRING,
                                       &action);
      p_dbus_message_iter_append_basic(&arr, DBUS_TYPE_STRING,
                                       &action);
      p_dbus_message_iter_close_container(&it, &arr);
    }
    if (p_dbus_message_iter_open_container(&it, DBUS_TYPE_ARRAY,
                                           "{sv}", &arr)) {
      p_dbus_message_iter_close_container(&it, &arr);
    }
    p_dbus_message_iter_append_basic(&it, DBUS_TYPE_INT32, &timeout);
  }
  rep = bus_call(call, &err);
  err_live = 1;
  if (rep == 0 || p_dbus_error_is_set(&err)) {
    detail = err.message != 0 ? err.message : "call failed";
    if (err.name != 0 && err.name[0] != 0) detail = err.name;
    goto done;
  }
  {
    DBusMessageIter it;
    if (p_dbus_message_iter_init(rep, &it)
        && p_dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_UINT32) {
      p_dbus_message_iter_get_basic(&it, &nid);
      detail = "freedesktop-notifications";
    } else {
      detail = "bad reply";
    }
    p_dbus_message_unref(rep);
  }
done:
  /* Copy out first: dbus_error_free releases name/message storage. */
  vdetail = caml_copy_string(detail);
  if (err_live && p_dbus_error_is_set(&err)) p_dbus_error_free(&err);
  vres = caml_alloc(2, 0);
  Store_field(vres, 0, Val_int((int) nid));
  Store_field(vres, 1, vdetail);
  CAMLreturn(vres);
}

/* ---- Status item ---- */

CAMLprim value lui_shx_status_create(value vtag)
{
  CAMLparam1(vtag);
  CAMLlocal1(v);
  si_t *s = (si_t *) calloc(1, sizeof(si_t));
  s->tag = Int_val(vtag);
  if (gtk_ready && (cap_bits & 4)) {
    char name[64];
    snprintf(name, sizeof(name), "lui-%d-%d", (int) getpid(),
             Int_val(vtag));
    s->ind = p_app_indicator_new(name, "application-x-executable", 0);
    if (s->ind != 0)
      p_app_indicator_set_status(s->ind, 1); /* ACTIVE */
  }
  v = caml_alloc_custom(&lui_si_ops, sizeof(si_t *), 0, 1);
  Lui_si_val(v) = s;
  CAMLreturn(v);
}

CAMLprim value lui_shx_status_remove(value v)
{
  CAMLparam1(v);
  si_t *s = Lui_si_val(v);
  if (s != 0) {
    if (s->ind != 0 && gtk_ready) {
      p_app_indicator_set_status(s->ind, 0);
      p_g_object_unref(s->ind);
      s->ind = 0;
    }
    si_drop_menu(s);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shx_status_live(value v)
{
  CAMLparam1(v);
  si_t *s = Lui_si_val(v);
  CAMLreturn(Val_bool(s != 0 && s->ind != 0));
}

CAMLprim value lui_shx_status_set_title(value v, value vtitle)
{
  CAMLparam2(v, vtitle);
  si_t *s = Lui_si_val(v);
  if (s != 0 && s->ind != 0) {
    char *title = caml_stat_strdup(String_val(vtitle));
    if (p_app_indicator_set_label != 0)
      p_app_indicator_set_label(s->ind, title, title);
    if (p_app_indicator_set_title != 0)
      p_app_indicator_set_title(s->ind, title);
    caml_stat_free(title);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shx_status_set_image(value v, value vseq,
                                        value vpng)
{
  CAMLparam3(v, vseq, vpng);
  si_t *s = Lui_si_val(v);
  if (s != 0 && s->ind != 0) {
    int seq = Int_val(vseq);
    if (seq < 0) {
      /* Restore the fallback icon. */
      p_app_indicator_set_icon_full(s->ind,
                                    "application-x-executable", "");
    } else {
      char name[64], path[600];
      FILE *f;
      const char *dir = icon_dir();
      snprintf(name, sizeof(name), "lui-icon-%d", seq);
      snprintf(path, sizeof(path), "%s/%s.png", dir, name);
      f = fopen(path, "wb");
      if (f != 0) {
        fwrite(Bytes_val(vpng), 1, caml_string_length(vpng), f);
        fclose(f);
        p_app_indicator_set_icon_theme_path(s->ind, dir);
        p_app_indicator_set_icon_full(s->ind, name, "");
      }
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shx_status_set_menu(value v, value vtitle,
                                       value vrows_opt)
{
  CAMLparam3(v, vtitle, vrows_opt);
  si_t *s = Lui_si_val(v);
  if (s != 0 && s->ind != 0) {
    (void) vtitle;
    if (s->menu != 0) {
      p_app_indicator_set_menu(s->ind, 0);
      p_g_object_unref(s->menu);
      s->menu = 0;
    }
    if (Is_block(vrows_opt)) {
      void *menu = lui_menu_build(Field(vrows_opt, 0));
      s->menu = p_g_object_ref_sink(menu);
      p_gtk_widget_show_all(menu);
      p_app_indicator_set_menu(s->ind, s->menu);
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shx_status_set_on_click(value v, value von)
{
  CAMLparam2(v, von);
  si_t *s = Lui_si_val(v);
  if (s != 0 && s->ind != 0
      && p_app_indicator_set_secondary_activate_target != 0) {
    if (Bool_val(von)) {
      if (s->click_item == 0) {
        s->click_item = p_gtk_menu_item_new_with_label("");
        s->click_item = p_g_object_ref_sink(s->click_item);
        p_g_signal_connect_data(s->click_item, "activate",
                                (void *) on_status_click,
                                (void *) (intptr_t) s->tag, 0, 0);
      }
      p_app_indicator_set_secondary_activate_target(s->ind,
                                                    s->click_item);
    } else {
      p_app_indicator_set_secondary_activate_target(s->ind, 0);
    }
  }
  CAMLreturn(Val_unit);
}

/* ---- Clipboard ---- */

CAMLprim value lui_shx_clip_write(value vstr)
{
  CAMLparam1(vstr);
  void *board = clip_board();
  int ok = 0;
  if (board != 0) {
    p_gtk_clipboard_clear(board);
    p_gtk_clipboard_set_text(board, String_val(vstr),
                             (int) caml_string_length(vstr));
    clip_generation++;
    ok = 1;
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_shx_clip_read(value unit)
{
  CAMLparam1(unit);
  CAMLlocal2(vopt, vs);
  void *board = clip_board();
  char *text = 0;
  vopt = Val_int(0);
  if (board != 0) text = p_gtk_clipboard_wait_for_text(board);
  if (text != 0) {
    vs = caml_copy_string(text);
    p_g_free(text);
    vopt = caml_alloc(1, 0);
    Store_field(vopt, 0, vs);
  }
  CAMLreturn(vopt);
}

CAMLprim value lui_shx_clip_clear(value unit)
{
  CAMLparam1(unit);
  void *board = clip_board();
  if (board != 0) {
    p_gtk_clipboard_clear(board);
    clip_generation++;
  }
  CAMLreturn(Val_int(board != 0 ? clip_generation : -1));
}

CAMLprim value lui_shx_clip_count(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_int(clip_board() != 0 ? clip_generation : -1));
}

/* ---- Dialogs ---- */

CAMLprim value lui_shx_can_present(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(gtk_ready));
}

CAMLprim value lui_shx_open_panel(value vfiles, value vdirs,
                                  value vmulti, value vfilters)
{
  CAMLparam4(vfiles, vdirs, vmulti, vfilters);
  CAMLlocal4(vopt, varr, vs, vtmp);
  void *dlg = 0;
  int response = -1;
  vopt = Val_int(0);
  if (gtk_ready) {
    /* GTK3 choosers cannot mix files and folders in one mode:
       folders win. */
    int action = Bool_val(vdirs) ? 2 /* SELECT_FOLDER */ : 0 /* OPEN */;
    dlg = p_gtk_file_chooser_native_new("Open", 0, action, "_Open",
                                        "_Cancel");
    if (dlg != 0) {
      mlsize_t nf = Wosize_val(vfilters);
      (void) vfiles;
      if (Bool_val(vmulti))
        p_gtk_file_chooser_set_select_multiple(dlg, 1);
      if (nf > 0) {
        void *filter = p_gtk_file_filter_new();
        mlsize_t i;
        p_gtk_file_filter_set_name(filter, "Files");
        for (i = 0; i < nf; i++) {
          char pat[300];
          const char *ext = String_val(Field(vfilters, i));
          snprintf(pat, sizeof(pat), "*.%s", ext);
          p_gtk_file_filter_add_pattern(filter, pat);
        }
        p_gtk_file_chooser_add_filter(dlg, filter);
      }
      response = p_gtk_native_dialog_run(dlg);
      if (response == -3 || response == -5) {
        GSList *list = p_gtk_file_chooser_get_filenames(dlg);
        GSList *node;
        int n = 0, k = 0;
        for (node = list; node != 0; node = node->next) n++;
        varr = caml_alloc((mlsize_t) n, 0);
        for (node = list; node != 0; node = node->next) {
          vs = caml_copy_string((const char *) node->data);
          Store_field(varr, k++, vs);
          p_g_free(node->data);
        }
        p_g_slist_free(list);
        vtmp = varr;
        vopt = caml_alloc(1, 0);
        Store_field(vopt, 0, vtmp);
      }
      p_gtk_native_dialog_destroy(dlg);
      p_g_object_unref(dlg);
    }
  }
  CAMLreturn(vopt);
}

CAMLprim value lui_shx_save_panel(value vname)
{
  CAMLparam1(vname);
  CAMLlocal2(vopt, vs);
  void *dlg = 0;
  int response = -1;
  vopt = Val_int(0);
  if (gtk_ready) {
    dlg = p_gtk_file_chooser_native_new("Save", 0, 1 /* SAVE */,
                                        "_Save", "_Cancel");
    if (dlg != 0) {
      if (caml_string_length(vname) > 0)
        p_gtk_file_chooser_set_current_name(dlg,
                                            String_val(vname));
      p_gtk_file_chooser_set_do_overwrite_confirmation(dlg, 1);
      response = p_gtk_native_dialog_run(dlg);
      if (response == -3 || response == -5) {
        char *path = p_gtk_file_chooser_get_filename(dlg);
        if (path != 0) {
          vs = caml_copy_string(path);
          p_g_free(path);
          vopt = caml_alloc(1, 0);
          Store_field(vopt, 0, vs);
        }
      }
      p_gtk_native_dialog_destroy(dlg);
      p_g_object_unref(dlg);
    }
  }
  CAMLreturn(vopt);
}

/* ---- Open-url ---- */

/* Fallback when gio cannot launch: spawn xdg-open detached. */
static int spawn_xdg_open(const char *url)
{
  pid_t pid = fork();
  if (pid == 0) {
    pid_t p2 = fork();
    if (p2 == 0) {
      execlp("xdg-open", "xdg-open", url, (char *) 0);
      _exit(127);
    }
    _exit(p2 > 0 ? 0 : 127);
  }
  if (pid > 0) {
    int st;
    waitpid(pid, &st, 0);
    return WIFEXITED(st) && WEXITSTATUS(st) == 0;
  }
  return 0;
}

CAMLprim value lui_shx_open_url(value vurl)
{
  CAMLparam1(vurl);
  int ok = 0;
  if (p_g_app_info_launch_default_for_uri != 0) {
    GError *err = 0;
    ok = p_g_app_info_launch_default_for_uri(String_val(vurl), 0,
                                             &err);
    if (err != 0) p_g_error_free(err);
  }
  if (!ok) ok = spawn_xdg_open(String_val(vurl));
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_shx_openurl_bus(value vname, value vpath)
{
  CAMLparam2(vname, vpath);
  int ok = 0;
  if (session != 0) {
    DBusError err;
    dbus_uint32_t r;
    p_dbus_error_init(&err);
    r = p_dbus_bus_request_name(session, String_val(vname), 0, &err);
    if (!p_dbus_error_is_set(&err) && (r == 1 || r == 2 || r == 4)) {
      /* PRIMARY_OWNER=1, IN_QUEUE=2, ALREADY_OWNER=4: all mean the
         name is claimable or owned. Only PRIMARY_OWNER serves. */
      if (r == 1 || r == 4) {
        snprintf(openurl_path, sizeof(openurl_path), "%s",
                 String_val(vpath));
        ok = p_dbus_connection_register_object_path(
            session, openurl_path, &lui_app_vtable, 0);
      }
    }
    if (p_dbus_error_is_set(&err)) p_dbus_error_free(&err);
  }
  CAMLreturn(Val_bool(ok));
}

/* ---- Pump ---- */

CAMLprim value lui_shx_pump(value vtimeout)
{
  CAMLparam1(vtimeout);
  CAMLlocal4(vout, vev, vs, vtmp);
  int n = 0, i;
  if (session != 0) {
    p_dbus_connection_read_write_dispatch(session,
                                          Int_val(vtimeout));
    drain_signals();
  }
  if (gtk_ready) {
    int spins = 0;
    while (spins++ < 64
           && p_g_main_context_iteration(0, 0)) {
    }
  }
  n = ev_len;
  vout = caml_alloc((mlsize_t) n, 0);
  for (i = 0; i < n; i++) {
    ev_t *e = &ev_queue[(ev_head + i) % EV_MAX];
    vs = caml_copy_string(e->sarg != 0 ? e->sarg : "");
    vev = caml_alloc(3, 0);
    vtmp = vs;
    Store_field(vev, 0, Val_int(e->kind));
    Store_field(vev, 1, Val_int(e->iarg));
    Store_field(vev, 2, vtmp);
    Store_field(vout, i, vev);
  }
  /* Drop everything returned. */
  for (i = 0; i < n; i++) {
    ev_t *e = &ev_queue[ev_head];
    free(e->sarg);
    e->sarg = 0;
    ev_head = (ev_head + 1) % EV_MAX;
    ev_len--;
  }
  CAMLreturn(vout);
}

#else /* !__linux__ */

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void)
{
  caml_failwith("lui_shell_linux: this backend requires Linux");
  return Val_unit;
}

CAMLprim value lui_shx_probe(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_gui(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_indicator(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_launcher(value a, value b, value c, value d,
                                value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }
CAMLprim value lui_shx_notify(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_shx_status_create(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_status_remove(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_status_live(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_status_set_title(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shx_status_set_image(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_shx_status_set_menu(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_shx_status_set_on_click(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shx_clip_write(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_clip_read(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_clip_clear(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_clip_count(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_can_present(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_open_panel(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_shx_save_panel(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_open_url(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shx_openurl_bus(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shx_pump(value a) {
  (void)a; return unsupported(); }

#endif /* __linux__ */
