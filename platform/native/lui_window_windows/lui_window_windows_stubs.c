/* C stubs backing Lui_win32 for the window host executable: the host
   window (class + wndproc, with WM_GETOBJECT forwarded to the
   lui_ax_windows bridge), a C-side decoded input-event queue the
   OCaml loop drains, DIB presentation for the CPU renderer, IMM32
   candidate placement and the high-resolution clock.

   Every OCaml-callable entry raises [Failure] on non-Windows so the
   library still builds and links on other platforms; the executable
   and the real-call tests are gated on mingw64. */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/custom.h>
#include <caml/signals.h>

#ifdef _WIN32

#include <windows.h>
#include <imm.h>
#include <string.h>

#define LWW_MIN(a, b) ((a) < (b) ? (a) : (b))

/* ------------------------------------------------------------------ */
/* Event queue — decoded window events pushed by the wndproc, popped  */
/* by lww_next_event. Tags mirror lui_win32.mli.                       */

enum {
  EV_QUIT = 1,
  EV_RESIZE = 2,
  EV_KEY_DOWN = 3,
  EV_TEXT_INPUT = 4,
  EV_TEXT_EDITING = 5,
  EV_MOVE = 6,
  EV_BUTTON_DOWN = 7,
  EV_BUTTON_UP = 8,
  EV_WHEEL = 9,
  EV_PRESENT_REQUEST = 10
};

typedef struct ev {
  struct ev *next;
  int tag, a, b, c;
  double x, y;
  char *text;
} ev_t;

static ev_t *ev_head = NULL, *ev_tail = NULL;

static void ev_push(int tag, int a, int b, int c, double x, double y,
                    const char *text)
{
  ev_t *e = (ev_t *)malloc(sizeof(ev_t));
  if (!e) return;
  e->next = NULL;
  e->tag = tag; e->a = a; e->b = b; e->c = c;
  e->x = x; e->y = y;
  e->text = text ? strdup(text) : NULL;
  if (ev_tail) ev_tail->next = e; else ev_head = e;
  ev_tail = e;
}

static int mods_now(void)
{
  int m = 0;
  if (GetKeyState(VK_CONTROL) & 0x8000) m |= 1;
  if (GetKeyState(VK_SHIFT) & 0x8000) m |= 2;
  if (GetKeyState(VK_MENU) & 0x8000) m |= 4;
  if ((GetKeyState(VK_LWIN) | GetKeyState(VK_RWIN)) & 0x8000) m |= 8;
  return m;
}

/* ------------------------------------------------------------------ */
/* UTF-8 <-> UTF-16 helpers                                            */

static wchar_t *utf8_to_16(const char *s, int *out_len)
{
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  wchar_t *w;
  if (n <= 0) return NULL;
  w = (wchar_t *)malloc(sizeof(wchar_t) * (size_t)n);
  if (!w) return NULL;
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  if (out_len) *out_len = n - 1;
  return w;
}

static char *utf16_to_8(const wchar_t *w, int wlen)
{
  int n = WideCharToMultiByte(CP_UTF8, 0, w, wlen, NULL, 0, NULL, NULL);
  char *s;
  if (n <= 0) return NULL;
  s = (char *)malloc((size_t)n + 1);
  if (!s) return NULL;
  WideCharToMultiByte(CP_UTF8, 0, w, wlen, s, n, NULL, NULL);
  s[n] = 0;
  return s;
}

/* ------------------------------------------------------------------ */
/* IME state tracked across messages                                   */

static int ime_composing = 0;
static int ime_had_result = 0;
static HIMC ime_saved = NULL;

/* UTF-8 byte length of the first [units] UTF-16 code units of [w]. */
static int utf16_prefix_utf8_len(const wchar_t *w, int units)
{
  return WideCharToMultiByte(CP_UTF8, 0, w, units, NULL, 0, NULL, NULL);
}

