(* Unit tests for the platform-neutral interaction machines. Each
   machine is a pure transition: a state goes in with a snapshot of
   the store (and, where geometry matters, the rect table and text
   hooks) and a next state plus intents comes out. The composer in
   Lui_window.Ui performs the intents; these tests pin the machine
   semantics on their own — the split's whole point is that they do
   not need a window. *)

open Lui_scene
open Lui_protocol

let store_of ops =
  let s = Lui_store.create () in
  Lui_store.apply_batch s { generation = 1; ops };
  s

let rects_of l =
  let t = Lui_query.Rects.create () in
  List.iter (fun (id, r) -> Hashtbl.replace t id r) l;
  t

(* root 1 → column 2 → text-field 4 ("hello"), list 5 → items
   6,7,8; dialog 9 → button 10 mounts on demand *)
let base_ops =
  [ CreateNode (1, Root);
    CreateNode (2, Column);
    CreateNode (4, TextField);
    CreateNode (5, ListContainer);
    CreateNode (6, ListItem);
    CreateNode (7, ListItem);
    CreateNode (8, ListItem);
    InsertChild (1, 2, 0);
    InsertChild (2, 4, 0);
    InsertChild (2, 5, 1);
    InsertChild (5, 6, 0);
    InsertChild (5, 7, 1);
    InsertChild (5, 8, 2);
    SetProp (4, TextValue, StringValue "hello");
    SetProp (6, TextValue, StringValue "apple");
    SetProp (7, TextValue, StringValue "banana");
    SetProp (8, TextValue, StringValue "cherry") ]

let dialog_ops =
  [ CreateNode (9, Dialog);
    CreateNode (10, Button);
    InsertChild (1, 9, 1);
    InsertChild (9, 10, 0) ]

let base_store () = store_of (base_ops @ dialog_ops)
let hooks = Lui_query.default_hooks
let none = Lui_input.mods_none

(* ---------- Lui_focus ---------- *)

let test_focus_step () =
  let store = store_of base_ops in
  (* 4 (text-field) is the only focusable here — buttons alone do
     not count without activation props? activatable kinds do. *)
  let st = Lui_focus.initial in
  let n = Lui_focus.step store ~scope:None ~cur:0 ~dir:1 in
  Alcotest.(check bool) "a focusable exists" true (n <> 0);
  (* modal scope: nothing inside dialog 9 except button 10 — but
     the dialog is not in base_ops' store; scope on subtree 2 *)
  let n2 =
    Lui_focus.step store ~scope:(Some 2) ~cur:0 ~dir:1
  in
  Alcotest.(check bool) "in-scope focusable" true (n2 <> 0);
  ignore st

let test_focus_dead () =
  let store = store_of base_ops in
  let st = Lui_focus.set Lui_focus.initial ~id:4 ~kbd:false in
  Alcotest.(check int) "focused" 4 (Lui_focus.focused st);
  let acts = Lui_focus.sync_dead store st in
  Alcotest.(check int) "live node: no intents" 0 (List.length acts);
  (* drop the node *)
  Lui_store.apply_op store (DropNode 4);
  match Lui_focus.sync_dead store st with
  | [ `Focus (0, false) ] -> ()
  | _ -> Alcotest.fail "expected a clear-focus intent"

let test_inert_subtree () =
  let store = store_of
    [ CreateNode (1, Column); CreateNode (2, Box); CreateNode (3, Box); CreateNode (6, Button);
      CreateNode (4, TextField); CreateNode (5, Button);
      InsertChild (1,2,0); InsertChild (2,3,0); InsertChild (3,6,0); InsertChild (2,4,1);
      InsertChild (1,5,1); SetProp (6,TextValue,StringValue "Hidden action");
      SetProp (6,PointerEnabled,BoolValue true);
      SetProp (4,Autofocus,BoolValue true);
      SetProp (4,AppearEnabled,BoolValue true);
      SetProp (2,Inert,BoolValue true);
      SetProp (3,Inert,BoolValue false) ] in
  let failures = ref [] in
  let expect label value = if not value then failures := label :: !failures in
  expect "inert descendants leave Tab order"
    (Lui_focus.focusables store ~scope:None = [5]);
  expect "inert descendants cannot autofocus"
    (snd (Lui_focus.scan_autofocus store Lui_focus.initial ~scope:0) = None);
  let focused = Lui_focus.set Lui_focus.initial ~id:4 ~kbd:false in
  expect "making the focused subtree inert releases focus"
    (Lui_focus.sync_dead store focused = [`Focus (0,false)]);
  expect "inert descendants reject user events"
    (not (Lui_query.event_supported store 6 (Press 6))
     && not (Lui_query.event_supported store 4 (TextChanged (4,"x"))));
  expect "inert preserves mount lifecycle events"
    (Lui_query.event_supported store 4 (Appear 4));
  let mask = Lui_store.mask_of_prop "inert" in
  expect "inert changes input and semantics without relayout"
    (Lui_store.mask_has mask Lui_store.d_input
     && Lui_store.mask_has mask Lui_store.d_semantics
     && not (Lui_store.mask_has mask Lui_store.d_layout));
  let rects = rects_of [1,rect 0. 0. 200. 100.; 2,rect 0. 0. 100. 100.;
    3,rect 0. 0. 100. 40.; 6,rect 0. 0. 100. 40.; 4,rect 0. 40. 100. 40.; 5,rect 100. 0. 100. 40.] in
  expect "inert descendants cannot opt back into pointer hits"
    (not (List.mem 6 (Lui_query.hit_path store rects ~x:20. ~y:20.)));
  Lui_store.apply_op store (RemoveProp (2,Inert));
  expect "removing inert restores the same controls"
    (Lui_focus.focusables store ~scope:None = [6;4;5]
     && Lui_query.event_supported store 6 (Press 6));
  List.iter prerr_endline (List.rev !failures);
  Alcotest.(check (list string)) "inert interaction contract" [] (List.rev !failures)

let test_inert_overlay () =
  let store = store_of
    [CreateNode (1,Column); CreateNode (2,Box); CreateNode (3,Dialog);
     CreateNode (4,Button); InsertChild (1,2,0); InsertChild (2,3,0);
     InsertChild (3,4,0); SetProp (2,Inert,BoolValue true);
     SetProp (4,PointerEnabled,BoolValue true)] in
  Alcotest.(check (option (triple int bool bool)))
    "inert modal cannot capture the active interaction scope" None
    (Lui_overlay.top_scan store ~open_menu:0)

