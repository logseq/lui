open Ppxlib
module Schema = Lui_nesting_schema
module Names = Map.Make (String)

type module_kind = Elements | Lists | Standard | Ui | Other

type scope = {
  opened : bool;
  values : value Names.t;
  modules : module_kind Names.t;
  budget : int ref;
  serial : int ref;
  symbols : int Names.t;
  namespace : int;
  assumptions : bool Names.t ref;
}

and value =
  | Unknown
  | Bound of scope * expression
  | Nodes of (Schema.node_kind * Location.t) list

let initial_scope () =
  {
    opened = false;
    values = Names.empty;
    modules = Names.empty;
    budget = ref 0;
    serial = ref 0;
    symbols = Names.empty;
    namespace = 0;
    assumptions = ref Names.empty;
  }

let fresh scope =
  incr scope.serial;
  !(scope.serial)

let store scope name value =
  {
    scope with
    values = Names.add name value scope.values;
    symbols = Names.add name (fresh scope) scope.symbols;
  }

let consume scope fuel =
  if fuel = 0 || !(scope.budget) = 0 then false
  else (
    decr scope.budget;
    true)

let bind scope pattern =
  let values = ref scope.values in
  let modules = ref scope.modules in
  let symbols = ref scope.symbols in
  let visitor =
    object
      inherit Ast_traverse.iter as super

      method! pattern pattern =
        (match pattern.ppat_desc with
        | Ppat_var name | Ppat_alias (_, name) ->
            values := Names.add name.txt Unknown !values;
            symbols := Names.add name.txt (fresh scope) !symbols
        | Ppat_unpack { txt = Some name; _ } ->
            modules := Names.add name Other !modules
        | _ -> ());
        super#pattern pattern
    end
  in
  visitor#pattern pattern;
  { scope with values = !values; modules = !modules; symbols = !symbols }

let rec bind_value scope pattern value =
  match (pattern.ppat_desc, value) with
  | Ppat_var name, _ -> store scope name.txt value
  | Ppat_alias (pattern, name), _ ->
      bind_value (store scope name.txt value) pattern value
  | Ppat_constraint (pattern, _), _ -> bind_value scope pattern value
  | ( Ppat_tuple patterns,
      Bound (captured, { pexp_desc = Pexp_tuple expressions; _ }) )
    when List.length patterns = List.length expressions ->
      List.fold_left2
        (fun scope pattern expression ->
          bind_value scope pattern (Bound (captured, expression)))
        scope patterns expressions
  | _ -> bind scope pattern

let bind_all scope bindings =
  List.fold_left
    (fun scope binding -> bind scope binding.pvb_pat)
    scope bindings

let definitions scope recursive bindings =
  if recursive = Recursive then bind_all scope bindings
  else
    List.fold_left
      (fun next binding ->
        bind_value next binding.pvb_pat (Bound (scope, binding.pvb_expr)))
      scope bindings

let rec module_kind scope = function
  | Lident name ->
      Option.value
        (Names.find_opt name scope.modules)
        ~default:
          (match name with
          | "Lui_elements" -> Elements
          | "List" -> Lists
          | "Stdlib" -> Standard
          | "Lui_ui" -> Ui
          | _ -> Other)
  | Ldot (parent, "List") when module_kind scope parent = Standard -> Lists
  | _ -> Other

let module_expression scope expression =
  match expression.pmod_desc with
  | Pmod_ident name -> module_kind scope name.txt
  | _ -> Other

let bind_module scope name kind =
  match name.txt with
  | Some name -> { scope with modules = Names.add name kind scope.modules }
  | None -> scope

let open_module scope expression =
  let opened = module_expression scope expression = Elements in
  let values =
    if opened then
      Names.filter (fun name _ -> not (Schema.exports name)) scope.values
    else Names.empty
  in
  let symbols =
    if opened then
      Names.filter (fun name _ -> not (Schema.exports name)) scope.symbols
    else Names.empty
  in
  {
    scope with
    opened;
    values;
    symbols;
    namespace = (if opened then scope.namespace else fresh scope);
  }

let symbol scope name =
  match Names.find_opt name scope.symbols with
  | Some id -> "local:" ^ string_of_int id
  | None -> Printf.sprintf "global:%d:%s" scope.namespace name

