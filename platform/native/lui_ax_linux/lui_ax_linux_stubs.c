/* AT-SPI/D-Bus transport for lui_ax_linux.

   The OCaml side owns all protocol semantics; this file only carries
   marshalled values over the platform D-Bus client library.  The
   library is resolved at runtime with dlopen/dlsym so the stub links
   and runs on machines without dbus development headers; when the
   library (or a reachable bus) is absent the bridge stays offline and
   every entry point degrades to a no-op rather than failing.

   Required system dependency for a live session: libdbus-1.so.3 plus a
   running accessibility bus (at-spi-bus-launcher / at-spi2-registryd)
   or at least a session bus.  On this VM the runtime library may exist
   without the daemons: connect() then reports Session_bus or Offline
   and events stay queued for drain_events/flush. */

#if defined(__linux__)

#include <string.h>
#include <stdlib.h>
#include <dlfcn.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/custom.h>

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
#define DBUS_TYPE_BYTE         ((int) 'y')
#define DBUS_TYPE_BOOLEAN      ((int) 'b')
#define DBUS_TYPE_INT16        ((int) 'n')
#define DBUS_TYPE_UINT16       ((int) 'q')
#define DBUS_TYPE_INT32        ((int) 'i')
#define DBUS_TYPE_UINT32       ((int) 'u')
#define DBUS_TYPE_INT64        ((int) 'x')
#define DBUS_TYPE_UINT64       ((int) 't')
#define DBUS_TYPE_DOUBLE       ((int) 'd')
#define DBUS_TYPE_STRING       ((int) 's')
#define DBUS_TYPE_OBJECT_PATH  ((int) 'o')
#define DBUS_TYPE_SIGNATURE    ((int) 'g')
#define DBUS_TYPE_ARRAY        ((int) 'a')
#define DBUS_TYPE_VARIANT      ((int) 'v')
#define DBUS_TYPE_STRUCT       ((int) 'r')
#define DBUS_TYPE_DICT_ENTRY   ((int) 'e')
#define DBUS_TYPE_UNIX_FD      ((int) 'h')

#define DBUS_STRUCT_BEGIN_CHAR      '('
#define DBUS_STRUCT_END_CHAR        ')'
#define DBUS_DICT_ENTRY_BEGIN_CHAR  '{'
#define DBUS_DICT_ENTRY_END_CHAR    '}'

#define DBUS_MESSAGE_TYPE_METHOD_CALL   1
#define DBUS_MESSAGE_TYPE_METHOD_RETURN 2
#define DBUS_MESSAGE_TYPE_ERROR         3
#define DBUS_MESSAGE_TYPE_SIGNAL        4

typedef int dbus_bool_t;
typedef unsigned int dbus_uint32_t;
typedef int dbus_int32_t;
typedef short dbus_int16_t;
typedef unsigned short dbus_uint16_t;
typedef long long dbus_int64_t;
typedef unsigned long long dbus_uint64_t;
typedef unsigned char dbus_bool_wire_t;

/* ---- Resolved symbols ---- */

static DBusConnection *(*p_dbus_connection_open)(const char *,
                                                 DBusError *) = 0;
static dbus_bool_t (*p_dbus_bus_register)(DBusConnection *,
                                          DBusError *) = 0;
static const char *(*p_dbus_bus_get_unique_name)(DBusConnection *) = 0;
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
static DBusMessage *(*p_dbus_message_new_method_call)(const char *,
                                                    const char *,
                                                    const char *,
                                                    const char *) = 0;
static DBusMessage *(*p_dbus_message_new_signal)(const char *,
                                               const char *,
                                               const char *) = 0;
static DBusMessage *(*p_dbus_message_new_method_return)(
    DBusMessage *) = 0;
static DBusMessage *(*p_dbus_message_new_error)(DBusMessage *,
                                              const char *,
                                              const char *) = 0;
static void (*p_dbus_message_unref)(DBusMessage *) = 0;
static int (*p_dbus_message_get_type)(DBusMessage *) = 0;
static const char *(*p_dbus_message_get_path)(DBusMessage *) = 0;
static const char *(*p_dbus_message_get_interface)(DBusMessage *) = 0;
static const char *(*p_dbus_message_get_member)(DBusMessage *) = 0;
static dbus_uint32_t (*p_dbus_message_get_serial)(DBusMessage *) = 0;
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
static void (*p_dbus_free)(void *) = 0;
static char *(*p_dbus_message_iter_get_signature)(
    DBusMessageIter *) = 0;

static int dbus_available = -1;

static int sym(void *h, const char *name, void **out)
{
  *out = dlsym(h, name);
  return *out != 0;
}

