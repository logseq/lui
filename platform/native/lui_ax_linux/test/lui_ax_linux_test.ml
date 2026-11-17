(* Pure-OCaml tests for the AT-SPI bridge: role/state mapping,
   path/name wiring, diff -> event translation, and the incoming-call
   contract ([handle_call]).  Everything runs without a bus: the D-Bus
   transport is exercised only through the Offline state machine. *)

open Lui_protocol
open Alcotest

module Ax = Lui_ax_linux

let batch ops = { generation = 1; ops }
let apply t ops = Lui_store.apply_batch t (batch ops)

let find_exn a id =
  match Lui_a11y.find a id with
  | Some n -> n
  | None -> fail ("no a11y node " ^ string_of_int id)

(* ---------- role mapping ---------- *)

let all_roles : Lui_a11y.role list =
  [ Window; Group; Static_text; Heading; Text_field; Text_area;
    Search_field; Button; Toggle_button; Check_box; Radio_button;
    Radio_group; Switch; Slider; Spin_button; Progress_indicator; Link;
    Image; List; List_item; Outline; Outline_item; Tab_group; Tab; Menu;
    Menu_item; Combo_box; Dialog; Sheet; Tooltip; Table; Table_row;
    Table_cell; Separator; Toolbar; Status_bar; Navigation; Split_group;
    Extension ]

let test_role_map_complete () =
  let mapped = List.map (fun (r, _, _) -> r) Ax.role_map in
  check int "table size" 39 (List.length Ax.role_map);
  List.iter
    (fun r ->
      let n = List.length (List.filter (fun x -> x = r) mapped) in
      check int
        ("role " ^ Lui_a11y.role_name r ^ " mapped exactly once")
        1 n)
    all_roles;
  (* names are non-empty and numbers distinct enough to be sane *)
  List.iter
    (fun (r, n, name) ->
      check bool (Lui_a11y.role_name r ^ " has a name") true (name <> "");
      check bool (Lui_a11y.role_name r ^ " has a role number") true
        (n >= 0))
    Ax.role_map

let test_role_map_values () =
  let num r = Ax.atspi_role_of r in
  check int "window -> frame" 23 (num Lui_a11y.Window);
  check int "button" 43 (num Lui_a11y.Button);
  check int "check box" 7 (num Lui_a11y.Check_box);
  check int "switch" 130 (num Lui_a11y.Switch);
  check int "tree" 65 (num Lui_a11y.Outline);
  check int "tree item" 91 (num Lui_a11y.Outline_item);
  check int "tab group" 38 (num Lui_a11y.Tab_group);
  check int "tab" 37 (num Lui_a11y.Tab);
  check int "menu popup" 41 (num Lui_a11y.Menu);
  check int "text field entry" 79 (num Lui_a11y.Text_field);
  check int "text area" 61 (num Lui_a11y.Text_area);
  check int "slider" 51 (num Lui_a11y.Slider);
  check int "progress" 42 (num Lui_a11y.Progress_indicator);
  check int "link" 88 (num Lui_a11y.Link);
  check int "table cell" 56 (num Lui_a11y.Table_cell);
  check int "navigation landmark" 110 (num Lui_a11y.Navigation);
  check int "extension unknown" 67 (num Lui_a11y.Extension);
  check string "role name" "push button" (Ax.atspi_role_name Button);
  check string "toggle name" "toggle button"
    (Ax.atspi_role_name Toggle_button)

(* ---------- paths ---------- *)

let test_paths () =
  check string "path" "/org/a11y/atspi/accessible/42" (Ax.path_of 42);
  check (option int) "id roundtrip" (Some 42)
    (Ax.id_of_path (Ax.path_of 42));
  check (option int) "root is not an id" None
    (Ax.id_of_path Ax.root_path);
  check (option int) "junk" None (Ax.id_of_path "/other/path/1");
  check (option int) "non-numeric" None
    (Ax.id_of_path "/org/a11y/atspi/accessible/abc")

(* ---------- states ---------- *)

let st = Ax.stateset_of

