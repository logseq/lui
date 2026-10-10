/* Desktop shell services for the native backend on Windows: the
   notification-area (tray) icon, popup menus, balloon/toast
   notifications, the clipboard, file dialogs and open-url handling.

   Plain C throughout; COM calls go through the COBJMACROS inline
   wrappers like the other Windows stubs. Every external fails cleanly
   off Windows so the library still builds everywhere.

   Callbacks into OCaml: each event kind has a single handler,
   registered by lui_shell_windows.ml under a fixed named value. All
   events arrive as messages on one hidden window the library owns —
   tray callbacks, menu commands, balloon clicks — so dispatch happens
   on whatever thread pumps that window's queue. The OCaml domain must
   live on that thread: window procedures run reentrantly inside the
   C call that pumps (or inside a menu's own modal loop), which is
   exactly the context a callback into OCaml is legal in. */

#if defined(_WIN32)

#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0600
#endif
#ifndef NTDDI_VERSION
#define NTDDI_VERSION 0x06000000
#endif

#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shobjidl.h>
#include <objbase.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/printexc.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

/* ------------------------------------------------------------ helpers */

/* UTF-8 OCaml string -> freshly allocated NUL-terminated UTF-16.
   An OCaml string is bytes plus a length, so embedded NULs survive —
   Win32 APIs take the terminator anyway. Falls back to CP_ACP for
   bytes that are not valid UTF-8. */
static WCHAR *lui_u16(const char *s, mlsize_t len)
{
  int n = MultiByteToWideChar(CP_UTF8, 0, s, (int)len, NULL, 0);
  WCHAR *w;
  if (n <= 0 && len > 0) {
    n = MultiByteToWideChar(CP_ACP, 0, s, (int)len, NULL, 0);
    w = (WCHAR *)malloc((size_t)(n + 1) * sizeof(WCHAR));
    if (w == NULL) return NULL;
    MultiByteToWideChar(CP_ACP, 0, s, (int)len, w, n);
  } else {
    w = (WCHAR *)malloc((size_t)(n + 1) * sizeof(WCHAR));
    if (w == NULL) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, s, (int)len, w, n);
  }
  w[n] = 0;
  return w;
}

static WCHAR *lui_u16v(value v)
{
  return lui_u16((const char *)Bytes_val(v), caml_string_length(v));
}

static value lui_ocamlstring_u16(const WCHAR *w)
{
  CAMLparam0();
  CAMLlocal1(v);
  int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
  if (n <= 1) CAMLreturn(caml_alloc_initialized_string(0, ""));
  v = caml_alloc_string((mlsize_t)(n - 1));
  WideCharToMultiByte(CP_UTF8, 0, w, -1,
                      (char *)Bytes_val(v), n, NULL, NULL);
  CAMLreturn(v);
}

static void lui_log_exn(value res, const char *name)
{
  if (Is_exception_result(res)) {
    char *msg = caml_format_exception(Extract_exception(res));
    fprintf(stderr, "lui_shell_windows: %s callback raised: %s\n",
            name, msg);
    caml_stat_free(msg);
  }
}

static void lui_cb_int(const char *name, intnat v)
{
  const value *cb = caml_named_value(name);
  if (cb == NULL) return;
  CAMLparam0();
  lui_log_exn(caml_callback_exn(*cb, Val_long(v)), name);
  CAMLreturn0;
}

static void lui_cb_str(const char *name, const char *utf8)
{
  const value *cb = caml_named_value(name);
  if (cb == NULL || utf8 == NULL) return;
  CAMLparam0();
  CAMLlocal1(vs);
  vs = caml_alloc_initialized_string((mlsize_t)strlen(utf8), utf8);
  lui_log_exn(caml_callback_exn(*cb, vs), name);
  CAMLreturn0;
}

/* --------------------------------------------------- command ids */

/* WM_COMMAND and TrackPopupMenuEx carry 16-bit command ids; each maps
   back to the OCaml item id it was built from. Ids >= 0xF000 are
   system commands and must not be allocated. */
struct lui_cmd { UINT cmd; int id; int owner; };

static struct lui_cmd *lui_cmds = NULL;
static int lui_ncmds = 0, lui_cmds_cap = 0;
static UINT lui_next_cmd = 0;

static UINT lui_cmd_add(int id, int owner)
{
  int i;
  for (i = 0; i < 0xEFFF; i++) {
    int k;
    lui_next_cmd++;
    if (lui_next_cmd == 0 || lui_next_cmd >= 0xF000) lui_next_cmd = 1;
    for (k = 0; k < lui_ncmds; k++)
      if (lui_cmds[k].cmd == lui_next_cmd) break;
    if (k == lui_ncmds) {
      if (lui_ncmds == lui_cmds_cap) {
        int cap = lui_cmds_cap ? lui_cmds_cap * 2 : 32;
        struct lui_cmd *p =
          (struct lui_cmd *)realloc(lui_cmds,
                                    (size_t)cap * sizeof(*p));
        if (p == NULL) return 0;
        lui_cmds = p;
        lui_cmds_cap = cap;
      }
      lui_cmds[lui_ncmds].cmd = lui_next_cmd;
      lui_cmds[lui_ncmds].id = id;
      lui_cmds[lui_ncmds].owner = owner;
      lui_ncmds++;
      return lui_next_cmd;
    }
  }
  return 0;
}

static int lui_cmd_find(UINT cmd)
{
  int i;
  for (i = 0; i < lui_ncmds; i++)
    if (lui_cmds[i].cmd == cmd) return lui_cmds[i].id;
  return -1;
}

