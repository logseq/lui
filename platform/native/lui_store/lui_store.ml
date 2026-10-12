(* Retained mirror of LUI patch batches for the native backend.

   The store keeps the node tree the patch stream describes and marks
   nodes dirty as their props or children change, so paint and layout
   can invalidate incrementally. Kinds and props are keyed by their wire
   names (Lui_wire_schema names), matching the convention used elsewhere
   so a prop lookup like [bool_prop t id "enabled"] reads the same key
   every backend sees.

   Children are an intrusive doubly-linked list: a child detaches in
   O(1) through its own sibling links (no parent-wide scan), appends
   stay O(1) through the tail pointer, and index inserts walk from the
   nearer end. A wide parent losing N children one op at a time is
   O(N) total instead of the O(N^2) a compacting array paid. *)

open Lui_protocol

(* ---------- typed dirty masks ----------

   Every applied op tags the nodes it touched with a bitmask naming the
   pipeline stages that must see the change. [drain_dirty] keeps its
   flat id-list contract for existing consumers; masked drains let
   layout and paint pick only the work a change actually needs. *)

type dirty_mask = int

let d_structure = 0x01 (* produced child set/order changed *)
let d_layout = 0x02 (* own flex style or measure inputs changed *)
let d_paint = 0x04 (* scene ops changed *)
let d_semantics = 0x08 (* a11y tree *)
let d_input = 0x10 (* focus/selection/interactive state *)
(* A prop that flows into the styles or order of the node's *children*
   (grid [columns], split [value], edge-inset [edge]): layout must
   re-derive produced children, not just the node's own style. *)
let d_layout_kids = 0x20
let d_all = 0x3f

let mask_has m f = m land f <> 0

(* The props [Lui_layout] reads, directly or through a parent. Keep in
   sync with style_of/adjust/text_of/ordered_child_ids/refine_popups. *)
let layout_prop_names =
  [ "alignment"; "anchor"; "anchor-alignment"; "anchor-offset"; "x"; "y";
    "columns"; "container-relative-frame"; "container-relative-frame-inset";
    "cross"; "main"; "description"; "edge"; "flex-wrap"; "gap"; "row-gap";
    "column-gap"; "grow";
    "width"; "height"; "min-width"; "min-height"; "max-width";
    "max-height"; "width-viewport"; "height-viewport";
    "min-width-viewport"; "min-height-viewport"; "max-width-viewport";
    "max-height-viewport";
    "icon"; "inset"; "inset-top"; "inset-right"; "inset-bottom";
    "inset-left"; "label"; "margin"; "margin-top"; "margin-right";
    "margin-bottom"; "margin-left"; "margin-horizontal"; "margin-vertical";
    "orientation"; "overflow"; "padding"; "padding-horizontal";
    "padding-vertical"; "placeholder"; "position"; "selected"; "size";
    "text"; "title"; "value" ]

let layout_props =
  let t = Hashtbl.create 64 in
  List.iter (fun n -> Hashtbl.replace t n ()) layout_prop_names;
  t

(* Props whose change ripples into produced children. [display] is the
   only prop that rewrites the produced set itself (none/contents lift);
   the three rest restyle or reorder the children a parent produced. *)
let child_prop_names = [ "columns"; "value"; "edge" ]
let child_props =
  let t = Hashtbl.create 8 in
  List.iter (fun n -> Hashtbl.replace t n ()) child_prop_names;
  t

(* Pure-paint props: consumed by paint/hit-test, never by style_of or
   the measure text. Only names verified absent from [layout_props] may
   live here — a wrong entry produces a stale layout, so the list is
   kept deliberately narrow; anything unlisted falls through to the
   conservative layout|paint default. *)
let paint_prop_names =
  [ "background"; "foreground"; "opacity"; "shadow"; "corner-radius";
    "border-color"; "border-width"; "border-style"; "z-index";
    "cursor"; "caret-color"; "tint"; "image"; "name"; "src"; "fit";
    "blend-mode"; "secure"; "style-class"; "variant"; "placement";
    "autofocus"; "submit-on-enter"; "scroll-x"; "scroll-y";
    "key"; "id"; "class" ]

let paint_props =
  let t = Hashtbl.create 64 in
  List.iter (fun n -> Hashtbl.replace t n ()) paint_prop_names;
  t

(* Paint props the a11y tree also mirrors (visibility, control state,
   links): they repaint and re-semantize but never move geometry. *)
let paint_sem_prop_names =
  [ "visible"; "checked"; "indeterminate"; "href"; "target"; "rel";
    "alt"; "draggable"; "drop-target"; "tooltip" ]

let paint_sem_props =
  let t = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace t n ()) paint_sem_prop_names;
  t