let test_states_basic () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Button);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1);
      SetProp (2, Enabled, BoolValue false);
      SetProp (3, Selected, BoolValue true) ];
  let a = Lui_a11y.of_store t in
  let enabled id = st (Some Lui_a11y.Group) (find_exn a id) in
  (* disabled: no ENABLED / SENSITIVE *)
  check bool "disabled drops enabled" false (List.mem 8 (enabled 2));
  check bool "disabled drops sensitive" false (List.mem 24 (enabled 2));
  check bool "enabled keeps enabled" true (List.mem 8 (enabled 3));
  check bool "selected" true (List.mem 23 (enabled 3));
  check bool "visible+showing" true (List.mem 30 (enabled 3));
  check bool "showing" true (List.mem 25 (enabled 3));
  check bool "opaque" true (List.mem 19 (enabled 3));
  check bool "focusable" true (List.mem 11 (enabled 3));
  (* sorted *)
  check (list int) "sorted" (List.sort compare (enabled 3)) (enabled 3)

let test_states_checked () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Checkbox);
      CreateNode (2, Checkbox);
      CreateNode (3, Checkbox);
      SetProp (1, Checked, BoolValue true);
      SetProp (3, Checked, StringValue "mixed") ];
  let a = Lui_a11y.of_store t in
  let s id = st None (find_exn a id) in
  check bool "checkable" true (List.mem 41 (s 1));
  check bool "checked" true (List.mem 4 (s 1));
  check bool "unchecked" false (List.mem 4 (s 2));
  check bool "indeterminate" true (List.mem 32 (s 3))

let test_states_text_and_expansion () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, TextField);
      CreateNode (2, TextField);
      CreateNode (3, Textarea);
      CreateNode (4, Row);
      SetProp (1, TextValue, StringValue "x");
      SetExtensionProp (2, "read-only", BoolValue true);
      SetProp (3, TextValue, StringValue "a\nb");
      SetProp (4, Expanded, BoolValue false) ];
  let a = Lui_a11y.of_store t in
  let s id = st None (find_exn a id) in
  check bool "editable" true (List.mem 7 (s 1));
  check bool "single line" true (List.mem 26 (s 1));
  check bool "read-only not editable" false (List.mem 7 (s 2));
  check bool "read only" true (List.mem 43 (s 2));
  check bool "multi line" true (List.mem 17 (s 3));
  check bool "expandable" true (List.mem 9 (s 4));
  check bool "collapsed" true (List.mem 5 (s 4))

let test_states_selectable_parent () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, ListContainer);
      CreateNode (2, ListItem);
      CreateNode (3, ListItem);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1) ];
  let a = Lui_a11y.of_store t in
  let child = find_exn a 2 in
  check bool "selectable under list" true (List.mem 22 (st (Some Lui_a11y.List) child));
  check bool "not selectable under column" false
    (List.mem 22 (st (Some Lui_a11y.Group) child));
  check bool "none parent" false (List.mem 22 (st None child))

let test_states_window_active () =
  let t = Lui_store.create () in
  apply t [ CreateNode (1, Root); CreateNode (2, Column); InsertChild (1, 2, 0) ];
  let a = Lui_a11y.of_store t in
  check bool "root role is window" true
    ((find_exn a 1).Lui_a11y.role = Lui_a11y.Window);
  check bool "window active" true (List.mem 1 (st None (find_exn a 1)));
  check bool "column not active" false
    (List.mem 1 (st (Some Lui_a11y.Window) (find_exn a 2)))

(* ---------- interfaces / actions / text ---------- *)

let test_interfaces () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Button);
      CreateNode (2, TextField);
      CreateNode (3, Slider);
      CreateNode (4, Column);
      SetProp (2, TextValue, StringValue "x");
      SetProp (3, ProgressValue, FloatValue 0.5) ];
  let a = Lui_a11y.of_store t in
  let ifs id = Ax.interfaces_of (find_exn a id) in
  check (list string) "button ifaces"
    [ "Accessible"; "Component"; "Action" ] (ifs 1);
  check bool "text iface" true (List.mem "Text" (ifs 2));
  check bool "action on field" true (List.mem "Action" (ifs 2));
  check bool "value iface" true (List.mem "Value" (ifs 3));
  check bool "plain column" false (List.mem "Action" (ifs 4));
  check bool "always component" true (List.mem "Component" (ifs 4))