/* Forgets the commands of one owner (a built menu). */
static void lui_cmd_drop(int owner)
{
  int i = 0;
  while (i < lui_ncmds) {
    if (lui_cmds[i].owner == owner) {
      lui_cmds[i] = lui_cmds[lui_ncmds - 1];
      lui_ncmds--;
    } else {
      i++;
    }
  }
}

static int lui_next_owner = 0;

static void lui_menu_dispatch(UINT cmd)
{
  int id = lui_cmd_find(cmd);
  if (id >= 0) lui_cb_int("lui_shellw_menu_select", id);
}

/* ----------------------------------------------------- menu build */

/* Rows from the OCaml side: (depth, kind, label, id, enabled, checked)
   with kind 0 item, 1 separator, 2 submenu; a submenu's children
   follow it at depth+1. */
static HMENU lui_menu_build(value rows, int owner)
{
  HMENU root = CreatePopupMenu();
  HMENU stack[64];
  mlsize_t n, i;
  if (root == NULL) return NULL;
  memset(stack, 0, sizeof(stack));
  stack[0] = root;
  n = Wosize_val(rows);
  for (i = 0; i < n; i++) {
    value row = Field(rows, i);
    int depth = Int_val(Field(row, 0));
    int kind = Int_val(Field(row, 1));
    WCHAR *label = lui_u16v(Field(row, 2));
    int ident = Int_val(Field(row, 3));
    int enabled = Int_val(Field(row, 4)) != 0;
    int checked = Int_val(Field(row, 5)) != 0;

    /* stack[depth] is the most recent submenu seen at depth-1 — the
       flattening guarantees children follow their submenu row.
       Rows that overstep the depth cap, or arrive at a depth no
       submenu opened, are skipped. */
    if (depth < 0 || depth > 62 || stack[depth] == NULL) {
      free(label); continue;
    }
    {
      UINT flags = MF_STRING;
      if (!enabled) flags |= MF_GRAYED;
      if (kind == 1) {
        AppendMenuW(stack[depth], MF_SEPARATOR, 0, NULL);
      } else if (kind == 2) {
        HMENU sub = CreatePopupMenu();
        if (sub != NULL &&
            AppendMenuW(stack[depth], flags | MF_POPUP,
                        (UINT_PTR)sub, label ? label : L"")) {
          stack[depth + 1] = sub;
        }
      } else {
        UINT cmd = lui_cmd_add(ident, owner);
        if (checked) flags |= MF_CHECKED;
        if (cmd != 0)
          AppendMenuW(stack[depth], flags, cmd,
                      label ? label : L"");
      }
    }
    free(label);
  }
  return root;
}

/* Synchronous popup at the cursor, dispatching the selection through
   the menu handler. Returns the command id chosen, 0 when dismissed. */
static UINT lui_popup_track(HWND owner, HMENU m)
{
  POINT pt;
  UINT cmd;
  GetCursorPos(&pt);
  /* The owner must be in the foreground or the menu does not close
     when the user clicks elsewhere. */
  SetForegroundWindow(owner);
  cmd = (UINT)TrackPopupMenuEx(m,
          TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY,
          pt.x, pt.y, owner, NULL);
  PostMessageW(owner, WM_NULL, 0, 0); /* as the documentation asks */
  return cmd;
}

/* --------------------------------------------------- hidden window */

#define LUI_WM_TRAY (WM_APP + 42)

struct lui_tray {
  UINT id;
  int tag;
  HWND hwnd;
  HICON icon;
  HMENU menu;
  int menu_owner;
  WCHAR *tip;
  char *notify_id;
  int added;
  int temporary;
  int on_click;
  int ocaml_owned;
};

static HWND lui_hwnd = NULL;
static ATOM lui_class = 0;

static struct lui_tray **lui_trays = NULL;
static int lui_ntrays = 0, lui_trays_cap = 0;
static UINT lui_next_tray_id = 0;

static struct lui_tray *lui_tray_find(UINT id);
static void lui_tray_finish_notify(struct lui_tray *t);

static LRESULT CALLBACK lui_wndproc(HWND h, UINT m, WPARAM w, LPARAM l)
{
  if (m == LUI_WM_TRAY) {
    struct lui_tray *t = lui_tray_find((UINT)w);
    UINT event = (UINT)LOWORD(l);
    if (t == NULL) return 0;
    switch (event) {
    case WM_LBUTTONUP:
      if (t->on_click)
        lui_cb_int("lui_shellw_status_click", t->tag);
      break;
    case WM_RBUTTONUP:
      if (t->menu != NULL) {
        UINT cmd = lui_popup_track(t->hwnd, t->menu);
        if (cmd != 0) lui_menu_dispatch(cmd);
      }
      break;
    case NIN_BALLOONUSERCLICK:
      if (t->notify_id != NULL)
        lui_cb_str("lui_shellw_notify_click", t->notify_id);
      /* fall through */
    case NIN_BALLOONTIMEOUT:
    case NIN_BALLOONHIDE:
    case NIN_POPUPCLOSE:
      lui_tray_finish_notify(t);
      break;
    }
    return 0;
  }
  if (m == WM_COMMAND && HIWORD(w) == 0) {
    /* Menu commands: only reached for menus shown without
       TPM_RETURNCMD (a window menu bar we do not build); popup
       selections arrive through lui_popup_track instead. */
    lui_menu_dispatch(LOWORD(w));
    return 0;
  }
  return DefWindowProcW(h, m, w, l);
}

/* The hidden window the tray callbacks and menu commands target.
   A plain invisible overlapped window, not a message-only one:
   SetForegroundWindow must be able to take it for menus to track. */