CAMLprim value lui_ax_dbus_probe(value unit)
{
  CAMLparam1(unit);
  if (dbus_available < 0) {
    void *h = dlopen("libdbus-1.so.3", RTLD_NOW | RTLD_GLOBAL);
    dbus_available = 0;
    if (h) {
      int ok = 1;
      ok &= sym(h, "dbus_connection_open",
                (void **) &p_dbus_connection_open);
      ok &= sym(h, "dbus_bus_register", (void **) &p_dbus_bus_register);
      ok &= sym(h, "dbus_bus_get_unique_name",
                (void **) &p_dbus_bus_get_unique_name);
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
      ok &= sym(h, "dbus_message_new_method_call",
                (void **) &p_dbus_message_new_method_call);
      ok &= sym(h, "dbus_message_new_signal",
                (void **) &p_dbus_message_new_signal);
      ok &= sym(h, "dbus_message_new_method_return",
                (void **) &p_dbus_message_new_method_return);
      ok &= sym(h, "dbus_message_new_error",
                (void **) &p_dbus_message_new_error);
      ok &= sym(h, "dbus_message_unref",
                (void **) &p_dbus_message_unref);
      ok &= sym(h, "dbus_message_get_type",
                (void **) &p_dbus_message_get_type);
      ok &= sym(h, "dbus_message_get_path",
                (void **) &p_dbus_message_get_path);
      ok &= sym(h, "dbus_message_get_interface",
                (void **) &p_dbus_message_get_interface);
      ok &= sym(h, "dbus_message_get_member",
                (void **) &p_dbus_message_get_member);
      ok &= sym(h, "dbus_message_get_serial",
                (void **) &p_dbus_message_get_serial);
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
      ok &= sym(h, "dbus_free", (void **) &p_dbus_free);
      ok &= sym(h, "dbus_message_iter_get_signature",
                (void **) &p_dbus_message_iter_get_signature);
      dbus_available = ok;
    }
  }
  CAMLreturn(Val_int(dbus_available));
}

/* ---- Connection table ----

   Connections are handed to OCaml as small ints; each slot owns its
   connection plus a list of pending method-call messages waiting for
   replies. */

#define MAX_CONNS 8

typedef struct pend {
  dbus_uint32_t serial;
  DBusMessage *msg;
  struct pend *next;
} pend_t;

typedef struct {
  DBusConnection *conn;
  pend_t *pending;
} conn_t;

static conn_t conns[MAX_CONNS];

static conn_t *conn_of(value v)
{
  int i = Int_val(v);
  if (i < 0 || i >= MAX_CONNS || conns[i].conn == 0)
    caml_invalid_argument("lui_ax_linux: bad connection handle");
  return &conns[i];
}

static void pend_put(conn_t *c, DBusMessage *m)
{
  pend_t *p = (pend_t *) malloc(sizeof(pend_t));
  p->serial = p_dbus_message_get_serial(m);
  p->msg = m;
  p->next = c->pending;
  c->pending = p;
}

static DBusMessage *pend_take(conn_t *c, dbus_uint32_t serial)
{
  pend_t **pp = &c->pending;
  while (*pp) {
    if ((*pp)->serial == serial) {
      DBusMessage *m = (*pp)->msg;
      pend_t *dead = *pp;
      *pp = (*pp)->next;
      free(dead);
      return m;
    }
    pp = &(*pp)->next;
  }
  return 0;
}

CAMLprim value lui_ax_dbus_open(value vaddr)
{
  CAMLparam1(vaddr);
  int slot = -1;
  int i;
  DBusError err;
  DBusConnection *conn;
  if (!dbus_available) CAMLreturn(Val_int(0));
  for (i = 1; i < MAX_CONNS; i++)
    if (conns[i].conn == 0) {
      slot = i;
      break;
    }
  if (slot < 0) CAMLreturn(Val_int(0));
  p_dbus_error_init(&err);
  conn = p_dbus_connection_open(String_val(vaddr), &err);
  if (!conn || p_dbus_error_is_set(&err)) {
    p_dbus_error_free(&err);
    CAMLreturn(Val_int(0));
  }
  if (!p_dbus_bus_register(conn, &err) || p_dbus_error_is_set(&err)) {
    p_dbus_error_free(&err);
    p_dbus_connection_unref(conn);
    CAMLreturn(Val_int(0));
  }
  p_dbus_error_free(&err);
  p_dbus_connection_set_exit_on_disconnect(conn, 0);
  conns[slot].conn = conn;
  conns[slot].pending = 0;
  CAMLreturn(Val_int(slot));
}

CAMLprim value lui_ax_dbus_close(value vc)
{
  CAMLparam1(vc);
  conn_t *c;
  pend_t *p;
  if (!dbus_available) CAMLreturn(Val_unit);
  {
    int i = Int_val(vc);
    if (i < 0 || i >= MAX_CONNS || conns[i].conn == 0)
      CAMLreturn(Val_unit);
    c = &conns[i];
  }
  p = c->pending;
  while (p) {
    pend_t *nx = p->next;
    p_dbus_message_unref(p->msg);
    free(p);
    p = nx;
  }
  c->pending = 0;
  p_dbus_connection_unref(c->conn);
  c->conn = 0;
  CAMLreturn(Val_unit);
}

