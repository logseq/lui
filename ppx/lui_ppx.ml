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
module Names = Map.Make (String)

type module_kind = Lui | Elements | Slot_style | Other

let rec resolve_module modules = function
  | Lident name ->
      Option.value (Names.find_opt name modules)
        ~default:
          (match name with
          | "Lui" -> Lui
          | "Lui_elements" | "Elements" -> Elements
          | "Slot_style" -> Slot_style
          | _ -> Other)
  | Ldot (parent, "Elements") when resolve_module modules parent = Lui ->
      Elements
  | Ldot (parent, "Slot_style") when resolve_module modules parent = Elements ->
      Slot_style
  | _ -> Other

let bind_module modules name kind =
  match name.txt with
  | Some name -> Names.add name kind modules
  | None -> modules

let bind_pattern modules pattern =
  let modules = ref modules in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! pattern pat =
        (match pat.ppat_desc with
        | Ppat_unpack { txt = Some name; _ } ->
            modules := Names.add name Other !modules
        | _ -> ());
        super#pattern pat
    end
  in
  visitor#pattern pattern;
  !modules

let rec module_expr_kind modules expr =
  match expr.pmod_desc with
  | Pmod_ident { txt; _ } -> resolve_module modules txt
  | Pmod_constraint (inner, _) -> module_expr_kind modules inner
  | Pmod_structure items ->
      snd
        (List.fold_left
           (fun (modules, acc) item ->
             match item.pstr_desc with
             | Pstr_module binding ->
                 ( bind_module modules binding.pmb_name
                     (module_expr_kind modules binding.pmb_expr),
                   acc )
             | Pstr_open decl -> (open_module modules decl.popen_expr, acc)
             | Pstr_include { pincl_mod; _ } -> (
                 match module_expr_kind modules pincl_mod with
                 | Other -> (modules, acc)
                 | kind -> (modules, kind))
             | _ -> (modules, acc))
           (modules, Other) items)
  | _ -> Other

and open_module modules expr =
  match module_expr_kind modules expr with
  | Lui ->
      modules
      |> Names.add "Elements" Elements
      |> Names.add "Raw" Other
      |> Names.add "Ui" Other
  | Elements -> Names.add "Slot_style" Slot_style modules
  | _ -> modules

let rec fn_ident modules expr =
  match expr.pexp_desc with
  | Pexp_ident { txt; _ } -> Some (modules, txt)
  | Pexp_open (decl, body) ->
      fn_ident (open_module modules decl.popen_expr) body
  | Pexp_letmodule (name, def, body) ->
      fn_ident (bind_module modules name (module_expr_kind modules def)) body
  | Pexp_constraint (body, _) | Pexp_coerce (body, _, _) ->
      fn_ident modules body
  | _ -> None

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

let scoped_expression ?(adapter = "scoped") ?property ~loc build =
  let context = gen_symbol ~prefix:"__lui_context_" () in
  let own_generated = object
    inherit Ast_traverse.map as super
    method! expression expression =
      let expression = super#expression expression in
      match expression.pexp_desc with
      | Pexp_apply ({ pexp_desc = Pexp_ident
          { txt = Ldot (Lident "Signal", (("map" | "map2") as name)); _ }; _ }, args) ->
        B.pexp_apply ~loc (B.pexp_ident ~loc
          { txt = Ldot (Lident "Lui_ui", name); loc }) ((Nolabel, evar ~loc context) :: args)
      | _ -> expression
  end in
  let path = if adapter = "slot_style" then
      Ldot (Ldot (Lident "Lui_elements", "Slot_style"), "scoped")
    else Ldot (Lident "Lui_elements", adapter) in
  let scoped = B.pexp_ident ~loc { txt = path; loc } in
  apply ~loc scoped (Option.to_list property @ [lam ~loc [pvar ~loc context] (build own_generated)])

let is_structural_name name =
  name = "if_" || name = "keyed" || name = "virtual_rows"
  || Lui_nesting_schema.dynamic_adapter name

let structural_constructor modules expression =
  match fn_ident modules expression with
  | Some (_, Lident name) -> is_structural_name name
  | Some (modules, Ldot (parent, name)) ->
      resolve_module modules parent = Elements && is_structural_name name
  | Some (_, Lapply _) | None -> false

let is_slot_style_constructor modules expression =
  match fn_ident modules expression with
  | Some
      ( modules,
        Ldot (parent, ("make" | "typography" | "text_flow" | "collision")) ) ->
      resolve_module modules parent = Slot_style
  | _ -> false

