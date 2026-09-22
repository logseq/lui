(* Headless demo: mounts the todos app against a printing backend, then
   simulates a few user actions. Run with `dune exec examples/todos`. *)

let backend =
  {
    Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch =
      (fun batch ->
         Printf.printf "patch batch generation=%d ops=%d\n%!"
           batch.Lui_protocol.generation
           (List.length batch.Lui_protocol.ops);
         true);
  }

let print_model label (model : Model.t) =
  Printf.printf "\n%s\n" label;
  List.iter
    (fun (item : Model.todo) ->
       Printf.printf "  %s #%d %s\n"
         (if item.done_ then "[x]" else "[ ]")
         item.id item.title)
    model.items;
  Printf.printf "  draft=%S notes=%S\n%!" model.draft model.notes

let () =
  let app = Lui_app.create backend Model.initial Model.update View.view in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  print_model "== initial ==" (Lui_app.model app);
  ignore (Lui_app.send app (Model.ChangeDraft "buy milk"));
  ignore (Lui_app.send app Model.AddTodo);
  ignore (Lui_app.send app (Model.ChangeDraft "ship lui"));
  ignore (Lui_app.send app Model.AddTodo);
  ignore (Lui_app.send app (Model.ToggleTodo 1));
  ignore (Lui_app.send app (Model.MoveTodoUp 2));
  ignore (Lui_app.flush app);
  print_model "== after actions ==" (Lui_app.model app);
  ignore (Lui_app.dispose app)