CAMLprim value lui_ax_dbus_name(value vc)
{
  CAMLparam1(vc);
  CAMLlocal1(vs);
  conn_t *c = conn_of(vc);
  const char *n = p_dbus_bus_get_unique_name(c->conn);
  vs = caml_copy_string(n ? n : "");
  CAMLreturn(vs);
}

/* Ask the session bus for the accessibility bus address:
   org.a11y.Bus.GetAddress at /org/a11y/bus. */

CAMLprim value lui_ax_dbus_a11y_address(value vc)
{
  CAMLparam1(vc);
  CAMLlocal1(vs);
  conn_t *c = conn_of(vc);
  DBusMessage *call, *rep;
  DBusError err;
  DBusMessageIter it;
  const char *addr = "";
  call = p_dbus_message_new_method_call("org.a11y.Bus", "/org/a11y/bus",
                                        "org.a11y.Bus", "GetAddress");
  if (!call) {
    vs = caml_copy_string("");
    CAMLreturn(vs);
  }
  p_dbus_error_init(&err);
  rep = p_dbus_connection_send_with_reply_and_block(c->conn, call, 5000,
                                                    &err);
  p_dbus_message_unref(call);
  if (rep && p_dbus_message_iter_init(rep, &it)
      && p_dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_STRING)
    p_dbus_message_iter_get_basic(&it, &addr);
  vs = caml_copy_string(addr);
  if (rep) p_dbus_message_unref(rep);
  if (p_dbus_error_is_set(&err)) p_dbus_error_free(&err);
  CAMLreturn(vs);
}

/* Register the application root with the a11y registry:
   Socket.Embed((so) our_root) on org.a11y.atspi.Registry returns
   (so) the desktop reference. */

CAMLprim value lui_ax_dbus_embed(value vc, value vpath)
{
  CAMLparam2(vc, vpath);
  CAMLlocal2(vt, vs);
  conn_t *c = conn_of(vc);
  DBusMessage *call, *rep;
  DBusMessageIter it, sub;
  DBusError err;
  const char *dname = "", *dpath = "";
  const char *self = p_dbus_bus_get_unique_name(c->conn);
  if (!self) self = "";
  call = p_dbus_message_new_method_call(
      "org.a11y.atspi.Registry", "/org/a11y/atspi/registry",
      "org.a11y.atspi.Socket", "Embed");
  if (!call) goto done;
  p_dbus_message_iter_init_append(call, &it);
  if (!p_dbus_message_iter_open_container(&it, DBUS_TYPE_STRUCT, 0,
                                          &sub))
    goto unref_done;
  p_dbus_message_iter_append_basic(&sub, DBUS_TYPE_STRING, &self);
  {
    const char *p = String_val(vpath);
    p_dbus_message_iter_append_basic(&sub, DBUS_TYPE_OBJECT_PATH, &p);
  }
  p_dbus_message_iter_close_container(&it, &sub);
  p_dbus_error_init(&err);
  rep = p_dbus_connection_send_with_reply_and_block(c->conn, call, 5000,
                                                    &err);
  if (rep && p_dbus_message_iter_init(rep, &it)
      && p_dbus_message_iter_get_arg_type(&it) == DBUS_TYPE_STRUCT) {
    p_dbus_message_iter_recurse(&it, &sub);
    if (p_dbus_message_iter_get_arg_type(&sub) == DBUS_TYPE_STRING)
      p_dbus_message_iter_get_basic(&sub, &dname);
    if (p_dbus_message_iter_next(&sub)
        && p_dbus_message_iter_get_arg_type(&sub)
               == DBUS_TYPE_OBJECT_PATH)
      p_dbus_message_iter_get_basic(&sub, &dpath);
  }
  if (rep) p_dbus_message_unref(rep);
  if (p_dbus_error_is_set(&err)) p_dbus_error_free(&err);
unref_done:
  p_dbus_message_unref(call);
done:
  vt = caml_alloc_tuple(2);
  vs = caml_copy_string(dname);
  Store_field(vt, 0, vs);
  vs = caml_copy_string(dpath);
  Store_field(vt, 1, vs);
  CAMLreturn(vt);
}

/* ---- Argument decoding ----

   Flattens a message's basic arguments into three arrays: ints (all
   integer-ish types incl. bool), doubles, and strings (string, object
   path, signature).  Container arguments are recursed into so a
   VARIANT's payload or a (so)'s members land in the flat arrays. */

typedef struct {
  long long ibuf[64];
  double fbuf[16];
  const char *sbuf[64];
  int ni, nf, ns;
} args_t;