let rec reference fuel scope name =
  if fuel = 0 then symbol scope name
  else
    match Names.find_opt name scope.values with
    | Some
        (Bound
           (captured, { pexp_desc = Pexp_ident { txt = Lident alias; _ }; _ }))
      ->
        reference (fuel - 1) captured alias
    | _ -> symbol scope name

let host_key scope expression =
  match expression.pexp_desc with
  | Pexp_apply
      ( { pexp_desc = Pexp_ident { txt = Ldot (parent, "host"); _ }; _ },
        [ (Nolabel, { pexp_desc = Pexp_ident { txt = Lident context; _ }; _ }) ]
      )
    when module_kind scope parent = Ui ->
      Some ("host:" ^ reference 32 scope context)
  | _ -> None

let constructor_key expression =
  match expression.pexp_desc with
  | Pexp_construct ({ txt = Lident name; _ }, None) -> Some name
  | _ -> None

let rec condition fuel scope expression =
  if fuel = 0 then None
  else
    let next = condition (fuel - 1) in
    match expression.pexp_desc with
    | Pexp_ident { txt = Lident name; _ } ->
        let aliased =
          match Names.find_opt name scope.values with
          | Some (Bound (captured, value)) -> next captured value
          | _ -> None
        in
        Some (Option.value aliased ~default:(symbol scope name, true))
    | Pexp_apply
        ( { pexp_desc = Pexp_ident { txt = Lident "not"; _ }; _ },
          [ (Nolabel, value) ] )
      when not (Names.mem "not" scope.values) ->
        Option.map
          (fun (key, positive) -> (key, not positive))
          (next scope value)
    | Pexp_apply
        ( { pexp_desc = Pexp_ident { txt = Lident (("=" | "<>") as op); _ }; _ },
          [ (Nolabel, left); (Nolabel, right) ] )
      when not (Names.mem op scope.values) -> (
        let pair left right =
          match (host_key scope left, constructor_key right) with
          | Some host, Some kind -> Some (host ^ "=" ^ kind, op = "=")
          | _ -> None
        in
        match pair left right with
        | Some _ as key -> key
        | None -> pair right left)
    | Pexp_constraint (value, _) | Pexp_coerce (value, _, _) -> next scope value
    | _ -> None

(* Captured bindings share branch facts; lexical identities prevent shadowed or
   separately evaluated booleans from being conflated. Host reads are pure. *)
let in_branch scope test truth ~none visit =
  match condition 32 scope test with
  | None -> visit ()
  | Some (key, positive) -> (
      let truth = truth = positive in
      match Names.find_opt key !(scope.assumptions) with
      | Some known when known <> truth -> none
      | _ ->
          let previous = !(scope.assumptions) in
          scope.assumptions := Names.add key truth previous;
          Fun.protect visit ~finally:(fun () -> scope.assumptions := previous))

let rec in_case scope value pattern ~none visit =
  match pattern.ppat_desc with
  | Ppat_construct ({ txt = Lident (("true" | "false") as name); _ }, None) ->
      in_branch scope value (name = "true") ~none visit
  | Ppat_constraint (pattern, _) | Ppat_alias (pattern, _) ->
      in_case scope value pattern ~none visit
  | _ -> visit ()

let dsl_name scope expression =
  match expression.pexp_desc with
  | Pexp_ident { txt = Lident "reactive"; _ } -> Some "reactive"
  | Pexp_ident { txt = Ldot (parent, name); _ }
    when module_kind scope parent = Elements ->
      Some name
  | Pexp_ident { txt = Lident name; _ }
    when scope.opened && not (Names.mem name scope.values) ->
      Some name
  | _ -> None

let positional args =
  List.filter_map (function Nolabel, value -> Some value | _ -> None) args

let last values = List.fold_left (fun _ value -> Some value) None values

let check_edge parent (child, loc) =
  let supported =
    if child = Schema.VirtualRows then parent = Schema.VirtualList
    else
      Schema.can_contain_children parent
      && Schema.child_kind_supported parent child
  in
  if not supported then
    Location.raise_errorf ~loc
      "LUI nesting: parent=%s child=%s is not supported. Check the parent's \
       child contract; wrap content in an allowed container or move it outside \
       this parent."
      (Schema.name parent) (Schema.name child)

(* Recursive/opaque bindings are unknown; a bounded walk also protects the PPX
   from deeply nested generated expressions and higher-order self application. *)
