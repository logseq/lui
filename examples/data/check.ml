module P = Lui_protocol
module D = Data_view
module E = D.Edn

let require message condition = if not condition then failwith message
let kw name = E.any (E.keyword name)
let str value = E.any (E.string value)

let obj fields =
  E.any (E.map (List.map (fun (key, value) -> (kw key, value)) fields))

let contract () =
  let document =
    {|{:version 1
    :components {:entry {:props {:id :string :title :string} :view [:row
      [:text-field {:text {:bind [:props :title]}}]
      [:button {:text "Remove" :on {:press [:remove {:bind [:props :id]} {:bind [:props :title]}]}}]]}}
    :view [:column
      [:when {:bind [:model :visible]} [:text {:text "Visible"}]]
      [:for {:items {:bind [:model :items]} :as :item :key [:id]}
        [:use :entry {:id {:bind [:item :id]} :title {:bind [:item :title]}}]]]}|}
  in
  let contract =
    let module C = D.Contract in
    C.create ~model:(C.record ["visible", C.Bool; "items", C.Vector (C.record ["id", C.String; "title", C.String])])
      ~actions:[{C.name = "remove"; arguments = [C.String; C.String]; events = ["press"]}]
      ~hosts:[C.host (P.generic_profile ()) ""] ()
  in
  let compiled =
    match D.compile ~contract document with
    | Ok view -> view
    | Error error -> failwith error
  in
  let operations = ref [] and received = ref [] in
  let backend =
    {
      P.backend_profile = P.generic_profile ();
      apply_batch =
        (fun batch ->
          operations := batch.P.ops;
          true);
    }
  in
  let project (visible, items) =
    obj
      [
        ("visible", E.any (E.bool visible));
        ( "items",
          E.any
            (E.vector
               (List.map
                  (fun (id, title) ->
                    obj [ ("id", str id); ("title", str title) ])
                  items)) );
      ]
  in
  let app =
    Lui_app.create backend
      (true, [ ("a", "A"); ("b", "B") ])
      (fun _ next -> next)
      (fun _ model _ ->
        D.render compiled ~model ~project ~dispatch:(fun action args _ ->
            received := (action, args) :: !received))
  in
  Fun.protect
    ~finally:(fun () -> ignore (Lui_app.dispose app))
    (fun () ->
      ignore (Lui_app.start app);
      ignore (Lui_app.flush app);
      let created =
        List.filter_map
          (function P.CreateNode (id, P.TextField) -> Some id | _ -> None)
          !operations
      in
      let buttons =
        List.filter_map
          (function P.CreateNode (id, P.Button) -> Some id | _ -> None)
          !operations
      in
      require "two editable rows mounted"
        (List.length created = 2 && List.length buttons = 2);
      let first = List.hd created and button = List.hd buttons in
      ignore (Lui_app.send app (false, [ ("b", "B"); ("a", "A updated") ]));
      ignore (Lui_app.flush app);
      require "reorder preserves editable nodes"
        (not
           (List.exists
              (function
                | P.DropNode id when List.mem id created -> true
                | P.CreateNode (_, P.TextField) -> true
                | _ -> false)
              !operations));
      require "reorder emits a move"
        (List.exists
           (function P.MoveChild _ -> true | _ -> false)
           !operations);
      require "bound property updates in place"
        (List.exists
           (function
             | P.SetProp (id, P.TextValue, P.StringValue "A updated") ->
                 id = first
             | _ -> false)
           !operations);
      ignore (Lui_app.dispatch_event app (P.Press button));
      ignore (Lui_app.flush app);
      require "action arguments read the current keyed row"
        (!received = [ ("remove", [ str "a"; str "A updated" ]) ]);
      ignore (Lui_app.send app (true, [ ("b", "B") ]));
      ignore (Lui_app.flush app);
      require "removed row is disposed"
        (not (Lui_runtime.node_live (Lui_app.runtime app) first));
      ());
  print_endline
    "PASS: keyed editable identity, in-place bindings, fresh OCaml action \
     arguments and row disposal"

let () = contract ()