static void collect_arg(args_t *a, DBusMessageIter *it)
{
  int ty = p_dbus_message_iter_get_arg_type(it);
  switch (ty) {
  case DBUS_TYPE_BYTE:
  case DBUS_TYPE_BOOLEAN:
  case DBUS_TYPE_INT16:
  case DBUS_TYPE_UINT16:
  case DBUS_TYPE_INT32:
  case DBUS_TYPE_UINT32:
  case DBUS_TYPE_UNIX_FD: {
    dbus_int32_t v = 0;
    p_dbus_message_iter_get_basic(it, &v);
    if (a->ni < 64) a->ibuf[a->ni++] = v;
    break;
  }
  case DBUS_TYPE_INT64:
  case DBUS_TYPE_UINT64: {
    dbus_int64_t v = 0;
    p_dbus_message_iter_get_basic(it, &v);
    if (a->ni < 64) a->ibuf[a->ni++] = (long long) v;
    break;
  }
  case DBUS_TYPE_DOUBLE: {
    double v = 0;
    p_dbus_message_iter_get_basic(it, &v);
    if (a->nf < 16) a->fbuf[a->nf++] = v;
    break;
  }
  case DBUS_TYPE_STRING:
  case DBUS_TYPE_OBJECT_PATH:
  case DBUS_TYPE_SIGNATURE: {
    const char *v = "";
    p_dbus_message_iter_get_basic(it, &v);
    if (a->ns < 64) a->sbuf[a->ns++] = v;
    break;
  }
  case DBUS_TYPE_VARIANT:
  case DBUS_TYPE_STRUCT:
  case DBUS_TYPE_DICT_ENTRY:
  case DBUS_TYPE_ARRAY: {
    DBusMessageIter sub;
    p_dbus_message_iter_recurse(it, &sub);
    do {
      collect_arg(a, &sub);
    } while (p_dbus_message_iter_next(&sub));
    break;
  }
  default:
    break;
  }
}

static void collect_args(args_t *a, DBusMessage *m)
{
  DBusMessageIter it;
  if (!p_dbus_message_iter_init(m, &it)) return;
  do {
    collect_arg(a, &it);
  } while (p_dbus_message_iter_next(&it));
}

/* Poll for queued incoming method calls; returns an array of
   (serial, path, iface, member, iargs, fargs, sargs). */

CAMLprim value lui_ax_dbus_poll(value vc, value vtimeout_ms)
{
  CAMLparam2(vc, vtimeout_ms);
  CAMLlocal5(vout, vcall, vi, vf, vs);
  CAMLlocal5(vt, vp, vif, vm, vempty);
  conn_t *c = conn_of(vc);
  int n = 0, i;
  DBusMessage *list[64];
  DBusMessage *m;
  args_t a;

  p_dbus_connection_read_write_dispatch(c->conn, Int_val(vtimeout_ms));
  while (n < 64 && (m = p_dbus_connection_pop_message(c->conn)) != 0) {
    if (p_dbus_message_get_type(m) == DBUS_MESSAGE_TYPE_METHOD_CALL)
      list[n++] = m;
    else
      p_dbus_message_unref(m);
  }
  vout = caml_alloc(n, 0);
  for (i = 0; i < n; i++) {
    const char *pth, *ifc, *mm;
    args_t *arg = &a;
    int k;
    arg->ni = arg->nf = arg->ns = 0;
    collect_args(arg, list[i]);
    pth = p_dbus_message_get_path(list[i]);
    ifc = p_dbus_message_get_interface(list[i]);
    mm = p_dbus_message_get_member(list[i]);
    vp = caml_copy_string(pth ? pth : "");
    vif = caml_copy_string(ifc ? ifc : "");
    vm = caml_copy_string(mm ? mm : "");
    vi = caml_alloc(arg->ni, 0);
    for (k = 0; k < arg->ni; k++)
      Store_field(vi, k, Val_int((int) arg->ibuf[k]));
    vf = caml_alloc(arg->nf * Double_wosize, Double_array_tag);
    for (k = 0; k < arg->nf; k++)
      Store_double_field(vf, k, arg->fbuf[k]);
    vs = caml_alloc(arg->ns, 0);
    for (k = 0; k < arg->ns; k++)
      Store_field(vs, k, caml_copy_string(arg->sbuf[k]));
    vcall = caml_alloc_tuple(7);
    Store_field(vcall, 0,
                Val_int((int) p_dbus_message_get_serial(list[i])));
    Store_field(vcall, 1, vp);
    Store_field(vcall, 2, vif);
    Store_field(vcall, 3, vm);
    Store_field(vcall, 4, vi);
    Store_field(vcall, 5, vf);
    Store_field(vcall, 6, vs);
    Store_field(vout, i, vcall);
    pend_put(c, list[i]);
  }
  CAMLreturn(vout);
}