(* ---------- Lui_overlay: the modal focus scope (C3) ---------- *)

let test_modal_clears_background_focus () =
  let store = store_of base_ops in
  let ov = ref Lui_overlay.initial in
  (* no overlay yet *)
  let st, acts = Lui_overlay.sync store !ov ~focused:4 in
  ov := st;
  Alcotest.(check int) "no overlay acts" 0 (List.length acts);
  Alcotest.(check int) "top" 0 (Lui_overlay.top !ov);
  (* mount the dialog while the text-field holds focus *)
  Lui_store.apply_batch store
    { generation = 2; ops = dialog_ops };
  let st, acts = Lui_overlay.sync store !ov ~focused:4 in
  ov := st;
  Alcotest.(check int) "modal on top" 9 (Lui_overlay.top !ov);
  (* the machine must ask the driver to clear focus and drop any
     static selection *)
  (match acts with
   | [ `Clear_selection; `Focus (0, false) ] -> ()
   | _ -> Alcotest.fail "expected clear-selection + clear-focus");
  Alcotest.(check int) "saved focus" 4 (Lui_overlay.saved_focus !ov);
  (* dialog disappears — focus restores *)
  Lui_store.apply_op store (DropNode 9);
  let st, acts = Lui_overlay.sync store !ov ~focused:0 in
  ov := st;
  (match acts with
   | [ `Focus (4, false) ] -> ()
   | _ -> Alcotest.fail "expected restore-focus intent");
  Alcotest.(check int) "save slot reset" 0
    (Lui_overlay.saved_focus !ov)

let test_modal_press_swallow_and_dismiss () =
  let store = base_store () in
  (* modal dialog: a press outside its subtree is swallowed *)
  (match Lui_overlay.press store Lui_overlay.initial [ 4; 2; 1 ] with
   | _, `Swallow -> ()
   | _ -> Alcotest.fail "modal should swallow an outside press");
  (match Lui_overlay.press store Lui_overlay.initial [ 10; 9; 1 ] with
   | _, `Proceed [] -> ()
   | _ -> Alcotest.fail "inside press proceeds quietly");
  (* a light-dismissible overlay emits Dismiss on an outside press *)
  Lui_store.apply_op store (DropNode 9);
  Lui_store.apply_batch store
    { generation = 3;
      ops =
        [ CreateNode (11, Popover);
          InsertChild (1, 11, 1) ] };
  (match Lui_overlay.press store Lui_overlay.initial [ 4; 2; 1 ] with
   | _, `Proceed [ `Dispatch (Dismiss 11) ] -> ()
   | _ -> Alcotest.fail "popover should light-dismiss")

let test_escape_peels () =
  let store = base_store () in
  let st, res = Lui_overlay.escape store Lui_overlay.initial in
  (match res with
   | `Dismissed 9 -> ()
   | _ -> Alcotest.fail "dialog dismisses on Escape");
  ignore st;
  Lui_store.apply_op store (DropNode 9);
  let _, res = Lui_overlay.escape store Lui_overlay.initial in
  (match res with
   | `Pass -> ()
   | _ -> Alcotest.fail "no overlay: Escape falls through")

(* ---------- Lui_gesture: list nav inside the modal scope ---------- *)

let test_list_nav () =
  let store = store_of base_ops in
  let st =
    Lui_gesture.note_list_context store Lui_gesture.initial
      ~path:[ 6; 5; 2; 1 ]
  in
  Alcotest.(check int) "pressed item highlights" 6
    (Lui_gesture.hl st);
  let st, _ =
    Lui_gesture.move_hl store st ~scope:0 1
  in
  Alcotest.(check int) "down" 7 (Lui_gesture.hl st);
  let items = Lui_gesture.list_items store st ~scope:0 in
  Alcotest.(check int) "items" 3 (List.length items)

let test_list_modal_scope () =
  let store = base_store () in
  let st =
    Lui_gesture.note_list_context store Lui_gesture.initial
      ~path:[ 6; 5; 2; 1 ]
  in
  (* the list sits outside the dialog: scope 9 hides it *)
  let items = Lui_gesture.list_items store st ~scope:9 in
  Alcotest.(check int) "outside-scope list is dead" 0
    (List.length items);
  let st', acts =
    Lui_gesture.list_key store st ~scope:9
      ~content_rect:(fun _ -> Lui_scene.rect 0. 0. 100. 100.)
      ~key:Lui_input.Arrow_down ~mods:none
  in
  Alcotest.(check int) "no highlight move outside scope" 6
    (Lui_gesture.hl st');
  Alcotest.(check int) "no acts outside scope" 0
    (List.length acts)

(* ---------- Lui_text_input: edits, undo, caret ops ---------- *)

let test_text_session () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"hello"
  in
  Alcotest.(check int) "caret at end" 5 (Lui_text_input.caret st);
  let st, acts = Lui_text_input.splice st "!" in
  Alcotest.(check string) "shadow" "hello!" (Lui_text_input.text st);
  (match acts with
   | `Dispatch (TextChanged (4, "hello!")) :: _ -> ()
   | _ -> Alcotest.fail "expected TextChanged dispatch");
  (* mirror follows *)
  Alcotest.(check bool) "mirror emitted" true
    (List.exists
       (function `Mirror_text (4, "hello!") -> true | _ -> false)
       acts);
  ignore store

let test_text_navigation () =
  List.iter (fun kind ->
    let store = store_of [CreateNode (1,kind);
      SetProp (1,TextValue,StringValue "first\nsecond");
      SetProp (1,NavigateEnabled,BoolValue true)] in
    let rects = rects_of [1,rect 0. 0. 200. 60.] in
    let st = Lui_text_input.attach Lui_text_input.initial ~node:1 ~text:"first\nsecond" in
    let run st mods key = Lui_text_input.key hooks store rects st ~k:key ~mods ~prim:false in
    List.iter (fun (key,event) ->
      let next,actions = run st none key in
      Alcotest.(check bool) "navigation dispatches without editing" true
        (actions = [`Dispatch event] && next = st))
      [Lui_input.Arrow_up,NavigatePrevious 1;Lui_input.Arrow_down,NavigateNext 1];
    List.iter (fun mods ->
      let _,actions = run st mods Lui_input.Arrow_up in
      Alcotest.(check bool) "modified arrows retain caret semantics" false
        (List.exists (function `Dispatch (NavigatePrevious _ | NavigateNext _) -> true | _ -> false) actions))
      [{none with shift=true};{none with ctrl=true};{none with meta=true};{none with alt=true}];
    let composing,_ = Lui_text_input.feed_ime store st (`Editing ("candidate",0,0)) in
    let _,actions = run composing none Lui_input.Arrow_down in
    Alcotest.(check bool) "composition owns navigation keys" false
      (List.exists (function `Dispatch (NavigatePrevious _ | NavigateNext _) -> true | _ -> false) actions);
    Lui_store.apply_op store (RemoveProp (1,NavigateEnabled));
    let next,actions = run st none Lui_input.Arrow_up in
    Alcotest.(check bool) "unregistered arrows move the caret" true
      (Lui_text_input.caret next <> Lui_text_input.caret st && actions = [`Repaint]);
    Alcotest.(check bool) "unregistered navigation is rejected" false
      (Lui_query.event_supported store 1 (NavigateNext 1));
    Lui_store.apply_op store (SetProp (1,NavigateEnabled,BoolValue true));
    Lui_store.apply_op store (SetProp (1,Enabled,BoolValue false));
    let _,actions = run st none Lui_input.Arrow_down in
    Alcotest.(check bool) "disabled controls cannot navigate" false
      (List.exists (function `Dispatch (NavigatePrevious _ | NavigateNext _) -> true | _ -> false) actions))
    [TextField;SecureField;Input;SearchField;Textarea]

let test_scroll_anchor_alignment () =
  List.iter (fun scale ->
    let store = store_of [CreateNode (1,ListContainer);CreateNode (2,ListItem);
      InsertChild (1,2,0)] in
    let aligned ~offset ~top ~height anchor =
      let env = Lui_scroll.{content_rect=(fun id ->
        if id=1 then rect 0. 0. 100. (100. *. scale)
        else rect 0. (top *. scale) 100. (height *. scale));rects_epoch=0;vlist=None} in
      let state,_ = Lui_scroll.set_cap Lui_scroll.initial Lui_scroll.Y 1 (500. *. scale) in
      let state,_ = Lui_scroll.set_offset env store state Lui_scroll.Y 1 (offset *. scale) in
      let state,_ = Lui_scroll.scroll_align env store state 1 2 anchor in
      Lui_scroll.offset state Lui_scroll.Y 1 /. scale in
    List.iter (fun (label,offset,top,height,anchor,expected) ->
      Alcotest.(check (float 0.001)) label expected (aligned ~offset ~top ~height anchor))
      ["visible row stays still",50.,60.,20.,"nearest",50.;
       "reveal above",50.,20.,20.,"nearest",20.;
       "reveal below",50.,140.,30.,"nearest",70.;
       "explicit top aligns",50.,60.,20.,"top",60.;
       "center aligns",50.,160.,20.,"center",120.;
       "bottom aligns",50.,160.,20.,"bottom",80.]) [1.;2.]

let test_text_undo () =
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"ab"
  in
  let st, _ = Lui_text_input.splice st "c" in
  let st, _ = Lui_text_input.undo st ~shift:false in
  Alcotest.(check string) "undo restores" "ab"
    (Lui_text_input.text st);
  let st, _ = Lui_text_input.undo st ~shift:true in
  Alcotest.(check string) "redo replays" "abc"
    (Lui_text_input.text st)

let test_text_padding_hit () =
  List.iter
    (fun scale ->
      let store =
        store_of
          [
            CreateNode (1, SearchField);
            SetProp (1, PaddingHorizontal, IntValue 10);
            SetProp (1, PaddingVertical, IntValue 6);
            SetProp (1, PaddingLeft, IntValue 28);
            SetProp (1, PaddingRight, IntValue 8);
            SetProp (1, PaddingTop, IntValue 3);
            SetProp (1, PaddingBottom, IntValue 9);
          ]
      in
      let rects =
        rects_of
          [
            ( 1,
              rect (10. *. scale) (20. *. scale) (200. *. scale) (40. *. scale)
            );
          ]
      in
      let hooks =
        {
          hooks with
          Lui_query.scale;
          measure =
            (fun _ _ text ->
              (float (String.length text * 8) *. scale, 16. *. scale));
        }
      in
      List.iter
        (fun (x, expected) ->
          let got =
            Lui_query.offset_at_point hooks store rects 1
              ~x:((10. +. x) *. scale)
              ~y:(28. *. scale) "hello"
          in
          Alcotest.(check int)
            "click maps through the leading inset" expected got)
        [ (12., 0); (28., 0); (36., 1); (44., 2); (68., 5) ];
      let got =
        Lui_query.offset_at_point hooks store rects 1 ~x:(38. *. scale)
          ~y:(39.5 *. scale) "a\nb"
      in
      Alcotest.(check int) "multiline hit uses the top inset" 2 got)
    [ 1.; 2. ]

(* The caret-ops hook (C7): horizontal moves and Backspace/Delete
   consult the engine's grapheme model; without it the codepoint
   fallback stands. *)
let test_text_caret_ops () =
  let store = store_of base_ops in
  let seen = ref [] in
  let ops =
    { Lui_query.c_before = (fun i -> seen := `B i :: !seen; i - 2);
      c_after = (fun i -> seen := `A i :: !seen; i + 2);
      c_up = (fun i -> i);
      c_down = (fun i -> i);
      c_rect = (fun _ -> (0., 0., 0.)) }
  in
  let hooks' =
    { hooks with
      Lui_query.caret_ops =
        Some (fun _s _id _t ~lw:_ ~lh:_ -> ops) }
  in
  let rects = rects_of [ (4, rect 0. 0. 100. 20.) ] in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"hello"
  in
  let st, _ =
    Lui_text_input.key hooks' store rects st ~k:Lui_input.Arrow_left
      ~mods:none ~prim:false
  in
  Alcotest.(check int) "engine step back" 3
    (Lui_text_input.caret st);
  Alcotest.(check bool) "op consulted" true (!seen <> []);
  (* the fallback path with no engine steps one codepoint *)
  let st, _ =
    Lui_text_input.key hooks store rects st ~k:Lui_input.Arrow_left
      ~mods:none ~prim:false
  in
  Alcotest.(check int) "codepoint step" 2 (Lui_text_input.caret st)

let test_text_ime_commit () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  (* a composition's commit lands through the normal splice path *)
  let st, _acts =
    Lui_text_input.feed_ime store st
      (`Editing ("に", 0, 2))
  in
  Alcotest.(check string) "marked" "に" (Lui_text_input.marked st);
  let st, _acts2 =
    Lui_text_input.feed_ime store st (`Commit "に")
  in
  Alcotest.(check string) "committed" "xに" (Lui_text_input.text st);
  Alcotest.(check bool) "not composing" false
    (Lui_text_input.composing st)

(* ---------- P1-2: the session revision protocol ---------- *)

(* Rapid typing: every local edit mirrors into the prop instantly,
   so the model echo Acks without ever rolling the shadow back —
   local typing never waits on the round trip. *)
let test_revision_rapid_typing () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  let st, _ = Lui_text_input.splice st "a" in
  Alcotest.(check int) "local rev" 1
    (Lui_text_input.local_revision st);
  (* the app's echo of the mirrored prop arrives — an Ack *)
  let st, acts =
    Lui_text_input.sync_model store st ~model_text:"xa"
  in
  Alcotest.(check bool) "ack response" true
    (Lui_text_input.model_response st = `Ack);
  Alcotest.(check int) "no repaint churn" 0 (List.length acts);
  Alcotest.(check string) "shadow intact" "xa"
    (Lui_text_input.text st);
  (* type ahead before the next frame — still intact *)
  let st, _ = Lui_text_input.splice st "b" in
  let st, _ =
    Lui_text_input.sync_model store st ~model_text:"xab"
  in
  Alcotest.(check string) "rapid typing stable" "xab"
    (Lui_text_input.text st)

(* A stale model re-write of the attached baseline is a no-op —
   it cannot roll the shadow back over pending local edits. *)
let test_revision_stale_model_ignored () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  let st, _ = Lui_text_input.splice st "a" in
  let st, acts =
    Lui_text_input.sync_model store st ~model_text:"x"
  in
  Alcotest.(check string) "stale baseline ignored" "xa"
    (Lui_text_input.text st);
  Alcotest.(check int) "no acts" 0 (List.length acts)

(* A genuinely new model text while local edits are in flight is a
   Correction: the model is canonical — adopt, clamp, drop undo. *)
let test_revision_correction () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  let st, _ = Lui_text_input.splice st "a" in
  let st, acts =
    Lui_text_input.sync_model store st ~model_text:"replaced"
  in
  Alcotest.(check bool) "correction" true
    (Lui_text_input.model_response st = `Correction);
  Alcotest.(check string) "model wins" "replaced"
    (Lui_text_input.text st);
  Alcotest.(check int) "model rev" 1
    (Lui_text_input.model_revision st);
  Alcotest.(check bool) "repaint" true
    (List.exists (function `Repaint -> true | _ -> false) acts);
  (* no pending undo across a correction *)
  let st, _ = Lui_text_input.undo st ~shift:false in
  Alcotest.(check string) "undo does not resurrect" "replaced"
    (Lui_text_input.text st)

(* The same change on a clean session is a Reset, not a
   Correction. *)
let test_revision_reset () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  let st, _ =
    Lui_text_input.sync_model store st ~model_text:"remote"
  in
  Alcotest.(check bool) "reset" true
    (Lui_text_input.model_response st = `Reset);
  Alcotest.(check string) "adopted" "remote"
    (Lui_text_input.text st)

(* A model update landing mid-composition cancels it — marked text
   was never dispatched, so rollback on the changed base is the
   only stable answer. *)
let test_revision_cancels_composition () =
  let store = store_of base_ops in
  let st =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  let st, _ =
    Lui_text_input.feed_ime store st (`Editing ("に", 0, 2))
  in
  Alcotest.(check bool) "composing" true
    (Lui_text_input.composing st);
  let st, _ =
    Lui_text_input.sync_model store st ~model_text:"new base"
  in
  Alcotest.(check string) "marked cleared" ""
    (Lui_text_input.marked st);
  Alcotest.(check string) "base adopted" "new base"
    (Lui_text_input.text st)

(* Every attach starts a fresh session — responses to the old one
   cannot leak across the boundary. *)
let test_session_ids () =
  let a =
    Lui_text_input.attach Lui_text_input.initial ~node:4 ~text:"x"
  in
  let b = Lui_text_input.attach a ~node:0 ~text:"" in
  let c = Lui_text_input.attach b ~node:4 ~text:"y" in
  Alcotest.(check bool) "session bumps" true
    (Lui_text_input.session_id a <> Lui_text_input.session_id c);
  Alcotest.(check int) "fresh revisions" 0
    (Lui_text_input.local_revision c)

(* ---------- Lui_selection ---------- *)

let test_static_selection () =
  let store =
    store_of
      [ CreateNode (1, Root);
        CreateNode (2, Column);
        CreateNode (3, Text);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0);
        SetProp (3, TextValue, StringValue "selectable words");
        SetProp
          (3, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("data-user-select", "text") ])) ]
  in
  let rects = rects_of [ (3, rect 0. 0. 200. 20.) ] in
  let st, _ =
    Lui_selection.press hooks store rects Lui_selection.initial
      ~path:[ 3; 2; 1 ] ~clicks:1 ~shift:false ~x:10. ~y:10.
  in
  (* default measure is 8px/char: x=10 → byte ~1 *)
  Alcotest.(check bool) "anchor set" true
    (Lui_selection.text st <> None);
  let st, _ =
    Lui_selection.drag_move hooks store rects st ~x:80. ~y:10.
  in
  (match Lui_selection.selected_text store st with
   | Some s ->
     Alcotest.(check bool) "nonempty selection" true
       (String.length s > 0)
   | None -> Alcotest.fail "expected selected text")