let test_actions () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Button);
      CreateNode (2, Checkbox);
      CreateNode (3, Row);
      SetProp (3, Expanded, BoolValue false) ];
  let a = Lui_a11y.of_store t in
  let names id = List.map (fun (x : Ax.action) -> x.name) (Ax.actions_of (find_exn a id)) in
  check (list string) "press" [ "press" ] (names 1);
  check (list string) "toggle" [ "toggle" ] (names 2);
  check (list string) "expand" [ "expand" ] (names 3);
  check (list string) "row expand order" [ "expand" ] (names 3)

let test_text_of () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, TextField);
      CreateNode (2, Text);
      CreateNode (3, Button);
      SetProp (1, TextValue, StringValue "typed");
      SetProp (2, TextValue, StringValue "shown") ];
  let a = Lui_a11y.of_store t in
  check (option string) "field text" (Some "typed")
    (Ax.text_of (find_exn a 1));
  check (option string) "static name" (Some "shown")
    (Ax.text_of (find_exn a 2));
  check (option string) "button none" None
    (Ax.text_of (find_exn a 3))

(* ---------- char offsets ---------- *)

let test_char_offsets () =
  (* e-acute is 2 bytes, the CJK char is 3 *)
  let s = "a\xc3\xa9\xe4\xb8\xadz" in
  check int "chars" 4 (Ax.char_offset_of_byte s (String.length s));
  check int "byte of 0" 0 (Ax.byte_of_char_offset s 0);
  check int "byte of 1" 1 (Ax.byte_of_char_offset s 1);
  check int "byte of 2" 3 (Ax.byte_of_char_offset s 2);
  check int "byte of 3" 6 (Ax.byte_of_char_offset s 3);
  check int "byte of 4" 7 (Ax.byte_of_char_offset s 4);
  check int "byte clamp" 7 (Ax.byte_of_char_offset s 9);
  check int "char at 0" 97 (Ax.char_at s 0);
  check int "char at 1" 0xE9 (Ax.char_at s 1);
  check int "char at 2" 0x4E2D (Ax.char_at s 2);
  check int "char at end" (-1) (Ax.char_at s 4);
  check int "ascii" 3 (Ax.char_offset_of_byte "abc" 3)

let test_text_range () =
  let s = "one two\nthree four" in
  (* char granularity at offset 4 -> 't' *)
  let bs, be, cs = Ax.text_range ~offset:4 s 0 0 in
  check string "char at" "t" (String.sub s bs (be - bs));
  check int "char off" 4 cs;
  (* word at offset inside 'two' *)
  let bs, be, cs = Ax.text_range ~offset:5 s 1 0 in
  check string "word at" "two" (String.sub s bs (be - bs));
  check int "word start" 4 cs;
  (* word before *)
  let bs, be, _cs = Ax.text_range ~offset:5 s 1 (-1) in
  check string "word before" "one" (String.sub s bs (be - bs));
  (* word after *)
  let bs, be, _ = Ax.text_range ~offset:1 s 1 1 in
  check string "word after" "two" (String.sub s bs (be - bs));
  (* line at offset inside 'three' *)
  let bs, be, cs = Ax.text_range ~offset:10 s 5 0 in
  check string "line at" "three four" (String.sub s bs (be - bs));
  check int "line start" 8 cs;
  (* line before *)
  let bs, be, _ = Ax.text_range ~offset:10 s 5 (-1) in
  check string "line before" "one two\n" (String.sub s bs (be - bs));
  (* multibyte-safe: boundaries never split UTF-8 *)
  let s2 = "\xe4\xb8\xad\xe4\xb8\xad x" in
  let bs, be, _ = Ax.text_range ~offset:0 s2 0 0 in
  check string "mb char" "\xe4\xb8\xad" (String.sub s2 bs (be - bs))

(* ---------- bridge: attach + served calls ---------- *)

let call ?(serial = 1) ?(iargs = [||]) ?(fargs = [||]) ?(sargs = [||])
    ~path ~iface ~member () =
  { Ax.serial; path; iface; member; iargs; fargs; sargs }

let itf = "org.a11y.atspi."
let fd = "org.freedesktop.DBus."