static HWND lui_msg_window(void)
{
  if (lui_hwnd != NULL) return lui_hwnd;
  if (lui_class == 0) {
    WNDCLASSEXW wc;
    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = lui_wndproc;
    wc.hInstance = GetModuleHandleW(NULL);
    wc.lpszClassName = L"LuiShellWindows";
    lui_class = RegisterClassExW(&wc);
    if (lui_class == 0) return NULL;
  }
  lui_hwnd = CreateWindowExW(0, L"LuiShellWindows", L"", WS_OVERLAPPED,
                             0, 0, 0, 0, NULL, NULL,
                             GetModuleHandleW(NULL), NULL);
  return lui_hwnd;
}

/* ---------------------------------------------------------- tray */

static struct lui_tray *lui_tray_find(UINT id)
{
  int i;
  for (i = 0; i < lui_ntrays; i++)
    if (lui_trays[i]->id == id) return lui_trays[i];
  return NULL;
}

static void lui_tray_register(struct lui_tray *t)
{
  if (lui_ntrays == lui_trays_cap) {
    int cap = lui_trays_cap ? lui_trays_cap * 2 : 8;
    struct lui_tray **p =
      (struct lui_tray **)realloc(lui_trays,
                                  (size_t)cap * sizeof(*p));
    if (p == NULL) return;
    lui_trays = p;
    lui_trays_cap = cap;
  }
  lui_trays[lui_ntrays++] = t;
}

static void lui_tray_unregister(struct lui_tray *t)
{
  int i;
  for (i = 0; i < lui_ntrays; i++)
    if (lui_trays[i] == t) {
      lui_trays[i] = lui_trays[lui_ntrays - 1];
      lui_ntrays--;
      return;
    }
}

static void lui_tray_data(struct lui_tray *t, NOTIFYICONDATAW *d)
{
  memset(d, 0, sizeof(*d));
  d->cbSize = sizeof(*d);
  d->hWnd = t->hwnd;
  d->uID = t->id;
  d->uFlags = NIF_MESSAGE;
  d->uCallbackMessage = LUI_WM_TRAY;
  if (t->icon != NULL) {
    d->uFlags |= NIF_ICON;
    d->hIcon = t->icon;
  }
  if (t->tip != NULL) {
    d->uFlags |= NIF_TIP | NIF_SHOWTIP;
    wcsncpy(d->szTip, t->tip,
            sizeof(d->szTip) / sizeof(WCHAR) - 1);
    d->szTip[sizeof(d->szTip) / sizeof(WCHAR) - 1] = 0;
  }
  if (t->icon == NULL && t->tip == NULL)
    d->hIcon = LoadIconW(NULL, (LPCWSTR)32512); /* IDI_APPLICATION */
}

/* Pushes the tray's current fields to the shell; tries NIM_ADD once
   for items not yet on the notification area. */
static void lui_tray_sync(struct lui_tray *t)
{
  NOTIFYICONDATAW d;
  if (t->hwnd == NULL) t->hwnd = lui_msg_window();
  if (t->hwnd == NULL) return;
  lui_tray_data(t, &d);
  if (!t->added) {
    NOTIFYICONDATAW v;
    if (!Shell_NotifyIconW(NIM_ADD, &d)) return;
    t->added = 1;
    /* Version 4 so balloon clicks arrive as NIN_BALLOONUSERCLICK. */
    v = d;
    v.uFlags = 0;
    v.uVersion = 4;
    Shell_NotifyIconW(NIM_SETVERSION, &v);
  } else {
    Shell_NotifyIconW(NIM_MODIFY, &d);
  }
}

static void lui_tray_teardown(struct lui_tray *t)
{
  NOTIFYICONDATAW d;
  if (t->added && t->hwnd != NULL) {
    lui_tray_data(t, &d);
    Shell_NotifyIconW(NIM_DELETE, &d);
  }
  t->added = 0;
}

static void lui_tray_free_fields(struct lui_tray *t)
{
  if (t->icon != NULL) { DestroyIcon(t->icon); t->icon = NULL; }
  if (t->menu != NULL) {
    DestroyMenu(t->menu);
    lui_cmd_drop(t->menu_owner);
    t->menu = NULL;
  }
  free(t->tip);
  t->tip = NULL;
  free(t->notify_id);
  t->notify_id = NULL;
}

/* A balloon has closed: forget its id, and a temporary tray made only
   to carry it goes away entirely. */
static void lui_tray_finish_notify(struct lui_tray *t)
{
  free(t->notify_id);
  t->notify_id = NULL;
  if (t->temporary) {
    lui_tray_teardown(t);
    lui_tray_unregister(t);
    lui_tray_free_fields(t);
    free(t);
  } else {
    /* An empty balloon field hides the current one. */
    NOTIFYICONDATAW d;
    if (!t->added) return;
    memset(&d, 0, sizeof(d));
    d.cbSize = sizeof(d);
    d.hWnd = t->hwnd;
    d.uID = t->id;
    d.uFlags = NIF_INFO;
    Shell_NotifyIconW(NIM_MODIFY, &d);
  }
}

#define Lui_icon_val(v) (*(HICON *)Data_custom_val(v))
#define Lui_tray_val(v) (*(struct lui_tray **)Data_custom_val(v))

static void lui_icon_finalize(value v)
{
  HICON h = Lui_icon_val(v);
  if (h != NULL) DestroyIcon(h);
}

static void lui_tray_finalize(value v)
{
  struct lui_tray *t = Lui_tray_val(v);
  if (t == NULL) return;
  lui_tray_teardown(t);
  lui_tray_unregister(t);
  lui_tray_free_fields(t);
  free(t);
  Lui_tray_val(v) = NULL;
}

