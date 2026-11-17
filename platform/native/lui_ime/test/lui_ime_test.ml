(* Unit tests for the IME composition state machine. Everything here
   is pure OCaml — no SDL, no window — so the suite runs headless on
   every platform. SDL-side wiring (TEXTEDITING delivery, candidate
   rect) is exercised separately by the window driver; the dummy video
   driver emits no IME events, so a live-IME check is interactive
   only and stays manual. *)

open Lui_ime

let r x y w h : Lui_scene.rect = Lui_scene.rect x y w h

let strings_of acts = List.map string_of_action acts

(* Feed a sequence, collecting every action list. *)
let run evs =
  let st, out =
    List.fold_left
      (fun (st, acc) ev ->
        let st, acts = feed_event st ev in
        (st, acc @ strings_of acts))
      (initial, []) evs
  in
  (st, out)

let check_actions tag expected acts =
  Alcotest.(check (list string)) tag expected (strings_of acts)

(* ---------- lifecycle ---------- *)

let test_begin_edit_commit () =
  (* begin → extend → commit "你好" *)
  let st, acts = feed_event initial (`Editing ("n", 1, 0)) in
  check_actions "begin" [ "begin"; "update(\"n\",1)" ] acts;
  Alcotest.(check bool) "active" true st.active;
  Alcotest.(check bool) "composing" true (composing st);
  let st, acts = feed_event st (`Editing ("ni", 2, 0)) in
  check_actions "extend" [ "update(\"ni\",2)" ] acts;
  let st, acts = feed_event st (`Editing ("nih", 3, 0)) in
  check_actions "extend2" [ "update(\"nih\",3)" ] acts;
  let cjk = "\228\189\160\229\165\189" in
  let st, acts = feed_event st (`Commit cjk) in
  check_actions "commit" [ Printf.sprintf "commit(%S)" cjk ] acts;
  Alcotest.(check bool) "closed" false st.active;
  Alcotest.(check string) "marked cleared" "" st.marked_text;
  Alcotest.(check bool) "not composing" false (composing st)

