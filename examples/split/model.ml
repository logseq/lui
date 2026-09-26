(* Split demo model: the pane tree lives in the shared Lui_split.Model
   controller; host gesture/keyboard events arrive as actions. *)

type t = { panes : Lui_split.Model.t }

type action = Split of Lui_split.Model.action

let initial =
  let open Lui_split.Model in
  {
    panes =
      create ~focused:"editor"
        (Split
           {
             split_id = "root";
             split_orientation = `horizontal;
             split_ratio = 0.6;
             split_first =
               Leaf
                 (pane ~pane_id:"editor" ~selected:"welcome"
                    [
                      tab ~tab_id:"welcome" ~title:"Welcome" ();
                      tab ~tab_id:"notes" ~title:"Notes.md" ~dirty:true ();
                      tab ~tab_id:"repl" ~title:"REPL" ();
                    ]);
             split_second =
               Leaf
                 (pane ~pane_id:"sidebar" ~selected:"outline"
                    [
                      tab ~tab_id:"outline" ~title:"Outline" ();
                      tab ~tab_id:"backlinks" ~title:"Backlinks" ();
                    ]);
           });
  }

let update model = function
  | Split action ->
    { panes = Lui_split.Model.update model.panes action }
