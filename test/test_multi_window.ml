(* Tests for Lui_multi_window: a shared-model application whose
   windows mount per-surface runtimes over independent backends.

   Each surface's backend here replays its patch batches into a
   Drive.Model queryable tree — the in-process equivalent of two OS
   windows. The suite pins the shared-model contract:

   - two windows mount the same page from one model
   - an edit dispatched in one window re-renders every window
   - per-window UI scope/state stays independent
   - the shared payload (resource cache / DB handle) is not duplicated
   - a window opened late sees the current model; a closed window
     stops receiving work without affecting the others *)

module Mw = Lui_multi_window
module Dm = Drive.Model

(* ---------- fixtures ---------- *)

(* One backend per window: batches replay into a private Model tree. *)
let model_backend () =
  let tree = Dm.create () in
  let backend =
    {
      Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
      apply_batch = (fun b -> Dm.apply_batch tree b; true);
    }
  in
  (backend, tree)

type doc = {
  title : string;
  count : int;
}

type doc_action =
  | Set_title of string
  | Bump

let doc_reducer model = function
  | Set_title title -> { model with title }
  | Bump -> { model with count = model.count + 1 }

(* A document editor view: a title field fed by the model, an edit
   count, and a bump button — enough to exercise text events, button
   presses and signal-driven re-render. *)
let doc_view _surface _context model_source send =
  Lui_elements.column
    [
      Lui_elements.dyn
        ~equal:(fun (a : doc) b -> a.title = b.title)
        (fun d ->
           Lui_elements.text_field ~text:d.title
             ~on_input:
               (Lui_elements.on_input send (fun s -> Set_title s))
             [])
        model_source;
      Lui_elements.dyn
        ~equal:(fun (a : doc) b -> a.count = b.count)
        (fun d ->
           Lui_elements.text ~value:("edits=" ^ string_of_int d.count)
             [])
        model_source;
      Lui_elements.button ~text:"Bump"
        ~on_press:(Lui_elements.press send Bump) [];
    ]

let doc_app () =
  Mw.create ~shared:() { title = "doc"; count = 0 } doc_reducer doc_view

let first_node tree sel =
  match Dm.first tree sel with
  | Some node -> node
  | None -> Alcotest.failf "no node matching selector in tree"

let field_id tree = (first_node tree (Dm.Kind "text-field")).Dm.id
let button_id tree = (first_node tree (Dm.Kind "button")).Dm.id

(* ---------- same model, two windows ---------- *)

let test_two_windows_same_page () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let _s1 = Mw.open_window app b1 and _s2 = Mw.open_window app b2 in
  Alcotest.(check int) "two surfaces" 2 (Mw.surface_count app);
  Alcotest.(check (list int)) "open order" [ 0; 1 ]
    (List.map Mw.surface_id (Mw.surfaces app));
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 shows title" true
    (Dm.exists t1 (Dm.Text "doc"));
  Alcotest.(check bool) "w2 shows title" true
    (Dm.exists t2 (Dm.Text "doc"));
  Alcotest.(check bool) "w1 shows counter" true
    (Dm.exists t1 (Dm.Text "edits=0"));
  Alcotest.(check bool) "w2 shows counter" true
    (Dm.exists t2 (Dm.Text "edits=0"));
  (* same logical tree, mounted twice: equal node counts, independent
     id spaces (each runtime numbers from 1) *)
  Alcotest.(check int) "same size"
    (List.length (Dm.all_nodes t1))
    (List.length (Dm.all_nodes t2));
  ignore (Mw.dispose app)

(* An edit made through one window's runtime reduces into the shared
   model and re-renders every window on the next flush. *)