let rec roots ?(detached = false) fuel scope expression =
  if not (consume scope fuel) then []
  else
    let fuel = fuel - 1 in
    match expression.pexp_desc with
    | Pexp_ident { txt = Lident name; _ } ->
        value_roots ~detached fuel
          (Option.value (Names.find_opt name scope.values) ~default:Unknown)
    | Pexp_apply (fn, args) ->
        apply_roots ~detached fuel scope fn
          (List.map
             (fun (label, expression) -> (label, Bound (scope, expression)))
             args)
    | Pexp_construct
        ( { txt = Lident "::"; _ },
          Some { pexp_desc = Pexp_tuple [ head; tail ]; _ } ) ->
        roots ~detached fuel scope head @ roots ~detached (fuel + 1) scope tail
    | Pexp_ifthenelse (test, yes, no) ->
        in_branch scope test true ~none:[] (fun () ->
            roots ~detached fuel scope yes)
        @ Option.fold ~none:[]
            ~some:(fun no ->
              in_branch scope test false ~none:[] (fun () ->
                  roots ~detached fuel scope no))
            no
    | Pexp_try (body, cases) ->
        roots ~detached fuel scope body @ case_roots ~detached fuel scope cases
    | Pexp_match (value, cases) ->
        List.concat_map
          (fun case ->
            in_case scope value case.pc_lhs ~none:[] (fun () ->
                roots ~detached fuel
                  (bind_value scope case.pc_lhs (Bound (scope, value)))
                  case.pc_rhs))
          cases
    | Pexp_let (recursive, bindings, body) ->
        roots ~detached fuel (definitions scope recursive bindings) body
    | Pexp_letmodule (name, definition, body) ->
        roots ~detached fuel
          (bind_module scope name (module_expression scope definition))
          body
    | Pexp_open (declaration, body) ->
        roots ~detached fuel (open_module scope declaration.popen_expr) body
    | Pexp_constraint (body, _)
    | Pexp_coerce (body, _, _)
    | Pexp_sequence (_, body) ->
        roots ~detached fuel scope body
    | _ -> []

and value_roots ?(detached = false) fuel = function
  | Unknown -> []
  | Bound (scope, expression) -> roots ~detached fuel scope expression
  | Nodes nodes -> nodes

and case_roots ?(detached = false) fuel scope cases =
  List.concat_map
    (fun case -> roots ~detached fuel (bind scope case.pc_lhs) case.pc_rhs)
    cases

and function_roots ?(detached = false) fuel = function
  | Unknown | Nodes _ -> []
  | Bound (scope, expression) -> (
      if not (consume scope fuel) then []
      else
        match expression.pexp_desc with
        | Pexp_ident { txt = Lident name; _ } ->
            function_roots ~detached (fuel - 1)
              (Option.value (Names.find_opt name scope.values) ~default:Unknown)
        | Pexp_function (parameters, _, body) -> (
            let scope =
              List.fold_left
                (fun scope parameter ->
                  match parameter.pparam_desc with
                  | Pparam_val (_, _, pattern) -> bind scope pattern
                  | Pparam_newtype _ -> scope)
                scope parameters
            in
            match body with
            | Pfunction_body body -> roots ~detached (fuel - 1) scope body
            | Pfunction_cases (cases, _, _) ->
                case_roots ~detached (fuel - 1) scope cases)
        | _ -> roots ~detached (fuel - 1) scope expression)

and call_roots ?(detached = false) fuel fn args =
  match fn with
  | Unknown | Nodes _ -> []
  | Bound (scope, fn) -> apply_roots ~detached fuel scope fn args

