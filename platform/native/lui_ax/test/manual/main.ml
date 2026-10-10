(* Manual probe for the macOS accessibility bridge.

   Creates an offscreen NSWindow + host view, attaches a small Lui_a11y
   tree through Lui_ax, then dumps the AX attributes each element
   reports — the same answers VoiceOver would read. Run:

     OPAMSWITCH=5.5.0 opam exec -- dune exec \
       platform/native/lui_ax/test/manual/main.exe

   Introspecting your own process needs no AXIsProcessTrusted grant. *)

open Lui_protocol

external manual_window : unit -> nativeint = "lui_manual_window"
external manual_dump : nativeint -> unit = "lui_manual_dump"
external manual_perform : nativeint -> int -> string -> unit =
  "lui_manual_perform"

let apply t ops = Lui_store.apply_batch t { generation = 1; ops }

(* Fixed view-space rects (points); the manual view is 480x360 and not
   flipped, so layout rects (y-down) are flipped into it here — the
   same job a real host's frame_of does. *)
let frame_of =
  let open Lui_ax in
  let rect x y w h = Some (y_flip ~container_height:360. { x; y; w; h }) in
  function
  | 1 -> rect 0. 0. 480. 360.
  | 2 -> rect 16. 16. 448. 328.
  | 3 -> rect 24. 24. 300. 28.
  | 4 -> rect 24. 60. 400. 20.
  | 5 -> rect 24. 92. 120. 32.
  | 6 -> rect 24. 140. 200. 24.
  | 7 -> rect 24. 180. 160. 24.
  | 8 -> rect 24. 220. 220. 28.
  | 9 -> rect 24. 260. 300. 80.
  | 10 -> rect 24. 260. 300. 28.
  | 11 -> rect 24. 288. 300. 28.
  | _ -> None

let () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root);
      CreateNode (2, Column); InsertChild (1, 2, 0);
      CreateNode (3, Heading); InsertChild (2, 3, 0);
      SetProp (3, TextValue, StringValue "Settings");
      CreateNode (4, Text); InsertChild (2, 4, 1);
      SetProp (4, TextValue, StringValue "General preferences");
      CreateNode (5, Button); InsertChild (2, 5, 2);
      SetProp (5, TextValue, StringValue "Save");
      CreateNode (6, Slider); InsertChild (2, 6, 3);
      SetProp (6, AccessibilityLabel, StringValue "Volume");
      SetProp (6, MinValue, FloatValue 0.);
      SetProp (6, MaxValue, FloatValue 1.);
      SetProp (6, ProgressValue, FloatValue 0.4);
      CreateNode (7, Checkbox); InsertChild (2, 7, 4);
      SetProp (7, TextValue, StringValue "Enable iCloud sync");
      SetProp (7, Checked, BoolValue true);
      CreateNode (8, SearchField); InsertChild (2, 8, 5);
      SetProp (8, TextValue, StringValue "query");
      CreateNode (9, ListContainer); InsertChild (2, 9, 6);
      SetProp (9, AccessibilityLabel, StringValue "Sidebar");
      CreateNode (10, ListItem); InsertChild (9, 10, 0);
      SetProp (10, TextValue, StringValue "Inbox");
      CreateNode (11, ListItem); InsertChild (9, 11, 1);
      SetProp (11, TextValue, StringValue "Trash");
      SetProp (11, Selected, BoolValue true) ];
  let a11y = Lui_a11y.of_store store in
  Printf.fprintf stderr "== a11y model: %d nodes, roots %s ==\n"
    (Lui_a11y.node_count a11y)
    (String.concat "," (List.map string_of_int (Lui_a11y.root_ids a11y)));

  let view = manual_window () in
  let bridge = Lui_ax.attach ~frame_of a11y view in
  manual_dump view;

  (* move focus + a value change, then re-sync *)
  Printf.fprintf stderr "== after focus=5 and slider=0.9 ==\n";
  apply store [ SetProp (6, ProgressValue, FloatValue 0.9) ];
  Lui_ax.set_focused bridge 5;
  ignore (Lui_ax.sync bridge);
  manual_dump view;

  (* drive the elements the way VoiceOver would, then drain the queue *)
  manual_perform view 5 "AXPress";
  manual_perform view 6 "AXIncrement";
  let acts = Lui_ax.drain_actions bridge in
  Printf.fprintf stderr "== drained actions: %d ==\n" (List.length acts);
  List.iter
    (fun (id, a) ->
      Printf.fprintf stderr "  id=%d action=%s\n" id
        (match a with
         | Lui_ax.Press -> "press" | Lui_ax.Increment -> "increment"
         | Lui_ax.Decrement -> "decrement" | Lui_ax.Focus -> "focus"
         | Lui_ax.Set_value s -> "set-value:" ^ s
         | Lui_ax.Scroll_to_visible -> "scroll-to-visible"
         | Lui_ax.Expand -> "expand" | Lui_ax.Collapse -> "collapse"))
    acts;
  Lui_ax.detach bridge
