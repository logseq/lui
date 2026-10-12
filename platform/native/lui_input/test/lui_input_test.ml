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
    rects_epoch = 1 }

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

let () =
  Alcotest.run "lui_input"
    [ ( "focus",
        [ Alcotest.test_case "step" `Quick test_focus_step;
          Alcotest.test_case "dead" `Quick test_focus_dead ] );
      ( "overlay",
        [ Alcotest.test_case "modal focus scope" `Quick
            test_modal_clears_background_focus;
          Alcotest.test_case "press gate" `Quick
            test_modal_press_swallow_and_dismiss;
          Alcotest.test_case "escape" `Quick test_escape_peels ] );
      ( "gesture",
        [ Alcotest.test_case "list nav" `Quick test_list_nav;
          Alcotest.test_case "modal scope" `Quick
            test_list_modal_scope ] );
      ( "text input",
        [ Alcotest.test_case "splice" `Quick test_text_session;
          Alcotest.test_case "undo" `Quick test_text_undo;
          Alcotest.test_case "caret ops" `Quick test_text_caret_ops;
          Alcotest.test_case "ime commit" `Quick test_text_ime_commit ] );
      ( "selection",
        [ Alcotest.test_case "static" `Quick test_static_selection ] );
      ( "scroll",
        [ Alcotest.test_case "offsets" `Quick test_scroll_offsets;
          Alcotest.test_case "wheel" `Quick test_wheel ] );
      ( "drag",
        [ Alcotest.test_case "flow" `Quick test_drag_flow ] );
      ( "pointer",
        [ Alcotest.test_case "hover+press" `Quick
            test_pointer_hover_press ] );
      ( "spatial",
        [ Alcotest.test_case "hit equivalence" `Quick
            test_spatial_hit_equiv;
          Alcotest.test_case "popup escape" `Quick
            test_spatial_hit_popup_escape;
          Alcotest.test_case "wide list" `Quick
            test_spatial_hit_wide_list ] ) ]