(* Interactive-state channels. Hover/pressed/selected/disabled state
   variants are paint-only (the bare "selected" stays layout: a drawer's
   selected prop moves it in and out of popup flow). *)
let state_prefixes = [ "hover-"; "pressed-"; "selected-"; "disabled-"; "focus-" ]

let has_prefix s p =
  let n = String.length p in
  String.length s >= n && String.sub s 0 n = p

(* Semantics-only props: the a11y tree cares, paint and layout do not. *)
let semantics_prop_names =
  [ "accessibility-label"; "accessibility-identifier"; "role"; "expanded";
    "level"; "sort" ]

let semantics_props =
  let t = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace t n ()) semantics_prop_names;
  t

(* Focus/selection/input-channel props. *)
let input_prop_names =
  [ "enabled"; "disabled"; "focus"; "focused"; "selection";
    "selection-start"; "selection-end"; "input-mode"; "readonly" ]

let input_props =
  let t = Hashtbl.create 16 in
  List.iter (fun n -> Hashtbl.replace t n ()) input_prop_names;
  t

(* Wire prop name -> dirty mask. Unknown and extension props land on
   the conservative default: a missed layout bit is a stale frame, a
   superfluous one only costs a style recompute. *)
let mask_of_prop name : dirty_mask =
  if name = "display" then d_structure lor d_layout lor d_paint
  else if Hashtbl.mem child_props name then d_layout_kids lor d_layout lor d_paint
  else if Hashtbl.mem layout_props name then d_layout lor d_paint
  else if Hashtbl.mem semantics_props name then d_semantics
  else if Hashtbl.mem input_props name then d_input lor d_paint lor d_semantics
  else if List.exists (has_prefix name) state_prefixes then d_paint lor d_semantics
  else if Hashtbl.mem paint_sem_props name then d_paint lor d_semantics
  else if Hashtbl.mem paint_props name then d_paint
  else d_layout lor d_paint

(* ---------- store ---------- *)

type node = {
  id : int;
  kind : string; (* node_kind_name, or "extension:<identifier>" *)
  mutable ext_id : string option;
  props : (string, wire_value) Hashtbl.t;
  mutable parent : int option;
  (* Intrusive child list: [first_child]/[last_child] own the endpoints,
     [prev_sib]/[next_sib] let a child unlink itself in O(1). *)
  mutable first_child : node option;
  mutable last_child : node option;
  mutable child_count : int;
  mutable prev_sib : node option;
  mutable next_sib : node option;
  mutable revision : int; (* last store revision that touched this node *)
}

(* One journal entry: the store revision right after the op applied and
   the op itself. Consumers replay ops since their last seen revision to
   update their own mirrors incrementally. *)
type change = { crev : int; cop : patch_op }

type t = {
  nodes : (int, node) Hashtbl.t;
  dirty : (int, dirty_mask) Hashtbl.t;
  mutable generation : int;
  mutable revision : int;
  (* Bumped only by ops that can move geometry (structure, layout and
     layout-kids bits). The layout memo keys on it so pure paint churn
     leaves the flex mirror untouched. *)
  mutable layout_rev : int;
  journal : change Queue.t;
  mutable journal_len : int;
  (* Journal completeness: every op whose [crev] exceeds
     [journal_base] is queued. When the cap drops entries the base moves
     to the oldest surviving revision, so [changes_since] for an older
     cursor reports [None] and the consumer rebuilds. *)
  mutable journal_base : int;
}

let journal_cap = 8192

let create () =
  { nodes = Hashtbl.create 64; dirty = Hashtbl.create 64;
    generation = 0; revision = 0; layout_rev = 0;
    journal = Queue.create (); journal_len = 0; journal_base = -1 }

let node_count t = Hashtbl.length t.nodes
let generation t = t.generation
let revision t = t.revision
let layout_rev t = t.layout_rev
let find_opt t id = Hashtbl.find_opt t.nodes id
let mem t id = Hashtbl.mem t.nodes id