let dstr = function Ax.DStr s -> s | _ -> fail "DStr"
let dint = function Ax.DInt i -> i | _ -> fail "DInt"
let duint = function Ax.DUInt i -> i | _ -> fail "DUInt"
let dbool = function Ax.DBool b -> b | _ -> fail "DBool"
let dref = function
  | Ax.DStruct [ Ax.DStr n; Ax.DObj p ] -> (n, p)
  | _ -> fail "DStruct(so)"

let value = function Ax.Value v -> v | _ -> fail "expected Value"
let single f = function [ x ] -> f x | _ -> fail "single out arg"
let dvar f = function Ax.DVar (_, v) -> f v | _ -> fail "DVar"

let sample_tree () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Text);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0);
      SetProp (2, AccessibilityLabel, StringValue "Save button");
      SetProp (3, TextValue, StringValue "Save") ];
  let a = Lui_a11y.of_store t in
  ignore (Lui_store.drain_dirty t);
  a

let test_attach_events () =
  let a = sample_tree () in
  let br = Ax.create () in
  Ax.attach br a;
  let evs = Ax.drain_events br in
  let adds =
    List.filter
      (function Ax.Cache_add _ -> true | _ -> false)
      evs
  and ready =
    List.exists (function Ax.Cache_ready -> true | _ -> false) evs
  in
  check int "three add-accessible" 3 (List.length adds);
  check bool "cache ready" true ready;
  check int "drained" 0 (Ax.pending_count br);
  (* the add carries the cache snapshot fields *)
  match List.hd adds with
  | Ax.Cache_add ci ->
    check string "path" (Ax.path_of 1) ci.path;
    check int "child count" 1 ci.child_count;
    check int "index" 0 ci.index_in_parent
  | _ -> fail "add"

let test_served_calls () =
  let a = sample_tree () in
  let br = Ax.create () in
  Ax.attach br a;
  ignore (Ax.drain_events br);
  let call = call ~serial:1 in
  (* name / role *)
  check string "name"
    (single dstr
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Accessible")
                ~member:"GetName" ()))))
    "Save button";
  check int "role push button" 43
    (single duint
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Accessible")
                ~member:"GetRole" ()))));
  (* parent / children *)
  check (pair string string) "parent" ("", Ax.path_of 1)
    (single dref
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Accessible")
                ~member:"GetParent" ()))));
  check int "child count" 1
    (single dint
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 1) ~iface:(itf ^ "Accessible")
                ~member:"GetChildCount" ()))));
  check (pair string string) "child at"
    ("", Ax.path_of 2)
    (single dref
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 1) ~iface:(itf ^ "Accessible")
                ~member:"GetChildAtIndex" ~iargs:[| 0 |] ()))));
  check int "index in parent" 0
    (single dint
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Accessible")
                ~member:"GetIndexInParent" ()))));
  (* root: children = forest roots, parent = null until embedded *)
  check (pair string string) "root parent null" ("", "/org/a11y/atspi/null")
    (single dref
       (value
          (Ax.handle_call br
             (call ~path:Ax.root_path ~iface:(itf ^ "Accessible")
                ~member:"GetParent" ()))));
  check int "root children" 1
    (single dint
       (value
          (Ax.handle_call br
             (call ~path:Ax.root_path ~iface:(itf ^ "Accessible")
                ~member:"GetChildCount" ()))));
  check int "root role" Ax.role_application
    (single duint
       (value
          (Ax.handle_call br
             (call ~path:Ax.root_path ~iface:(itf ^ "Accessible")
                ~member:"GetRole" ()))));
  (* application iface *)
  check string "toolkit"
    (single (dvar dstr)
       (value
          (Ax.handle_call br
             (call ~path:Ax.root_path
                ~iface:(fd ^ "Properties") ~member:"Get"
                ~sargs:[| itf ^ "Application"; "ToolkitName" |] ()))))
    "lui";
  (* properties get *)
  check (pair string string) "prop get" ("s", "Save button")
    (single
       (function
         | Ax.DVar (sg, v) -> (sg, dstr v)
         | _ -> fail "DVar")
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(fd ^ "Properties")
                ~member:"Get"
                ~sargs:[| itf ^ "Accessible"; "Name" |] ()))));
  (* get-all returns a dict with Name *)
  (match
     value
       (Ax.handle_call br
          (call ~path:(Ax.path_of 2) ~iface:(fd ^ "Properties")
             ~member:"GetAll" ~sargs:[| itf ^ "Accessible" |] ()))
   with
   | [ Ax.DDict ("{sv}", pairs) ] ->
     check bool "name present" true (List.mem_assoc "Name" pairs)
   | _ -> fail "GetAll dict");
  (* unknown method -> error *)
  (match
     Ax.handle_call br
       (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Accessible")
          ~member:"Bogus" ())
   with
   | Ax.Error _ -> ()
   | _ -> fail "expected error");
  (* unknown object -> error *)
  (match
     Ax.handle_call br
       (call ~path:(Ax.path_of 999) ~iface:(itf ^ "Accessible")
          ~member:"GetName" ())
   with
   | Ax.Error _ -> ()
   | _ -> fail "expected error");
  (* cache items *)
  (match
     value
       (Ax.handle_call br
          (call ~path:Ax.cache_path ~iface:(itf ^ "Cache")
             ~member:"GetItems" ()))
   with
   | [ Ax.DArr (_, items) ] ->
     check int "app + 3 nodes" 4 (List.length items)
   | _ -> fail "GetItems");
  (* introspection XML covers the claimed interfaces *)
  check bool "xml declares Action" true
    (match
       value
         (Ax.handle_call br
            (call ~path:(Ax.path_of 2)
               ~iface:(fd ^ "Introspectable") ~member:"Introspect" ()))
     with
     | [ Ax.DStr xml ] ->
       let has sub =
         let n = String.length sub in
         let rec go i =
           i + n <= String.length xml
           && (String.sub xml i n = sub || go (i + 1))
         in
         go 0
       in
       has "org.a11y.atspi.Action" && has "org.a11y.atspi.Accessible"
     | _ -> false)