let test_commit_without_composition () =
  (* Plain input arrives as bare text_input with no preceding
     editing: it must pass straight through. *)
  let st, acts = feed_event initial (`Commit "a") in
  check_actions "passthrough" [ "commit(\"a\")" ] acts;
  Alcotest.(check bool) "still idle" false st.active

let test_dedup_churn () =
  (* IMEs re-report identical preedit on cursor blinks: dedup it. *)
  let st, _ = feed_event initial (`Editing ("ka", 2, 0)) in
  let st', acts = feed_event st (`Editing ("ka", 2, 0)) in
  check_actions "dup suppressed" [] acts;
  Alcotest.(check bool) "state kept" true (st == st');
  (* A cursor-only change IS a real update. *)
  let _, acts = feed_event st (`Editing ("ka", 0, 0)) in
  check_actions "cursor moved" [ "update(\"ka\",0)" ] acts

let test_rapid_edits () =
  let st, out =
    run
      [ `Editing ("n", 1, 0); `Editing ("ni", 2, 0);
        `Editing ("nih", 3, 0); `Editing ("niha", 4, 0);
        `Editing ("nihao", 5, 0); `Commit "nihao" ]
  in
  Alcotest.(check (list string)) "sequence"
    [ "begin"; "update(\"n\",1)"; "update(\"ni\",2)";
      "update(\"nih\",3)"; "update(\"niha\",4)";
      "update(\"nihao\",5)"; "commit(\"nihao\")" ]
    out;
  Alcotest.(check bool) "idle at end" false st.active

let test_empty_editing_clears_keeps_session () =
  (* Clearing the preedit does not end the IME session: resume must
     not emit a second Begin. *)
  let st, _ = feed_event initial (`Editing ("ni", 2, 0)) in
  let st, acts = feed_event st (`Editing ("", 0, 0)) in
  check_actions "cleared" [ "update(\"\",0)" ] acts;
  Alcotest.(check bool) "still active" true st.active;
  Alcotest.(check bool) "not composing" false (composing st);
  let st, acts = feed_event st (`Editing ("ha", 2, 0)) in
  check_actions "resume no begin" [ "update(\"ha\",2)" ] acts;
  Alcotest.(check bool) "composing again" true (composing st)

(* ---------- cancel paths ---------- *)

let test_focus_loss_cancels () =
  let st, _ = feed_event initial (`Editing ("ni", 2, 0)) in
  let st, acts = feed_event st (`Focus false) in
  check_actions "cancel" [ "cancel" ] acts;
  Alcotest.(check bool) "closed" false st.active;
  Alcotest.(check string) "marked dropped" "" st.marked_text;
  (* Refocus + fresh composition begins cleanly. *)
  let st, acts = feed_event st (`Focus true) in
  check_actions "refocus noop" [] acts;
  let _, acts = feed_event st (`Editing ("x", 1, 0)) in
  check_actions "new session" [ "begin"; "update(\"x\",1)" ] acts

let test_focus_loss_idle () =
  let st, acts = feed_event initial (`Focus false) in
  check_actions "idle blur noop" [] acts;
  Alcotest.(check bool) "state kept" true (st == st)

let test_empty_commit_cancels () =
  let st, _ = feed_event initial (`Editing ("ni", 2, 0)) in
  let st, acts = feed_event st (`Commit "") in
  check_actions "empty commit cancels" [ "cancel" ] acts;
  Alcotest.(check bool) "closed" false st.active;
  let _, acts = feed_event initial (`Commit "") in
  check_actions "empty commit idle" [] acts

(* ---------- utf8 passthrough ---------- *)

let test_utf8_passthrough () =
  (* CJK + emoji + a combining sequence arrive and leave byte-exact. *)
  let cjk = "\228\189\160\229\165\189" in
  let emoji = "\240\159\153\130" in
  let combined = cjk ^ emoji in
  let st, acts = feed_event initial (`Editing (combined, 0, 0)) in
  Alcotest.(check string) "marked verbatim" combined st.marked_text;
  ignore acts;
  let _, acts = feed_event st (`Commit combined) in
  check_actions "commit verbatim"
    [ Printf.sprintf "commit(%S)" combined ] acts

let test_selection_clamps () =
  (* Out-of-range sel reports clamp into the text's byte length. *)
  let st, _ = feed_event initial (`Editing ("ab", 99, 99)) in
  Alcotest.(check int) "cursor clamped" 2 st.cursor;
  Alcotest.(check int) "len clamped" 0 st.sel_len;
  let _, acts = feed_event initial (`Editing ("ab", -3, -1)) in
  check_actions "negative clamps" [ "begin"; "update(\"ab\",0)" ] acts

(* ---------- candidate rect ---------- *)

let test_candidate_gating () =
  let r1 = r 10. 20. 2. 20. and r2 = r 18. 20. 2. 20. in
  (* Caret moves while idle: recorded silently, never emitted. *)
  let st, acts = feed_event initial (`Caret r1) in
  check_actions "idle move silent" [] acts;
  (* The remembered rect positions the window at composition start. *)
  let st, acts = feed_event st (`Editing ("n", 1, 0)) in
  check_actions "begin positions window"
    [ "begin"; "move(10,20,2,20)"; "update(\"n\",1)" ] acts;
  (* Composing caret moves emit; identical repeats do not. *)
  let st, acts = feed_event st (`Caret r2) in
  check_actions "composing move" [ "move(18,20,2,20)" ] acts;
  let st, acts = feed_event st (`Caret r2) in
  check_actions "same rect dedup" [] acts;
  (* After commit, further caret moves go quiet again. *)
  let st, acts = feed_event st (`Commit "x") in
  check_actions "commit" [ "commit(\"x\")" ] acts;
  let _, acts = feed_event st (`Caret r1) in
  check_actions "post-commit silent" [] acts

let test_cancel_drops_composition_but_keeps_caret () =
  let rc = r 5. 5. 2. 18. in
  let st, _ = feed_event initial (`Caret rc) in
  let st, _ = feed_event st (`Editing ("n", 1, 0)) in
  let st, _ = feed_event st (`Focus false) in
  (* A later composition re-emits the still-current caret rect. *)
  let _, acts = feed_event st (`Editing ("x", 1, 0)) in
  check_actions "rebegin positions"
    [ "begin"; "move(5,5,2,18)"; "update(\"x\",1)" ] acts

let () =
  Alcotest.run "lui_ime"
    [ ( "lifecycle",
        [ Alcotest.test_case "begin/edit/commit" `Quick
            test_begin_edit_commit;
          Alcotest.test_case "bare commit" `Quick
            test_commit_without_composition;
          Alcotest.test_case "dedup" `Quick test_dedup_churn;
          Alcotest.test_case "rapid edits" `Quick test_rapid_edits;
          Alcotest.test_case "empty edit" `Quick
            test_empty_editing_clears_keeps_session ] );
      ( "cancel",
        [ Alcotest.test_case "focus loss" `Quick test_focus_loss_cancels;
          Alcotest.test_case "idle blur" `Quick test_focus_loss_idle;
          Alcotest.test_case "empty commit" `Quick
            test_empty_commit_cancels ] );
      ( "utf8",
        [ Alcotest.test_case "passthrough" `Quick test_utf8_passthrough;
          Alcotest.test_case "sel clamp" `Quick test_selection_clamps ] );
      ( "candidate",
        [ Alcotest.test_case "gating" `Quick test_candidate_gating;
          Alcotest.test_case "cancel keeps rect" `Quick
            test_cancel_drops_composition_but_keeps_caret ] ) ]