(* Ops newer than [rev], oldest first. [None] when the journal no
   longer reaches back to [rev] — the caller must resync wholesale.
   Passing the store's current revision yields [Some []]. *)
let changes_since t rev : patch_op list option =
  if rev < t.journal_base then None
  else Some (Queue.fold (fun acc c -> if c.crev > rev then c.cop :: acc else acc) [] t.journal |> List.rev)

(* Every store mutation ends here: revision bumps once per mark so a
   batch of marks keeps a strictly increasing clock. *)
let mark_dirty_mask t id m =
  t.revision <- t.revision + 1;
  if m land (d_structure lor d_layout lor d_layout_kids) <> 0 then
    t.layout_rev <- t.layout_rev + 1;
  Hashtbl.replace t.dirty id
    (match Hashtbl.find_opt t.dirty id with
     | Some old -> old lor m
     | None -> m);
  match Hashtbl.find_opt t.nodes id with
  | Some (n : node) -> n.revision <- t.revision
  | None -> ()

(* Ids touched since the last drain, in application order (unstable). *)
let drain_dirty t =
  let ids = Hashtbl.fold (fun id _ acc -> id :: acc) t.dirty [] in
  Hashtbl.reset t.dirty;
  List.sort compare ids

(* Same drain, with the accumulated mask per id. *)
let drain_dirty_masked t =
  let ids = Hashtbl.fold (fun id m acc -> (id, m) :: acc) t.dirty [] in
  Hashtbl.reset t.dirty;
  List.sort (fun a b -> compare (fst a) (fst b)) ids

let peek_dirty t id = Hashtbl.mem t.dirty id
let peek_dirty_mask t id = Option.value ~default:0 (Hashtbl.find_opt t.dirty id)

let new_node id kind =
  { id; kind; ext_id = None; props = Hashtbl.create 8; parent = None;
    first_child = None; last_child = None; child_count = 0;
    prev_sib = None; next_sib = None; revision = 0 }

(* ---------- intrusive child list ---------- *)

let node_children_list n =
  (* Iterative walk + one reverse: a 100k-wide sibling list must not
     recurse per element. *)
  let acc = ref [] in
  let cur = ref n.first_child in
  while !cur <> None do
    let c = Option.get !cur in
    acc := c :: !acc;
    cur := c.next_sib
  done;
  List.rev !acc

(* Detach [c] from its recorded parent's list. O(1): the sibling links
   carry the position. Callers fix [c.parent] themselves — this only
   cuts the links. *)
let unlink (p : node) (c : node) =
  (match c.prev_sib with
   | Some s -> s.next_sib <- c.next_sib
   | None -> p.first_child <- c.next_sib);
  (match c.next_sib with
   | Some s -> s.prev_sib <- c.prev_sib
   | None -> p.last_child <- c.prev_sib);
  p.child_count <- p.child_count - 1;
  c.prev_sib <- None;
  c.next_sib <- None

let push_back (p : node) (c : node) =
  c.prev_sib <- p.last_child;
  c.next_sib <- None;
  (match p.last_child with
   | Some l -> l.next_sib <- Some c
   | None -> p.first_child <- Some c);
  p.last_child <- Some c;
  p.child_count <- p.child_count + 1

let push_front (p : node) (c : node) =
  c.next_sib <- p.first_child;
  c.prev_sib <- None;
  (match p.first_child with
   | Some f -> f.prev_sib <- Some c
   | None -> p.last_child <- Some c);
  p.first_child <- Some c;
  p.child_count <- p.child_count + 1

(* Insert before the element at [index], clamped like list insert_at:
   i <= 0 prepends, i >= count appends. Walks from the nearer end. *)
let insert_at (p : node) (c : node) index =
  if index <= 0 then push_front p c
  else if index >= p.child_count then push_back p c
  else begin
    let rec nth_front i n =
      match (i, n) with
      | 0, cur -> cur
      | i, Some cur -> nth_front (i - 1) cur.next_sib
      | _, None -> None
    in
    let rec nth_back i n =
      match (i, n) with
      | 0, cur -> cur
      | i, Some cur -> nth_back (i + 1) cur.prev_sib
      | _, None -> None
    in
    (* Walk to the node currently at [index]. *)
    let target =
      if index <= p.child_count / 2 then nth_front index p.first_child
      else nth_back (index - p.child_count + 1) p.last_child
    in
    match target with
    | Some at ->
      c.prev_sib <- at.prev_sib;
      c.next_sib <- Some at;
      (match at.prev_sib with
       | Some s -> s.next_sib <- Some c
       | None -> p.first_child <- Some c);
      at.prev_sib <- Some c;
      p.child_count <- p.child_count + 1
    | None -> push_back p c
  end

(* Drop a subtree: remove every descendant from the table and unlink the
   node from its parent. Marks the parent's children changed and every
   removed id dirty so repaint can forget it. Children are detached
   from the doomed parent in O(1) each by clearing their parent link
   before the recursive drop — the parent's list is discarded wholesale
   rather than unlinked child by child. *)
let rec drop t id =
  match Hashtbl.find_opt t.nodes id with
  | None -> ()
  | Some node ->
    List.iter
      (fun (c : node) ->
        c.parent <- None;
        drop t c.id)
      (node_children_list node);
    node.first_child <- None;
    node.last_child <- None;
    node.child_count <- 0;
    (match node.parent with
     | Some pid -> (
       match Hashtbl.find_opt t.nodes pid with
       | Some p ->
         unlink p node;
         mark_dirty_mask t pid (d_structure lor d_layout lor d_paint)
       | None -> ())
     | None -> ());
    Hashtbl.remove t.nodes id;
    mark_dirty_mask t id (d_structure lor d_paint)

(* Insert child at index within parent, detaching it from its previous
   parent first so a move never leaves the id listed twice.

   The detach consults the child's recorded parent instead of scanning
   the target's children: [c.parent = None] means the id sits in no
   child list, so the common first-attach path skips any walk. *)
let insert_child t parent child index =
  match (Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child) with
  | Some p, Some c ->
    (match c.parent with
     | Some pid -> (
       match Hashtbl.find_opt t.nodes pid with
       | Some op ->
         unlink op c;
         if pid <> parent then
           mark_dirty_mask t pid (d_structure lor d_layout lor d_paint)
       | None -> ())
     | None -> ());
    insert_at p c index;
    c.parent <- Some parent;
    mark_dirty_mask t parent (d_structure lor d_layout lor d_paint);
    mark_dirty_mask t child (d_structure lor d_paint)
  | _ -> ()

let journal_push t op =
  Queue.push { crev = t.revision; cop = op } t.journal;
  t.journal_len <- t.journal_len + 1;
  while t.journal_len > journal_cap do
    let dropped = Queue.pop t.journal in
    t.journal_len <- t.journal_len - 1;
    (* Entries that survived are complete only back to just after the
       dropped one's revision: ops that shared its revision may have
       fallen out with it, so the base must sit strictly below the
       oldest surviving entry but above the dropped one. *)
    t.journal_base <- dropped.crev
  done

let apply_op t = function
  | CreateNode (id, k) as op ->
    (* Recreate must drop the previous subtree first: a bare
       Hashtbl.replace leaves former children with parent=Some id while
       the new node starts with an empty child list — orphans. *)
    if Hashtbl.mem t.nodes id then drop t id;
    Hashtbl.replace t.nodes id (new_node id (Lui_wire_schema.node_kind_name k));
    mark_dirty_mask t id d_all;
    journal_push t op
  | CreateExtension (id, identifier, _fp) as op ->
    if Hashtbl.mem t.nodes id then drop t id;
    let n = new_node id ("extension:" ^ identifier) in
    n.ext_id <- Some identifier;
    Hashtbl.replace t.nodes id n;
    mark_dirty_mask t id d_all;
    journal_push t op
  | (DropNode id | DetachSubtree id) as op ->
    drop t id;
    journal_push t op
  | SetProp (id, p, v) as op -> (
    let name = Lui_wire_schema.property_name p in
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.replace n.props name v;
      mark_dirty_mask t id (mask_of_prop name)
    | None -> ());
    journal_push t op
  | RemoveProp (id, p) as op -> (
    let name = Lui_wire_schema.property_name p in
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.remove n.props name;
      mark_dirty_mask t id (mask_of_prop name)
    | None -> ());
    journal_push t op
  | SetExtensionProp (id, name, v) as op -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.replace n.props name v;
      mark_dirty_mask t id d_all
    | None -> ());
    journal_push t op
  | RemoveExtensionProp (id, name) as op -> (
    match Hashtbl.find_opt t.nodes id with
    | Some n ->
      Hashtbl.remove n.props name;
      mark_dirty_mask t id d_all
    | None -> ());
    journal_push t op
  | (InsertChild (parent, child, index) | MoveChild (parent, child, index)) as op ->
    insert_child t parent child index;
    journal_push t op
  | RemoveChild (parent, child) as op -> (
    match (Hashtbl.find_opt t.nodes parent, Hashtbl.find_opt t.nodes child) with
    | Some p, Some c ->
      if c.parent = Some parent then (
        unlink p c;
        c.parent <- None)
      else begin
        (* Defensive scan: the child claims a different parent but the
           op names this one — walk the list and cut any matching link
           so a stale record cannot leave the id listed twice. *)
        let rec scan prev cur =
          match cur with
          | None -> ()
          | Some c' ->
            if c'.id = child then (
              let next = c'.next_sib in
              (match prev with
               | Some s -> s.next_sib <- next
               | None -> p.first_child <- next);
              (match next with
               | Some s -> s.prev_sib <- prev
               | None -> p.last_child <- prev);
              p.child_count <- p.child_count - 1;
              c'.prev_sib <- None;
              c'.next_sib <- None)
            else scan cur c'.next_sib
        in
        scan None p.first_child;
        c.parent <- None
      end;
      mark_dirty_mask t parent (d_structure lor d_layout lor d_paint);
      mark_dirty_mask t child (d_structure lor d_paint)
    | _ -> ());
    journal_push t op

