(* In-process backend fast path: transport selection at the patch
   seam. See the .mli. *)

open Lui_protocol

type transport = Lui_wire.transport =
  | In_process
  | Wire

let transport_name = function
  | In_process -> "in-process"
  | Wire -> "wire"

type t = {
  transport : transport;
  deliver : patch_batch -> unit;
}

let create transport deliver = { transport; deliver }
let over_store transport store = create transport (Lui_store.apply_batch store)

let apply_batch t batch =
  t.deliver (Lui_wire.transcode t.transport batch)

let transport t = t.transport

let backend t profile =
  {
    backend_profile = profile;
    apply_batch = (fun batch -> apply_batch t batch; true);
  }
