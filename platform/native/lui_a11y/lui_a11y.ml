(* Platform-agnostic accessibility semantic model derived from the
   retained Lui_store node mirror.

   The module reads kinds and props by their wire names, so every string
   here matches what Lui_wire_schema emits — the same convention
   Lui_store uses when consuming patch ops. Records are recomputed
   field-by-field from the store, which keeps [update] simple: a node is
   "changed" iff its recomputed record differs from the stored one. *)

open Lui_protocol

type role =
  | Window
  | Group
  | Static_text
  | Heading
  | Text_field
  | Text_area
  | Search_field
  | Button
  | Toggle_button
  | Check_box
  | Radio_button
  | Radio_group
  | Switch
  | Slider
  | Spin_button
  | Progress_indicator
  | Link
  | Image
  | List
  | List_item
  | Outline
  | Outline_item
  | Tab_group
  | Tab
  | Menu
  | Menu_item
  | Combo_box
  | Dialog
  | Sheet
  | Tooltip
  | Table
  | Table_row
  | Table_cell
  | Separator
  | Toolbar
  | Status_bar
  | Navigation
  | Split_group
  | Extension

type check_state =
  | Checked
  | Unchecked
  | Mixed

type state_flags = {
  focusable : bool;
  focused : bool;
  selected : bool;
  checked : check_state option;
  disabled : bool;
  expanded : bool option;
  required : bool;
  read_only : bool;
  password : bool;
}

type a11y_value = {
  numeric : float option;
  minimum : float option;
  maximum : float option;
  text : string option;
}

type node_a11y = {
  id : int;
  kind : string;
  role : role;
  name : string option;
  description : string option;
  state : state_flags;
  value : a11y_value option;
  parent : int option;
  children : int list;
  ext_id : string option;
}

type t = {
  store : Lui_store.t;
  nodes : (int, node_a11y) Hashtbl.t;
  mutable roots : int list;
  mutable focused : int option;
}

module ISet = Set.Make (Int)

(* ---------- kind -> role ---------- *)