and apply_roots ?(detached = false) fuel scope fn args =
  if not (consume scope fuel) then []
  else
    let fuel = fuel - 1 in
    match fn.pexp_desc with
    | Pexp_ident { txt = Lident name; _ }
      when name <> "reactive" && Names.mem name scope.values -> (
        match Names.find name scope.values with
        | Unknown | Nodes _ -> []
        | Bound (captured, fn) -> apply_roots ~detached fuel captured fn args)
    | Pexp_apply (fn, previous) ->
        apply_roots ~detached fuel scope fn
          (List.map
             (fun (label, expression) -> (label, Bound (scope, expression)))
             previous
          @ args)
    | Pexp_function (parameters, _, body) ->
        let rec parameters_scope scope args = function
          | [] -> (
              match body with
              | Pfunction_body body ->
                  if args = [] then roots ~detached fuel scope body
                  else apply_roots ~detached fuel scope body args
              | Pfunction_cases (cases, _, _) -> (
                  match positional args with
                  | value :: _ ->
                      List.concat_map
                        (fun case ->
                          roots ~detached fuel
                            (bind_value scope case.pc_lhs value)
                            case.pc_rhs)
                        cases
                  | [] -> []))
          | parameter :: rest -> (
              match parameter.pparam_desc with
              | Pparam_newtype _ -> parameters_scope scope args rest
              | Pparam_val (label, default, pattern) -> (
                  let matches candidate =
                    match (label, candidate) with
                    | Optional a, Labelled b | Optional a, Optional b -> a = b
                    | _ -> label = candidate
                  in
                  let rec take prefix = function
                    | (candidate, value) :: rest when matches candidate ->
                        Some (candidate, value, List.rev_append prefix rest)
                    | arg :: rest -> take (arg :: prefix) rest
                    | [] -> None
                  in
                  match take [] args with
                  | Some (candidate, value, args) ->
                      let value =
                        match candidate with
                        | Optional _ -> Unknown
                        | _ -> value
                      in
                      parameters_scope
                        (bind_value scope pattern value)
                        args rest
                  | None -> (
                      match label with
                      | Optional _ ->
                          let value =
                            Option.fold ~none:Unknown
                              ~some:(fun e -> Bound (scope, e))
                              default
                          in
                          parameters_scope
                            (bind_value scope pattern value)
                            args rest
                      | _ -> [])))
        in
        parameters_scope scope args parameters
    | Pexp_let (recursive, bindings, body) ->
        apply_roots ~detached fuel
          (definitions scope recursive bindings)
          body args
    | Pexp_ifthenelse (test, yes, no) ->
        in_branch scope test true ~none:[] (fun () ->
            apply_roots ~detached fuel scope yes args)
        @ Option.fold ~none:[]
            ~some:(fun no ->
              in_branch scope test false ~none:[] (fun () ->
                  apply_roots ~detached fuel scope no args))
            no
    | Pexp_match (value, cases) ->
        List.concat_map
          (fun case ->
            in_case scope value case.pc_lhs ~none:[] (fun () ->
                apply_roots ~detached fuel
                  (bind_value scope case.pc_lhs (Bound (scope, value)))
                  case.pc_rhs args))
          cases
    | Pexp_open (declaration, body) ->
        apply_roots ~detached fuel
          (open_module scope declaration.popen_expr)
          body args
    | Pexp_constraint (body, _) | Pexp_coerce (body, _, _) ->
        apply_roots ~detached fuel scope body args
    | _ -> (
        match Option.bind (dsl_name scope fn) Schema.constructor with
        | Some (kind, parent, children) ->
            let values = positional args in
            (match (children, values) with
            | Schema.Children_list, children :: _ ->
                List.iter (check_edge parent) (value_roots fuel children);
                if parent = Schema.VirtualList then
                  check_exclusive fuel children
            | Schema.Child_arguments count, children ->
                List.iteri
                  (fun index child ->
                    if index < count then
                      List.iter (check_edge parent) (value_roots fuel child))
                  children
            | _ -> ());
            [ (kind, fn.pexp_loc) ]
        | None -> (
            match (dsl_name scope fn, positional args) with
            | Some ("align" | "themed"), values ->
                Option.fold ~none:[]
                  ~some:(value_roots ~detached fuel)
                  (last values)
            | Some "scoped", fn :: _ -> function_roots ~detached fuel fn
            | Some "if_", values ->
                dynamic_roots detached fn.pexp_loc
                  (Option.fold ~none:[]
                     ~some:(value_roots ~detached:true fuel)
                     (last values))
            | Some ("reactive" | "dyn"), fn_value :: _ ->
                dynamic_roots detached fn.pexp_loc
                  (function_roots ~detached:true fuel fn_value)
            | Some "virtual_rows", _ ->
                if detached then
                  Location.raise_errorf ~loc:fn.pexp_loc
                    "LUI nesting: virtual-rows requires a direct virtual-list \
                     parent, not a dynamic branch.";
                let rows =
                  Option.fold ~none:[]
                    ~some:(function_roots ~detached:true fuel)
                    (List.assoc_opt (Labelled "mount") args)
                in
                List.iter (check_edge Schema.VirtualList) rows;
                [ (Schema.VirtualRows, fn.pexp_loc) ]
            | ( Some
                  ( "keyed" | "keyed_step" | "keyed_timeline_item"
                  | "keyed_bottom_tab" | "keyed_table_row" | "keyed_table_cell"
                  | "keyed_radio" | "keyed_swipe_action" ),
                _ ) ->
                dynamic_roots detached fn.pexp_loc
                  (Option.fold ~none:[]
                     ~some:(function_roots ~detached:true fuel)
                     (List.assoc_opt (Labelled "mount") args))
            | _ -> (
                match (fn.pexp_desc, positional args) with
                | Pexp_ident { txt = Lident "@"; _ }, [ left; right ]
                  when not (Names.mem "@" scope.values) ->
                    value_roots ~detached fuel left
                    @ value_roots ~detached fuel right
                | ( Pexp_ident { txt = Ldot (parent, "append"); _ },
                    [ left; right ] )
                  when module_kind scope parent = Lists ->
                    value_roots ~detached fuel left
                    @ value_roots ~detached fuel right
                | ( Pexp_ident { txt = Ldot (parent, ("map" | "concat_map")); _ },
                    [ fn; values ] )
                  when module_kind scope parent = Lists ->
                    call_roots ~detached fuel fn [ (Nolabel, values) ]
                | _ -> [])))