/* ---- Reply marshalling ----

   [dvalue] layout (see lui_ax_linux.mli): every constructor is a
   block; the tag selects the wire type:
   0 DStr s | 1 DInt i | 2 DUInt u | 3 DN16 n | 4 DBool b | 5 DDbl d |
   6 DObj o | 7 DVar(sig, v) | 8 DArr(elemsig, items) |
   9 DStruct(items) | 10 DDict(contsig, pairs). */

static void append_dvalue(DBusMessageIter *it, value v);

static void append_list(DBusMessageIter *it, value items)
{
  while (Is_block(items)) {
    append_dvalue(it, Field(items, 0));
    items = Field(items, 1);
  }
}

static void append_dvalue(DBusMessageIter *it, value v)
{
  DBusMessageIter sub;
  switch (Tag_val(v)) {
  case 0: { /* DStr */
    const char *s = String_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_STRING, &s);
    break;
  }
  case 1: { /* DInt */
    dbus_int32_t x = Int_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_INT32, &x);
    break;
  }
  case 2: { /* DUInt */
    dbus_uint32_t x = Int_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_UINT32, &x);
    break;
  }
  case 3: { /* DN16 */
    dbus_int16_t x = (dbus_int16_t) Int_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_INT16, &x);
    break;
  }
  case 4: { /* DBool */
    dbus_bool_t x = Bool_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_BOOLEAN, &x);
    break;
  }
  case 5: { /* DDbl */
    double x = Double_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_DOUBLE, &x);
    break;
  }
  case 6: { /* DObj */
    const char *s = String_val(Field(v, 0));
    p_dbus_message_iter_append_basic(it, DBUS_TYPE_OBJECT_PATH, &s);
    break;
  }
  case 7: /* DVar(sig, payload) */
    p_dbus_message_iter_open_container(it, DBUS_TYPE_VARIANT,
                                       String_val(Field(v, 0)), &sub);
    append_dvalue(&sub, Field(v, 1));
    p_dbus_message_iter_close_container(it, &sub);
    break;
  case 8: /* DArr(elem_sig, items) */
    p_dbus_message_iter_open_container(it, DBUS_TYPE_ARRAY,
                                       String_val(Field(v, 0)), &sub);
    append_list(&sub, Field(v, 1));
    p_dbus_message_iter_close_container(it, &sub);
    break;
  case 9: /* DStruct(items) */
    p_dbus_message_iter_open_container(it, DBUS_TYPE_STRUCT, 0, &sub);
    append_list(&sub, Field(v, 0));
    p_dbus_message_iter_close_container(it, &sub);
    break;
  case 10: { /* DDict(container_sig, pairs) */
    value pairs;
    p_dbus_message_iter_open_container(it, DBUS_TYPE_ARRAY,
                                       String_val(Field(v, 0)), &sub);
    pairs = Field(v, 1);
    while (Is_block(pairs)) {
      DBusMessageIter ent;
      value pair = Field(pairs, 0);
      const char *k = String_val(Field(pair, 0));
      p_dbus_message_iter_open_container(&sub, DBUS_TYPE_DICT_ENTRY, 0,
                                         &ent);
      p_dbus_message_iter_append_basic(&ent, DBUS_TYPE_STRING, &k);
      append_dvalue(&ent, Field(pair, 1));
      p_dbus_message_iter_close_container(&sub, &ent);
      pairs = Field(pairs, 1);
    }
    p_dbus_message_iter_close_container(it, &sub);
    break;
  }
  default:
    break;
  }
}