(* The explicit mapping table for every standard kind. Unknown kinds
   fall back to Group; extension nodes get Extension with the identifier
   kept on the record's ext_id field. *)
let kind_role_table =
  [ ("root", Window);
    ("row", Group); ("column", Group); ("grid", Group); ("stack", Group);
    ("edge-inset", Group); ("overlay", Group); ("view-that-fits", Group);
    ("panel", Group); ("card", Group); ("bubble", Group); ("box", Group);
    ("alert", Dialog);
    ("text", Static_text); ("paragraph", Static_text);
    ("label", Static_text); ("kbd", Static_text); ("br", Static_text);
    ("heading", Heading);
    ("button", Button); ("menu-trigger", Button);
    ("swipe-action", Button); ("file-picker", Button);
    ("toggle-button", Toggle_button); ("toggle", Toggle_button);
    ("checkbox", Check_box);
    ("radio", Radio_button); ("radio-group", Radio_group);
    ("switch", Switch);
    ("slider", Slider); ("number-stepper", Spin_button);
    ("text-field", Text_field); ("secure-field", Text_field);
    ("input", Text_field); ("search-field", Search_field);
    ("textarea", Text_area);
    ("progress", Progress_indicator); ("spinner", Progress_indicator);
    ("divider", Separator);
    ("scroll", Group);
    ("list", List); ("virtual-list", List); ("timeline", List);
    ("list-item", List_item); ("timeline-item", List_item);
    ("list-section", Group); ("list-section-header", Static_text);
    ("list-section-footer", Static_text);
    ("tabs", Tab_group); ("bottom-tabs", Tab_group); ("bottom-tab", Tab);
    ("dropdown-menu", Menu); ("context-menu", Menu);
    ("menu-item", Menu_item);
    ("select", Combo_box); ("combobox", Combo_box);
    ("link", Link);
    ("image", Image); ("icon", Image); ("avatar", Image);
    ("file-image", Image);
    ("media-surface", Group); ("file-preview", Group);
    ("spacer", Group); ("button-group", Group); ("toggle-group", Group);
    ("input-group", Group); ("input-group-actions", Toolbar);
    ("stepper", Group); ("step", Group); ("swipe-actions", Group);
    ("breadcrumb", Navigation); ("pagination", Navigation);
    ("accordion", Group);
    ("table", Table); ("table-row", Table_row); ("table-cell", Table_cell);
    ("tree", Outline);
    ("resizable", Group); ("split", Split_group);
    ("dialog", Dialog); ("popover", Dialog);
    ("drawer", Sheet); ("sheet", Sheet);
    ("tooltip", Tooltip); ("toast", Group);
    ("toolbar", Toolbar); ("status-bar", Status_bar) ]

let extension_prefix = "extension:"

let is_extension_kind name =
  let lp = String.length extension_prefix in
  String.length name >= lp && String.sub name 0 lp = extension_prefix

(* ARIA-style "role" prop overrides (the wire schema marks tree rows this
   way). Only honored when the value names a known override. *)
let role_of_role_prop = function
  | "treeitem" -> Some Outline_item
  | "tree" -> Some Outline
  | "tab" -> Some Tab
  | "tablist" -> Some Tab_group
  | "menu" -> Some Menu
  | "menuitem" -> Some Menu_item
  | "button" -> Some Button
  | "checkbox" -> Some Check_box
  | "radio" -> Some Radio_button
  | "switch" -> Some Switch
  | "slider" -> Some Slider
  | "textbox" -> Some Text_field
  | "searchbox" -> Some Search_field
  | "progressbar" -> Some Progress_indicator
  | "link" -> Some Link
  | "img" | "image" -> Some Image
  | "list" | "listbox" -> Some List
  | "listitem" | "option" -> Some List_item
  | "table" | "grid" -> Some Table
  | "row" -> Some Table_row
  | "cell" | "gridcell" | "columnheader" | "rowheader" -> Some Table_cell
  | "dialog" | "alertdialog" | "alert" -> Some Dialog
  | "tooltip" -> Some Tooltip
  | "separator" -> Some Separator
  | "navigation" -> Some Navigation
  | "toolbar" -> Some Toolbar
  | "status" -> Some Status_bar
  | "heading" -> Some Heading
  | "combobox" -> Some Combo_box
  | "spinbutton" -> Some Spin_button
  | _ -> None

let role_of_kind name =
  if is_extension_kind name then Extension
  else match List.assoc_opt name kind_role_table with
  | Some r -> r
  | None -> Group

let role_name = function
  | Window -> "window"
  | Group -> "group"
  | Static_text -> "static-text"
  | Heading -> "heading"
  | Text_field -> "text-field"
  | Text_area -> "text-area"
  | Search_field -> "search-field"
  | Button -> "button"
  | Toggle_button -> "toggle-button"
  | Check_box -> "check-box"
  | Radio_button -> "radio-button"
  | Radio_group -> "radio-group"
  | Switch -> "switch"
  | Slider -> "slider"
  | Spin_button -> "spin-button"
  | Progress_indicator -> "progress-indicator"
  | Link -> "link"
  | Image -> "image"
  | List -> "list"
  | List_item -> "list-item"
  | Outline -> "outline"
  | Outline_item -> "outline-item"
  | Tab_group -> "tab-group"
  | Tab -> "tab"
  | Menu -> "menu"
  | Menu_item -> "menu-item"
  | Combo_box -> "combo-box"
  | Dialog -> "dialog"
  | Sheet -> "sheet"
  | Tooltip -> "tooltip"
  | Table -> "table"
  | Table_row -> "table-row"
  | Table_cell -> "table-cell"
  | Separator -> "separator"
  | Toolbar -> "toolbar"
  | Status_bar -> "status-bar"
  | Navigation -> "navigation"
  | Split_group -> "split-group"
  | Extension -> "extension"

(* ---------- prop readers ---------- *)

let prop store id name = Lui_store.prop store id name
let bool_prop store id name = Lui_store.bool_prop store id name

(* First non-empty string prop among [names], in order. *)
let first_string store id names =
  let rec go = function
    | [] -> None
    | n :: rest ->
      (match prop store id n with
       | Some (StringValue s) when s <> "" -> Some s
       | _ -> go rest)
  in
  go names

(* Accessible name precedence: own content props first, then the
   explicit a11y label. *)
let name_props =
  [ "text"; "label"; "placeholder"; "title"; "aria-label";
    "accessibility-label" ]

let description_props = [ "title"; "description"; "meta" ]

(* ---------- visibility ---------- *)

let self_hidden store id =
  (match prop store id "visible" with
   | Some (BoolValue false) | Some (StringValue "false") -> true
   | _ -> false)
  ||
  match prop store id "display" with
  | Some (StringValue "none") -> true
  | _ -> false

(* A node is excluded when it or any ancestor is hidden. *)
let rec hidden_in_chain store id =
  self_hidden store id
  ||
  match Lui_store.parent store id with
  | Some p -> hidden_in_chain store p
  | None -> false

(* ---------- names accumulated from descendants ---------- *)

(* Roles that take their accessible name from descendant content when no
   own prop supplies one (the classic button-with-label-children case). *)
let composite_role = function
  | Button | Toggle_button | Link | Menu_item | Tab | Check_box
  | Radio_button | Switch | List_item | Outline_item | Combo_box -> true
  | _ -> false

let interactive_role = function
  | Button | Toggle_button | Check_box | Radio_button | Switch | Slider
  | Spin_button | Text_field | Text_area | Search_field | Combo_box
  | Menu_item | Link | Tab | Outline_item -> true
  | _ -> false

let value_role = function
  | Text_field | Text_area | Search_field | Slider | Spin_button
  | Progress_indicator | Combo_box -> true
  | _ -> false

(* Preorder walk over the subtree collecting "text" props; hidden
   subtrees are skipped. *)
let accumulate_text store id =
  let buf = Buffer.create 64 in
  let rec walk cid =
    if not (self_hidden store cid) then begin
      (match prop store cid "text" with
       | Some (StringValue s) when s <> "" ->
         if Buffer.length buf > 0 then Buffer.add_char buf ' ';
         Buffer.add_string buf s
       | _ -> ());
      List.iter walk (Lui_store.child_ids store cid)
    end
  in
  List.iter walk (Lui_store.child_ids store id);
  match Buffer.contents buf with "" -> None | s -> Some s

(* ---------- state flags ---------- *)

let compute_checked store id role =
  match prop store id "checked" with
  | Some (BoolValue true) -> Some Checked
  | Some (BoolValue false) -> Some Unchecked
  | Some (IntValue i) -> Some (if i <> 0 then Checked else Unchecked)
  | Some (FloatValue f) -> Some (if f <> 0.0 then Checked else Unchecked)
  | Some (StringValue s) ->
    (match String.lowercase_ascii s with
     | "true" | "checked" | "on" -> Some Checked
     | "mixed" | "indeterminate" -> Some Mixed
     | _ -> Some Unchecked)
  | None ->
    (* Checkable roles report Unchecked by default; other roles carry
       no checked state at all. *)
    (match role with
     | Check_box | Radio_button | Switch | Toggle_button -> Some Unchecked
     | _ -> None)

let compute_focusable store id role disabled =
  match prop store id "focusable" with
  | Some (BoolValue b) -> b
  | _ ->
    (not disabled)
    && (interactive_role role
        || bool_prop store id "press-enabled"
        || bool_prop store id "change-enabled"
        || bool_prop store id "toggle-enabled"
        || bool_prop store id "submit-enabled"
        || bool_prop store id "long-press-enabled"
        || bool_prop store id "autofocus")

let compute_disabled store id =
  (match prop store id "enabled" with
   | Some (BoolValue false) -> true
   | _ -> false)
  || bool_prop store id "disabled"

let compute_password store id kind =
  kind = "secure-field"
  || (match prop store id "input-type" with
      | Some (StringValue "password") -> true
      | _ -> false)
  || bool_prop store id "password"

let compute_state store id kind role focused =
  let disabled = compute_disabled store id in
  { focusable = compute_focusable store id role disabled;
    focused = focused = Some id;
    selected =
      bool_prop store id "selected" || bool_prop store id "aria-selected";
    checked = compute_checked store id role;
    disabled;
    expanded =
      (match prop store id "expanded" with
       | Some (BoolValue b) -> Some b
       | _ -> None);
    required =
      bool_prop store id "required" || bool_prop store id "aria-required";
    read_only =
      bool_prop store id "read-only" || bool_prop store id "readonly"
      || bool_prop store id "aria-readonly";
    password = compute_password store id kind }

let compute_value store id role =
  let numeric =
    match prop store id "value" with
    | Some (FloatValue f) -> Some f
    | Some (IntValue i) -> Some (Float.of_int i)
    | _ -> None
  and text =
    match prop store id "value" with
    | Some (StringValue s) -> Some s
    | _ -> if value_role role then Lui_store.string_prop store id "text"
      else None
  and flt name =
    match prop store id name with
    | Some (FloatValue f) -> Some f
    | Some (IntValue i) -> Some (Float.of_int i)
    | _ -> None
  in
  let minimum = flt "min" and maximum = flt "max" in
  if
    value_role role || numeric <> None || text <> None
    || minimum <> None || maximum <> None
  then Some { numeric; minimum; maximum; text }
  else None

(* ---------- node computation ---------- *)

let compute_role store id kind =
  match prop store id "role" with
  | Some (StringValue s) ->
    (match role_of_role_prop (String.lowercase_ascii s) with
     | Some r -> r
     | None -> role_of_kind kind)
  | _ -> role_of_kind kind

let compute_node_a11y t id =
  match Lui_store.find_opt t.store id with
  | None -> None
  | Some n ->
    if hidden_in_chain t.store id then None
    else begin
      let kind = Lui_store.node_kind n in
      let role = compute_role t.store id kind in
      let name =
        match first_string t.store id name_props with
        | Some _ as s -> s
        | None ->
          if composite_role role then accumulate_text t.store id else None
      in
      let children =
        List.filter
          (fun c -> Lui_store.mem t.store c && not (self_hidden t.store c))
          (Lui_store.node_children n)
      in
      Some
        { id;
          kind;
          role;
          name;
          description = first_string t.store id description_props;
          state = compute_state t.store id kind role t.focused;
          value = compute_value t.store id role;
          parent = Lui_store.node_parent n;
          children;
          ext_id = Lui_store.node_ext_id n }
    end

let records_equal a b =
  match a, b with
  | None, None -> true
  | Some x, Some y -> x = y
  | _ -> false

let replace_record t id record =
  let old = Hashtbl.find_opt t.nodes id in
  if records_equal old record then false
  else begin
    (match record with
     | Some r -> Hashtbl.replace t.nodes id r
     | None -> Hashtbl.remove t.nodes id);
    true
  end

(* ---------- build / queries ---------- *)

let rebuild_roots t =
  t.roots <-
    List.filter
      (fun id -> not (hidden_in_chain t.store id))
      (Lui_store.root_ids t.store)

let populate t =
  Hashtbl.reset t.nodes;
  List.iter
    (fun id ->
      match compute_node_a11y t id with
      | Some r -> Hashtbl.replace t.nodes id r
      | None -> ())
    (Lui_store.preorder t.store);
  rebuild_roots t

let of_store store =
  let t = { store; nodes = Hashtbl.create 64; roots = []; focused = None } in
  populate t;
  t

let store t = t.store
let root_ids t = t.roots
let node_count t = Hashtbl.length t.nodes
let mem t id = Hashtbl.mem t.nodes id
let find t id = Hashtbl.find_opt t.nodes id

let roots t = List.filter_map (Hashtbl.find_opt t.nodes) t.roots
let build store = roots (of_store store)

let flatten t =
  let rec collect acc id =
    match Hashtbl.find_opt t.nodes id with
    | None -> acc
    | Some n -> List.fold_left collect (n :: acc) n.children
  in
  List.rev (List.fold_left collect [] t.roots)

(* ---------- incremental update ---------- *)

(* The work set for a dirty-id batch: each dirty id, its old a11y subtree
   (catches dropped or newly hidden descendants), its store subtree
   (catches newly visible descendants), and both ancestor chains
   (catches reparents, children-list edits and names accumulated from
   descendant text). Recomputation reads only the store, so a single
   pass over this set reconciles every derived field. *)
let update t dirty =
  let work = ref ISet.empty in
  let add id = work := ISet.add id !work in
  let add_a11y_subtree id =
    let rec walk i =
      match Hashtbl.find_opt t.nodes i with
      | Some n -> add i; List.iter walk n.children
      | None -> ()
    in
    walk id
  in
  let add_store_subtree id =
    List.iter add (Lui_store.preorder ~root:id t.store)
  in
  let rec add_store_ancestors id =
    match Lui_store.parent t.store id with
    | Some p -> add p; add_store_ancestors p
    | None -> ()
  in
  let rec add_a11y_ancestors id =
    match Hashtbl.find_opt t.nodes id with
    | Some { parent = Some p; _ } -> add p; add_a11y_ancestors p
    | _ -> ()
  in
  List.iter
    (fun id ->
      add id;
      add_a11y_subtree id;
      add_store_subtree id;
      add_store_ancestors id;
      add_a11y_ancestors id)
    dirty;
  let changed = ref ISet.empty in
  ISet.iter
    (fun id ->
      if replace_record t id (compute_node_a11y t id) then
        changed := ISet.add id !changed)
    !work;
  rebuild_roots t;
  ISet.elements !changed

let sync t = update t (Lui_store.drain_dirty t.store)

(* ---------- focus ---------- *)

let focused t = t.focused

let focused_node t =
  match t.focused with
  | Some id -> find t id
  | None -> None

let recompute_change t id =
  if replace_record t id (compute_node_a11y t id) then [ id ] else []

let set_focused t id =
  let prev = t.focused in
  t.focused <- Some id;
  let changed =
    (match prev with Some p -> recompute_change t p | None -> [])
    @ recompute_change t id
  in
  List.sort_uniq compare changed

let clear_focused t =
  match t.focused with
  | None -> []
  | Some p ->
    t.focused <- None;
    recompute_change t p
