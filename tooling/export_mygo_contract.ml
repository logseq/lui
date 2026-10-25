(* Export the native contract by evaluating LUI's canonical validators.
   The Python generator translates only the restricted validation expressions;
   unsupported future syntax fails generation instead of weakening validation. *)
open Lui_protocol
open Parsetree

let obj fields = `Assoc fields
let arr values = `List values
let str value = `String value
let ident value = Longident.flatten value |> String.concat "."
let fail loc text = Location.raise_errorf ~loc "MyGo contract: %s" text

let constant c = match c.pconst_desc with
  | Pconst_integer (s, _) | Pconst_float (s, _) -> obj ["number", str s]
  | Pconst_string (s, _, _) -> obj ["string", str s]
  | _ -> fail c.pconst_loc "unsupported constant"

let rec pattern p = match p.ppat_desc with
  | Ppat_any -> obj ["any", `Bool true]
  | Ppat_var name -> obj ["var", str name.txt]
  | Ppat_construct (name, argument) ->
      obj (["constructor", str (ident name.txt)] @
        match argument with None -> [] | Some (_, p) -> ["argument", pattern p])
  | Ppat_or (a, b) -> obj ["or", arr [pattern a; pattern b]]
  | Ppat_tuple (items, _) -> obj ["tuple", arr (List.map (fun (_, p) -> pattern p) items)]
  | Ppat_constant c -> constant c
  | _ -> fail p.ppat_loc "unsupported pattern"