static struct custom_operations lui_icon_ops = {
  "lui_shell_windows.icon",
  lui_icon_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static struct custom_operations lui_tray_ops = {
  "lui_shell_windows.status_item",
  lui_tray_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static value lui_wrap_icon(HICON h)
{
  value v = caml_alloc_custom(&lui_icon_ops, sizeof(HICON), 0, 1);
  Lui_icon_val(v) = h;
  return v;
}

static value lui_wrap_tray(struct lui_tray *t)
{
  value v =
    caml_alloc_custom(&lui_tray_ops, sizeof(struct lui_tray *), 0, 1);
  Lui_tray_val(v) = t;
  return v;
}

/* ------------------------------------------------------------- image */

CAMLprim value lui_shw_image_rgba(value vw, value vh, value vbytes)
{
  CAMLparam3(vw, vh, vbytes);
  CAMLlocal2(vopt, vimg);
  int w = Int_val(vw);
  int h = Int_val(vh);
  HICON icon = NULL;
  if (w > 0 && h > 0 &&
      (size_t)caml_string_length(vbytes) >= (size_t)(w * h * 4)) {
    BITMAPV5HEADER b5;
    void *bits = NULL;
    HBITMAP color, mask;
    ICONINFO ii;
    memset(&b5, 0, sizeof(b5));
    b5.bV5Size = sizeof(b5);
    b5.bV5Width = w;
    b5.bV5Height = -h; /* top-down */
    b5.bV5Planes = 1;
    b5.bV5BitCount = 32;
    b5.bV5Compression = BI_BITFIELDS;
    b5.bV5RedMask = 0x00FF0000;
    b5.bV5GreenMask = 0x0000FF00;
    b5.bV5BlueMask = 0x000000FF;
    b5.bV5AlphaMask = 0xFF000000;
    color = CreateDIBSection(NULL, (BITMAPINFO *)&b5, DIB_RGB_COLORS,
                             &bits, NULL, 0);
    mask = CreateBitmap(w, h, 1, 1, NULL);
    if (color != NULL && bits != NULL && mask != NULL) {
      /* RGBA -> premultiplied BGRA: 32bpp icons composite with
         the alpha channel when the AND mask is all zero. */
      const unsigned char *src = (const unsigned char *)Bytes_val(vbytes);
      unsigned char *dst = (unsigned char *)bits;
      int np = w * h, i;
      for (i = 0; i < np; i++) {
        unsigned a = src[i * 4 + 3];
        dst[i * 4 + 0] = (unsigned char)((src[i * 4 + 2] * a + 127) / 255);
        dst[i * 4 + 1] = (unsigned char)((src[i * 4 + 1] * a + 127) / 255);
        dst[i * 4 + 2] = (unsigned char)((src[i * 4 + 0] * a + 127) / 255);
        dst[i * 4 + 3] = (unsigned char)a;
      }
      memset(&ii, 0, sizeof(ii));
      ii.fIcon = TRUE;
      ii.hbmColor = color;
      ii.hbmMask = mask;
      icon = CreateIconIndirect(&ii);
    }
    if (color != NULL) DeleteObject(color);
    if (mask != NULL) DeleteObject(mask);
  }
  if (icon == NULL) CAMLreturn(Val_int(0));
  vimg = lui_wrap_icon(icon);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vimg);
  CAMLreturn(vopt);
}

CAMLprim value lui_shw_image_size(value vimg)
{
  CAMLparam1(vimg);
  CAMLlocal1(vsize);
  double w = 0, h = 0;
  ICONINFO ii;
  if (GetIconInfo(Lui_icon_val(vimg), &ii)) {
    BITMAP bm;
    HBITMAP hb = ii.hbmColor != NULL ? ii.hbmColor : ii.hbmMask;
    if (hb != NULL && GetObjectW(hb, sizeof(bm), &bm)) {
      w = (double)bm.bmWidth;
      h = (double)bm.bmHeight;
      if (ii.hbmColor == NULL) h = h / 2; /* mask doubles as XOR+AND */
    }
    if (ii.hbmColor != NULL) DeleteObject(ii.hbmColor);
    if (ii.hbmMask != NULL) DeleteObject(ii.hbmMask);
  }
  vsize = caml_alloc(2, 0);
  Store_field(vsize, 0, caml_copy_double(w));
  Store_field(vsize, 1, caml_copy_double(h));
  CAMLreturn(vsize);
}

/* ------------------------------------------------------------- menus */

CAMLprim value lui_shw_popup_menu(value vrows)
{
  CAMLparam1(vrows);
  HWND hw = lui_msg_window();
  int id = -1;
  if (hw != NULL) {
    int owner = ++lui_next_owner;
    HMENU m = lui_menu_build(vrows, owner);
    if (m != NULL) {
      UINT cmd = lui_popup_track(hw, m);
      if (cmd != 0) {
        id = lui_cmd_find(cmd);
        lui_menu_dispatch(cmd);
      }
      DestroyMenu(m);
    }
    lui_cmd_drop(owner);
  }
  CAMLreturn(Val_int(id));
}

/* ------------------------------------------------------- status item */

CAMLprim value lui_shw_status_create(value vtag)
{
  CAMLparam1(vtag);
  CAMLlocal1(vsi);
  struct lui_tray *t = (struct lui_tray *)calloc(1, sizeof(*t));
  if (t == NULL) caml_failwith("lui_shell_windows: out of memory");
  t->id = ++lui_next_tray_id;
  t->tag = (int)Int_val(vtag);
  t->hwnd = lui_msg_window();
  t->ocaml_owned = 1;
  lui_tray_register(t);
  lui_tray_sync(t);
  vsi = lui_wrap_tray(t);
  CAMLreturn(vsi);
}

CAMLprim value lui_shw_status_remove(value vsi)
{
  CAMLparam1(vsi);
  struct lui_tray *t = Lui_tray_val(vsi);
  if (t != NULL) {
    lui_tray_teardown(t);
    lui_tray_unregister(t);
    lui_tray_free_fields(t);
    free(t);
    Lui_tray_val(vsi) = NULL;
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shw_status_set_title(value vsi, value vtitle)
{
  CAMLparam2(vsi, vtitle);
  struct lui_tray *t = Lui_tray_val(vsi);
  if (t != NULL) {
    WCHAR *tip = lui_u16v(vtitle);
    free(t->tip);
    t->tip = tip;
    lui_tray_sync(t);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shw_status_set_image(value vsi, value vopt)
{
  CAMLparam2(vsi, vopt);
  struct lui_tray *t = Lui_tray_val(vsi);
  if (t != NULL) {
    HICON icon = Is_block(vopt) ? Lui_icon_val(Field(vopt, 0)) : NULL;
    /* The tray owns its icon: the image custom block keeps its own
       handle, so the tray always displays a copy. */
    if (t->icon != NULL) DestroyIcon(t->icon);
    t->icon = icon != NULL ? CopyIcon(icon) : NULL;
    lui_tray_sync(t);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shw_status_set_menu(value vsi, value vrows_opt)
{
  CAMLparam2(vsi, vrows_opt);
  struct lui_tray *t = Lui_tray_val(vsi);
  if (t != NULL) {
    if (t->menu != NULL) {
      DestroyMenu(t->menu);
      lui_cmd_drop(t->menu_owner);
      t->menu = NULL;
    }
    if (Is_block(vrows_opt)) {
      t->menu_owner = ++lui_next_owner;
      t->menu = lui_menu_build(Field(vrows_opt, 0), t->menu_owner);
    }
    lui_tray_sync(t);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_shw_status_set_on_click(value vsi, value von)
{
  CAMLparam2(vsi, von);
  struct lui_tray *t = Lui_tray_val(vsi);
  if (t != NULL) t->on_click = Bool_val(von);
  CAMLreturn(Val_unit);
}

/* -------------------------------------------------------- notification */

/* A balloon notification is a field of a tray icon. The first tray not
   already carrying one is used; with none, a temporary icon is added
   just to carry it (Windows 10 and later render the balloon as a
   toast). */
static struct lui_tray *lui_notify_tray(void)
{
  int i;
  struct lui_tray *t;
  HICON shared;
  for (i = 0; i < lui_ntrays; i++) {
    if (!lui_trays[i]->temporary && lui_trays[i]->notify_id == NULL)
      return lui_trays[i];
  }
  shared = LoadIconW(NULL, (LPCWSTR)32512); /* IDI_APPLICATION */
  if (shared == NULL) return NULL;
  t = (struct lui_tray *)calloc(1, sizeof(*t));
  if (t == NULL) return NULL;
  t->id = ++lui_next_tray_id;
  t->hwnd = lui_msg_window();
  t->temporary = 1;
  /* The tray owns its icons, so take a copy of the shared stock icon. */
  t->icon = CopyIcon(shared);
  if (t->icon == NULL) { free(t); return NULL; }
  lui_tray_register(t);
  if (t->hwnd != NULL) {
    NOTIFYICONDATAW d, v;
    lui_tray_data(t, &d);
    if (Shell_NotifyIconW(NIM_ADD, &d)) {
      t->added = 1;
      v = d;
      v.uFlags = 0;
      v.uVersion = 4;
      Shell_NotifyIconW(NIM_SETVERSION, &v);
      return t;
    }
  }
  lui_tray_unregister(t);
  lui_tray_free_fields(t);
  free(t);
  return NULL;
}

CAMLprim value lui_shw_notify(value vid, value vtitle, value vsub,
                              value vbody)
{
  CAMLparam4(vid, vtitle, vsub, vbody);
  CAMLlocal2(vres, vdetail);
  BOOL ok = FALSE;
  const char *detail = "unavailable";
  struct lui_tray *t = lui_notify_tray();
  if (t == NULL) {
    detail = "no tray icon can be shown";
  } else {
    NOTIFYICONDATAW d;
    WCHAR *title = lui_u16v(vtitle);
    WCHAR *sub = lui_u16v(vsub);
    WCHAR *body = lui_u16v(vbody);
    char *id8 = NULL;
    {
      mlsize_t n = caml_string_length(vid);
      id8 = (char *)malloc(n + 1);
      if (id8 != NULL) {
        memcpy(id8, Bytes_val(vid), n);
        id8[n] = 0;
      }
    }
    memset(&d, 0, sizeof(d));
    d.cbSize = sizeof(d);
    d.hWnd = t->hwnd;
    d.uID = t->id;
    d.uFlags = NIF_INFO;
    if (title != NULL) {
      wcsncpy(d.szInfoTitle, title,
              sizeof(d.szInfoTitle) / sizeof(WCHAR) - 1);
      d.szInfoTitle[sizeof(d.szInfoTitle) / sizeof(WCHAR) - 1] = 0;
    }
    {
      /* The body carries the subtitle as its first line. */
      WCHAR *line = body;
      WCHAR *joined = NULL;
      if (sub != NULL && sub[0] != 0) {
        size_t a = wcslen(sub), b = body ? wcslen(body) : 0;
        joined = (WCHAR *)malloc((a + b + 2) * sizeof(WCHAR));
        if (joined != NULL) {
          memcpy(joined, sub, a * sizeof(WCHAR));
          joined[a] = L'\n';
          memcpy(joined + a + 1, body ? body : L"",
                 (b + 1) * sizeof(WCHAR));
          line = joined;
        }
      }
      if (line != NULL) {
        wcsncpy(d.szInfo, line, sizeof(d.szInfo) / sizeof(WCHAR) - 1);
        d.szInfo[sizeof(d.szInfo) / sizeof(WCHAR) - 1] = 0;
      }
      free(joined);
    }
    /* NIIF_USER puts the tray icon on the balloon; NOSOUND matches the
       quiet-by-default toast behavior. */
    d.dwInfoFlags = NIIF_USER | NIIF_NOSOUND;
    if (t->hwnd != NULL && Shell_NotifyIconW(NIM_MODIFY, &d)) {
      free(t->notify_id);
      t->notify_id = id8;
      id8 = NULL;
      ok = TRUE;
      detail = "tray-balloon";
    } else {
      detail = "balloon update failed";
      lui_tray_finish_notify(t);
    }
    free(id8);
    free(title);
    free(sub);
    free(body);
  }
  vdetail = caml_alloc_initialized_string((mlsize_t)strlen(detail),
                                          detail);
  vres = caml_alloc(2, 0);
  Store_field(vres, 0, Val_bool(ok));
  Store_field(vres, 1, vdetail);
  CAMLreturn(vres);
}

/* --------------------------------------------------------- clipboard */

/* Opens the clipboard, retrying briefly while another program holds
   it. The hidden window owns the open when it exists. */
static int lui_clip_open(void)
{
  int i;
  for (i = 0; i < 10; i++) {
    if (OpenClipboard(lui_msg_window())) return 1;
    Sleep(10);
  }
  return 0;
}

CAMLprim value lui_shw_clip_write(value vstr)
{
  CAMLparam1(vstr);
  BOOL ok = FALSE;
  if (lui_clip_open()) {
    if (EmptyClipboard()) {
      WCHAR *w = lui_u16v(vstr);
      if (w != NULL) {
        size_t n = (wcslen(w) + 1) * sizeof(WCHAR);
        HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, n);
        if (h != NULL) {
          void *p = GlobalLock(h);
          if (p != NULL) {
            memcpy(p, w, n);
            GlobalUnlock(h);
            ok = SetClipboardData(CF_UNICODETEXT, h) != NULL;
            if (!ok) GlobalFree(h);
          } else {
            GlobalFree(h);
          }
        }
        free(w);
      }
    }
    CloseClipboard();
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_shw_clip_read(value unit)
{
  CAMLparam1(unit);
  CAMLlocal2(vopt, vs);
  vopt = Val_int(0);
  if (lui_clip_open()) {
    HGLOBAL h = GetClipboardData(CF_UNICODETEXT);
    if (h != NULL) {
      const WCHAR *w = (const WCHAR *)GlobalLock(h);
      if (w != NULL) {
        vs = lui_ocamlstring_u16(w);
        GlobalUnlock(h);
        vopt = caml_alloc(1, 0);
        Store_field(vopt, 0, vs);
      }
    }
    CloseClipboard();
  }
  CAMLreturn(vopt);
}

CAMLprim value lui_shw_clip_clear(value unit)
{
  CAMLparam1(unit);
  int n = -1;
  if (lui_clip_open()) {
    EmptyClipboard();
    CloseClipboard();
    n = (int)GetClipboardSequenceNumber();
  }
  CAMLreturn(Val_int(n));
}

CAMLprim value lui_shw_clip_count(value unit)
{
  CAMLparam1(unit);
  DWORD n = GetClipboardSequenceNumber();
  CAMLreturn(Val_int(n == 0 ? -1 : (int)n));
}

/* Registered formats: a name becomes a CF_* id the first time it is
   asked for. */
static UINT lui_clip_format(value vname)
{
  WCHAR *w = lui_u16v(vname);
  UINT f = 0;
  if (w != NULL) {
    f = RegisterClipboardFormatW(w);
    free(w);
  }
  return f;
}

CAMLprim value lui_shw_clip_write_format(value vname, value vdata)
{
  CAMLparam2(vname, vdata);
  BOOL ok = FALSE;
  UINT fmt = lui_clip_format(vname);
  if (fmt != 0 && lui_clip_open()) {
    mlsize_t n = caml_string_length(vdata);
    HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, (SIZE_T)(n > 0 ? n : 1));
    if (h != NULL) {
      void *p = GlobalLock(h);
      if (p != NULL) {
        memcpy(p, Bytes_val(vdata), n);
        GlobalUnlock(h);
        ok = SetClipboardData(fmt, h) != NULL;
        if (!ok) GlobalFree(h);
      } else {
        GlobalFree(h);
      }
    }
    CloseClipboard();
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_shw_clip_read_format(value vname)
{
  CAMLparam1(vname);
  CAMLlocal2(vopt, vs);
  UINT fmt = lui_clip_format(vname);
  vopt = Val_int(0);
  if (fmt != 0 && lui_clip_open()) {
    HGLOBAL h = GetClipboardData(fmt);
    if (h != NULL) {
      SIZE_T n = GlobalSize(h);
      const void *p = GlobalLock(h);
      if (p != NULL && n > 0) {
        vs = caml_alloc_initialized_string((mlsize_t)n, (const char *)p);
        GlobalUnlock(h);
        vopt = caml_alloc(1, 0);
        Store_field(vopt, 0, vs);
      } else if (p != NULL) {
        GlobalUnlock(h);
      }
    }
    CloseClipboard();
  }
  CAMLreturn(vopt);
}

/* ------------------------------------------------------------ dialogs */

static int lui_com_ready = 0;

static int lui_com_init(void)
{
  HRESULT hr;
  if (lui_com_ready) return 1;
  hr = CoInitializeEx(NULL,
        COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
  /* RPC_E_CHANGED_MODE: something already initialized us MTA — COM
     dialogs still work on this thread. */
  if (SUCCEEDED(hr) || hr == RPC_E_CHANGED_MODE) {
    lui_com_ready = 1;
    return 1;
  }
  return 0;
}

/* Whether an interactive input desktop can present UI right now. */
static int lui_can_present(void)
{
  HDESK d = OpenInputDesktop(0, FALSE, GENERIC_READ);
  if (d != NULL) {
    CloseDesktop(d);
    return 1;
  }
  return 0;
}

CAMLprim value lui_shw_can_present(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(lui_can_present()));
}

/* One filter spec joining every extension: "md;txt" -> "*.md;*.txt". */
static int lui_dialog_filters(value vfilters, COMDLG_FILTERSPEC *spec,
                              WCHAR **buf_out)
{
  mlsize_t n = Wosize_val(vfilters);
  mlsize_t i;
  SIZE_T total = 2; /* "*" + NUL */
  WCHAR *buf, *p;
  if (n == 0) return 0;
  for (i = 0; i < n; i++)
    total += caml_string_length(Field(vfilters, i)) + 1;
  buf = (WCHAR *)malloc(total * sizeof(WCHAR));
  if (buf == NULL) return 0;
  p = buf;
  *p++ = L'*';
  *p++ = L'.';
  for (i = 0; i < n; i++) {
    WCHAR *w = lui_u16v(Field(vfilters, i));
    if (w != NULL) {
      size_t l = wcslen(w);
      if (i > 0) *p++ = L';';
      memcpy(p, w, l * sizeof(WCHAR));
      p += l;
      free(w);
    }
  }
  *p = 0;
  spec->pszName = buf;
  spec->pszSpec = buf;
  *buf_out = buf;
  return 1;
}

static value lui_shell_item_path(IShellItem *item)
{
  CAMLparam0();
  CAMLlocal1(vs);
  LPWSTR p = NULL;
  vs = caml_alloc_initialized_string(0, "");
  if (SUCCEEDED(IShellItem_GetDisplayName(item, SIGDN_FILESYSPATH, &p))
      && p != NULL) {
    vs = lui_ocamlstring_u16(p);
    CoTaskMemFree(p);
  }
  CAMLreturn(vs);
}

CAMLprim value lui_shw_open_panel(value vfiles, value vdirs,
                                  value vmulti, value vfilters)
{
  CAMLparam4(vfiles, vdirs, vmulti, vfilters);
  CAMLlocal3(vopt, varr, vs);
  vopt = Val_int(0);
  if (lui_com_init() && lui_can_present()) {
    IFileOpenDialog *dlg = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_FileOpenDialog, NULL,
                                  CLSCTX_ALL, &IID_IFileOpenDialog,
                                  (void **)&dlg);
    if (SUCCEEDED(hr) && dlg != NULL) {
      DWORD opts = 0;
      COMDLG_FILTERSPEC spec;
      WCHAR *specbuf = NULL;
      IFileDialog_GetOptions(dlg, &opts);
      opts |= FOS_FORCEFILESYSTEM | FOS_PATHMUSTEXIST;
      if (Bool_val(vdirs)) opts |= FOS_PICKFOLDERS;
      else opts |= FOS_FILEMUSTEXIST;
      if (Bool_val(vmulti)) opts |= FOS_ALLOWMULTISELECT;
      IFileDialog_SetOptions(dlg, opts);
      if (lui_dialog_filters(vfilters, &spec, &specbuf))
        IFileDialog_SetFileTypes(dlg, 1, &spec);
      hr = IFileDialog_Show(dlg, NULL);
      if (hr == S_OK) {
        IShellItemArray *items = NULL;
        if (SUCCEEDED(IFileOpenDialog_GetResults(dlg, &items))
            && items != NULL) {
          DWORD count = 0, i;
          IShellItemArray_GetCount(items, &count);
          varr = caml_alloc((mlsize_t)count, 0);
          for (i = 0; i < count; i++) {
            IShellItem *item = NULL;
            if (SUCCEEDED(IShellItemArray_GetItemAt(items, i, &item))
                && item != NULL) {
              vs = lui_shell_item_path(item);
              IShellItem_Release(item);
            } else {
              vs = caml_alloc_initialized_string(0, "");
            }
            Store_field(varr, i, vs);
          }
          vopt = caml_alloc(1, 0);
          Store_field(vopt, 0, varr);
          IShellItemArray_Release(items);
        }
      }
      /* HRESULT_FROM_WIN32(ERROR_CANCELLED) and friends: vopt stays
         None. */
      IFileOpenDialog_Release(dlg);
      free(specbuf);
    }
  }
  CAMLreturn(vopt);
}

CAMLprim value lui_shw_save_panel(value vname)
{
  CAMLparam1(vname);
  CAMLlocal2(vopt, vs);
  vopt = Val_int(0);
  if (lui_com_init() && lui_can_present()) {
    IFileSaveDialog *dlg = NULL;
    HRESULT hr = CoCreateInstance(&CLSID_FileSaveDialog, NULL,
                                  CLSCTX_ALL, &IID_IFileSaveDialog,
                                  (void **)&dlg);
    if (SUCCEEDED(hr) && dlg != NULL) {
      DWORD opts = 0;
      WCHAR *name = lui_u16v(vname);
      IFileDialog_GetOptions(dlg, &opts);
      IFileDialog_SetOptions(dlg, opts | FOS_FORCEFILESYSTEM
                                    | FOS_OVERWRITEPROMPT
                                    | FOS_PATHMUSTEXIST);
      if (name != NULL && name[0] != 0)
        IFileDialog_SetFileName(dlg, name);
      hr = IFileDialog_Show(dlg, NULL);
      if (hr == S_OK) {
        IShellItem *item = NULL;
        if (SUCCEEDED(IFileDialog_GetResult(dlg, &item))
            && item != NULL) {
          vs = lui_shell_item_path(item);
          vopt = caml_alloc(1, 0);
          Store_field(vopt, 0, vs);
          IShellItem_Release(item);
        }
      }
      IFileSaveDialog_Release(dlg);
      free(name);
    }
  }
  CAMLreturn(vopt);
}

/* ------------------------------------------------------------ open-url */

CAMLprim value lui_shw_open_url(value vurl)
{
  CAMLparam1(vurl);
  BOOL ok = FALSE;
  WCHAR *w = lui_u16v(vurl);
  if (w != NULL) {
    HINSTANCE r = ShellExecuteW(NULL, L"open", w,
                              NULL, NULL, SW_SHOWNORMAL);
    ok = (INT_PTR)r > 32;
    free(w);
  }
  CAMLreturn(Val_bool(ok));
}

/* HKCU\Software\Classes\<scheme>: (Default) = "URL:<name>",
   "URL Protocol" = "", DefaultIcon = "<exe>",0,
   shell\open\command = "\"<exe>\" \"%1\"". */
static int lui_reg_set(HKEY root, const WCHAR *path,
                       const WCHAR *name, const WCHAR *value)
{
  HKEY k = NULL;
  LONG r = RegCreateKeyExW(root, path, 0, NULL, 0, KEY_SET_VALUE,
                           NULL, &k, NULL);
  if (r != 0) return 0;
  r = RegSetValueExW(k, name, 0, REG_SZ, (const BYTE *)value,
                     (DWORD)((wcslen(value) + 1) * sizeof(WCHAR)));
  RegCloseKey(k);
  return r == 0;
}

CAMLprim value lui_shw_register_scheme(value vscheme, value vname)
{
  CAMLparam2(vscheme, vname);
  BOOL ok = FALSE;
  WCHAR *scheme = lui_u16v(vscheme);
  WCHAR *name = lui_u16v(vname);
  if (scheme != NULL && wcslen(scheme) > 400) ok = FALSE;
  else if (scheme != NULL && name != NULL) {
    WCHAR exe[MAX_PATH + 2];
    DWORD n = GetModuleFileNameW(NULL, exe, MAX_PATH);
    if (n > 0 && n < MAX_PATH) {
      WCHAR path[512];
      WCHAR def[512];
      WCHAR icon[MAX_PATH + 8];
      WCHAR cmd[MAX_PATH + 8];
      _snwprintf(def, 512, L"URL:%s", name);
      def[511] = 0;
      _snwprintf(icon, MAX_PATH + 8, L"\"%s\",0", exe);
      icon[MAX_PATH + 7] = 0;
      _snwprintf(cmd, MAX_PATH + 8, L"\"%s\" \"%%1\"", exe);
      cmd[MAX_PATH + 7] = 0;

      _snwprintf(path, 512, L"Software\\Classes\\%s", scheme);
      path[511] = 0;
      ok = lui_reg_set(HKEY_CURRENT_USER, path, NULL, def)
        && lui_reg_set(HKEY_CURRENT_USER, path, L"URL Protocol", L"");

      _snwprintf(path, 512, L"Software\\Classes\\%s\\DefaultIcon",
                 scheme);
      path[511] = 0;
      ok = ok && lui_reg_set(HKEY_CURRENT_USER, path, NULL, icon);

      _snwprintf(path, 512,
                 L"Software\\Classes\\%s\\shell\\open\\command", scheme);
      path[511] = 0;
      ok = ok && lui_reg_set(HKEY_CURRENT_USER, path, NULL, cmd);
    }
  }
  free(scheme);
  free(name);
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_shw_unregister_scheme(value vscheme)
{
  CAMLparam1(vscheme);
  BOOL ok = TRUE;
  WCHAR *scheme = lui_u16v(vscheme);
  if (scheme != NULL) {
    WCHAR path[512];
    LONG r;
    _snwprintf(path, 512, L"Software\\Classes\\%s", scheme);
    path[511] = 0;
    r = RegDeleteTreeW(HKEY_CURRENT_USER, path);
    ok = r == 0 || r == ERROR_FILE_NOT_FOUND;
    free(scheme);
  }
  CAMLreturn(Val_bool(ok));
}

/* ------------------------------------------------------------ pump */

CAMLprim value lui_shw_pump(value unit)
{
  CAMLparam1(unit);
  int n = 0;
  MSG m;
  /* Only this window's messages: pumping must not steal another
     window's queue. */
  while (lui_hwnd != NULL &&
         PeekMessageW(&m, lui_hwnd, 0, 0, PM_REMOVE | PM_NOYIELD)) {
    TranslateMessage(&m);
    DispatchMessageW(&m);
    n++;
  }
  CAMLreturn(Val_int(n));
}

#else /* !_WIN32 */

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void)
{
  caml_failwith("lui_shell_windows: this backend requires Windows");
  return Val_unit;
}

CAMLprim value lui_shw_image_rgba(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_shw_image_size(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_popup_menu(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_status_create(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_status_remove(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_status_set_title(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shw_status_set_image(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shw_status_set_menu(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shw_status_set_on_click(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shw_notify(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_shw_clip_write(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_clip_read(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_clip_clear(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_clip_count(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_clip_write_format(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shw_clip_read_format(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_can_present(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_open_panel(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_shw_save_panel(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_open_url(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_register_scheme(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_shw_unregister_scheme(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_shw_pump(value a) {
  (void)a; return unsupported(); }

#endif /* _WIN32 */
