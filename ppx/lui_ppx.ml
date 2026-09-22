(* lui_ppx: rewrites labelled arguments that carry a `reactive` marker.

   ~p:(reactive f src)         ->  ~p_signal:(Signal.map f src)
   ~p:(reactive f s1 s2)       ->  ~p_signal:(Signal.map2 f s1 s2)
   ~p:(reactive f s1 .. sn)    ->  ~p_signal:(Signal.map2 f' s1 rest)
      where rest combines s2 .. sn into a tuple via nested map2 calls.
   ~p:(reactive src)           ->  ~p_signal:src

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

class mapper =
  object
    inherit Ast_traverse.map as super

    method! expression expr =
      let expr = super#expression expr in
      match expr.pexp_desc with
      | Pexp_apply (fn, args) ->
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
                      | [ (Nolabel, _source) ] ->
                          (* reactive f src: reactive is Signal.map *)
                          (Labelled (name ^ "_signal"), arg)
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
          { expr with pexp_desc = Pexp_apply (fn, args) }
      | _ -> expr
  end

let () =
  Driver.register_transformation ~impl:(new mapper)#structure "lui_ppx"
