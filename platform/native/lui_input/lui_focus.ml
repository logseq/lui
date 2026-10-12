(* Focus state machine — see lui_focus.mli for the contract. Owns
   the focused node id, the keyboard-focus ring flag, tab-order
   stepping, autofocus and Appear mount-lifecycle tracking. Pure
   transitions: they read the store and return intents ([`Focus])
   plus dispatches for the driver to perform. *)

open Lui_protocol

module IntSet = Set.Make (Int)

type state = {
  focused : int;
  kbd_visible : bool;
      (* focus arrived via keyboard (Tab) rather than the pointer —
         the distinction behind focus-ring visibility *)
  autofocus_seen : IntSet.t;
      (* autofocus controls already observed during their mount
         lifecycle *)
  appear_seen : IntSet.t;
      (* appear-enabled ids already announced (mount lifecycle) *)
}

let initial =
  { focused = 0; kbd_visible = false;
    autofocus_seen = IntSet.empty; appear_seen = IntSet.empty }

let focused st = st.focused
let kbd_visible st = st.kbd_visible

(* Record a focus change; the surrounding bookkeeping (text session
   re-attach, selection reset, Focus_changed dispatch) is the
   driver's — it composes the other machines. *)
let set st ~id ~kbd =
  if id = st.focused then st
  else { st with focused = id; kbd_visible = kbd }

(* A node is visible unless it or an ancestor carries
   visible=false — the autofocus gate's chain walk. *)
let rec chain_visible store id =
  match Lui_store.prop store id "visible" with
  | Some (BoolValue false) -> false
  | _ ->
    match Lui_store.parent store id with
    | Some parent -> chain_visible store parent
    | None -> true

(* Activation-capable control kinds — the pointer does not focus
   them on this host (macOS-like), Tab/Shift-Tab do. *)
let activatable store id =
  Lui_query.node_enabled store id
  &&
  match Lui_query.kind_name store id with
  | "button" | "toggle-button" | "toggle" | "checkbox" | "switch"
  | "radio" | "slider" | "number-stepper" | "select" | "menu-item" ->
    true
  | _ -> false

(* Whether the node's focused field accepts edits — admits
   TextChanged. *)
let admits_text store id =
  Lui_query.event_supported store id (Lui_query.ev_text id)

let focusables store ~scope =
  List.filter
    (fun id ->
       Lui_query.node_enabled store id
       && (admits_text store id || activatable store id)
       &&
       match scope with
       | None -> true
       | Some ov -> id = ov || Lui_query.is_desc store id ov)
    (Lui_store.preorder store)

(* Next focusable in tab order; wraps. 0 when no focusable exists. *)
let step store ~scope ~cur ~dir =
  match focusables store ~scope with
  | [] -> 0
  | ids ->
    let n = List.length ids in
    let idx =
      match Lui_query.index_of cur ids with
      | Some i -> i
      | None -> if dir > 0 then -1 else n
    in
    List.nth ids (((idx + dir) mod n + n) mod n)

(* Store-sync half A: the focused node disappeared — ask the driver
   to drop focus ([`Focus (0, false)] intent). *)
let sync_dead store st =
  if st.focused <> 0 && not (Lui_store.mem store st.focused)
  then [ `Focus (0, false) ]
  else []

(* Store-sync half B: first not-yet-seen visible autofocus control in
   the active overlay scope. The seen set is refreshed to whatever
   carries autofocus now (it is a mount-lifecycle record). *)
let scan_autofocus store st ~scope:ov_id =
  let autofocus_now =
    List.filter
      (fun id ->
         Lui_store.bool_prop store id "autofocus" && chain_visible store id)
      (Lui_store.preorder store)
  in
  let cand =
    List.find_opt
      (fun id ->
         not (IntSet.mem id st.autofocus_seen)
         && Lui_query.node_enabled store id
         && (admits_text store id || activatable store id)
         && (ov_id = 0 || id = ov_id || Lui_query.is_desc store id ov_id))
      autofocus_now
  in
  ( { st with autofocus_seen = IntSet.of_list autofocus_now },
    cand )

(* Store-sync half C: appear-enabled nodes announce their mount once. *)
let scan_appear store st =
  let now =
    List.filter
      (fun id ->
         Lui_query.node_enabled store id
         && Lui_store.bool_prop store id "appear-enabled"
         && Lui_query.event_supported store id (Appear id))
      (Lui_store.preorder store)
  in
  let acts =
    List.filter_map
      (fun id ->
         if IntSet.mem id st.appear_seen then None
         else Some (`Dispatch (Appear id)))
      now
  in
  ({ st with appear_seen = IntSet.of_list now }, acts)