static void push_ime_composition(HWND hwnd, LPARAM lp)
{
  HIMC himc = ImmGetContext(hwnd);
  if (!himc) return;
  if (lp & GCS_RESULTSTR) {
    LONG n = ImmGetCompositionStringW(himc, GCS_RESULTSTR, NULL, 0);
    if (n > 0) {
      wchar_t *buf = (wchar_t *)malloc((size_t)n + 2);
      if (buf) {
        char *u8;
        ImmGetCompositionStringW(himc, GCS_RESULTSTR, buf, n);
        u8 = utf16_to_8(buf, n / 2);
        if (u8) {
          ev_push(EV_TEXT_INPUT, 0, 0, 0, 0, 0, u8);
          free(u8);
          ime_had_result = 1;
        }
        free(buf);
      }
    }
  }
  if (lp & GCS_COMPSTR) {
    LONG n = ImmGetCompositionStringW(himc, GCS_COMPSTR, NULL, 0);
    if (n > 0) {
      wchar_t *buf = (wchar_t *)malloc((size_t)n + 2);
      if (buf) {
        char *u8;
        ImmGetCompositionStringW(himc, GCS_COMPSTR, buf, n);
        u8 = utf16_to_8(buf, n / 2);
        if (u8) {
          /* GCS_CURSORPOS is a UTF-16 unit count; the overlay contract
             is a UTF-8 byte offset. */
          int cur16 =
            ImmGetCompositionStringW(himc, GCS_CURSORPOS, NULL, 0);
          int start = utf16_prefix_utf8_len(
              buf, LWW_MIN(cur16, (int)(n / 2)));
          ev_push(EV_TEXT_EDITING, start, 0, 0, 0, 0, u8);
          free(u8);
        }
        free(buf);
      }
    } else {
      /* Composition text cleared. */
      ev_push(EV_TEXT_EDITING, 0, 0, 0, 0, 0, "");
    }
  }
  ImmReleaseContext(hwnd, himc);
}

/* ------------------------------------------------------------------ */
/* Window procedure                                                    */

/* lui_ax_windows' WM_GETOBJECT entry point, linked from the
   lui_ax_windows library's own stubs into this same executable. */
extern value lui_axw_get_object(value hwnd, value wp, value lp);

static WCHAR pending_surrogate = 0;

static void push_text_input_utf16(const wchar_t *units, int n)
{
  char *u8 = utf16_to_8(units, n);
  if (u8) {
    ev_push(EV_TEXT_INPUT, 0, 0, 0, 0, 0, u8);
    free(u8);
  }
}

