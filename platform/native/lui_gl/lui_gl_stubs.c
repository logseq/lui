/* glibc before 2.36 exposes RTLD_DEFAULT only when _GNU_SOURCE is defined
   before the first libc header. Other libcs declare it unconditionally.
   Linux-only so the macOS dlfcn.h and the Windows GetProcAddress path stay
   unchanged. */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

/* Byte copies between OCaml Bytes and the bigarrays the GL bindings
   consume, so atlas, image and framebuffer pixels cross as one memcpy
   instead of an elementwise loop. */
#include <string.h>
#include <caml/mlvalues.h>
#include <caml/bigarray.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <limits.h>

#if defined(_WIN32)
#include <windows.h>
#define LUI_GL_CALL APIENTRY
#else
#include <dlfcn.h>
#define LUI_GL_CALL
#endif

/* lui_gl_blit_bytes_to_ba src src_off dst dst_off len */
value lui_gl_blit_bytes_to_ba(value src, value src_off, value dst,
                              value dst_off, value len)
{
  CAMLparam5(src, src_off, dst, dst_off, len);
  memcpy((char *)Caml_ba_data_val(dst) + Long_val(dst_off),
         (const char *)Bytes_val(src) + Long_val(src_off),
         (size_t)Long_val(len));
  CAMLreturn(Val_unit);
}

/* Keep the source rooted across the upload. A pointer-to-string FFI cell
   does not retain the temporary C string stored behind that pointer. */
CAMLprim value lui_gl_shader_source(value shader, value source)
{
  CAMLparam2(shader, source);
  typedef void (LUI_GL_CALL *shader_source_fn)(unsigned int, int, const char *const *, const int *);
  shader_source_fn submit;
#if defined(_WIN32)
  HMODULE library = GetModuleHandleA("opengl32.dll");
  typedef PROC (WINAPI *get_proc_fn)(LPCSTR);
  get_proc_fn get_proc = library ? (get_proc_fn)GetProcAddress(library, "wglGetProcAddress") : NULL;
  submit = get_proc ? (shader_source_fn)get_proc("glShaderSource") : NULL;
#else
  submit = (shader_source_fn)dlsym(RTLD_DEFAULT, "glShaderSource");
#endif
  if (!submit) caml_failwith("lui_gl: glShaderSource is unavailable in the active context");
  mlsize_t length = caml_string_length(source);
  if (length > INT_MAX) caml_invalid_argument("lui_gl: shader source is too large");
  const char *text = String_val(source);
  int count = (int)length;
  submit((unsigned int)Int_val(shader), 1, &text, &count);
  CAMLreturn(Val_unit);
}
