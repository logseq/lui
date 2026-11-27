(* Evaluate canonical property admission rather than duplicating the renderer's
   supported-feature list. Compiler-libs supplies string literals for the oracle. *)
open Lui_protocol
open Parsetree

let () =
  let channel = open_in Sys.argv.(1) in
  let syntax = Parse.implementation (Lexing.from_channel channel) in
  close_in channel;
  let literals = ref ["sample"; "app:sample"; ""; "0 0 1 1"; "opacity 1s"] in
  let iterator = { Ast_iterator.default_iterator with
    expr = (fun self e ->
      (match e.pexp_desc with
      | Pexp_constant {pconst_desc = Pconst_string (s, _, _); _} -> literals := s :: !literals
      | _ -> ()); Ast_iterator.default_iterator.expr self e);
    pat = (fun self p ->
      (match p.ppat_desc with
      | Ppat_constant {pconst_desc = Pconst_string (s, _, _); _} -> literals := s :: !literals
      | _ -> ()); Ast_iterator.default_iterator.pat self p) } in
  iterator.structure iterator syntax;
  let values = List.map (fun s -> StringValue s) (List.sort_uniq String.compare !literals)
    @ [BoolValue false; BoolValue true]
    @ List.map (fun n -> IntValue n) [-1; 0; 1; 4; 6; 7; 246; 1000; 1001; 2147483647; 2147483648]
    @ List.map (fun f -> FloatValue f) [-1.; 0.; 0.4; 0.7; 1.; 246.; 1000.] in
  let json_value = function
    | StringValue s -> `Assoc ["type", `String "string"; "value", `String s]
    | BoolValue b -> `Assoc ["type", `String "bool"; "value", `Bool b]
    | IntValue n -> `Assoc ["type", `String "int"; "value", `Int n]
    | FloatValue f -> `Assoc ["type", `String "float"; "value", `Float f] in
  let verdict predicate = `String (String.concat "" (List.map (fun v -> if predicate v then "1" else "0") values)) in
  let properties = Lui_wire_schema.all_properties in
  let kinds = Lui_wire_schema.all_node_kinds in
  let name = Lui_wire_schema.property_name in
  let kind_name = Lui_wire_schema.node_kind_name in
  let detail = { x = 0.; y = 0.; modifiers = 0; button = 0; target_class = "" } in
  let events = [
    "Press", Press 0; "LongPress", LongPress 0;
    "TextChanged", TextChanged (0, ""); "Submit", Submit 0;
    "ToggleChanged", ToggleChanged (0, false); "Change", Change 0;
    "ValueChanged", ValueChanged (0, 0.); "Dismiss", Dismiss 0;
    "DoublePress", DoublePress 0; "Appear", Appear 0;
    "ScrollCompleted", ScrollCompleted (0, 0, "");
    "VisibleRange", VisibleRange (0, 0, 0); "Picked", Picked (0, "");
    "PressModifiers", PressModifiers (0, 0); "PressDetail", PressDetail (0, detail);
    "PointerDown", PointerDown (0, detail); "PointerUp", PointerUp (0, detail);
    "PointerEnter", PointerEnter 0; "PointerLeave", PointerLeave 0;
    "ContextMenuPress", ContextMenuPress (0, detail); "Load", Load 0;
    "NavigatePrevious", NavigatePrevious 0; "NavigateNext", NavigateNext 0;
    "NavigationKey", NavigationKey (0, "ArrowRight", false);
    "ScrollEdges", ScrollEdges (0, false, false);
    "VirtualWindow", VirtualWindow (0, 0, 0, 0, []);
    "PointerMove", PointerMove (0, detail); "PointerCancel", PointerCancel (0, detail);
    "ToggleChangedDetail", ToggleChangedDetail (0, false, 0);
    "FocusWithinChanged", FocusWithinChanged (0, false);
    "VirtualRetention", VirtualRetention (0, 0, "");
  ] in
  let admitted_kinds event =
    List.filter_map (fun kind ->
      if event_supported kind event then Some (`String (kind_name kind)) else None) kinds
  in
  let navigation_key_kinds =
    List.sort_uniq compare
      (admitted_kinds (NavigationKey (0, "ArrowRight", false))
       @ admitted_kinds (NavigationKey (0, "Enter", false)))
  in
  Yojson.Basic.to_channel stdout (`Assoc [
    "events", `Assoc (List.map (fun (name, event) -> name,
      `List (if name = "NavigationKey" then navigation_key_kinds
             else admitted_kinds event)) events);
    "modalKinds", `List (List.filter_map (fun kind ->
      if modal_surface kind then Some (`String (kind_name kind)) else None) kinds);
    "kinds", `Assoc (List.map (fun kind -> kind_name kind,
      `List (List.filter_map (fun p -> if property_supported kind p then Some (`String (name p)) else None) properties)) kinds);
    "values", `List (List.map json_value values);
    "properties", `Assoc (List.map (fun p -> name p, verdict (property_value_supported p)) properties);
    "kindValues", `Assoc (List.map (fun kind -> kind_name kind,
      `Assoc (List.map (fun p -> name p, verdict (property_value_supported_for_kind kind p)) [RoleValue; SizeValue; As])) kinds)
  ]);
  print_newline ()