static LRESULT CALLBACK lww_wndproc(HWND hwnd, UINT msg, WPARAM wp,
                                    LPARAM lp)
{
  switch (msg) {
  case WM_GETOBJECT: {
    value r = lui_axw_get_object(
        caml_copy_nativeint((intnat)(uintptr_t)hwnd),
        caml_copy_nativeint((intnat)wp),
        caml_copy_nativeint((intnat)lp));
    if (Nativeint_val(r) != 0)
      return (LRESULT)Nativeint_val(r);
    return DefWindowProcW(hwnd, msg, wp, lp);
  }
  case WM_ERASEBKGND:
    return 1; /* we draw everything; suppress the white erase flash */
  case WM_PAINT: {
    PAINTSTRUCT ps;
    BeginPaint(hwnd, &ps);
    EndPaint(hwnd, &ps);
    ev_push(EV_PRESENT_REQUEST, 0, 0, 0, 0, 0, NULL);
    return 0;
  }
  case WM_CLOSE:
    ev_push(EV_QUIT, 0, 0, 0, 0, 0, NULL);
    return 0; /* let the OCaml loop decide */
  case WM_DESTROY:
    ev_push(EV_QUIT, 0, 0, 0, 0, 0, NULL);
    return 0;
  case WM_SIZE:
    ev_push(EV_RESIZE, (int)LOWORD(lp), (int)HIWORD(lp), 0, 0, 0,
            NULL);
    return 0;
  case WM_DPICHANGED: {
    const RECT *r = (const RECT *)lp;
    SetWindowPos(hwnd, NULL, r->left, r->top, r->right - r->left,
                 r->bottom - r->top, SWP_NOZORDER | SWP_NOACTIVATE);
    return 0; /* the following WM_SIZE queues the resize event */
  }
  case WM_MOUSEMOVE:
    ev_push(EV_MOVE, 0, 0, 0, (double)(short)LOWORD(lp),
            (double)(short)HIWORD(lp), NULL);
    return 0;
  case WM_LBUTTONDOWN: case WM_MBUTTONDOWN: case WM_RBUTTONDOWN: {
    int btn = msg == WM_LBUTTONDOWN ? 1 : msg == WM_MBUTTONDOWN ? 2 : 3;
    SetCapture(hwnd);
    ev_push(EV_BUTTON_DOWN, btn, 1, mods_now(),
            (double)(short)LOWORD(lp), (double)(short)HIWORD(lp),
            NULL);
    return 0;
  }
  case WM_LBUTTONDBLCLK: case WM_MBUTTONDBLCLK:
  case WM_RBUTTONDBLCLK: {
    int btn = msg == WM_LBUTTONDBLCLK ? 1
                                      : msg == WM_MBUTTONDBLCLK ? 2 : 3;
    SetCapture(hwnd);
    ev_push(EV_BUTTON_DOWN, btn, 2, mods_now(),
            (double)(short)LOWORD(lp), (double)(short)HIWORD(lp),
            NULL);
    return 0;
  }
  case WM_LBUTTONUP: case WM_MBUTTONUP: case WM_RBUTTONUP: {
    int btn = msg == WM_LBUTTONUP ? 1 : msg == WM_MBUTTONUP ? 2 : 3;
    ev_push(EV_BUTTON_UP, btn, 0, mods_now(),
            (double)(short)LOWORD(lp), (double)(short)HIWORD(lp),
            NULL);
    if (wp == 0) ReleaseCapture();
    return 0;
  }
  case WM_MOUSEWHEEL:
    ev_push(EV_WHEEL, 0, 0, 0, 0,
            (double)GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA, NULL);
    return 0;
  case WM_MOUSEHWHEEL: {
    ev_push(EV_WHEEL, 0, 0, 0,
            (double)GET_WHEEL_DELTA_WPARAM(wp) / WHEEL_DELTA, 0,
            NULL);
    return 0;
  }
  case WM_KEYDOWN: case WM_SYSKEYDOWN:
    ev_push(EV_KEY_DOWN, (int)wp, mods_now(), (int)((lp >> 30) & 1),
            0, 0, NULL);
    return 0;
  case WM_CHAR: {
    WCHAR w = (WCHAR)wp;
    if (pending_surrogate) {
      if (w >= 0xDC00 && w <= 0xDFFF) {
        WCHAR pair[2] = { pending_surrogate, w };
        pending_surrogate = 0;
        push_text_input_utf16(pair, 2);
      } else {
        WCHAR rep = 0xFFFD;
        push_text_input_utf16(&rep, 1);
        pending_surrogate = 0;
        if (w >= 0xD800 && w <= 0xDBFF) pending_surrogate = w;
        else push_text_input_utf16(&w, 1);
      }
    } else if (w >= 0xD800 && w <= 0xDBFF) {
      pending_surrogate = w;
    } else {
      push_text_input_utf16(&w, 1);
    }
    return 0;
  }
  case WM_IME_STARTCOMPOSITION:
    ime_composing = 1;
    ime_had_result = 0;
    return TRUE; /* we draw marked text ourselves; composition proceeds */
  case WM_IME_COMPOSITION:
    push_ime_composition(hwnd, lp);
    return TRUE;
  case WM_IME_ENDCOMPOSITION:
    if (ime_composing && !ime_had_result) {
      /* Cancelled: clear the marked text, then end the session — the
         lui_ime state machine reads the empty commit as a cancel. */
      ev_push(EV_TEXT_EDITING, 0, 0, 0, 0, 0, "");
      ev_push(EV_TEXT_INPUT, 0, 0, 0, 0, 0, "");
    }
    ime_composing = 0;
    ime_had_result = 0;
    return TRUE;
  default:
    return DefWindowProcW(hwnd, msg, wp, lp);
  }
}