(* ---------- Lui_scroll ---------- *)

let scroll_env () =
  { Lui_scroll.content_rect =
      (fun id ->
         if id = 5 then rect 0. 0. 100. 100.
         else rect 0. 0. 100. 20.);
    rects_epoch = 1;
    vlist = None }

let test_scroll_offsets () =
  let store = store_of base_ops in
  let env = scroll_env () in
  let st, _ = Lui_scroll.set_cap Lui_scroll.initial Lui_scroll.Y 5 200. in
  let st, _ = Lui_scroll.scroll_by env store st 5 50. in
  Alcotest.(check (float 0.001)) "offset" 50.
    (Lui_scroll.offset st Lui_scroll.Y 5);
  let st, _ = Lui_scroll.scroll_by env store st 5 500. in
  Alcotest.(check (float 0.001)) "clamped" 200.
    (Lui_scroll.offset st Lui_scroll.Y 5);
  (* a shrinking cap clamps a dangling offset *)
  let st, m = Lui_scroll.set_cap st Lui_scroll.Y 5 30. in
  Alcotest.(check (float 0.001)) "cap clamp" 30.
    (Lui_scroll.offset st Lui_scroll.Y 5);
  Alcotest.(check bool) "repaint emitted" true
    (List.exists (function `Repaint -> true | _ -> false) m)

let test_wheel () =
  let store = store_of base_ops in
  let env = scroll_env () in
  let st, _ =
    Lui_scroll.set_cap Lui_scroll.initial Lui_scroll.Y 5 200.
  in
  let st, _ =
    Lui_scroll.wheel env store st ~path:[ 6; 5; 2; 1 ] ~scale:1.
      ~dx:0. ~dy:(-1.) ~mods:none
  in
  Alcotest.(check bool) "wheel moved content" true
    (Lui_scroll.offset st Lui_scroll.Y 5 > 0.)

let test_wheel_boundary_chaining () =
  let store =
    store_of
      [
        CreateNode (1, Root);
        CreateNode (2, Scroll);
        CreateNode (3, Scroll);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0);
      ]
  in
  let env = scroll_env () in
  List.iter
    (fun axis ->
      List.iter
        (fun (inner, delta, expected_inner, expected_outer) ->
          let state, _ = Lui_scroll.set_cap Lui_scroll.initial axis 2 200. in
          let state, _ = Lui_scroll.set_cap state axis 3 100. in
          let state, _ = Lui_scroll.set_offset env store state axis 2 50. in
          let state, _ = Lui_scroll.set_offset env store state axis 3 inner in
          let dx, dy =
            match axis with Lui_scroll.X -> (delta, 0.) | Y -> (0., -.delta)
          in
          let result, _ =
            Lui_scroll.wheel env store state ~path:[ 3; 2; 1 ] ~scale:1. ~dx ~dy
              ~mods:none
          in
          Alcotest.(check (float 0.001))
            "inner scroll owns available movement" expected_inner
            (Lui_scroll.offset result axis 3);
          Alcotest.(check (float 0.001))
            "wheel reaches an ancestor at the inner boundary" expected_outer
            (Lui_scroll.offset result axis 2))
        [
          (100., 1., 100., 94.);
          (0., -1., 0., 6.);
          (50., 1., 94., 50.);
          (50., -1., 6., 50.);
        ])
    [ Lui_scroll.X; Y ]

(* ---------- Lui_drag ---------- *)

let test_drag_flow () =
  let store =
    store_of
      [ CreateNode (1, Root);
        CreateNode (2, Column);
        CreateNode (3, Box);
        CreateNode (4, Box);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0);
        InsertChild (2, 4, 1);
        SetProp
          (3, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("draggable", "true");
                   ("data-drag-payload", "card1") ]));
        SetProp
          (4, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("data-drop-target", "true") ])) ]
  in
  let st = Lui_drag.note_down Lui_drag.initial ~x:0. ~y:0. in
  let st = Lui_drag.arm store st ~path:[ 3; 2; 1 ] in
  (* below the threshold: no session yet *)
  Alcotest.(check bool) "not live" false (Lui_drag.active st);
  (match Lui_drag.promote store st ~x:3. ~y:2. with
   | Some _ -> Alcotest.fail "premature promote"
   | None -> ());
  (match Lui_drag.promote store st ~x:10. ~y:10. with
   | Some (st', _m) ->
     Alcotest.(check bool) "live" true (Lui_drag.active st');
     let st'', _ =
       Lui_drag.track store st' ~path:[ 4; 2; 1 ]
     in
     Alcotest.(check int) "target" 4 (Lui_drag.target st'');
     let st''', _ = Lui_drag.drop st'' in
     (match Lui_drag.last_drop st''' with
      | Some (4, "card1", _) -> ()
      | _ -> Alcotest.fail "expected drop record")
   | None -> Alcotest.fail "expected promote")

(* ---------- Lui_pointer ---------- *)

let test_pointer_hover_press () =
  let store =
    store_of
      [ CreateNode (1, Root);
        CreateNode (2, Button);
        InsertChild (1, 2, 0);
        SetProp (2, PointerEnabled, BoolValue true) ]
  in
  let st =
    Lui_pointer.move store Lui_pointer.initial ~path:[ 2; 1 ]
      ~x:5. ~y:5.
  in
  ignore st;
  let st, m =
    Lui_pointer.down store Lui_pointer.initial ~path:[ 2; 1 ]
      ~x:5. ~y:5. ~button:Lui_input.Left ~clicks:1 ~mods:none
  in
  Alcotest.(check int) "press target" 2 (Lui_pointer.pressed st);
  Alcotest.(check bool) "down dispatched" true
    (List.exists
       (function `Dispatch (PointerDown (2, _)) -> true | _ -> false)
       m);
  let _st2, m2 =
    Lui_pointer.up store st ~x:5. ~y:5. ~button:Lui_input.Left
      ~mods:none
  in
  Alcotest.(check bool) "up dispatched" true
    (List.exists
       (function `Dispatch (PointerUp (2, _)) -> true | _ -> false)
       m2)

(* ---------- spatial index (P2-2) ---------- *)

(* A tree exercising everything hit-testing must agree on: a scroll
   clip with clipped-away children, a popover promoted out of that
   clip, a wide list exercising the interval index, display:contents,
   a hidden subtree, a spacer and z-reordered overlap. *)
let spatial_hit_store () =
  store_of
    ([ CreateNode (1, Root); CreateNode (2, Scroll);
       CreateNode (3, Button);
       CreateNode (4, Column); CreateNode (50, Popover);
       CreateNode (7, ListContainer);
       CreateNode (8, Column); CreateNode (9, Button);
       CreateNode (10, Button); CreateNode (11, Spacer);
       CreateNode (12, Button); CreateNode (13, Button);
       SetProp (8, DisplayValue, StringValue "contents");
       SetProp (10, Visible, BoolValue false);
       SetProp (12, ZIndex, IntValue 1);
       SetProp (13, ZIndex, IntValue 2);
       InsertChild (1, 2, 0);
       InsertChild (2, 3, 0); InsertChild (2, 4, 1);
       InsertChild (4, 50, 0);
       InsertChild (1, 7, 1);
       InsertChild (1, 8, 2); InsertChild (8, 9, 0);
       InsertChild (1, 10, 3); InsertChild (1, 11, 4);
       InsertChild (1, 12, 5); InsertChild (1, 13, 6) ]
    @ List.concat_map
        (fun i ->
          [ CreateNode (100 + i, ListItem);
            SetProp (100 + i, TextValue, StringValue "row");
            InsertChild (7, 100 + i, i) ])
        (List.init 40 Fun.id))

let spatial_hit_rects =
  [ (1, rect 0. 0. 300. 200.); (2, rect 0. 0. 100. 80.);
    (3, rect 0. 0. 100. 40.); (4, rect 0. 120. 100. 40.);
    (50, rect 0. 120. 60. 20.); (7, rect 100. 0. 200. 200.);
    (8, rect 100. 60. 100. 20.); (9, rect 100. 60. 100. 20.);
    (10, rect 150. 100. 50. 50.); (11, rect 0. 90. 100. 10.);
    (12, rect 150. 150. 50. 40.); (13, rect 150. 150. 50. 40.) ]
  @ List.init 40 (fun i ->
        (100 + i, rect 100. (float_of_int i *. 5.) 200. 5.))

let spatial_index store rects =
  Lui_spatial.build Lui_paint.spatial_env store
    ~rect_of:(Lui_query.Rects.get rects)

(* Indexed and unindexed hit paths must agree on every point. *)
let test_spatial_hit_equiv () =
  let store = spatial_hit_store () in
  let rects = rects_of spatial_hit_rects in
  let idx = spatial_index store rects in
  let y = ref (-10.) in
  while !y < 210. do
    let x = ref (-10.) in
    while !x < 310. do
      let a = Lui_query.hit_path store rects ~x:!x ~y:!y in
      let b = Lui_query.hit_path ~spatial:idx store rects ~x:!x ~y:!y in
      if a <> b then
        Alcotest.failf "hit_path diverged at (%.1f,%.1f): %s vs %s" !x !y
          (String.concat "," (List.map string_of_int a))
          (String.concat "," (List.map string_of_int b));
      x := !x +. 7.5
    done;
    y := !y +. 7.5
  done

(* The promoted popover escapes its off-clip parent: indexed or not,
   a click in its painted area must still land on it. *)
let test_spatial_hit_popup_escape () =
  let store = spatial_hit_store () in
  let rects = rects_of spatial_hit_rects in
  let idx = spatial_index store rects in
  Alcotest.(check (option int)) "popover hits" (Some 50)
    (Lui_query.hit ~spatial:idx store rects ~x:10. ~y:130.);
  Alcotest.(check (option int)) "clipped child misses" (Some 1)
    (Lui_query.hit ~spatial:idx store rects ~x:10. ~y:100.)

(* The interval index enumerates the same candidates in the same
   order the unindexed walk would — a click deep in a 40-row list. *)
let test_spatial_hit_wide_list () =
  let store = spatial_hit_store () in
  let rects = rects_of spatial_hit_rects in
  let idx = spatial_index store rects in
  Alcotest.(check (option int)) "row 20 hits" (Some 120)
    (Lui_query.hit ~spatial:idx store rects ~x:110. ~y:102.);
  Alcotest.(check (option int)) "last row hits" (Some 139)
    (Lui_query.hit ~spatial:idx store rects ~x:110. ~y:197.)

let test_frontmost_hit_ancestry () =
  let check_modes store rects f =
    List.iter
      (fun spatial -> f (Lui_query.hit_path ?spatial store rects))
      [ None; Some (spatial_index store rects) ]
  in
  let store =
    store_of
      [
        CreateNode (1, Root);
        CreateNode (2, Button);
        CreateNode (3, Dialog);
        CreateNode (4, TextField);
        InsertChild (1, 2, 0);
        InsertChild (1, 3, 1);
        InsertChild (3, 4, 0);
        SetProp (2, TextValue, StringValue "Background");
        SetProp (2, PressEnabled, BoolValue true);
      ]
  in
  let rects =
    rects_of
      [
        (1, rect 0. 0. 400. 300.);
        (2, rect 20. 20. 200. 40.);
        (3, rect 10. 10. 250. 100.);
        (4, rect 20. 20. 200. 40.);
      ]
  in
  check_modes store rects (fun hit ->
      let path = hit ~x:50. ~y:40. in
      Alcotest.(check (list int))
        "modal input owns its ancestry" [ 4; 3; 1 ] path;
      Alcotest.(check (option int))
        "modal input keeps text focus" (Some 4)
        (Lui_query.focus_target store path);
      Alcotest.(check bool)
        "modal input never activates the background button" false
        (Lui_query.press_target store path = Some 2));
  let store =
    store_of
      [
        CreateNode (1, Root);
        CreateNode (2, Button);
        CreateNode (3, Button);
        InsertChild (1, 2, 0);
        InsertChild (1, 3, 1);
        SetProp (2, TextValue, StringValue "Back");
        SetProp (3, TextValue, StringValue "Front");
        SetProp (2, PressEnabled, BoolValue true);
        SetProp (3, PressEnabled, BoolValue true);
      ]
  in
  let rects =
    rects_of
      [
        (1, rect 0. 0. 400. 300.);
        (2, rect 20. 20. 200. 40.);
        (3, rect 20. 20. 200. 40.);
      ]
  in
  check_modes store rects (fun hit ->
      Alcotest.(check (list int))
        "overlapping siblings do not share a hit path" [ 3; 1 ]
        (hit ~x:50. ~y:40.));
  Lui_store.apply_op store (SetProp (3, PointerEnabled, BoolValue false));
  check_modes store rects (fun hit ->
      Alcotest.(check (list int))
        "pointer-disabled sibling passes through" [ 2; 1 ] (hit ~x:50. ~y:40.));
  let store =
    store_of
      [
        CreateNode (1, Root);
        CreateNode (2, Scroll);
        CreateNode (3, Column);
        CreateNode (4, Popover);
        CreateNode (5, MenuItem);
        CreateNode (6, Button);
        InsertChild (1, 2, 0);
        InsertChild (1, 6, 1);
        InsertChild (2, 3, 0);
        InsertChild (3, 4, 0);
        InsertChild (4, 5, 0);
        SetProp (5, TextValue, StringValue "Choice");
        SetProp (5, PressEnabled, BoolValue true);
        SetProp (6, TextValue, StringValue "Behind popup");
        SetProp (6, PressEnabled, BoolValue true);
      ]
  in
  let rects =
    rects_of
      [
        (1, rect 0. 0. 400. 300.);
        (2, rect 0. 0. 100. 50.);
        (3, rect 0. 120. 100. 30.);
        (4, rect 0. 120. 100. 30.);
        (5, rect 0. 120. 100. 16.);
        (6, rect 0. 120. 100. 30.);
      ]
  in
  check_modes store rects (fun hit ->
      Alcotest.(check (list int))
        "promoted popup retains only hit ancestors" [ 5; 4; 1 ]
        (hit ~x:20. ~y:125.);
      let path = hit ~x:20. ~y:145. in
      Alcotest.(check (list int))
        "popup blank area excludes the covered button" [ 4; 1 ] path;
      Alcotest.(check bool)
        "popup blank area never activates the covered button" false
        (Lui_query.press_target store path = Some 6))

let test_hit_path_allocation () =
  let depth = 128 in
  let ops = ref [CreateNode (1,Root)] in
  let rects = Lui_query.Rects.create () in
  Hashtbl.add rects 1 (rect 0. 0. 200. 200.);
  for id = 2 to depth do
    ops := InsertChild (id-1,id,0) :: CreateNode (id,Column) :: !ops;
    Hashtbl.add rects id (rect 0. 0. 200. 200.)
  done;
  let store = store_of (List.rev !ops) in
  let hit () = Lui_query.hit_path store rects ~x:100. ~y:100. in
  ignore (hit ());
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  for _ = 1 to 1000 do ignore (Sys.opaque_identity (hit ())) done;
  let allocated = (Gc.allocated_bytes () -. before) /. 1000. in
  Printf.printf "Nested pointer hit allocation: %.0f bytes/hit\n%!" allocated;
  if allocated > 56_000. then
    Alcotest.failf "Pointer state propagation allocates %.0f bytes per hit" allocated

let wide_sync_store () =
  let ops = ref [CreateNode (1, Root)] in
  for id = 2 to 6001 do
    ops := InsertChild (1, id, id - 2) :: CreateNode (id, Column) :: !ops
  done;
  store_of (List.rev !ops)

let test_sync_scan_allocation scan () =
  let store = wide_sync_store () in
  scan store;
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10 do scan store done;
  let per_scan = (Gc.allocated_bytes () -. before) /. 10. in
  Printf.printf "Interaction scan allocation: %.0f bytes\n%!" per_scan;
  if per_scan > 16_384. then
    Alcotest.failf "Scanning unchanged controls allocates %.0f bytes" per_scan

let scan_focus store =
  ignore (Lui_focus.scan_autofocus store Lui_focus.initial ~scope:0)

let scan_appear store =
  ignore (Lui_focus.scan_appear store Lui_focus.initial)

let scan_overlay store = ignore (Lui_overlay.top_scan store ~open_menu:0)

let scan_scroll store =
  let env = Lui_scroll.{content_rect=(fun _ -> Lui_scene.rect 0. 0. 0. 0.);
    rects_epoch=0; vlist=None} in
  ignore (Lui_scroll.sync env store Lui_scroll.initial)

let test_native_event_admission () =
  let events = [Appear 1; Press 1; Change 1; ToggleChanged (1,true);
    PointerEnter 1; PointerLeave 1; Dismiss 1; Load 1] in
  let gates = [AppearEnabled; PressEnabled; PointerEnabled; ChangeEnabled; ToggleEnabled] in
  List.iter (fun kind ->
    for mask = 0 to 31 do
      List.iter (fun role ->
        let props = List.mapi (fun bit property ->
          property, BoolValue (mask land (1 lsl bit) <> 0)) gates in
        let props = (RoleValue, StringValue role) :: props in
        let store = store_of (CreateNode (1,kind) :: List.map (fun (p,v) -> SetProp (1,p,v)) props) in
        let map = List.fold_left (fun acc (p,v) -> Property_map.add p v acc) Property_map.empty props in
        List.iter (fun event ->
          if event_supported_for_properties kind map event
             <> Lui_query.event_supported store 1 event then
            Alcotest.failf "Native admission diverged: kind=%s role=%s mask=%d"
              (Lui_wire_schema.node_kind_name kind) role mask) events)
        ["";"treeitem"]
    done) Lui_wire_schema.all_node_kinds;
  let store = store_of [CreateExtension (1,"test","");
    SetExtensionProp (1,"appear-enabled",BoolValue true)] in
  Alcotest.(check bool) "unknown extension cannot admit a standard event" false
    (Lui_query.event_supported store 1 (Appear 1))

let test_dense_lifecycle_allocation () =
  let store = wide_sync_store () in
  for id = 2 to 6001 do
    Lui_store.apply_op store (SetProp (id, AppearEnabled, BoolValue true))
  done;
  let state, actions = Lui_focus.scan_appear store Lui_focus.initial in
  Alcotest.(check int) "every eligible node appears" 6000 (List.length actions);
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  let _, actions = Lui_focus.scan_appear store state in
  let allocated = Gc.allocated_bytes () -. before in
  Alcotest.(check int) "existing nodes do not reappear" 0 (List.length actions);
  Printf.printf "Dense appearance scan allocation: %.0f bytes\n%!" allocated;
  if allocated > 1_000_000. then
    Alcotest.failf "A dense appearance scan allocates %.0f bytes" allocated

let test_sync_scan_order () =
  let store = store_of [
    CreateNode (1, Root); CreateNode (2, Column);
    CreateNode (30, TextField); CreateNode (20, TextField);
    CreateNode (10, TextField); CreateNode (9, TextField);
    CreateNode (50, Dialog); CreateNode (6, TextField);
    InsertChild (1, 2, 0); InsertChild (2, 30, 0);
    InsertChild (2, 20, 1); InsertChild (2, 10, 2);
    InsertChild (2, 9, 3); InsertChild (1, 50, 1);
    InsertChild (50, 6, 0);
    SetProp (30, Autofocus, BoolValue true);
    SetProp (30, Enabled, BoolValue false);
    SetProp (20, Autofocus, BoolValue true);
    SetProp (20, Visible, BoolValue false);
    SetProp (10, Autofocus, BoolValue true);
    SetProp (9, Autofocus, BoolValue true);
    SetProp (6, Autofocus, BoolValue true);
    SetProp (10, AppearEnabled, BoolValue true);
    SetProp (9, AppearEnabled, BoolValue true);
    SetProp (6, AppearEnabled, BoolValue true)] in
  let state, candidate = Lui_focus.scan_autofocus store Lui_focus.initial ~scope:0 in
  Alcotest.(check (option int)) "first eligible control in tree order" (Some 10) candidate;
  let _, candidate = Lui_focus.scan_autofocus store state ~scope:0 in
  Alcotest.(check (option int)) "seen controls do not autofocus again" None candidate;
  let _, candidate = Lui_focus.scan_autofocus store Lui_focus.initial ~scope:50 in
  Alcotest.(check (option int)) "autofocus remains in the overlay scope" (Some 6) candidate;
  let state, actions = Lui_focus.scan_appear store Lui_focus.initial in
  let appeared actions = List.map (function `Dispatch (Appear id) -> id
    | _ -> Alcotest.fail "unexpected appearance intent") actions in
  Alcotest.(check (list int)) "appearance follows tree order" [10;9;6] (appeared actions);
  let _, actions = Lui_focus.scan_appear store state in
  Alcotest.(check int) "appearance is emitted once per mount" 0 (List.length actions);
  Lui_store.apply_batch store {generation=2; ops=[RemoveProp (9, AppearEnabled)]};
  let state, _ = Lui_focus.scan_appear store state in
  Lui_store.apply_batch store {generation=3; ops=[SetProp (9, AppearEnabled, BoolValue true)]};
  let _, actions = Lui_focus.scan_appear store state in
  Alcotest.(check (list int)) "remounted appearance is emitted again" [9] (appeared actions);
  let before, _ = Lui_focus.scan_appear store Lui_focus.initial in
  Lui_store.apply_batch store {generation=4; ops=[
    RemoveProp (9, AppearEnabled); CreateNode (7, Column);
    InsertChild (2, 7, 4); SetProp (7, AppearEnabled, BoolValue true)]};
  let after, actions = Lui_focus.scan_appear store before in
  Alcotest.(check (list int)) "equal-size membership replacement appears" [7] (appeared actions);
  let _, actions = Lui_focus.scan_appear store after in
  Alcotest.(check int) "replacement is remembered" 0 (List.length actions);
  Lui_store.apply_batch store {generation=5; ops=[
    CreateNode (40, Dialog); InsertChild (1, 40, 2);
    CreateNode (60, ListContainer); CreateNode (55, ListContainer);
    InsertChild (2, 60, 4); InsertChild (2, 55, 5);
    SetProp (60, TrackVisibleRange, BoolValue true);
    SetProp (55, TrackVisibleRange, BoolValue true)]};
  Alcotest.(check (option (triple int bool bool))) "last overlay in paint order wins"
    (Some (40,true,true)) (Lui_overlay.top_scan store ~open_menu:0);
  let env = Lui_scroll.{content_rect=(fun _ -> Lui_scene.rect 0. 0. 0. 0.);
    rects_epoch=0; vlist=None} in
  let state, _ = Lui_scroll.sync env store Lui_scroll.initial in
  Alcotest.(check (list int)) "tracked lists keep tree order" [60;55] state.Lui_scroll.lists

let () =
  Alcotest.run "lui_input"
    [ ( "store sync",
        [ Alcotest.test_case "autofocus allocation" `Quick (test_sync_scan_allocation scan_focus);
          Alcotest.test_case "appearance allocation" `Quick (test_sync_scan_allocation scan_appear);
          Alcotest.test_case "overlay allocation" `Quick (test_sync_scan_allocation scan_overlay);
          Alcotest.test_case "scroll allocation" `Quick (test_sync_scan_allocation scan_scroll);
          Alcotest.test_case "native event admission" `Quick test_native_event_admission;
          Alcotest.test_case "dense lifecycle allocation" `Quick test_dense_lifecycle_allocation;
          Alcotest.test_case "tree order and lifecycle" `Quick test_sync_scan_order ] );
      ( "focus",
        [ Alcotest.test_case "inert subtree" `Quick test_inert_subtree;
          Alcotest.test_case "step" `Quick test_focus_step;
          Alcotest.test_case "dead" `Quick test_focus_dead ] );
      ( "overlay",
        [ Alcotest.test_case "inert owner" `Quick test_inert_overlay;
          Alcotest.test_case "modal focus scope" `Quick
            test_modal_clears_background_focus;
          Alcotest.test_case "press gate" `Quick
            test_modal_press_swallow_and_dismiss;
          Alcotest.test_case "escape" `Quick test_escape_peels ] );
      ( "gesture",
        [ Alcotest.test_case "list nav" `Quick test_list_nav;
          Alcotest.test_case "modal scope" `Quick
            test_list_modal_scope ] );
      ( "text input",
        [ Alcotest.test_case "navigation" `Quick test_text_navigation;
          Alcotest.test_case "splice" `Quick test_text_session;
          Alcotest.test_case "undo" `Quick test_text_undo;
          Alcotest.test_case "caret ops" `Quick test_text_caret_ops;
          Alcotest.test_case "padding hit" `Quick test_text_padding_hit;
          Alcotest.test_case "ime commit" `Quick test_text_ime_commit;
          Alcotest.test_case "rapid typing" `Quick
            test_revision_rapid_typing;
          Alcotest.test_case "stale model" `Quick
            test_revision_stale_model_ignored;
          Alcotest.test_case "correction" `Quick
            test_revision_correction;
          Alcotest.test_case "reset" `Quick test_revision_reset;
          Alcotest.test_case "model vs composition" `Quick
            test_revision_cancels_composition;
          Alcotest.test_case "session ids" `Quick test_session_ids ] );
      ( "selection",
        [ Alcotest.test_case "static" `Quick test_static_selection ] );
      ( "scroll",
        [ Alcotest.test_case "anchor alignment" `Quick test_scroll_anchor_alignment;
          Alcotest.test_case "offsets" `Quick test_scroll_offsets;
          Alcotest.test_case "wheel" `Quick test_wheel;
          Alcotest.test_case "boundary chaining" `Quick test_wheel_boundary_chaining ] );
      ( "drag",
        [ Alcotest.test_case "flow" `Quick test_drag_flow ] );
      ( "pointer",
        [ Alcotest.test_case "frontmost ancestry" `Quick test_frontmost_hit_ancestry;
          Alcotest.test_case "allocation" `Quick test_hit_path_allocation;
          Alcotest.test_case "hover+press" `Quick
            test_pointer_hover_press ] );
      ( "spatial",
        [ Alcotest.test_case "hit equivalence" `Quick
            test_spatial_hit_equiv;
          Alcotest.test_case "popup escape" `Quick
            test_spatial_hit_popup_escape;
          Alcotest.test_case "wide list" `Quick
            test_spatial_hit_wide_list ] ) ]
