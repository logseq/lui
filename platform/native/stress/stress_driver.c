/* Calls lui_ocaml_press_detail while the runtime lock is released.
   The export itself re-acquires the lock, so this primitive must be in a
   blocking section for the whole loop. */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/signals.h>

extern int32_t lui_ocaml_press_detail(int64_t node, double x, double y,
                                      int32_t modifiers, int32_t button,
                                      const char *target_class);

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