and dynamic_roots detached loc nodes =
  if detached then begin
    List.iter (check_edge Schema.Box) nodes;
    [ (Schema.Box, loc) ]
  end
  else nodes

and check_exclusive fuel children =
  List.iter
    (fun children ->
      match children with
      | [] | [ _ ] -> ()
      | _ ->
          List.iter
            (fun child ->
              List.iter
                (fun (kind, loc) ->
                  if kind = Schema.VirtualRows then
                    Location.raise_errorf ~loc
                      "LUI nesting: virtual-rows must be the sole virtual-list \
                       child.")
                (value_roots fuel child))
            children)
    (list_variants fuel children)

and list_variants fuel = function
  | Unknown | Nodes _ -> [ [] ]
  | Bound (scope, expression) -> (
      if not (consume scope fuel) then [ [] ]
      else
        let fuel = fuel - 1 in
        let variants = list_variants fuel in
        let combine left right =
          if List.length left * List.length right > 64 then [ [] ]
          else
            List.concat_map
              (fun left -> List.map (fun right -> left @ right) right)
              left
        in
        match expression.pexp_desc with
        | Pexp_ident { txt = Lident name; _ } ->
            variants
              (Option.value (Names.find_opt name scope.values) ~default:Unknown)
        | Pexp_construct
            ( { txt = Lident "::"; _ },
              Some { pexp_desc = Pexp_tuple [ head; tail ]; _ } ) ->
            List.map
              (fun children -> Bound (scope, head) :: children)
              (list_variants (fuel + 1) (Bound (scope, tail)))
        | Pexp_ifthenelse (test, yes, no) ->
            in_branch scope test true ~none:[] (fun () ->
                variants (Bound (scope, yes)))
            @ Option.fold ~none:[ [] ]
                ~some:(fun no ->
                  in_branch scope test false ~none:[] (fun () ->
                      variants (Bound (scope, no))))
                no
        | Pexp_match (value, cases) ->
            List.concat_map
              (fun case ->
                in_case scope value case.pc_lhs ~none:[] (fun () ->
                    variants
                      (Bound
                         ( bind_value scope case.pc_lhs (Bound (scope, value)),
                           case.pc_rhs ))))
              cases
        | Pexp_let (recursive, bindings, body) ->
            variants (Bound (definitions scope recursive bindings, body))
        | Pexp_open (declaration, body) ->
            variants (Bound (open_module scope declaration.popen_expr, body))
        | Pexp_constraint (body, _)
        | Pexp_coerce (body, _, _)
        | Pexp_sequence (_, body) ->
            variants (Bound (scope, body))
        | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, args) -> (
            match (txt, positional args) with
            | Lident "@", [ left; right ] when not (Names.mem "@" scope.values)
              ->
                combine
                  (variants (Bound (scope, left)))
                  (variants (Bound (scope, right)))
            | Ldot (parent, "append"), [ left; right ]
              when module_kind scope parent = Lists ->
                combine
                  (variants (Bound (scope, left)))
                  (variants (Bound (scope, right)))
            | Ldot (parent, "map"), [ fn; values ]
              when module_kind scope parent = Lists ->
                List.map
                  (List.map (fun value ->
                       Nodes
                         (call_roots fuel
                            (Bound (scope, fn))
                            [ (Nolabel, value) ])))
                  (variants (Bound (scope, values)))
            | _ -> [ [] ])
        | _ -> [ [] ])