let apply_batch t (batch : patch_batch) =
  t.generation <- batch.generation;
  List.iter (apply_op t) batch.ops

(* ---------- queries ---------- *)

let node_id n = n.id
let node_kind n = n.kind
let node_ext_id n = n.ext_id
let node_parent n = n.parent
let node_children n = List.map node_id (node_children_list n)
let node_prop n name = Hashtbl.find_opt n.props name
let node_revision (n : node) = n.revision
let node_child_count n = n.child_count

let kind t id = match find_opt t id with Some n -> n.kind | None -> ""
let is_editable_text_kind = function
  | "text-field" | "secure-field" | "input" | "search-field"
  | "textarea" -> true
  | _ -> false

let ext_id t id = match find_opt t id with Some n -> n.ext_id | None -> None
let parent t id = match find_opt t id with Some n -> n.parent | None -> None
let children t id =
  match find_opt t id with
  | Some n -> node_children_list n
  | None -> []

let child_ids t id =
  match find_opt t id with
  | Some n -> List.map node_id (node_children_list n)
  | None -> []

let last_child_id t id =
  match find_opt t id with
  | Some n -> Option.map node_id n.last_child
  | None -> None
let child_count t id =
  match find_opt t id with Some n -> n.child_count | None -> 0
let prop t id name =
  match find_opt t id with
  | Some n -> Hashtbl.find_opt n.props name
  | None -> None