/* ------------------------------------------------------------------ */
/* Window lifecycle                                                    */

static const wchar_t *LWW_CLASS = L"LuiWindowHost";
static int class_registered = 0;

static void register_once(void)
{
  WNDCLASSEXW wc;
  HMODULE user32;
  FARPROC set_ctx;

  if (class_registered) return;
  /* Per-monitor v2 so the window's reported DPI tracks the monitor it
     lands on; harmless when unavailable (older OS). */
  user32 = GetModuleHandleW(L"user32.dll");
  if (user32) {
    set_ctx = GetProcAddress(user32, "SetProcessDpiAwarenessContext");
    if (set_ctx)
      /* DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 == (HANDLE)-4 */
      ((BOOL (WINAPI *)(HANDLE))set_ctx)((HANDLE)(LONG_PTR)-4);
  }
  memset(&wc, 0, sizeof(wc));
  wc.cbSize = sizeof(wc);
  wc.style = CS_HREDRAW | CS_VREDRAW | CS_DBLCLKS;
  wc.lpfnWndProc = lww_wndproc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  wc.lpszClassName = LWW_CLASS;
  RegisterClassExW(&wc);
  class_registered = 1;
}

/* GetDpiForWindow via the export so the same binary runs on old OSs. */
static UINT win_dpi(HWND hwnd)
{
  HMODULE user32 = GetModuleHandleW(L"user32.dll");
  UINT (WINAPI *get_dpi)(HWND) = NULL;
  UINT (WINAPI *get_dpi_sys)(void) = NULL;
  if (user32) {
    get_dpi = (UINT (WINAPI *)(HWND))
        GetProcAddress(user32, "GetDpiForWindow");
    get_dpi_sys = (UINT (WINAPI *)(void))
        GetProcAddress(user32, "GetDpiForSystem");
  }
  if (get_dpi) return get_dpi(hwnd);
  if (get_dpi_sys) return get_dpi_sys();
  return 96;
}

CAMLprim value lww_create_window(value w, value h, value title,
                                 value hidden)
{
  CAMLparam4(w, h, title, hidden);
  HWND hwnd;
  wchar_t *titleW;
  UINT dpi;
  RECT r;
  HMODULE user32;
  BOOL (WINAPI *adjust_dpi)(LPRECT, DWORD, BOOL, DWORD, UINT) = NULL;

  register_once();
  titleW = utf8_to_16(String_val(title), NULL);
  hwnd = CreateWindowExW(0, LWW_CLASS, titleW ? titleW : L"lui",
                         WS_OVERLAPPEDWINDOW, CW_USEDEFAULT,
                         CW_USEDEFAULT, 100, 100, NULL, NULL,
                         GetModuleHandleW(NULL), NULL);
  free(titleW);
  if (!hwnd) caml_failwith("CreateWindowExW failed");

  /* Size the client area to w x h logical px times the window's DPI
     scale (like SDL's allow_highdpi drawable). */
  dpi = win_dpi(hwnd);
  r.left = 0;
  r.top = 0;
  r.right = MulDiv(Int_val(w), (int)dpi, 96);
  r.bottom = MulDiv(Int_val(h), (int)dpi, 96);
  user32 = GetModuleHandleW(L"user32.dll");
  if (user32)
    adjust_dpi = (BOOL (WINAPI *)(LPRECT, DWORD, BOOL, DWORD, UINT))
        GetProcAddress(user32, "AdjustWindowRectExForDpi");
  if (adjust_dpi)
    adjust_dpi(&r, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi);
  else
    AdjustWindowRectEx(&r, WS_OVERLAPPEDWINDOW, FALSE, 0);
  SetWindowPos(hwnd, NULL, 0, 0, r.right - r.left, r.bottom - r.top,
               SWP_NOMOVE | SWP_NOZORDER);
  if (!Bool_val(hidden)) {
    ShowWindow(hwnd, SW_SHOW);
    UpdateWindow(hwnd);
  }
  CAMLreturn(caml_copy_nativeint((intnat)(uintptr_t)hwnd));
}

