/* Test helper: an invisible overlapped window whose window procedure
   forwards WM_GETOBJECT to the bridge's OCaml entry point — the same
   path a real host takes. */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>

#if defined(_WIN32)
#include <windows.h>

extern value lui_axw_get_object(value hwnd, value wp, value lp);

static const wchar_t *AXW_TEST_CLASS = L"LuiAxwTestWindow";

static LRESULT CALLBACK test_wndproc(HWND hwnd, UINT msg, WPARAM wp,
                                     LPARAM lp)
{
  if (msg == WM_GETOBJECT) {
    value r = lui_axw_get_object(
        caml_copy_nativeint((intnat)(uintptr_t)hwnd),
        caml_copy_nativeint((intnat)wp),
        caml_copy_nativeint((intnat)lp));
    if (Nativeint_val(r) != 0)
      return (LRESULT)Nativeint_val(r);
  }
  return DefWindowProcW(hwnd, msg, wp, lp);
}

CAMLprim value axw_test_create_window(value unit)
{
  HWND hwnd;
  HINSTANCE inst;
  WNDCLASSW wc;
  (void)unit;
  inst = GetModuleHandleW(NULL);
  memset(&wc, 0, sizeof(wc));
  wc.lpfnWndProc = test_wndproc;
  wc.hInstance = inst;
  wc.lpszClassName = AXW_TEST_CLASS;
  RegisterClassW(&wc); /* may already exist; failure is harmless */
  hwnd = CreateWindowExW(0, AXW_TEST_CLASS, L"axw-test",
                         WS_OVERLAPPED | WS_POPUP,
                         0, 0, 400, 300, NULL, NULL, inst, NULL);
  if (!hwnd) caml_failwith("axw_test_create_window failed");
  return caml_copy_nativeint((intnat)(uintptr_t)hwnd);
}

CAMLprim value axw_test_destroy_window(value vh)
{
  DestroyWindow((HWND)(uintptr_t)Nativeint_val(vh));
  return Val_unit;
}
#else
CAMLprim value axw_test_create_window(value unit)
{
  caml_failwith("axw_test_create_window: windows-only");
  return Val_unit;
}

CAMLprim value axw_test_destroy_window(value vh)
{
  caml_failwith("axw_test_destroy_window: windows-only");
  return Val_unit;
}
#endif