let test_text_calls () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, TextField);
      InsertChild (1, 2, 0);
      SetProp (2, TextValue, StringValue "hello world") ];
  let a = Lui_a11y.of_store t in
  let br = Ax.create () in
  Ax.attach br a;
  ignore (Ax.drain_events br);
  let call = call ~serial:1 in
  check int "count" 11
    (single dint
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Text")
                ~member:"GetCharacterCount" ()))));
  check string "slice"
    (single dstr
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Text")
                ~member:"GetText" ~iargs:[| 0; 5 |] ()))))
    "hello";
  check string "all"
    (single dstr
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Text")
                ~member:"GetText" ~iargs:[| 0; -1 |] ()))))
    "hello world";
  (* GetTextAtOffset word *)
  (match
     value
       (Ax.handle_call br
          (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Text")
             ~member:"GetTextAtOffset" ~iargs:[| 8; 1 |] ()))
   with
   | [ Ax.DStr s; Ax.DInt b; Ax.DInt e ] ->
     check string "word" "world" s;
     check int "wstart" 6 b;
     check int "wend" 11 e
   | _ -> fail "text at offset");
  (* caret callback *)
  let ok = ref false in
  Ax.on_caret_request br (fun _id off -> ok := off = 3; true);
  check bool "set caret" true
    (single dbool
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Text")
                ~member:"SetCaretOffset" ~iargs:[| 3 |] ()))));
  check bool "callback ran" true !ok;
  check int "caret prop" 3
    (single dint
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Text")
                ~member:"GetCaretOffset" ()))));
  (* the caret move queues an event *)
  let evs = Ax.drain_events br in
  check bool "caret moved event" true
    (List.exists
       (function
         | Ax.Object_event { member = "TextCaretMoved"; _ } -> true
         | _ -> false)
       evs)