CAMLprim value lui_ax_reply(value vc, value vserial, value vargs)
{
  CAMLparam3(vc, vserial, vargs);
  conn_t *c = conn_of(vc);
  DBusMessage *orig = pend_take(c, (dbus_uint32_t) Int_val(vserial));
  DBusMessage *rep;
  DBusMessageIter it;
  mlsize_t i, n;
  if (!orig) CAMLreturn(Val_unit);
  rep = p_dbus_message_new_method_return(orig);
  if (rep) {
    n = Wosize_val(vargs);
    p_dbus_message_iter_init_append(rep, &it);
    for (i = 0; i < n; i++) append_dvalue(&it, Field(vargs, i));
    p_dbus_connection_send(c->conn, rep, 0);
    p_dbus_message_unref(rep);
    p_dbus_connection_flush(c->conn);
  }
  p_dbus_message_unref(orig);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_ax_reply_error(value vc, value vserial, value vname,
                                  value vmsg)
{
  CAMLparam4(vc, vserial, vname, vmsg);
  conn_t *c = conn_of(vc);
  DBusMessage *orig = pend_take(c, (dbus_uint32_t) Int_val(vserial));
  DBusMessage *rep;
  if (!orig) CAMLreturn(Val_unit);
  rep = p_dbus_message_new_error(orig, String_val(vname),
                                 String_val(vmsg));
  if (rep) {
    p_dbus_connection_send(c->conn, rep, 0);
    p_dbus_message_unref(rep);
    p_dbus_connection_flush(c->conn);
  }
  p_dbus_message_unref(orig);
  CAMLreturn(Val_unit);
}

/* ---- Signal emission ---- */

static void send_sig(conn_t *c, DBusMessage *sig)
{
  if (sig) {
    p_dbus_connection_send(c->conn, sig, 0);
    p_dbus_message_unref(sig);
  }
}

/* Event payload builder: the wire shape every AT event signal shares:
   detail(s) detail1(i) detail2(i) any_data(v) properties(a{sv}). */

static DBusMessage *event_signal(conn_t *c, value vpath, value viface,
                                 value vmember, value vdetail,
                                 value vd1, value vd2, int vkind,
                                 value vany)
{
  DBusMessage *sig;
  DBusMessageIter it, var, dict;
  const char *detail = String_val(vdetail);
  dbus_int32_t d1 = Int_val(vd1), d2 = Int_val(vd2);
  sig = p_dbus_message_new_signal(String_val(vpath), String_val(viface),
                                  String_val(vmember));
  if (!sig) return 0;
  p_dbus_message_iter_init_append(sig, &it);
  p_dbus_message_iter_append_basic(&it, DBUS_TYPE_STRING, &detail);
  p_dbus_message_iter_append_basic(&it, DBUS_TYPE_INT32, &d1);
  p_dbus_message_iter_append_basic(&it, DBUS_TYPE_INT32, &d2);
  switch (vkind) {
  case 0: { /* variant "i" */
    dbus_int32_t x = Int_val(vany);
    p_dbus_message_iter_open_container(&it, DBUS_TYPE_VARIANT, "i",
                                       &var);
    p_dbus_message_iter_append_basic(&var, DBUS_TYPE_INT32, &x);
    p_dbus_message_iter_close_container(&it, &var);
    break;
  }
  case 1: { /* variant "s" */
    const char *x = String_val(vany);
    p_dbus_message_iter_open_container(&it, DBUS_TYPE_VARIANT, "s",
                                       &var);
    p_dbus_message_iter_append_basic(&var, DBUS_TYPE_STRING, &x);
    p_dbus_message_iter_close_container(&it, &var);
    break;
  }
  case 2: { /* variant "(so)" = (self, path) */
    const char *self = p_dbus_bus_get_unique_name(c->conn);
    const char *p = String_val(vany);
    DBusMessageIter st;
    if (!self) self = "";
    p_dbus_message_iter_open_container(&it, DBUS_TYPE_VARIANT, "(so)",
                                       &var);
    p_dbus_message_iter_open_container(&var, DBUS_TYPE_STRUCT, 0, &st);
    p_dbus_message_iter_append_basic(&st, DBUS_TYPE_STRING, &self);
    p_dbus_message_iter_append_basic(&st, DBUS_TYPE_OBJECT_PATH, &p);
    p_dbus_message_iter_close_container(&var, &st);
    p_dbus_message_iter_close_container(&it, &var);
    break;
  }
  }
  /* Empty a{sv} properties tail. */
  p_dbus_message_iter_open_container(&it, DBUS_TYPE_ARRAY, "{sv}",
                                     &dict);
  p_dbus_message_iter_close_container(&it, &dict);
  return sig;
}

static value emit_num_impl(value *argv)
{
  CAMLparamN(argv, 8);
  conn_t *c = conn_of(argv[0]);
  send_sig(c, event_signal(c, argv[1], argv[2], argv[3], argv[4],
                           argv[5], argv[6], 0, argv[7]));
  p_dbus_connection_flush(c->conn);
  CAMLreturn(Val_unit);
}

/* >5-arg externals: the native entry takes individual arguments, the
   bytecode entry takes (argv, argc) — they must not share one name. */
CAMLprim value lui_ax_emit_num(value a, value b, value c, value d,
                               value e, value f, value g, value h)
{
  value argv[8] = { a, b, c, d, e, f, g, h };
  return emit_num_impl(argv);
}

CAMLprim value lui_ax_emit_num_bc(value *argv, int argc)
{
  (void)argc;
  return emit_num_impl(argv);
}

static value emit_str_impl(value *argv)
{
  CAMLparamN(argv, 8);
  conn_t *c = conn_of(argv[0]);
  send_sig(c, event_signal(c, argv[1], argv[2], argv[3], argv[4],
                           argv[5], argv[6], 1, argv[7]));
  p_dbus_connection_flush(c->conn);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_ax_emit_str(value a, value b, value c, value d,
                               value e, value f, value g, value h)
{
  value argv[8] = { a, b, c, d, e, f, g, h };
  return emit_str_impl(argv);
}

CAMLprim value lui_ax_emit_str_bc(value *argv, int argc)
{
  (void)argc;
  return emit_str_impl(argv);
}

static value emit_ref_impl(value *argv)
{
  CAMLparamN(argv, 8);
  conn_t *c = conn_of(argv[0]);
  send_sig(c, event_signal(c, argv[1], argv[2], argv[3], argv[4],
                           argv[5], argv[6], 2, argv[7]));
  p_dbus_connection_flush(c->conn);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_ax_emit_ref(value a, value b, value c, value d,
                               value e, value f, value g, value h)
{
  value argv[8] = { a, b, c, d, e, f, g, h };
  return emit_ref_impl(argv);
}

CAMLprim value lui_ax_emit_ref_bc(value *argv, int argc)
{
  (void)argc;
  return emit_ref_impl(argv);
}

CAMLprim value lui_ax_emit_sig(value vc, value vpath, value viface,
                               value vmember)
{
  CAMLparam4(vc, vpath, viface, vmember);
  conn_t *c = conn_of(vc);
  DBusMessage *sig = p_dbus_message_new_signal(
      String_val(vpath), String_val(viface), String_val(vmember));
  send_sig(c, sig);
  p_dbus_connection_flush(c->conn);
  CAMLreturn(Val_unit);
}

/* Cache AddAccessible: body is the item struct
   ((so)(so)(so)iiassusau) — object ref, application ref, parent ref,
   index, child count, interfaces, name, role, description, states. */

static value emit_cache_add_impl(value *argv)
{
  CAMLparamN(argv, 10);
  conn_t *c = conn_of(argv[0]);
  const char *self = p_dbus_bus_get_unique_name(c->conn);
  const char *path = String_val(argv[1]);
  const char *parent = String_val(argv[2]);
  dbus_int32_t iip = Int_val(argv[3]);
  dbus_int32_t cc = Int_val(argv[4]);
  value ifaces = argv[5];
  const char *name = String_val(argv[6]);
  dbus_uint32_t role = Int_val(argv[7]);
  const char *desc = String_val(argv[8]);
  value states = argv[9];
  DBusMessage *sig;
  DBusMessageIter it, item, ref, arr;
  if (!self) self = "";
  sig = p_dbus_message_new_signal("/org/a11y/atspi/cache",
                                  "org.a11y.atspi.Cache",
                                  "AddAccessible");
  if (!sig) CAMLreturn(Val_unit);
  p_dbus_message_iter_init_append(sig, &it);
  p_dbus_message_iter_open_container(&it, DBUS_TYPE_STRUCT, 0, &item);
  /* (so) object itself */
  p_dbus_message_iter_open_container(&item, DBUS_TYPE_STRUCT, 0, &ref);
  p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_STRING, &self);
  p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_OBJECT_PATH, &path);
  p_dbus_message_iter_close_container(&item, &ref);
  /* (so) application = our root */
  {
    const char *rp = "/org/a11y/atspi/accessible/root";
    p_dbus_message_iter_open_container(&item, DBUS_TYPE_STRUCT, 0,
                                       &ref);
    p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_STRING, &self);
    p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_OBJECT_PATH, &rp);
    p_dbus_message_iter_close_container(&item, &ref);
  }
  /* (so) parent */
  p_dbus_message_iter_open_container(&item, DBUS_TYPE_STRUCT, 0, &ref);
  p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_STRING, &self);
  p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_OBJECT_PATH,
                                   &parent);
  p_dbus_message_iter_close_container(&item, &ref);
  p_dbus_message_iter_append_basic(&item, DBUS_TYPE_INT32, &iip);
  p_dbus_message_iter_append_basic(&item, DBUS_TYPE_INT32, &cc);
  /* as interfaces */
  p_dbus_message_iter_open_container(&item, DBUS_TYPE_ARRAY, "s",
                                     &arr);
  {
    mlsize_t i, n = Wosize_val(ifaces);
    for (i = 0; i < n; i++) {
      const char *s = String_val(Field(ifaces, i));
      p_dbus_message_iter_append_basic(&arr, DBUS_TYPE_STRING, &s);
    }
  }
  p_dbus_message_iter_close_container(&item, &arr);
  p_dbus_message_iter_append_basic(&item, DBUS_TYPE_STRING, &name);
  p_dbus_message_iter_append_basic(&item, DBUS_TYPE_UINT32, &role);
  p_dbus_message_iter_append_basic(&item, DBUS_TYPE_STRING, &desc);
  /* au states */
  p_dbus_message_iter_open_container(&item, DBUS_TYPE_ARRAY, "u",
                                     &arr);
  {
    mlsize_t i, n = Wosize_val(states);
    for (i = 0; i < n; i++) {
      dbus_uint32_t st = (dbus_uint32_t) Int_val(Field(states, i));
      p_dbus_message_iter_append_basic(&arr, DBUS_TYPE_UINT32, &st);
    }
  }
  p_dbus_message_iter_close_container(&item, &arr);
  p_dbus_message_iter_close_container(&it, &item);
  send_sig(c, sig);
  p_dbus_connection_flush(c->conn);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_ax_emit_cache_add(value a, value b, value c, value d,
                                     value e, value f, value g, value h,
                                     value i, value j)
{
  value argv[10] = { a, b, c, d, e, f, g, h, i, j };
  return emit_cache_add_impl(argv);
}