let compilation_rejects_invalid_sources () =
  let module C = D.Contract in
  let basic = C.create ~model:(C.record ["visible", C.Bool]) ~actions:[]
    ~hosts:[C.host (P.generic_profile ()) ""] () in
  let sources = [
    ("unused imported view", basic,
     ["main.edn", "{:version 1 :imports {:bad \"bad.edn\"} :view [:text {:text \"ok\"}]}";
      "bad.edn", "{:version 1 :view [:unknown-kind]}"], "bad.edn");
    ("unused imported component", basic,
     ["main.edn", "{:version 1 :imports {:bad \"bad.edn\"} :view [:text {:text \"ok\"}]}";
      "bad.edn", "{:version 1 :components {:bad {:view [:text {:text {:bind [:model :missing]}}]}}}"], "bad.edn");
    ("inactive branch", basic,
     ["main.edn", "{:version 1 :view [:when false [:text {:text {:bind [:model :missing]}}]]}"], "main.edn");
    ("import cycle", basic,
     ["main.edn", "{:version 1 :imports {:bad \"bad.edn\"} :view [:text {:text \"ok\"}]}";
      "bad.edn", "{:version 1 :imports {:main \"main.edn\"}}"], "import cycle");
    ("missing import", basic,
     ["main.edn", "{:version 1 :imports {:missing \"missing.edn\"} :view [:text {:text \"ok\"}]}"], "missing.edn");
    ("missing component slot", basic,
     ["main.edn", "{:version 1 :imports {:other \"other.edn\"} :view [:use :other/panel {}]}";
      "other.edn", "{:version 1 :components {:panel {:slots [:body] :view [:row [:slot :body]]}}}"], "main.edn");
    ("binding type", basic,
     ["main.edn", "{:version 1 :view [:text {:text {:bind [:model :visible]}}]}"], "main.edn")
  ] in
  List.iter (fun (label, contract, sources, context) ->
    let cache = D.Sources.cache () in
    let load ~from:_ path = match List.assoc_opt path sources with
      | Some source -> Ok (path, source)
      | None -> Error (path ^ ": source not found")
    in
    match D.compile_files ~cache ~contract ~load ~entry:"main.edn" () with
    | Error message ->
        require (label ^ ": missing source context: " ^ message)
          (String.starts_with ~prefix:context message)
    | Ok _ -> failwith (label ^ ": invalid EDN produced a compiled view")) sources;
  print_endline "PASS: reachable EDN compilation rejects invalid source graphs"

let () = compilation_rejects_invalid_sources ()

let compilation_preserves_typed_view_contracts () =
  let module C = D.Contract in
  let extensions = Lui_split.registry () in
  let registered = Hashtbl.fold (fun name schema entries ->
    (name, Lui_extension.fingerprint schema) :: entries) extensions.Lui_extension.extension_schemas [] in
  let contract =
    C.create
      ~extensions
      ~model:(C.record ["direction", C.String; "size", C.Enum [kw "sm"; kw "lg"]])
      ~actions:[] ~hosts:[C.host ~registered (P.profile P.WebOS P.WebHost) ""] ()
  in
  let cases = [
    "typed float", true, "[:row {:grow 1.0}]";
    "integer is not float", false, "[:row {:grow 1}]";
    "string is not keyword", false, "[:text {:text :wrong}]";
    "finite variant binding", true, "[:spinner {:size {:bind [:model :size]}}]";
    "unbounded variant binding", false, "[:spinner {:size {:bind [:model :direction]}}]";
    "wire-only property", false, "[:column {:width-viewport 0.5}]";
    "typed alignment modifier", true, "[:column {:alignment :center}]";
    "invalid alignment modifier", false, "[:column {:alignment :middle}]";
    "abstract root", false, "[:table-cell]";
    "internal wire node", false, "[:list-section-header [:text {:text \"title\"}]]";
    "required typed argument", false, "[:edge-inset]";
    "one split pane", false, "[:split {:value 0.5} [:column]]";
    "two split panes", true, "[:split {:value 0.5} [:column] [:column]]";
    "two input fields", false, "[:input-group [:textarea] [:textarea]]";
    "typed action slot", true, "[:input-group {:slots {:actions [:input-group-actions [:button {:text \"Send\"}]]}} [:textarea]]";
    "abstract child through component", false,
      "[:use :cell {}]";
    "typed component child", true, "[:table [:table-row [:use :cell {}]]]";
    "conditional child category", false, "[:table [:table-row [:if true [:table-cell] [:column]]]]";
    "keyword binding is not a string", false, "[:text {:text {:bind [:model :size]}}]";
    "structured attributes", true, "[:row {:data-attrs [[\"data-id\" \"item\"]]}]";
    "raw attributes are not a typed list", false, "[:row {:data-attrs \"data-id=item\"}]";
    "structured anchor rectangle", true, "[:popover {:anchor :below :anchor-rect [0.0 0.0 12.0 12.0]}]";
    "raw rectangle is not a typed tuple", false, "[:popover {:anchor :below :anchor-rect \"0 0 12 12\"}]";
    "typed application icon", true, "[:icon {:name [:app \"company-logo\"]}]";
    "unknown built-in icon", false, "[:icon {:name :company-logo}]";
    "typed picker token", true, "[:file-picker {:request [:int 1]}]";
    "untyped picker token", false, "[:file-picker {:request 1}]";
    "typed extension variant", true, "[:ext/split-branch {:orientation :horizontal :ratio 0.5}]";
    "unknown extension variant", false, "[:ext/split-branch {:orientation :diagonal :ratio 0.5}]";
    "unbounded extension variant binding", false, "[:ext/split-branch {:orientation {:bind [:model :direction]} :ratio 0.5}]";
    "strict extension float", false, "[:ext/split-branch {:orientation :horizontal :ratio 1}]";
    "required extension argument", false, "[:ext/split-branch {:ratio 0.5}]"
  ] in
  List.iter (fun (label, accepted, view) ->
    let source = "{:version 1 :components {:cell {:view [:table-cell]}} :view " ^ view ^ "}" in
    let actual, error = match D.compile ~contract source with Ok _ -> true, "" | Error error -> false, error in
    require (label ^ ": EDN disagrees with the typed view contract: " ^ error) (actual = accepted)) cases;
  print_endline "PASS: EDN preserves typed constructor domains, child categories and arity"

let () = compilation_preserves_typed_view_contracts ()