let rec expression e = match e.pexp_desc with
  | Pexp_ident name -> obj ["ident", str (ident name.txt)]
  | Pexp_constant c -> constant c
  | Pexp_construct (name, argument) ->
      obj (["constructor", str (ident name.txt)] @
        match argument with None -> [] | Some e -> ["argument", expression e])
  | Pexp_tuple items -> obj ["tuple", arr (List.map (fun (_, e) -> expression e) items)]
  | Pexp_apply ({pexp_desc = Pexp_ident {txt = Longident.Lident "node_property_presence_supported"; _}; _}, _) ->
      obj ["presence", `Bool true]
  | Pexp_apply (f, args) -> obj ["call", expression f; "args", arr (List.map (fun (_, e) -> expression e) args)]
  | Pexp_ifthenelse (condition, yes, Some no) ->
      obj ["if", expression condition; "then", expression yes; "else", expression no]
  | Pexp_let (Asttypes.Nonrecursive, bindings, body) ->
      obj ["let", arr (List.map (fun b -> obj ["pattern", pattern b.pvb_pat; "value", expression b.pvb_expr]) bindings); "body", expression body]
  | Pexp_match (value, cases) ->
      obj ["match", expression value; "cases", arr (List.map (fun c ->
        if Option.is_some c.pc_guard then fail c.pc_lhs.ppat_loc "guarded match";
        obj ["pattern", pattern c.pc_lhs; "value", expression c.pc_rhs]) cases)]
  | _ -> fail e.pexp_loc "unsupported validation expression"

let body e = match e.pexp_desc with
  | Pexp_function (_, _, Pfunction_body body) -> body
  | _ -> fail e.pexp_loc "expected validator function"

let source = Sys.argv.(1)
let channel = open_in source
let syntax = Parse.implementation (Lexing.from_channel channel)
let () = close_in channel
let functions = Hashtbl.create 32
let literals = ref []
let () =
  let iterator = {Ast_iterator.default_iterator with expr = (fun self e ->
    (match e.pexp_desc with
    | Pexp_constant {pconst_desc = Pconst_string (s, _, _); _} -> literals := s :: !literals
    | _ -> ());
    Ast_iterator.default_iterator.expr self e);
    pat = (fun self p ->
      (match p.ppat_desc with
      | Ppat_constant {pconst_desc = Pconst_string (s, _, _); _} -> literals := s :: !literals
      | _ -> ());
      Ast_iterator.default_iterator.pat self p)} in
  iterator.structure iterator syntax;
  List.iter (function
    | {pstr_desc = Pstr_value (_, bindings); _} -> List.iter (fun b ->
        match b.pvb_pat.ppat_desc with
        | Ppat_var name -> Hashtbl.replace functions name.txt b.pvb_expr
        | _ -> ()) bindings
    | _ -> ()) syntax

exception Need_property of property
let rec presence kind assigned =
  let lookup property = match List.assoc_opt property assigned with
    | Some value -> value | None -> raise (Need_property property) in
  try `Bool (node_property_presence_supported kind ~definite:lookup ~possible:lookup)
  with Need_property property ->
    let yes = presence kind ((property, true) :: assigned) in
    let no = presence kind ((property, false) :: assigned) in
    if yes = no then yes else obj ["property", str (Lui_wire_schema.property_name property); "yes", yes; "no", no]

let pointer = {x = 0.; y = 0.; modifiers = 0; button = 0; target_class = ""}
let events = [
  "press", Press 0; "press-modifiers", PressModifiers (0, 0);
  "long-press", LongPress 0; "text-changed", TextChanged (0, "");
  "submit", Submit 0; "toggle-changed", ToggleChanged (0, false);
  "change", Change 0; "value-changed", ValueChanged (0, 0.);
  "dismiss", Dismiss 0; "double-press", DoublePress 0; "appear", Appear 0;
  "visible-range", VisibleRange (0, 0, 0); "scroll-completed", ScrollCompleted (0, 0, "");
  "picked", Picked (0, ""); "press-detail", PressDetail (0, pointer);
  "pointer-down", PointerDown (0, pointer); "pointer-up", PointerUp (0, pointer);
  "pointer-enter", PointerEnter 0; "pointer-leave", PointerLeave 0;
  "context-menu-press", ContextMenuPress (0, pointer); "load", Load 0;
  "navigate-previous", NavigatePrevious 0; "navigate-next", NavigateNext 0;
  "navigation-key", NavigationKey (0, "ArrowDown", false);
  "scroll-edges", ScrollEdges (0, false, false);
  "virtual-window", VirtualWindow (0, 1, 0, 0, [])]

let wire_json = function
  | StringValue value -> obj ["type", str "string"; "value", str value]
  | BoolValue value -> obj ["type", str "bool"; "value", `Bool value]
  | IntValue value -> obj ["type", str "int"; "value", `Int value]
  | FloatValue value -> obj ["type", str "float"; "value", `Float value]

let probes =
  let strings = [""; " "; "sample"; "app:sample"; "app:bad--slug";
    "0 0 1 1"; "0 0 -1 1"; "0  0 1 1"; "0 0 nan 1";
    "opacity 1s"; "opacity 1ms ease-in 2ms"; "opacity 0x1s";
    "opacity 1s cubic-bezier(0, 1, 0, 1)"; "opacity 1s, transform 2s";
    "underline line-through"; "none underline"; "data-test\x1fvalue";
    "data-test\x1fvalue\x1e aria-label\x1fname"; "id\x1fvalue";
    "\011"; "\012"; "\194\160"] in
  List.map (fun value -> StringValue value) (List.sort_uniq String.compare (strings @ !literals))
  @ [BoolValue false; BoolValue true]
  @ List.map (fun value -> IntValue value) [-1; 0; 1; 2; 6; 7; 1000; 1001; 2147483647; 2147483648]
  @ List.map (fun value -> FloatValue value) [-1.; 0.; 0.01; 0.5; 1.; 2.; 6.; 1000.; Float.max_float]

let probe_array = Array.of_list probes
let verdicts predicate =
  let count = Array.length probe_array in
  str (String.init ((count + 3) / 4) (fun i ->
    let bits = ref 0 in
    for offset = 0 to 3 do
      let index = 4 * i + offset in
      if index < count && predicate probe_array.(index) then bits := !bits lor (1 lsl offset)
    done;
    "0123456789abcdef".[!bits]))

let default_value kind property =
  match List.find_opt (property_value_supported_for_kind kind property)
    (BoolValue true :: StringValue "sample" :: FloatValue 1. :: IntValue 1 :: probes) with
  | Some value -> value
  | None -> failwith ("No valid value for " ^ Lui_wire_schema.property_name property)

let rec minimal_properties = function
  | `Bool true -> Some [] | `Bool false -> None
  | `Assoc fields ->
      (match minimal_properties (List.assoc "no" fields) with
       | Some props -> Some props
       | None -> Option.map (fun props ->
           (Yojson.Basic.Util.to_string (List.assoc "property" fields)) :: props)
           (minimal_properties (List.assoc "yes" fields)))
  | _ -> assert false

let baseline kind =
  let names = Option.get (minimal_properties (presence kind [])) in
  let props = List.fold_left (fun props name -> let p = Lui_wire.property_of_name name in
    Property_map.add p (default_value kind p) props) Property_map.empty names in
  if node_properties_supported kind props then props else
    match List.find_opt (fun property -> property_supported kind property &&
       node_properties_supported kind (Property_map.add property (default_value kind property) props)) Lui_wire_schema.all_properties with
    | Some property -> Property_map.add property (default_value kind property) props
    | None -> failwith ("No valid baseline for " ^ Lui_wire_schema.node_kind_name kind)

let () =
  let kinds = Lui_wire_schema.all_node_kinds in
  let properties = Lui_wire_schema.all_properties in
  let names items name = arr (List.map (fun item -> str (name item)) items) in
  let validators = ["property_value_supported"; "property_value_supported_for_kind"; "node_properties_supported";
    "is_finite"; "container_relative_frame_supported"; "orientation_supported";
    "placement_supported"; "control_size_supported"; "button_variant_supported";
    "icon_placement_supported"; "theme_mode_supported"; "picker_source_supported";
    "sizing_supported"; "main_alignment_supported"; "cross_alignment_supported"; "alignment_supported"] in
  let output = obj [
    "version", `Int 1;
    "oracle", obj [
      "values", arr (List.map wire_json probes);
      "properties", obj (List.map (fun property -> Lui_wire_schema.property_name property, verdicts (property_value_supported property)) properties);
      "kindValues", obj (List.map (fun kind -> Lui_wire_schema.node_kind_name kind,
        obj (List.map (fun property -> Lui_wire_schema.property_name property,
          verdicts (property_value_supported_for_kind kind property)) [RoleValue; SizeValue; As])) kinds);
      "nodes", obj (List.map (fun kind ->
        let base = baseline kind in
        let cases = List.filter (property_supported kind) properties in
        Lui_wire_schema.node_kind_name kind, obj [
          "baseline", obj (Property_map.bindings base |> List.map (fun (p,v) -> Lui_wire_schema.property_name p, wire_json v));
          "properties", obj (List.map (fun property -> Lui_wire_schema.property_name property,
            verdicts (fun value -> property_value_supported_for_kind kind property value &&
              node_properties_supported kind (Property_map.add property value base))) cases)
        ]) kinds)
    ];
    "validators", obj (List.map (fun name -> name, expression (body (Hashtbl.find functions name))) validators);
    "scalarTypes", obj (List.map (fun property ->
      let supported candidates = List.exists (property_value_supported property) candidates in
      let types = List.filter_map (fun (name, values) -> if supported values then Some (str name) else None)
        ["string", List.map (fun s -> StringValue s) ("sample" :: "opacity 1s" :: "0 0 1 1" :: "app:sample" :: !literals);
         "bool", [BoolValue false; BoolValue true]; "int", [IntValue 0; IntValue 1; IntValue 6; IntValue 1000];
         "float", [FloatValue 0.; FloatValue 1.]] in
      Lui_wire_schema.property_name property, arr types) properties);
    "properties", names properties Lui_wire_schema.property_name;
    "kinds", obj (List.map (fun kind -> Lui_wire_schema.node_kind_name kind, obj [
      "container", `Bool (can_contain_children kind);
      "properties", names (List.filter (property_supported kind) properties) Lui_wire_schema.property_name;
      "children", names (List.filter (fun child -> can_contain_children kind && child_kind_supported kind child) kinds) Lui_wire_schema.node_kind_name;
      "events", names (List.filter (fun (_, event) -> event_supported kind event) events) fst;
      "presence", presence kind [];
      "tags", names (List.filter (element_tag_supported kind) (List.sort_uniq String.compare !literals)) (fun x -> x);
      "treeRow", `Bool (tree_row_kind kind)]) kinds);
    "icons", names (List.filter built_in_icon_name_supported (List.sort_uniq String.compare !literals)) (fun x -> x)] in
  Yojson.Basic.pretty_to_channel stdout output;
  print_newline ()