class checker =
  object (self)
    inherit Ast_traverse.iter as super
    val mutable scope = initial_scope ()

    method private within : 'a. scope -> (unit -> 'a) -> 'a =
      fun next visit ->
        let previous = scope in
        scope <- next;
        Fun.protect visit ~finally:(fun () -> scope <- previous)

    method! structure items =
      self#within scope (fun () ->
          List.iter
            (fun item ->
              match item.pstr_desc with
              | Pstr_value (recursive, bindings) ->
                  let next = definitions scope recursive bindings in
                  self#within
                    (if recursive = Recursive then next else scope)
                    (fun () -> List.iter self#value_binding bindings);
                  scope <- next
              | Pstr_recmodule bindings ->
                  scope <-
                    List.fold_left
                      (fun scope binding ->
                        bind_module scope binding.pmb_name Other)
                      scope bindings;
                  List.iter self#module_binding bindings
              | _ -> (
                  super#structure_item item;
                  match item.pstr_desc with
                  | Pstr_open declaration ->
                      scope <- open_module scope declaration.popen_expr
                  | Pstr_module binding ->
                      scope <-
                        bind_module scope binding.pmb_name
                          (module_expression scope binding.pmb_expr)
                  | Pstr_include _ ->
                      scope <-
                        { scope with opened = false; values = Names.empty }
                  | _ -> ()))
            items)

    method! case case =
      self#within (bind scope case.pc_lhs) (fun () -> super#case case)

    method! class_structure structure =
      self#within { scope with opened = false; values = Names.empty } (fun () ->
          super#class_structure structure)

    method! class_expr expression =
      self#within { scope with opened = false; values = Names.empty } (fun () ->
          super#class_expr expression)

    method! module_expr expression =
      match expression.pmod_desc with
      | Pmod_functor (Named (name, argument), body) ->
          self#module_type argument;
          self#within (bind_module scope name Other) (fun () ->
              self#module_expr body)
      | _ -> super#module_expr expression

    method! expression expression =
      (match expression.pexp_desc with
      | Pexp_apply _ ->
          scope.budget := 10000;
          ignore (roots 128 scope expression)
      | _ -> ());
      match expression.pexp_desc with
      | Pexp_ifthenelse (test, yes, no) ->
          self#expression test;
          in_branch scope test true ~none:() (fun () -> self#expression yes);
          Option.iter
            (fun no ->
              in_branch scope test false ~none:() (fun () -> self#expression no))
            no
      | Pexp_match (value, cases) ->
          self#expression value;
          List.iter
            (fun case ->
              in_case scope value case.pc_lhs ~none:() (fun () ->
                  self#case case))
            cases
      | Pexp_open (declaration, body) ->
          self#module_expr declaration.popen_expr;
          self#within (open_module scope declaration.popen_expr) (fun () ->
              self#expression body)
      | Pexp_letmodule (name, definition, body) ->
          self#module_expr definition;
          self#within
            (bind_module scope name (module_expression scope definition))
            (fun () -> self#expression body)
      | Pexp_let (recursive, bindings, body) ->
          let next = definitions scope recursive bindings in
          self#within
            (if recursive = Recursive then next else scope)
            (fun () -> List.iter self#value_binding bindings);
          self#within next (fun () -> self#expression body)
      | Pexp_function (parameters, _, body) ->
          self#within scope (fun () ->
              List.iter
                (fun parameter ->
                  match parameter.pparam_desc with
                  | Pparam_val (_, default, pattern) ->
                      Option.iter self#expression default;
                      scope <- bind scope pattern
                  | Pparam_newtype _ -> ())
                parameters;
              self#function_body body)
      | Pexp_for (pattern, first, last, _, body) ->
          self#expression first;
          self#expression last;
          self#within (bind scope pattern) (fun () -> self#expression body)
      | _ -> super#expression expression
  end

let check structure = (new checker)#structure structure