let is_reactive_arg = function
  | ( Labelled _,
      {
        pexp_desc =
          Pexp_apply
            ( { pexp_desc = Pexp_ident { txt = Lident "reactive"; _ }; _ },
              (Nolabel, _) :: rest );
        _;
      } ) ->
      List.for_all (fun ((l : arg_label), _) -> l = Nolabel) rest
  | _ -> false

let rec constructor_name expression = match expression.pexp_desc with
  | Pexp_ident { txt = Lident name | Ldot (_, name); _ } -> name
  | Pexp_apply (fn, _)
  | Pexp_open (_, fn)
  | Pexp_letmodule (_, _, fn)
  | Pexp_constraint (fn, _)
  | Pexp_coerce (fn, _, _) -> constructor_name fn
  | _ -> ""

class mapper =
  object (self)
    inherit Ast_traverse.map as super
    val mutable modules = Names.empty

    method private within : 'a. module_kind Names.t -> (unit -> 'a) -> 'a =
      fun next visit ->
        let previous = modules in
        modules <- next;
        Fun.protect visit ~finally:(fun () -> modules <- previous)

    method! structure items =
      self#within modules (fun () ->
          List.map
            (fun item ->
              match item.pstr_desc with
              | Pstr_recmodule bindings ->
                  modules <-
                    List.fold_left
                      (fun modules binding ->
                        bind_module modules binding.pmb_name Other)
                      modules bindings;
                  super#structure_item item
              | Pstr_open declaration ->
                  let item = super#structure_item item in
                  modules <- open_module modules declaration.popen_expr;
                  item
              | Pstr_module binding ->
                  let kind = module_expr_kind modules binding.pmb_expr in
                  let item = super#structure_item item in
                  modules <- bind_module modules binding.pmb_name kind;
                  item
              | Pstr_include declaration ->
                  let item = super#structure_item item in
                  modules <- open_module modules declaration.pincl_mod;
                  item
              | Pstr_value (recursive, bindings) ->
                  let next =
                    List.fold_left
                      (fun modules binding ->
                        bind_pattern modules binding.pvb_pat)
                      modules bindings
                  in
                  let item =
                    self#within
                      (if recursive = Recursive then next else modules)
                      (fun () -> super#structure_item item)
                  in
                  modules <- next;
                  item
              | _ -> super#structure_item item)
            items)

    method! case case =
      self#within (bind_pattern modules case.pc_lhs) (fun () -> super#case case)

    method! module_expr expr =
      match expr.pmod_desc with
      | Pmod_functor (Named (name, argument), body) ->
          let argument = self#module_type argument in
          let body =
            self#within (bind_module modules name Other) (fun () ->
                self#module_expr body)
          in
          {
            expr with
            pmod_desc = Pmod_functor (Named (name, argument), body);
            pmod_attributes = self#attributes expr.pmod_attributes;
          }
      | _ -> super#module_expr expr

    method! expression expr =
      match expr.pexp_desc with
      | Pexp_open (declaration, body) ->
          let kind_modules = open_module modules declaration.popen_expr in
          let declaration = self#open_declaration declaration in
          let body =
            self#within kind_modules (fun () -> self#expression body)
          in
          {
            expr with
            pexp_desc = Pexp_open (declaration, body);
            pexp_attributes = self#attributes expr.pexp_attributes;
          }
      | Pexp_letmodule (name, definition, body) ->
          let kind = module_expr_kind modules definition in
          let definition = self#module_expr definition in
          let body =
            self#within (bind_module modules name kind) (fun () ->
                self#expression body)
          in
          {
            expr with
            pexp_desc = Pexp_letmodule (name, definition, body);
            pexp_attributes = self#attributes expr.pexp_attributes;
          }
      | Pexp_let (recursive, bindings, body) ->
          let next =
            List.fold_left
              (fun modules binding -> bind_pattern modules binding.pvb_pat)
              modules bindings
          in
          let bindings =
            self#within (if recursive = Recursive then next else modules)
              (fun () -> List.map self#value_binding bindings)
          in
          let body = self#within next (fun () -> self#expression body) in
          {
            expr with
            pexp_desc = Pexp_let (recursive, bindings, body);
            pexp_attributes = self#attributes expr.pexp_attributes;
          }
      | Pexp_function (parameters, constraint_, body) ->
          self#within modules (fun () ->
              let parameters =
                List.map
                  (fun parameter ->
                    match parameter.pparam_desc with
                    | Pparam_val (label, default, pattern) ->
                        let default = Option.map self#expression default in
                        let pattern = self#pattern pattern in
                        modules <- bind_pattern modules pattern;
                        {
                          parameter with
                          pparam_desc = Pparam_val (label, default, pattern);
                        }
                    | Pparam_newtype _ -> parameter)
                  parameters
              in
              let constraint_ = Option.map self#type_constraint constraint_ in
              let body = self#function_body body in
              {
                expr with
                pexp_desc = Pexp_function (parameters, constraint_, body);
                pexp_attributes = self#attributes expr.pexp_attributes;
              })
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
          let is_structural = structural_constructor modules fn in
          (* A constructor may already be applied to its mount context and
             parent. Scope the view builder, then preserve that application;
             wrapping the final node id would change the expression's type. *)
          let positional = List.filter (fun (label, _) -> label = Nolabel) args in
          let constructor_args, mount_args =
            match List.rev args with
            | (Nolabel, parent) :: (Nolabel, context) :: reversed
              when List.length positional >= 3
                || (is_structural && List.length positional = 2) ->
              List.rev reversed, [Nolabel, context; Nolabel, parent]
            | _ -> args, [] in
          let transform arguments owner =
          let bindings = ref [] in
          let args =
            List.concat_map
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
                          || is_structural then begin
                         needs_scope := true;
                         owner#expression expression
                       end else expression in
                     let signal = match rest with
                      | [ (Nolabel, source) ] ->
                          (* reactive f src *)
                          own (apply ~loc:arg.pexp_loc
                            (signal_map arg.pexp_loc) [ first; source ])
                      | [] ->
                          (* reactive src: the arg itself is the signal *)
                          first
                      | _ ->
                          (* reactive f s1 s2 .. sn *)
                          let sources =
                            List.map snd rest
                          in
                          own (expand ~loc:arg.pexp_loc first sources)
                     in
                     if List.mem name (Lui_nesting_schema.mandatory_labels (constructor_name fn)) then begin
                       needs_scope := true;
                       let loc = arg.pexp_loc in
                       let binding = gen_symbol ~prefix:"__lui_initial_" () in
                       bindings := B.value_binding ~loc ~pat:(pvar ~loc binding) ~expr:signal :: !bindings;
                       let source = evar ~loc binding in
                       let current = B.pexp_ident ~loc { txt = Ldot (Lident "Signal", "sample"); loc } in
                       [Labelled name, apply ~loc current [source]; Labelled target, source]
                     end else [Labelled target, signal]
                 | _ -> [label, arg])
              arguments
          in
          let result = { expr with pexp_desc = Pexp_apply (fn, args) } in
          let result = List.fold_left (fun result binding ->
            B.pexp_let ~loc:expr.pexp_loc Nonrecursive [binding] result) result !bindings in
          super#expression result in
          let plain = transform args (new Ast_traverse.map) in
          if !needs_scope then
            let adapter =
              if is_slot_style_constructor modules fn then "slot_style"
              else Lui_nesting_schema.scoped_adapter (constructor_name fn)
            in
            if adapter = "slot_style" then begin
              let static, reactive = List.partition (fun arg -> not (is_reactive_arg arg)) args in
              List.fold_left (fun base ((label, _) as argument) ->
                let name = match label with Labelled name -> name | _ -> assert false in
                let name = if ends_with name "_signal" then String.sub name 0 (String.length name - 7) else name in
                let name = String.concat "" (List.map String.capitalize_ascii (String.split_on_char '_' name)) in
                let property = B.pexp_construct ~loc:expr.pexp_loc
                  {txt = Ldot (Lident "Lui_protocol", name); loc = expr.pexp_loc} None in
                let unit = B.eunit ~loc:expr.pexp_loc in
                let style = scoped_expression ~adapter ~property ~loc:expr.pexp_loc
                  (transform [argument; Nolabel, unit]) in
                let merge = B.pexp_ident ~loc:expr.pexp_loc
                  {txt = Ldot (Ldot (Lident "Lui_elements", "Slot_style"), "merge"); loc = expr.pexp_loc} in
                apply ~loc:expr.pexp_loc merge [base; style])
                (transform static (new Ast_traverse.map)) reactive
            end else
            let scoped = scoped_expression ~adapter ~loc:expr.pexp_loc (transform constructor_args) in
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
