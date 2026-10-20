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
    :components {:entry [:row
      [:text-field {:text {:bind [:props :title]}}]
      [:button {:text "Remove" :on {:press [:remove {:bind [:props :id]} {:bind [:props :title]}]}}]]}
    :view [:column
      [:when {:bind [:model :visible]} [:text {:text "Visible"}]]
      [:for {:items {:bind [:model :items]} :as :item :key [:id]}
        [:use :entry {:id {:bind [:item :id]} :title {:bind [:item :title]}}]]]}|}
  in
  let compiled =
    match D.compile ~actions:[ "remove" ] document with
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
