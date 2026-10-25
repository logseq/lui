/* Calls lui_ocaml_press_detail while the runtime lock is released.
   The export itself re-acquires the lock, so this primitive must be in a
   blocking section for the whole loop. */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/signals.h>
#include <caml/fail.h>
#include <dlfcn.h>

extern int32_t lui_ocaml_press_detail(int64_t node, double x, double y,
                                      int32_t modifiers, int32_t button,
                                      const char *target_class);
extern int32_t lui_ocaml_virtual_window(int64_t node, int64_t generation,
                                        int64_t first, int64_t last,
                                        const int64_t *pins, int32_t count);

value stress_press_detail(value count) {
  CAMLparam1(count);
  int iterations = Int_val(count);
  int index;
  caml_enter_blocking_section();
  for (index = 0; index < iterations; index++) {
    lui_ocaml_press_detail(1, 1.25, 2.5, 3, 0, "hit");
  }
  caml_leave_blocking_section();
  CAMLreturn(Val_unit);
}

value stress_virtual_window(value count) {
  CAMLparam1(count);
  int32_t (*virtual_rows_version)(void) =
    (int32_t (*)(void))dlsym(RTLD_DEFAULT, "lui_ocaml_virtual_rows_version");
  if (virtual_rows_version == NULL || virtual_rows_version() != 1)
    caml_failwith("native host cannot negotiate bounded virtual rows");
  int iterations = Int_val(count);
  int64_t node = INT64_C(9007199254740993);
  int64_t pins[2048];
  int accepted = 1;
  for (int index = 0; index < 2048; index++) pins[index] = node + index + 1;
  caml_enter_blocking_section();
  for (int index = 0; index < iterations && accepted; index++) {
    accepted = lui_ocaml_virtual_window(node, 7, 99990, 100000, pins, 2048);
  }
  if (accepted) {
    accepted = !lui_ocaml_virtual_window(node, 7, 0, 1, NULL, 1) &&
      !lui_ocaml_virtual_window(node, 7, 0, 1, pins, -1) &&
      !lui_ocaml_virtual_window(node, 0, 0, 1, pins, 1) &&
      !lui_ocaml_virtual_window(node, 7, -1, 1, pins, 1) &&
      !lui_ocaml_virtual_window(node, 7, 2, 1, pins, 1) &&
      !lui_ocaml_virtual_window(INT64_MAX, 7, 0, 1, pins, 1);
    pins[0] = 0;
    accepted = accepted && !lui_ocaml_virtual_window(node, 7, 0, 1, pins, 1);
    pins[0] = INT64_MAX;
    accepted = accepted && !lui_ocaml_virtual_window(node, 7, 0, 1, pins, 1);
  }
  caml_leave_blocking_section();
  if (!accepted) caml_failwith("virtual window failed typed dispatch or input validation");
  CAMLreturn(Val_unit);
}