CAMLprim value lui_ax_emit_cache_add_bc(value *argv, int argc)
{
  (void)argc;
  return emit_cache_add_impl(argv);
}

CAMLprim value lui_ax_emit_cache_remove(value vc, value vpath)
{
  CAMLparam2(vc, vpath);
  conn_t *c = conn_of(vc);
  const char *self = p_dbus_bus_get_unique_name(c->conn);
  const char *p = String_val(vpath);
  DBusMessage *sig;
  DBusMessageIter it, ref;
  if (!self) self = "";
  sig = p_dbus_message_new_signal("/org/a11y/atspi/cache",
                                  "org.a11y.atspi.Cache",
                                  "RemoveAccessible");
  if (!sig) CAMLreturn(Val_unit);
  p_dbus_message_iter_init_append(sig, &it);
  p_dbus_message_iter_open_container(&it, DBUS_TYPE_STRUCT, 0, &ref);
  p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_STRING, &self);
  p_dbus_message_iter_append_basic(&ref, DBUS_TYPE_OBJECT_PATH, &p);
  p_dbus_message_iter_close_container(&it, &ref);
  send_sig(c, sig);
  p_dbus_connection_flush(c->conn);
  CAMLreturn(Val_unit);
}

#else /* !__linux__ */

#include <caml/mlvalues.h>
#include <caml/fail.h>