let bool_prop t id name = match prop t id name with Some (BoolValue b) -> b | _ -> false
let string_prop t id name = match prop t id name with Some (StringValue s) -> Some s | _ -> None
let float_prop t id name = match prop t id name with Some (FloatValue f) -> Some f | _ -> None
let int_prop t id name = match prop t id name with Some (IntValue i) -> Some i | _ -> None

let rec depth t id =
  match find_opt t id with
  | Some { parent = Some p; _ } -> 1 + depth t p
  | _ -> 0

(* Ids whose parent chain reaches no stored node: the forest roots. *)
let root_ids t =
  Hashtbl.fold
    (fun id n acc ->
      match n.parent with
      | None -> id :: acc
      | Some pid when not (Hashtbl.mem t.nodes pid) -> id :: acc
      | Some _ -> acc)
    t.nodes []
  |> List.sort compare

(* Preorder ids under [root] (or the whole forest when None). *)
let preorder ?root t =
  let rec walk id acc =
    match find_opt t id with
    | None -> acc
    | Some n ->
      let acc = id :: acc in
      List.fold_left (fun a c -> walk c.id a) acc (node_children_list n)
  in
  let roots = match root with Some id -> [ id ] | None -> root_ids t in
  List.rev (List.fold_left (fun acc id -> walk id acc) [] roots)

let all_nodes t =
  Hashtbl.fold (fun _ n acc -> n :: acc) t.nodes []
  |> List.sort (fun a b -> compare a.id b.id)
