#include <webview/webview.h>
#include <chrono>
#include <string>
#include <thread>

extern "C" {
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/threads.h>
}

#ifndef _WIN32
#include <cerrno>
#include <csignal>
#endif

#ifndef __APPLE__
extern "C" CAMLprim value lui_desktop_scheme_window_run(value options) {
  (void)options;
  caml_failwith("The lui URL scheme is not available in this platform adapter");
}
#endif

// OCaml owns application and helper lifetimes. Each process creates one
// WebView, so closing the updater releases its WebKit process session.
extern "C" CAMLprim value lui_desktop_webview_run(value options) {
  CAMLparam1(options);
  const std::string title = String_val(Field(options, 0));
  const std::string url = String_val(Field(options, 1));
  const std::string request = "[\"" + std::string(String_val(Field(options, 2))) + "\"]";
  const int width = Int_val(Field(options, 3));
  const int height = Int_val(Field(options, 4));
  const bool debug = Bool_val(Field(options, 5));
  std::string error;
  caml_enter_blocking_section();
  try {
    webview::webview main(debug, nullptr);
    main.set_title(title).ensure_ok();
    main.set_size(width, height, WEBVIEW_HINT_NONE).ensure_ok();
    main.bind("__lui_check_for_updates", [&](const std::string &args) {
      if (args != request) return std::string("false");
      caml_leave_blocking_section();
      const value result = caml_callback_exn(Field(options, 6), Val_unit);
      const bool opened = !Is_exception_result(result) && Bool_val(result);
      caml_enter_blocking_section();
      return opened ? std::string("true") : std::string("false");
    }).ensure_ok();
    main.navigate(url).ensure_ok();
    main.run().ensure_ok();
  } catch (const std::exception &exception) {
    error = exception.what();
  }
  caml_leave_blocking_section();
  if (!error.empty()) caml_failwith(error.c_str());
  CAMLreturn(Val_unit);
}

extern "C" CAMLprim value lui_desktop_updater_window_run(value options) {
  CAMLparam1(options);
  const std::string title = String_val(Field(options, 0));
  const std::string url = String_val(Field(options, 1));
  std::string error;
  caml_enter_blocking_section();
  try {
    webview::webview view(false, nullptr);
    view.set_title(title).ensure_ok();
    view.set_size(520, 440, WEBVIEW_HINT_NONE).ensure_ok();
    view.bind("__lui_later", [&](const std::string &id, const std::string &, void *) {
      view.resolve(id, 0, "null");
      // Stop after the reply. Destruction closes the live native window;
      // no callback dereferences a handle invalidated by window closure.
      view.dispatch([&] { view.terminate(); });
    }, nullptr).ensure_ok();
    view.navigate(url).ensure_ok();
    view.run().ensure_ok();
  } catch (const std::exception &exception) {
    error = exception.what();
  }
  caml_leave_blocking_section();
  if (!error.empty()) caml_failwith(error.c_str());
  CAMLreturn(Val_unit);
}

extern "C" CAMLprim value lui_desktop_wait_for_process(value process) {
  CAMLparam1(process);
  const int pid = Int_val(process);
  if (pid <= 0) caml_invalid_argument("Expected a positive parent process ID");
  bool exited = false;
  caml_enter_blocking_section();
#ifdef _WIN32
  HANDLE handle = OpenProcess(SYNCHRONIZE, FALSE, static_cast<DWORD>(pid));
  if (handle) {
    exited = WaitForSingleObject(handle, 60000) == WAIT_OBJECT_0;
    CloseHandle(handle);
  } else {
    exited = GetLastError() == ERROR_INVALID_PARAMETER;
  }
#else
  for (int i = 0; i < 600; ++i) {
    if (kill(pid, 0) < 0 && errno == ESRCH) { exited = true; break; }
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
  }
#endif
  caml_leave_blocking_section();
  CAMLreturn(Val_bool(exited));
}
