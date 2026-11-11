(* lui_ppx: rewrites the `reactive` marker in two positions.

   Labelled argument (prop position):
   ~p:(reactive f src)         ->  ~p_signal:(Signal.map f src)
   ~p:(reactive f s1 s2)       ->  ~p_signal:(Signal.map2 f s1 s2)
   ~p:(reactive f s1 .. sn)    ->  ~p_signal:(Signal.map2 f' s1 rest)
      where rest combines s2 .. sn into a tuple via nested map2 calls.
   ~p:(reactive src)           ->  ~p_signal:src

   Bare expression (children/element position — mounts a reactive subtree):
   reactive f src              ->  Lui_elements.dyn f src
   reactive src                ->  Lui_elements.dyn ~equal:(==) (fun __x -> __x) src
   reactive f s1 s2 .. sn      ->  Lui_elements.dyn (fun (v1,..,vn) -> f v1 .. vn)
                                     (Signal.map2 (fun v1 .. -> (v1, ..)) s1 rest)

   Labels already ending in "_signal" are left alone. *)

open Ppxlib

module B = Ast_builder.Default
module Bound_names = Set.Make (String)

let signal_map loc =
  B.pexp_ident ~loc { txt = Ldot (Lident "Signal", "map"); loc }

let signal_map2 loc =
  B.pexp_ident ~loc { txt = Ldot (Lident "Signal", "map2"); loc }

let evar ~loc name = B.pexp_ident ~loc { txt = Lident name; loc }
let pvar ~loc name = B.pvar ~loc name

let apply ~loc fn args =
  B.pexp_apply ~loc fn (List.map (fun a -> (Nolabel, a)) args)

let lam ~loc pats body =
  List.fold_right (B.pexp_fun ~loc Nolabel None) pats body

(* Fresh names prevent generated binders from capturing the user's closures. *)
let vname _index = gen_symbol ~prefix:"__lui_signal_" ()

(* [tuple_signal loc ~start sources] builds a signal publishing the tuple
   (v_start .. v_n) for two or more sources. *)
let rec tuple_signal ~loc start = function
  | [ s1; s2 ] ->
      let a, b = vname start, vname (start + 1) in
      apply ~loc (signal_map2 loc)
        [ lam ~loc [ pvar ~loc a; pvar ~loc b ]
            (B.pexp_tuple ~loc [ evar ~loc a; evar ~loc b ]);
          s1; s2 ]
  | s :: rest ->
      let a = vname start in
      let names = List.init (List.length rest) (fun i -> vname (start + 1 + i)) in
      let tuple_pat =
        B.ppat_tuple ~loc (List.map (pvar ~loc) names)
      in
      apply ~loc (signal_map2 loc)
        [ lam ~loc [ pvar ~loc a; tuple_pat ]
            (B.pexp_tuple ~loc
               (evar ~loc a :: List.map (evar ~loc) names));
          s; tuple_signal ~loc (start + 1) rest ]
  | _ -> assert false

(* [expand loc f sources] desugars `reactive f s1 .. sn` (n >= 2). *)
let expand ~loc f sources =
  match sources with
  | [ s1; s2 ] -> apply ~loc (signal_map2 loc) [ f; s1; s2 ]
  | s1 :: rest ->
      let n = 1 + List.length rest in
      let names = List.init n (fun i -> vname (i + 1)) in
      let rest_pats =
        B.ppat_tuple ~loc (List.map (pvar ~loc) (List.tl names))
      in
      apply ~loc (signal_map2 loc)
        [ lam ~loc [ pvar ~loc (List.hd names); rest_pats ]
            (apply ~loc f (List.map (evar ~loc) names));
          s1; tuple_signal ~loc 2 rest ]
  | _ -> assert false

let ends_with s suffix =
  let ls, lf = String.length s, String.length suffix in
  ls >= lf && String.sub s (ls - lf) lf = suffix

let is_reactive_ident (e : expression) =
  match e.pexp_desc with
  | Pexp_ident { txt = Lident "reactive"; _ } -> true
  | _ -> false

let dyn_ident ~loc =
  B.pexp_ident ~loc { txt = Ldot (Lident "Lui_elements", "dyn"); loc }

let dyn_call ~loc ?equal args =
  B.pexp_apply ~loc (dyn_ident ~loc)
    ((match equal with
     | Some e -> [ (Labelled "equal", e) ]
     | None -> [])
    @ List.map (fun a -> (Nolabel, a)) args)

(* A direct nested source is a signal projection, rather than another mounted
   subtree. Only this unambiguous source position consumes the nested marker. *)
let derived_source expression =
  match expression.pexp_desc with
  | Pexp_apply (fn, (Nolabel, project) :: sources)
    when is_reactive_ident fn && sources <> []
      && List.for_all (fun (label, _) -> label = Nolabel) sources ->
      let loc = expression.pexp_loc in
      Some (match List.map snd sources with
        | [source] -> apply ~loc (signal_map loc) [project; source]
        | sources -> expand ~loc project sources)
  | _ -> None

(* [dyn_expand loc args] desugars a bare `reactive` call at expression
   position (a mounted child) into [Lui_elements.dyn]; an optional
   [~equal] passes through to the comparator. *)
let dyn_expand ~loc args =
  let equal_arg, rest =
    List.partition
      (fun ((l : arg_label), _) -> l = Labelled "equal")
      args
  in
  let equal =
    match equal_arg with
    | [ (_, e) ] -> Some e
    | _ -> None
  in
  let has_derived_source = ref false in
  let source expression =
    match derived_source expression with
    | Some projected -> has_derived_source := true; projected
    | None -> expression in
  let expanded = match rest with
  | [ (Nolabel, f); (Nolabel, s) ] ->
      (* reactive f src: dyn over src with the default (=) *)
      dyn_call ~loc ?equal [ f; source s ]
  | [ (Nolabel, s) ] ->
      (* reactive src: the signal itself publishes elements; (==) avoids
         structural equality on mount closures *)
      let equal =
        match equal with
        | Some e -> e
        | None -> B.pexp_ident ~loc { txt = Lident "=="; loc }
      in
      let id = lam ~loc [ pvar ~loc "__x" ] (evar ~loc "__x") in
      dyn_call ~loc ~equal [ id; source s ]
  | (Nolabel, f) :: sources_args
    when List.length sources_args >= 2
         && List.for_all
              (fun ((l : arg_label), _) -> l = Nolabel)
              sources_args ->
      (* reactive f s1 s2 .. sn: dyn over the combined tuple signal *)
      let sources = List.map (fun (_, expression) -> source expression) sources_args in
      let names = List.init (List.length sources) (fun i -> vname (i + 1)) in
      let fn' =
        lam ~loc
          [ B.ppat_tuple ~loc (List.map (pvar ~loc) names) ]
          (apply ~loc f (List.map (evar ~loc) names))
      in
      dyn_call ~loc ?equal [ fn'; tuple_signal ~loc 1 sources ]
  | _ -> assert false in
  expanded, !has_derived_source

(* Bare `reactive` calls this file can desugar; anything else (0 args,
   unexpected labels) is left untouched so the type error points at the
   call site. *)
let dyn_supported args =
  let equal_args, rest =
    List.partition
      (fun ((l : arg_label), _) -> l = Labelled "equal")
      args
  in
  List.length equal_args <= 1
  &&
  match rest with
  | [ (Nolabel, _); (Nolabel, _) ] | [ (Nolabel, _) ] -> true
  | (Nolabel, _) :: rest_args ->
      List.length rest_args >= 2
      && List.for_all
           (fun ((l : arg_label), _) -> l = Nolabel)
           rest_args
  | _ -> false

(* Labels whose only value is a signal — there is no static twin, so
   `~test:(reactive f s)` stays `~test:(Signal.map f s)` instead of
   becoming a nonexistent `~test_signal:` parameter. *)
let signal_only_labels = [ "test"; "source" ]

let scoped_expression ~loc ?(helper = "scoped") build =
  let context = gen_symbol ~prefix:"__lui_context_" () in
  let scope = B.pexp_field ~loc (evar ~loc context)
    { txt = Ldot (Lident "Lui_ui", "ui_scope"); loc } in
  let own_generated = object
    inherit Ast_traverse.map as super
    method! expression expression =
      let expression = super#expression expression in
      match expression.pexp_desc with
      | Pexp_apply ({ pexp_desc = Pexp_ident
          { txt = Ldot (Lident "Signal", ("map" | "map2")); _ }; _ }, _) ->
        apply ~loc (B.pexp_ident ~loc
          { txt = Ldot (Lident "Signal", "own_signal"); loc }) [scope; expression]
      | _ -> expression
  end in
  let scoped = B.pexp_ident ~loc
    { txt = Ldot (Lident "Lui_elements", helper); loc } in
  apply ~loc scoped [lam ~loc [pvar ~loc context] (build own_generated)]

let constructor_name expression = match expression.pexp_desc with
  | Pexp_ident { txt = Lident name | Ldot (Lident "Lui_elements", name); _ } ->
      Some name
  | _ -> None

let typed_family = function
  | "step" | "keyed_step" -> Some "step"
  | "timeline_item" | "keyed_timeline_item" -> Some "timeline_item"
  | "bottom_tab" | "keyed_bottom_tab" -> Some "bottom_tab"
  | "table_row" | "keyed_table_row" -> Some "table_row"
  | "table_cell" | "keyed_table_cell" -> Some "table_cell"
  | "radio" | "keyed_radio" -> Some "radio"
  | "input_group_actions" -> Some "input_group_actions"
  | "swipe_action" | "keyed_swipe_action" -> Some "swipe_action"
  | _ -> None

let unshadowed_name bound expression =
  match expression.pexp_desc with
  | Pexp_ident { txt = Lident name; _ } when Bound_names.mem name bound -> None
  | _ -> constructor_name expression

let scope_helper bound expression =
  match Option.bind (unshadowed_name bound expression) typed_family with
  | Some family -> "scoped_" ^ family
  | None -> "scoped"

let structural_constructor bound expression =
  match unshadowed_name bound expression with
  | Some ("if_" | "keyed" | "virtual_rows" | "keyed_step"
      | "keyed_timeline_item" | "keyed_bottom_tab" | "keyed_table_row"
      | "keyed_table_cell" | "keyed_radio" | "keyed_swipe_action") -> true
  | _ -> false

let without_element_names bound =
  Bound_names.filter (fun name ->
    typed_family name = None &&
    not (List.mem name ["if_"; "keyed"; "virtual_rows"])) bound

(* Local values with DSL names still use the generic scope contract. *)
let pattern_names pattern =
  let names = ref Bound_names.empty in
  let collect = object
    inherit Ast_traverse.iter as super
    method! pattern pattern =
      (match pattern.ppat_desc with
      | Ppat_var name | Ppat_alias (_, name) ->
          names := Bound_names.add name.txt !names
      | _ -> ());
      super#pattern pattern
  end in
  collect#pattern pattern;
  !names

class mapper =
  let bound = ref Bound_names.empty in
  let with_bound names build =
    let previous = !bound in
    bound := Bound_names.union previous names;
    Fun.protect build ~finally:(fun () -> bound := previous)
  in
  object (self)
    inherit Ast_traverse.map as super

    method! structure items =
      let previous = !bound in
      Fun.protect (fun () -> List.map (fun item ->
        match item.pstr_desc with
        | Pstr_value (recursive, bindings) ->
            let names = List.fold_left (fun names binding ->
              Bound_names.union names (pattern_names binding.pvb_pat))
              Bound_names.empty bindings in
            let mapped = match recursive with
              | Recursive -> with_bound names (fun () -> super#structure_item item)
              | Nonrecursive -> super#structure_item item in
            bound := Bound_names.union !bound names;
            mapped
        | Pstr_open { popen_expr = { pmod_desc = Pmod_ident
            { txt = Lident "Lui_elements"; _ }; _ }; _ } ->
            bound := without_element_names !bound;
            super#structure_item item
        | _ -> super#structure_item item) items)
        ~finally:(fun () -> bound := previous)

    method! case case =
      with_bound (pattern_names case.pc_lhs) (fun () -> super#case case)

    method! expression expr =
      match expr.pexp_desc with
      | Pexp_let (recursive, bindings, body) ->
          let names = List.fold_left (fun names binding ->
            Bound_names.union names (pattern_names binding.pvb_pat))
            Bound_names.empty bindings in
          let map_bindings () = List.map (super#value_binding) bindings in
          let bindings = match recursive with
            | Recursive -> with_bound names map_bindings
            | Nonrecursive -> map_bindings () in
          let body = with_bound names (fun () -> self#expression body) in
          { expr with pexp_desc = Pexp_let (recursive, bindings, body) }
      | Pexp_open (({ popen_expr = { pmod_desc = Pmod_ident
          { txt = Lident "Lui_elements"; _ }; _ }; _ } as opened), body) ->
          let previous = !bound in
          bound := without_element_names previous;
          let body = Fun.protect (fun () -> self#expression body)
            ~finally:(fun () -> bound := previous) in
          { expr with pexp_desc = Pexp_open (opened, body) }
      | Pexp_function (parameters, constraint_, body) ->
          let previous = !bound in
          Fun.protect (fun () ->
            let parameters = List.map (fun parameter ->
              (* Defaults see earlier parameters, not their own binding. *)
              let parameter = super#function_param parameter in
              (match parameter.pparam_desc with
              | Pparam_val (_, _, pattern) ->
                  bound := Bound_names.union !bound (pattern_names pattern)
              | Pparam_newtype _ -> ());
              parameter) parameters in
            let constraint_ = Option.map (self#type_constraint) constraint_ in
            let body = self#function_body body in
            { expr with pexp_desc = Pexp_function (parameters, constraint_, body) })
            ~finally:(fun () -> bound := previous)
      | Pexp_apply (fn, args)
        when is_reactive_ident fn && dyn_supported args ->
          (* bare `reactive` at expression position: dyn over the signal *)
          let expanded, has_derived_source = dyn_expand ~loc:expr.pexp_loc args in
          if has_derived_source || List.length (List.filter (fun (label, _) -> label = Nolabel) args) > 2 then
            scoped_expression ~loc:expr.pexp_loc (fun owner ->
              super#expression (owner#expression expanded))
          else super#expression expanded
      | Pexp_apply (fn, args) ->
          (* labelled `~p:(reactive …)`: rewrite the label first so the
             inner `reactive` is consumed here rather than revisited as a
             bare dyn expansion when super descends *)
          let needs_scope = ref false in
          (* A constructor may already be applied to its mount context and
             parent. Scope the view builder, then preserve that application;
             wrapping the final node id would change the expression's type. *)
          let positional = List.filter (fun (label, _) -> label = Nolabel) args in
          let constructor_args, mount_args =
            match List.rev args with
            | (Nolabel, parent) :: (Nolabel, context) :: reversed
              when List.length positional >= 3
                || (structural_constructor !bound fn && List.length positional = 2) ->
              List.rev reversed, [Nolabel, context; Nolabel, parent]
            | _ -> args, [] in
          let transform arguments owner =
          let args =
            List.map
              (fun ((label : arg_label), arg) ->
                 match label, arg.pexp_desc with
                 | ( Labelled name,
                     Pexp_apply
                       ( { pexp_desc =
                             Pexp_ident { txt = Lident "reactive"; _ };
                           _ },
                         (Nolabel, first) :: rest ) )
                   when List.for_all
                          (fun ((l : arg_label), _) -> l = Nolabel)
                          rest ->
                     let target =
                       if List.mem name signal_only_labels
                          || ends_with name "_signal"
                       then name
                       else name ^ "_signal"
                     in
                     let own expression =
                       if not (List.mem name signal_only_labels)
                          || structural_constructor !bound fn then begin
                         needs_scope := true;
                         owner#expression expression
                       end else expression in
                     (match rest with
                      | [ (Nolabel, source) ] ->
                          (* reactive f src *)
                          ( Labelled target,
                            own (apply ~loc:arg.pexp_loc
                              (signal_map arg.pexp_loc) [ first; source ]) )
                      | [] ->
                          (* reactive src: the arg itself is the signal *)
                          (Labelled target, first)
                      | _ ->
                          (* reactive f s1 s2 .. sn *)
                          let sources =
                            List.map snd rest
                          in
                          ( Labelled target,
                            own (expand ~loc:arg.pexp_loc first sources) ))
                 | _ -> (label, arg))
              arguments
          in
          super#expression { expr with pexp_desc = Pexp_apply (fn, args) } in
          let plain = transform args (new Ast_traverse.map) in
          if !needs_scope then
            let scoped = scoped_expression ~loc:expr.pexp_loc
              ~helper:(scope_helper !bound fn) (transform constructor_args) in
            if mount_args = [] then scoped
            else B.pexp_apply ~loc:expr.pexp_loc scoped
              (List.map (fun (label, argument) -> label, super#expression argument) mount_args)
          else plain
      | _ -> super#expression expr
  end

let () =
  Driver.register_transformation
    ~impl:(fun structure ->
      Lui_nesting.check structure;
      (new mapper)#structure structure)
    "lui_ppx"
