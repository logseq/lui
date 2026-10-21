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
  if id = st.focused && kbd = st.kbd_visible then st
  else { st with focused = id; kbd_visible = kbd }

(* Hidden ancestors exclude controls from initial focus and Tab order. *)
let rec chain_visible store id =
  if Lui_store.prop store id "visible" = Some (BoolValue false)
     || Lui_store.string_prop store id "display" = Some "none"
     || not (Lui_store.anchor_available store id) then false
  else
    match Lui_store.parent store id with
    | Some parent -> chain_visible store parent
    | None -> true

let focusables store ~scope =
  List.filter
    (fun id ->
       Lui_query.node_enabled store id
       && Lui_query.focus_candidate store id
       && chain_visible store id
       && not (Lui_store.inert_in_chain store id)
       &&
       match scope with
       | None -> true
       | Some ov -> id = ov || Lui_query.is_desc store id ov)
    (Lui_store.preorder store)

(* Next focusable in tab order; wraps. 0 when no focusable exists. *)
let step store ~scope ~cur ~dir =
  let sequential id =
    match Lui_query.data_attr store id "tabindex" with
    | None -> true
    | Some value -> int_of_string value >= 0
  in
  match List.filter sequential (focusables store ~scope) with
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
  if st.focused <> 0
     && (not (Lui_store.mem store st.focused)
         || Lui_store.inert_in_chain store st.focused
         || not (chain_visible store st.focused))
  then [ `Focus (0, false) ]
  else []

let refresh_seen previous ids =
  if List.length ids = IntSet.cardinal previous
     && List.for_all (fun id -> IntSet.mem id previous) ids
  then previous
  else IntSet.of_list ids

(* Store-sync half B: first not-yet-seen visible autofocus control in
   the active overlay scope. The seen set is refreshed to whatever
   carries autofocus now (it is a mount-lifecycle record). *)
let scan_autofocus store st ~scope:ov_id =
  let now = ref [] and candidate = ref None in
  Lui_store.iter_preorder store (fun id ->
    if Lui_store.bool_prop store id "autofocus" && chain_visible store id
       && not (Lui_store.inert_in_chain store id) then begin
      now := id :: !now;
      if !candidate = None && not (IntSet.mem id st.autofocus_seen)
         && Lui_query.node_enabled store id
         && Lui_query.focus_candidate store id
         && (ov_id = 0 || id = ov_id || Lui_query.is_desc store id ov_id)
      then candidate := Some id
    end);
  ({ st with autofocus_seen = refresh_seen st.autofocus_seen !now }, !candidate)

(* Store-sync half C: appear-enabled nodes announce their mount once. *)
let scan_appear store st =
  let now = ref [] and actions = ref [] in
  Lui_store.iter_preorder store (fun id ->
    if Lui_query.node_enabled store id
       && Lui_store.bool_prop store id "appear-enabled"
       && Lui_query.event_supported store id (Appear id) then begin
      now := id :: !now;
      if not (IntSet.mem id st.appear_seen) then
        actions := `Dispatch (Appear id) :: !actions
    end);
  ({ st with appear_seen = refresh_seen st.appear_seen !now }, List.rev !actions)