CAMLprim value lww_destroy_window(value vhwnd)
{
  DestroyWindow((HWND)(uintptr_t)Nativeint_val(vhwnd));
  return Val_unit;
}

CAMLprim value lww_show_window(value vhwnd, value vis)
{
  ShowWindow((HWND)(uintptr_t)Nativeint_val(vhwnd),
             Bool_val(vis) ? SW_SHOW : SW_HIDE);
  return Val_unit;
}

CAMLprim value lww_set_title(value vhwnd, value vtitle)
{
  CAMLparam2(vhwnd, vtitle);
  wchar_t *w = utf8_to_16(String_val(vtitle), NULL);
  if (w) {
    SetWindowTextW((HWND)(uintptr_t)Nativeint_val(vhwnd), w);
    free(w);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lww_client_size(value vhwnd)
{
  CAMLparam1(vhwnd);
  CAMLlocal1(pair);
  RECT rc;
  GetClientRect((HWND)(uintptr_t)Nativeint_val(vhwnd), &rc);
  pair = caml_alloc_tuple(2);
  Store_field(pair, 0, Val_int(rc.right));
  Store_field(pair, 1, Val_int(rc.bottom));
  CAMLreturn(pair);
}

/* ------------------------------------------------------------------ */
/* Event pump                                                          */

CAMLprim value lww_next_event(value unit)
{
  CAMLparam1(unit);
  CAMLlocal4(ev, txt, fx, fy);
  MSG msg;
  ev_t *e;

  /* The runtime lock stays held: DispatchMessageW can re-enter the
     wndproc, which allocates OCaml values when it forwards
     WM_GETOBJECT to the ax bridge. PeekMessage is non-blocking, so
     there is nothing to release for anyway. */
  while (!ev_head && PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
    if (msg.message == WM_QUIT) {
      ev_push(EV_QUIT, 0, 0, 0, 0, 0, NULL);
      break;
    }
    TranslateMessage(&msg);
    DispatchMessageW(&msg);
  }

  ev = caml_alloc(7, 0);
  if (!ev_head) {
    Store_field(ev, 0, Val_int(0));
    Store_field(ev, 1, Val_int(0));
    Store_field(ev, 2, Val_int(0));
    Store_field(ev, 3, Val_int(0));
    Store_field(ev, 4, caml_copy_double(0.));
    Store_field(ev, 5, caml_copy_double(0.));
    Store_field(ev, 6, caml_copy_string(""));
    CAMLreturn(ev);
  }
  e = ev_head;
  ev_head = e->next;
  if (!ev_head) ev_tail = NULL;
  txt = caml_copy_string(e->text ? e->text : "");
  fx = caml_copy_double(e->x);
  fy = caml_copy_double(e->y);
  Store_field(ev, 0, Val_int(e->tag));
  Store_field(ev, 1, Val_int(e->a));
  Store_field(ev, 2, Val_int(e->b));
  Store_field(ev, 3, Val_int(e->c));
  Store_field(ev, 4, fx);
  Store_field(ev, 5, fy);
  Store_field(ev, 6, txt);
  free(e->text);
  free(e);
  CAMLreturn(ev);
}

/* ------------------------------------------------------------------ */
/* DIB presentation — the CPU renderer's present path                  */

static void fill_bmi(BITMAPINFO *bmi, int w, int h)
{
  memset(bmi, 0, sizeof(*bmi));
  bmi->bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi->bmiHeader.biWidth = w;
  bmi->bmiHeader.biHeight = -h; /* top-down */
  bmi->bmiHeader.biPlanes = 1;
  bmi->bmiHeader.biBitCount = 32;
  bmi->bmiHeader.biCompression = BI_RGB;
}

CAMLprim value lww_present_frame(value vhwnd, value pix, value w,
                                 value h)
{
  HWND hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  int cw = Int_val(w), ch = Int_val(h);
  HDC hdc;
  BITMAPINFO bmi;
  int ok = 0;
  if (cw <= 0 || ch <= 0) return Val_false;
  hdc = GetDC(hwnd);
  if (!hdc) return Val_false;
  fill_bmi(&bmi, cw, ch);
  ok = StretchDIBits(hdc, 0, 0, cw, ch, 0, 0, cw, ch,
                     Bytes_val(pix), &bmi, DIB_RGB_COLORS, SRCCOPY) != 0;
  ReleaseDC(hwnd, hdc);
  return Val_bool(ok);
}

CAMLprim value lww_present_region(value vhwnd, value vx0, value vy0,
                                  value vx1, value vy1, value pix,
                                  value vstride)
{
  HWND hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  int x0 = Int_val(vx0), y0 = Int_val(vy0);
  int x1 = Int_val(vx1), y1 = Int_val(vy1);
  int stride = Int_val(vstride);
  int total_h = (int)(caml_string_length(pix) / ((size_t)stride * 4));
  HDC hdc;
  BITMAPINFO bmi;
  int ok = 0;
  if (x1 <= x0 || y1 <= y0 || stride <= 0) return Val_false;
  hdc = GetDC(hwnd);
  if (!hdc) return Val_false;
  fill_bmi(&bmi, stride, total_h);
  /* Same-rectangle StretchDIBits: the source window into the
     top-down frame matches the destination rect. */
  ok = StretchDIBits(hdc, x0, y0, x1 - x0, y1 - y0,
                     x0, y0, x1 - x0, y1 - y0,
                     Bytes_val(pix), &bmi, DIB_RGB_COLORS, SRCCOPY) != 0;
  ReleaseDC(hwnd, hdc);
  return Val_bool(ok);
}

CAMLprim value lww_present_region_byte(value *argv, int argn)
{
  (void)argn;
  return lww_present_region(argv[0], argv[1], argv[2], argv[3],
                            argv[4], argv[5], argv[6]);
}

/* ------------------------------------------------------------------ */
/* DPI, IME, attention, timing                                         */

CAMLprim value lww_dpi_scale(value vhwnd)
{
  return caml_copy_double((double)win_dpi(
      (HWND)(uintptr_t)Nativeint_val(vhwnd)) / 96.0);
}

CAMLprim value lww_set_ime_rect(value vhwnd, value vx, value vy,
                                value vw, value vh)
{
  HWND hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  HIMC himc = ImmGetContext(hwnd);
  int x = Int_val(vx), y = Int_val(vy);
  int w = Int_val(vw), h = Int_val(vh);
  if (himc) {
    COMPOSITIONFORM cf;
    CANDIDATEFORM cand;
    cf.dwStyle = CFS_RECT;
    cf.ptCurrentPos.x = x;
    cf.ptCurrentPos.y = y;
    cf.rcArea.left = x;
    cf.rcArea.top = y;
    cf.rcArea.right = x + w;
    cf.rcArea.bottom = y + h;
    ImmSetCompositionWindow(himc, &cf);
    memset(&cand, 0, sizeof(cand));
    cand.dwIndex = 0;
    cand.dwStyle = CFS_CANDIDATEPOS;
    cand.ptCurrentPos.x = x;
    cand.ptCurrentPos.y = y + h;
    ImmSetCandidateWindow(himc, &cand);
    cand.dwIndex = 1;
    ImmSetCandidateWindow(himc, &cand);
    ImmReleaseContext(hwnd, himc);
  }
  return Val_unit;
}

CAMLprim value lww_set_ime_enabled(value vhwnd, value ven)
{
  HWND hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  if (Bool_val(ven)) {
    if (ime_saved) {
      ImmAssociateContext(hwnd, ime_saved);
      ime_saved = NULL;
    }
  } else {
    HIMC cur = ImmGetContext(hwnd);
    if (cur) {
      if (ImmAssociateContext(hwnd, NULL)) ime_saved = cur;
      ImmReleaseContext(hwnd, cur);
    }
  }
  return Val_unit;
}

CAMLprim value lww_request_attention(value vhwnd)
{
  FLASHWINFO fi;
  memset(&fi, 0, sizeof(fi));
  fi.cbSize = sizeof(fi);
  fi.hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  fi.dwFlags = FLASHW_ALL | FLASHW_TIMERNOFG;
  FlashWindowEx(&fi);
  return Val_unit;
}

CAMLprim value lww_perf_s(value unit)
{
  static double freq = 0.;
  LARGE_INTEGER c;
  if (freq == 0.) {
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f);
    freq = (double)f.QuadPart;
  }
  QueryPerformanceCounter(&c);
  return caml_copy_double((double)c.QuadPart / freq);
}

CAMLprim value lww_delay_ms(value vms)
{
  Sleep((DWORD)Int_val(vms));
  return Val_unit;
}


CAMLprim value lww_send_wm_getobject(value vhwnd, value vwp, value vlp)
{
  CAMLparam3(vhwnd, vwp, vlp);
  /* Real SendMessageW: the answer comes from the window procedure's
     WM_GETOBJECT case, which forwards to the lui_ax_windows bridge —
     this is the path an actual screen reader takes. */
  LRESULT r = SendMessageW((HWND)(uintptr_t)Nativeint_val(vhwnd),
                           WM_GETOBJECT,
                           (WPARAM)Nativeint_val(vwp),
                           (LPARAM)Nativeint_val(vlp));
  CAMLreturn(caml_copy_nativeint((intnat)r));
}

#else /* !_WIN32 — keep the library linkable on every platform */

#define LWW_UN                                                  \
  static value lww_unsupported(void)                            \
  {                                                             \
    caml_failwith("lui_window_windows: this backend requires "  \
                  "Windows");                                   \
    return Val_unit;                                            \
  }
LWW_UN

CAMLprim value lww_create_window(value a, value b, value c, value d)
{ (void)a; (void)b; (void)c; (void)d; return lww_unsupported(); }
CAMLprim value lww_destroy_window(value a)
{ (void)a; return lww_unsupported(); }
CAMLprim value lww_show_window(value a, value b)
{ (void)a; (void)b; return lww_unsupported(); }
CAMLprim value lww_set_title(value a, value b)
{ (void)a; (void)b; return lww_unsupported(); }
CAMLprim value lww_client_size(value a)
{ (void)a; return lww_unsupported(); }
CAMLprim value lww_next_event(value a)
{ (void)a; return lww_unsupported(); }
CAMLprim value lww_present_frame(value a, value b, value c, value d)
{ (void)a; (void)b; (void)c; (void)d; return lww_unsupported(); }
CAMLprim value lww_present_region(value a, value b, value c, value d,
                                  value e, value f, value g)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
  return lww_unsupported(); }
CAMLprim value lww_present_region_byte(value *argv, int argn)
{ (void)argv; (void)argn; return lww_unsupported(); }
CAMLprim value lww_dpi_scale(value a)
{ (void)a; return lww_unsupported(); }
CAMLprim value lww_set_ime_rect(value a, value b, value c, value d,
                                value e)
{ (void)a; (void)b; (void)c; (void)d; (void)e;
  return lww_unsupported(); }
CAMLprim value lww_set_ime_enabled(value a, value b)
{ (void)a; (void)b; return lww_unsupported(); }
CAMLprim value lww_request_attention(value a)
{ (void)a; return lww_unsupported(); }
CAMLprim value lww_perf_s(value a)
{ (void)a; return lww_unsupported(); }
CAMLprim value lww_delay_ms(value a)
{ (void)a; return lww_unsupported(); }

#endif /* _WIN32 */
