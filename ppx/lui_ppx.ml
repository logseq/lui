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
  match rest with
  | [ (Nolabel, f); (Nolabel, s) ] ->
      (* reactive f src: dyn over src with the default (=) *)
      dyn_call ~loc ?equal [ f; s ]
  | [ (Nolabel, s) ] ->
      (* reactive src: the signal itself publishes elements; (==) avoids
         structural equality on mount closures *)
      let equal =
        match equal with
        | Some e -> e
        | None -> B.pexp_ident ~loc { txt = Lident "=="; loc }
      in
      let id = lam ~loc [ pvar ~loc "__x" ] (evar ~loc "__x") in
      dyn_call ~loc ~equal [ id; s ]
  | (Nolabel, f) :: sources_args
    when List.length sources_args >= 2
         && List.for_all
              (fun ((l : arg_label), _) -> l = Nolabel)
              sources_args ->
      (* reactive f s1 s2 .. sn: dyn over the combined tuple signal *)
      let sources = List.map snd sources_args in
      let names = List.init (List.length sources) (fun i -> vname (i + 1)) in
      let fn' =
        lam ~loc
          [ B.ppat_tuple ~loc (List.map (pvar ~loc) names) ]
          (apply ~loc f (List.map (evar ~loc) names))
      in
      dyn_call ~loc ?equal [ fn'; tuple_signal ~loc 1 sources ]
  | _ -> assert false

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

let scoped_expression ~loc build =
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
    { txt = Ldot (Lident "Lui_elements", "scoped"); loc } in
  apply ~loc scoped [lam ~loc [pvar ~loc context] (build own_generated)]

let structural_constructor expression = match expression.pexp_desc with
  | Pexp_ident { txt = Lident ("if_" | "keyed")
      | Ldot (Lident "Lui_elements", ("if_" | "keyed")); _ } -> true
  | _ -> false

class mapper =
  object
    inherit Ast_traverse.map as super

    method! expression expr =
      match expr.pexp_desc with
      | Pexp_apply (fn, args)
        when is_reactive_ident fn && dyn_supported args ->
          (* bare `reactive` at expression position: dyn over the signal *)
          let expanded = dyn_expand ~loc:expr.pexp_loc args in
          if List.length (List.filter (fun (label, _) -> label = Nolabel) args) > 2 then
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
                || (structural_constructor fn && List.length positional = 2) ->
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
                          || structural_constructor fn then begin
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
            let scoped = scoped_expression ~loc:expr.pexp_loc (transform constructor_args) in
            if mount_args = [] then scoped
            else B.pexp_apply ~loc:expr.pexp_loc scoped
              (List.map (fun (label, argument) -> label, super#expression argument) mount_args)
          else plain
      | _ -> super#expression expr
  end

let () =
  Driver.register_transformation ~impl:(new mapper)#structure "lui_ppx"
