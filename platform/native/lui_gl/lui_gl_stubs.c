/* Byte copies between OCaml Bytes and the bigarrays the GL bindings
   consume, so atlas, image and framebuffer pixels cross as one memcpy
   instead of an elementwise loop. */
#include <string.h>
#include <caml/mlvalues.h>
#include <caml/bigarray.h>
#include <caml/memory.h>

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