let test_action_and_value_callbacks () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Slider);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1);
      SetProp (3, ProgressValue, FloatValue 0.5);
      SetProp (3, MinValue, FloatValue 0.0);
      SetProp (3, MaxValue, FloatValue 1.0) ];
  let a = Lui_a11y.of_store t in
  let br = Ax.create () in
  Ax.attach br a;
  ignore (Ax.drain_events br);
  let call = call ~serial:1 in
  (* DoAction *)
  let invoked = ref "" in
  Ax.on_action br (fun id name -> invoked := string_of_int id ^ ":" ^ name);
  (match
     Ax.handle_call br
       (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Action")
          ~member:"DoAction" ~iargs:[| 0 |] ())
   with
   | Ax.Value [] -> ()
   | _ -> fail "DoAction reply");
  check string "invoked press" "2:press" !invoked;
  (* action name + NActions property *)
  check string "action name" "press"
    (single dstr
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Action")
                ~member:"GetName" ~iargs:[| 0 |] ()))));
  check (pair string int) "nactions" ("i", 1)
    (single
       (function Ax.DVar (sg, v) -> (sg, dint v) | _ -> fail "var")
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(fd ^ "Properties")
                ~member:"Get"
                ~sargs:[| itf ^ "Action"; "NActions" |] ()))));
  (* GrabFocus *)
  let focused = ref 0 in
  Ax.on_focus_request br (fun id -> focused := id);
  check bool "grab focus" true
    (single dbool
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 2) ~iface:(itf ^ "Component")
                ~member:"GrabFocus" ()))));
  check int "focus cb" 2 !focused;
  (* SetCurrentValue *)
  let v = ref 0. in
  Ax.on_value_request br (fun _id x -> v := x; true);
  check bool "set value" true
    (single dbool
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 3) ~iface:(itf ^ "Value")
                ~member:"SetCurrentValue" ~fargs:[| 0.7 |] ()))));
  check (float 1e-9) "value cb" 0.7 !v;
  (* value props *)
  check (float 1e-9) "current value prop" 0.5
    (single
       (function
         | Ax.DVar (_, Ax.DDbl d) -> d
         | _ -> fail "DDbl")
       (value
          (Ax.handle_call br
             (call ~path:(Ax.path_of 3) ~iface:(fd ^ "Properties")
                ~member:"Get"
                ~sargs:[| itf ^ "Value"; "CurrentValue" |] ()))))

(* ---------- update diffs -> events ---------- *)

let obj_events evs =
  List.filter_map
    (function Ax.Object_event e -> Some e | _ -> None)
    evs

let test_update_add_remove () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Text);
      InsertChild (1, 2, 0) ];
  let a = Lui_a11y.of_store t in
  let br = Ax.create () in
  Ax.attach br a;
  ignore (Ax.drain_events br);
  (* add a child *)
  apply t [ CreateNode (3, Text); InsertChild (1, 3, 1) ];
  Ax.sync br;
  let evs = Ax.drain_events br in
  check bool "cache add" true
    (List.exists (function Ax.Cache_add _ -> true | _ -> false) evs);
  check bool "children add" true
    (List.exists
       (fun (e : Ax.object_event) ->
         e.Ax.member = "ChildrenChanged" && e.Ax.detail = "add"
         && e.Ax.detail1 = 1)
       (obj_events evs));
  (* remove it *)
  apply t [ DropNode 3 ];
  Ax.sync br;
  let evs = Ax.drain_events br in
  check bool "cache remove" true
    (List.exists
       (function Ax.Cache_remove p -> p = Ax.path_of 3 | _ -> false)
       evs);
  check bool "children remove" true
    (List.exists
       (fun (e : Ax.object_event) ->
         e.Ax.member = "ChildrenChanged" && e.Ax.detail = "remove"
         && e.Ax.detail1 = 1)
       (obj_events evs))

let test_update_props () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Checkbox);
      CreateNode (3, TextField);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1);
      SetProp (2, Checked, BoolValue false);
      SetProp (3, TextValue, StringValue "a") ];
  let a = Lui_a11y.of_store t in
  let br = Ax.create () in
  Ax.attach br a;
  ignore (Ax.drain_events br);
  (* toggle checked *)
  apply t [ SetProp (2, Checked, BoolValue true) ];
  Ax.sync br;
  let evs = Ax.drain_events br in
  check bool "state checked" true
    (List.exists
       (fun (e : Ax.object_event) ->
         e.Ax.member = "StateChanged" && e.Ax.detail = "checked"
         && e.Ax.detail1 = 1)
       (obj_events evs));
  (* text change *)
  apply t [ SetProp (3, TextValue, StringValue "ab") ];
  Ax.sync br;
  let evs = Ax.drain_events br in
  let texts =
    List.filter
      (fun (e : Ax.object_event) -> e.Ax.member = "TextChanged")
      (obj_events evs)
  in
  check bool "text delete+insert" true
    (List.exists (fun (e : Ax.object_event) -> e.Ax.detail = "delete") texts
     && List.exists (fun (e : Ax.object_event) -> e.Ax.detail = "insert") texts);
  (* name change *)
  apply t [ SetProp (2, AccessibilityLabel, StringValue "named") ];
  Ax.sync br;
  check bool "name prop change" true
    (List.exists
       (fun (e : Ax.object_event) ->
         e.Ax.member = "PropertyChange"
         && e.Ax.detail = "accessible-name")
       (obj_events (Ax.drain_events br)))

