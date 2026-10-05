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

(* Names for the destructured signal values: v2 .. vn. *)
let vname i = Printf.sprintf "v%d" i

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

class mapper =
  object
    inherit Ast_traverse.map as super

    method! expression expr =
      match expr.pexp_desc with
      | Pexp_apply (fn, args)
        when is_reactive_ident fn && dyn_supported args ->
          (* bare `reactive` at expression position: dyn over the signal *)
          super#expression (dyn_expand ~loc:expr.pexp_loc args)
      | Pexp_apply (fn, args) ->
          (* labelled `~p:(reactive …)`: rewrite the label first so the
             inner `reactive` is consumed here rather than revisited as a
             bare dyn expansion when super descends *)
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
                   when not (ends_with name "_signal")
                        && List.for_all
                             (fun ((l : arg_label), _) -> l = Nolabel)
                             rest ->
                     (match rest with
                      | [ (Nolabel, source) ] ->
                          (* reactive f src *)
                          ( Labelled (name ^ "_signal"),
                            apply ~loc:arg.pexp_loc
                              (signal_map arg.pexp_loc) [ first; source ] )
                      | [] ->
                          (* reactive src: the arg itself is the signal *)
                          (Labelled (name ^ "_signal"), first)
                      | _ ->
                          (* reactive f s1 s2 .. sn *)
                          let sources =
                            List.map snd rest
                          in
                          ( Labelled (name ^ "_signal"),
                            expand ~loc:arg.pexp_loc first sources ))
                 | _ -> (label, arg))
              args
          in
          super#expression { expr with pexp_desc = Pexp_apply (fn, args) }
      | _ -> super#expression expr
  end

let () =
  Driver.register_transformation ~impl:(new mapper)#structure "lui_ppx"