let test_edit_propagates_between_windows () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  (* type in window 1's title field *)
  let field = field_id t1 in
  Alcotest.(check bool) "dispatch w1" true
    (Mw.dispatch s1 (Lui_protocol.TextChanged (field, "draft")));
  ignore (Mw.flush app);
  Alcotest.(check string) "model" "draft" (Mw.model app).title;
  Alcotest.(check bool) "w1 updated" true
    (Dm.exists t1 (Dm.Text "draft"));
  Alcotest.(check bool) "w2 updated" true
    (Dm.exists t2 (Dm.Text "draft"));
  Alcotest.(check bool) "w1 old gone" false
    (Dm.exists t1
       (Dm.Prop ("text", Lui_protocol.StringValue "doc")));
  Alcotest.(check bool) "w2 old gone" false
    (Dm.exists t2
       (Dm.Prop ("text", Lui_protocol.StringValue "doc")));
  (* press the button in window 2 — same shared model *)
  let button = button_id t2 in
  Alcotest.(check bool) "dispatch w2" true
    (Mw.dispatch s2 (Lui_protocol.Press button));
  ignore (Mw.flush app);
  Alcotest.(check int) "count" 1 (Mw.model app).count;
  Alcotest.(check bool) "w1 counter" true
    (Dm.exists t1 (Dm.Text "edits=1"));
  Alcotest.(check bool) "w2 counter" true
    (Dm.exists t2 (Dm.Text "edits=1"));
  ignore (Mw.dispose app)

(* Node ids are per-surface namespaces: dispatch resolves against the
   surface's own runtime, so an event only ever reaches its own
   window's nodes. *)
let test_dispatch_is_per_surface () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  (* both windows mount the same tree, so the title field carries the
     same id in each — the runtime it dispatches into decides which
     control receives it. *)
  Alcotest.(check int) "parallel ids" (field_id t1) (field_id t2);
  (* unsupported event on a live node is rejected the same way a
     single-window app rejects it *)
  Alcotest.check_raises "unsupported event rejected"
    (Invalid_argument "event is unsupported by node kind") (fun () ->
       ignore
         (Mw.dispatch s1
            (Lui_protocol.Submit (button_id t1))));
  (* an id mounted in no window's runtime is a no-op *)
  Alcotest.(check bool) "unmounted id" false
    (Mw.dispatch s1 (Lui_protocol.TextChanged (999, "x")));
  ignore (Mw.dispose app);
  (* on a disposed application dispatch stops working *)
  Alcotest.(check bool) "dispatch after dispose" false
    (Mw.dispatch s2 (Lui_protocol.Press 1))

(* ---------- per-window UI scope ---------- *)

(* State created inside the view function is per surface: each window
   mounts its own copy under its own scope, so window-local UI state
   (the analog of focus/selection/scroll on real backends) never
   crosses windows. *)
let test_independent_surface_state () =
  let view surface context _model_source _send =
    let local = Signal.state context.Lui_ui.ui_scheduler "unset" in
    (* states are scheduler-owned, not scope-owned: drop it with the
       surface's scope so a closed window frees its UI state. *)
    Signal.on_dispose context.Lui_ui.ui_scope (fun () ->
        Signal.dispose_signal (Signal.value local));
    Lui_elements.column
      [
        Lui_elements.dyn ~equal:( = )
          (fun v -> Lui_elements.text ~value:("local=" ^ v) [])
          (Signal.value local);
        Lui_elements.button ~text:"Mark"
          ~on_press:(fun _event ->
             Signal.set local
               ("win" ^ string_of_int (Mw.surface_id surface)))
          [];
      ]
  in
  let app = Mw.create ~shared:() () (fun m _a -> m) view in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 unset" true
    (Dm.exists t1 (Dm.Text "local=unset"));
  Alcotest.(check bool) "w2 unset" true
    (Dm.exists t2 (Dm.Text "local=unset"));
  ignore (Mw.dispatch s1 (Lui_protocol.Press (button_id t1)));
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 marked" true
    (Dm.exists t1 (Dm.Text "local=win0"));
  Alcotest.(check bool) "w2 still unset" true
    (Dm.exists t2 (Dm.Text "local=unset"));
  ignore (Mw.dispatch s2 (Lui_protocol.Press (button_id t2)));
  ignore (Mw.flush app);
  Alcotest.(check bool) "w2 marked" true
    (Dm.exists t2 (Dm.Text "local=win1"));
  Alcotest.(check bool) "w1 kept its mark" true
    (Dm.exists t1 (Dm.Text "local=win0"));
  ignore (Mw.dispose app)

(* ---------- shared resources ---------- *)

(* The ['shared] payload lives once on the application: a resource
   cache reachable from every surface's view (and from drivers via
   [surface_application]) is never duplicated per window. *)
let test_shared_resource_cache () =
  let loads = ref 0 in
  let cache : (string, string) Hashtbl.t = Hashtbl.create 8 in
  let view surface _context _model_source _send =
    let shared = Mw.shared (Mw.surface_application surface) in
    let value =
      match Hashtbl.find_opt shared "doc:1" with
      | Some cached -> cached
      | None ->
        incr loads;
        let loaded = "shared-body" in
        Hashtbl.replace shared "doc:1" loaded;
        loaded
    in
    Lui_elements.text ~value []
  in
  let app = Mw.create ~shared:cache () (fun m _a -> m) view in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let _s1 = Mw.open_window app b1 and _s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  Alcotest.(check int) "loaded once for two windows" 1 !loads;
  Alcotest.(check bool) "w1 reads cache" true
    (Dm.exists t1 (Dm.Text "shared-body"));
  Alcotest.(check bool) "w2 reads cache" true
    (Dm.exists t2 (Dm.Text "shared-body"));
  ignore (Mw.dispose app)

(* ---------- window lifecycle ---------- *)

(* A window opened after edits sees the current model, not the
   initial one. *)
let test_late_window_sees_current_model () =
  let app = doc_app () in
  let b1, _t1 = model_backend () in
  let _s1 = Mw.open_window app b1 in
  ignore (Mw.flush app);
  ignore (Mw.send app (Set_title "v2"));
  ignore (Mw.send app Bump);
  ignore (Mw.flush app);
  let b2, t2 = model_backend () in
  let _s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  Alcotest.(check bool) "late window current title" true
    (Dm.exists t2 (Dm.Text "v2"));
  Alcotest.(check bool) "late window current count" true
    (Dm.exists t2 (Dm.Text "edits=1"));
  ignore (Mw.dispose app)

(* Closing a window unmounts its surface: its backend gets the drop
   ops, dispatch into it stops, and the remaining windows keep
   receiving model updates. *)
let test_close_window_keeps_others () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  Alcotest.(check bool) "close" true (Mw.close_window s1);
  Alcotest.(check bool) "closed" true (Mw.surface_closed s1);
  Alcotest.(check int) "one left" 1 (Mw.surface_count app);
  Alcotest.(check int) "w1 tree dropped" 0
    (List.length (Dm.all_nodes t1));
  Alcotest.(check bool) "close again is no-op" false
    (Mw.close_window s1);
  Alcotest.(check bool) "dispatch on closed" false
    (Mw.dispatch s1 (Lui_protocol.Press 1));
  (* the surviving window keeps dispatching into the shared model *)
  Alcotest.(check bool) "w2 dispatch still live" true
    (Mw.dispatch s2 (Lui_protocol.Press (button_id t2)));
  ignore (Mw.send app (Set_title "after-close"));
  ignore (Mw.flush app);
  Alcotest.(check bool) "w2 still live" true
    (Dm.exists t2 (Dm.Text "after-close"));
  Alcotest.(check int) "w1 stays empty" 0
    (List.length (Dm.all_nodes t1));
  ignore (Mw.dispose app)

(* A surface can mount a different view of the same model — e.g. an
   outline window next to the page window. *)
let test_per_window_view_override () =
  let app = doc_app () in
  let outline_view _surface _context model_source _send =
    Lui_elements.dyn
      ~equal:(fun (a : doc) b -> a.count = b.count)
      (fun d ->
         Lui_elements.text
           ~value:("outline edits=" ^ string_of_int d.count)
           [])
      model_source
  in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let _s1 = Mw.open_window app b1 in
  let _s2 = Mw.open_window app ~view:outline_view b2 in
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 page view" true
    (Dm.exists t1 (Dm.Kind "text-field"));
  Alcotest.(check bool) "w2 outline view" false
    (Dm.exists t2 (Dm.Kind "text-field"));
  ignore (Mw.send app Bump);
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 edit" true (Dm.exists t1 (Dm.Text "edits=1"));
  Alcotest.(check bool) "w2 edit" true
    (Dm.exists t2 (Dm.Text "outline edits=1"));
  ignore (Mw.dispose app)

(* [flush_surface] drives one window's frame: stabilization is shared,
   but each surface emits its own batch — a driver ticking windows
   independently sees per-window updates. *)
let test_per_surface_flush () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  ignore (Mw.send app Bump);
  (* flushing only window 2 publishes its batch; window 1's queued
     ops wait for its own flush — frame scheduling stays per window *)
  ignore (Mw.flush_surface s2);
  Alcotest.(check bool) "w2 updated first" true
    (Dm.exists t2 (Dm.Text "edits=1"));
  Alcotest.(check bool) "w1 behind" true
    (Dm.exists t1 (Dm.Text "edits=0"));
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 caught up" true
    (Dm.exists t1 (Dm.Text "edits=1"));
  ignore s1;
  ignore (Mw.dispose app)

(* Theme props fan out to every surface's root node. *)
let test_theme_fans_out () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let _s1 = Mw.open_window app b1 and _s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  Mw.set_theme_mode app `dark;
  ignore (Mw.flush app);
  Alcotest.(check bool) "w1 dark" true
    (Dm.prop t1 1 "theme-mode" = Some (Lui_protocol.StringValue "dark"));
  Alcotest.(check bool) "w2 dark" true
    (Dm.prop t2 1 "theme-mode" = Some (Lui_protocol.StringValue "dark"));
  ignore (Mw.dispose app)

(* ---------- application lifecycle ---------- *)

let test_dispose_closes_everything () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  Alcotest.(check bool) "dispose" true (Mw.dispose app);
  Alcotest.(check bool) "disposed" true (Mw.disposed app);
  Alcotest.(check bool) "w1 closed" true (Mw.surface_closed s1);
  Alcotest.(check bool) "w2 closed" true (Mw.surface_closed s2);
  Alcotest.(check int) "w1 dropped" 0 (List.length (Dm.all_nodes t1));
  Alcotest.(check int) "w2 dropped" 0 (List.length (Dm.all_nodes t2));
  Alcotest.(check bool) "send after dispose" false (Mw.send app Bump);
  Alcotest.check_raises "open after dispose"
    (Invalid_argument "application is not running") (fun () ->
       ignore (Mw.open_window app (fst (model_backend ()))));
  Alcotest.(check bool) "dispose idempotent" true (Mw.dispose app)

(* The model signal every surface observes is one instance: actions
   sent through the application (not through a window) update all
   windows, and an outside subscriber sees the same publishes. *)
let test_model_signal_is_shared () =
  let app = doc_app () in
  let b1, t1 = model_backend () and b2, t2 = model_backend () in
  let s1 = Mw.open_window app b1 and _s2 = Mw.open_window app b2 in
  ignore (Mw.flush app);
  let seen = ref [] in
  let sub =
    Signal.subscribe (Mw.model_signal app) (fun (d : doc) ->
        seen := d.title :: !seen)
  in
  ignore (Mw.dispatch s1 (Lui_protocol.TextChanged (field_id t1, "x")));
  ignore (Mw.flush app);
  Alcotest.(check (list string)) "observer saw publish"
    [ "x"; "doc" ] !seen;
  Alcotest.(check bool) "w2 saw the same publish" true
    (Dm.exists t2 (Dm.Text "x"));
  Signal.dispose_subscription sub;
  ignore (Mw.dispose app)

let tests =
  [
    Alcotest.test_case "two windows same page" `Quick
      test_two_windows_same_page;
    Alcotest.test_case "edit propagates between windows" `Quick
      test_edit_propagates_between_windows;
    Alcotest.test_case "dispatch is per-surface" `Quick
      test_dispatch_is_per_surface;
    Alcotest.test_case "independent surface state" `Quick
      test_independent_surface_state;
    Alcotest.test_case "shared resource cache" `Quick
      test_shared_resource_cache;
    Alcotest.test_case "late window sees current model" `Quick
      test_late_window_sees_current_model;
    Alcotest.test_case "close window keeps others" `Quick
      test_close_window_keeps_others;
    Alcotest.test_case "per-window view override" `Quick
      test_per_window_view_override;
    Alcotest.test_case "per-surface flush" `Quick
      test_per_surface_flush;
    Alcotest.test_case "theme fans out" `Quick test_theme_fans_out;
    Alcotest.test_case "dispose closes everything" `Quick
      test_dispose_closes_everything;
    Alcotest.test_case "model signal is shared" `Quick
      test_model_signal_is_shared;
  ]
