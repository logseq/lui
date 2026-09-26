(* Split demo view: one Lui_split.Model-rendered tree. Tab bodies are plain
   elements; the split extensions own the chrome. *)

open Lui_elements

let tab_page (tab : Lui_split.Model.tab) : t list =
  [
    column ~gap:8 ~padding:24
      [
        text ~value:tab.Lui_split.Model.tab_title [];
        paragraph
          ~value:
            "Drag tabs to reorder or move them across panes; drop on an edge \
             to split. Cmd-Alt arrows move focus, Cmd-Alt-D splits, Cmd-W \
             closes."
          [];
      ];
  ]

let view _context model_source send : t =
  column ~gap:0
    [
      dyn
        ~equal:(fun (a : Model.t) (b : Model.t) ->
          a.Model.panes == b.Model.panes)
        (fun (model : Model.t) ->
          Lui_split.Model.render
            ~build:(fun tab -> tab_page tab)
            ~dispatch:(fun action -> ignore (send (Model.Split action)))
            model.Model.panes)
        model_source;
    ]