static value ax_fail(void)
{
  caml_failwith("lui_ax_linux: this backend requires Linux");
  return Val_unit;
}

CAMLprim value lui_ax_dbus_probe(value a)
{
  (void) a;
  return ax_fail();
}

CAMLprim value lui_ax_dbus_open(value a)
{
  (void) a;
  return ax_fail();
}

CAMLprim value lui_ax_dbus_close(value a)
{
  (void) a;
  return ax_fail();
}

CAMLprim value lui_ax_dbus_name(value a)
{
  (void) a;
  return ax_fail();
}

CAMLprim value lui_ax_dbus_a11y_address(value a)
{
  (void) a;
  return ax_fail();
}

CAMLprim value lui_ax_dbus_embed(value a, value b)
{
  (void) a;
  (void) b;
  return ax_fail();
}

CAMLprim value lui_ax_dbus_poll(value a, value b)
{
  (void) a;
  (void) b;
  return ax_fail();
}

CAMLprim value lui_ax_reply(value a, value b, value c)
{
  (void) a;
  (void) b;
  (void) c;
  return ax_fail();
}

CAMLprim value lui_ax_reply_error(value a, value b, value c, value d)
{
  (void) a;
  (void) b;
  (void) c;
  (void) d;
  return ax_fail();
}

CAMLprim value lui_ax_emit_sig(value a, value b, value c, value d)
{
  (void) a;
  (void) b;
  (void) c;
  (void) d;
  return ax_fail();
}

CAMLprim value lui_ax_emit_cache_remove(value a, value b)
{
  (void) a;
  (void) b;
  return ax_fail();
}

/* Externals with arity > 5 use the argv/argc calling convention in
   both native and bytecode mode. */

CAMLprim value lui_ax_emit_num(value *argv, int argc)
{
  (void) argv;
  (void) argc;
  return ax_fail();
}

CAMLprim value lui_ax_emit_num_bc(value *argv, int argc)
{
  return lui_ax_emit_num(argv, argc);
}

CAMLprim value lui_ax_emit_str(value *argv, int argc)
{
  (void) argv;
  (void) argc;
  return ax_fail();
}

CAMLprim value lui_ax_emit_str_bc(value *argv, int argc)
{
  return lui_ax_emit_str(argv, argc);
}

CAMLprim value lui_ax_emit_ref(value *argv, int argc)
{
  (void) argv;
  (void) argc;
  return ax_fail();
}

CAMLprim value lui_ax_emit_ref_bc(value *argv, int argc)
{
  return lui_ax_emit_ref(argv, argc);
}

CAMLprim value lui_ax_emit_cache_add(value *argv, int argc)
{
  (void) argv;
  (void) argc;
  return ax_fail();
}

CAMLprim value lui_ax_emit_cache_add_bc(value *argv, int argc)
{
  return lui_ax_emit_cache_add(argv, argc);
}

#endif