let test_focus_events () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Button);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1) ];
  let a = Lui_a11y.of_store t in
  let br = Ax.create () in
  Ax.attach br a;
  ignore (Ax.drain_events br);
  Ax.set_focus br 2;
  let evs = Ax.drain_events br in
  check bool "focused state on" true
    (List.exists
       (fun (e : Ax.object_event) ->
         e.Ax.member = "StateChanged" && e.Ax.detail = "focused"
         && e.Ax.detail1 = 1)
       (obj_events evs));
  check bool "focus signal" true
    (List.exists
       (function
         | Ax.Focus_event p -> p = Ax.path_of 2
         | _ -> false)
       evs);
  check (option int) "focused" (Some 2) (Ax.focused br);
  Ax.set_focus br 3;
  let evs = Ax.drain_events br in
  check bool "old loses focus" true
    (List.exists
       (fun (e : Ax.object_event) ->
         e.Ax.member = "StateChanged" && e.Ax.detail = "focused"
         && e.Ax.detail1 = 0
         && e.Ax.path = Ax.path_of 2)
       (obj_events evs));
  Ax.clear_focus br;
  check (option int) "none" None (Ax.focused br)

(* ---------- attributes ---------- *)

let test_attributes () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateExtension (9, "chart", "fp");
      InsertChild (1, 9, 0);
      SetExtensionProp (9, "title", StringValue "Chart") ];
  let a = Lui_a11y.of_store t in
  let attrs = Ax.attributes_of (find_exn a 9) in
  check (list (pair string string)) "ext attrs"
    [ ("toolkit-kind", "extension:chart"); ("extension-id", "chart") ]
    attrs

(* ---------- offline transport ---------- *)

let test_offline () =
  let br = Ax.create () in
  check bool "offline" true (Ax.transport br = Ax.Offline);
  check int "flush no-op" 0 (Ax.flush br);
  check int "dispatch no-op" 0 (Ax.dispatch br);
  Ax.destroy br;
  check (option bool) "a11y gone" None
    (match Ax.a11y br with
     | None -> None
     | Some _ -> Some true)

let () =
  run "lui_ax_linux"
    [ ( "role-map",
        [ test_case "every role mapped once" `Quick
            test_role_map_complete;
          test_case "role numbers" `Quick test_role_map_values ] );
      ( "paths",
        [ test_case "path/id roundtrip" `Quick test_paths ] );
      ( "states",
        [ test_case "basic flags" `Quick test_states_basic;
          test_case "tri-state" `Quick test_states_checked;
          test_case "text+expansion" `Quick
            test_states_text_and_expansion;
          test_case "selectable parent" `Quick
            test_states_selectable_parent;
          test_case "window active" `Quick test_states_window_active ] );
      ( "derived",
        [ test_case "interfaces" `Quick test_interfaces;
          test_case "actions" `Quick test_actions;
          test_case "text payload" `Quick test_text_of;
          test_case "attributes" `Quick test_attributes ] );
      ( "offsets",
        [ test_case "utf-8 char offsets" `Quick test_char_offsets;
          test_case "granularity ranges" `Quick test_text_range ] );
      ( "served",
        [ test_case "attach cache events" `Quick test_attach_events;
          test_case "method table" `Quick test_served_calls;
          test_case "text calls" `Quick test_text_calls;
          test_case "action+value callbacks" `Quick
            test_action_and_value_callbacks ] );
      ( "update",
        [ test_case "add/remove events" `Quick test_update_add_remove;
          test_case "prop/state/text events" `Quick test_update_props;
          test_case "focus events" `Quick test_focus_events ] );
      ( "transport",
        [ test_case "offline no-ops" `Quick test_offline ] ) ]
