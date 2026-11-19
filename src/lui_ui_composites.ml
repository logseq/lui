include Lui_ui
include Lui_element_combine

module Tokens = Lui_tokens
type color = Tokens.color
type space = Tokens.space
type radius = Tokens.radius
type text_role = Tokens.text_role

let hstack ?key ?accessibility_identifier ?(gap = `sm) ?(padding = `none)
    ?(cross = `center) ?(main = `start) children =
  Lui_elements.row ?key ?accessibility_identifier ~gap:(Tokens.space_value gap)
    ~padding:(Tokens.space_value padding) ~cross ~main ~min_width:0
    ~style_class:"hstack" children

let vstack ?key ?accessibility_identifier ?(gap = `md) ?(padding = `none)
    ?(cross = `stretch) ?(main = `start) children =
  Lui_elements.column ?key ?accessibility_identifier ~gap:(Tokens.space_value gap)
    ~padding:(Tokens.space_value padding) ~cross ~main ~min_height:0
    ~style_class:"vstack" children

let nav_bar ?key ~title ?(leading = []) ?(trailing = []) () =
  Lui_elements.toolbar ?key ~label:title ~placement:`navigation
    (leading @ [Lui_elements.toolbar_text ~role:`headline ~value:title []] @ trailing)

let page ?key ~title ?navigation ?(actions = []) children =
  vstack ?key ~padding:`page
    ((match navigation with Some navigation -> [navigation]
      | None -> [Lui_elements.heading ~role:`title ~value:title []])
     @ children @ actions)

let section ?key ?title ?footer children =
  vstack ?key
    ((match title with None -> [] | Some title -> [Lui_elements.heading ~role:`headline ~value:title []])
      @ children
      @ (match footer with None -> [] | Some footer ->
          [Lui_elements.paragraph ~role:`footnote ~foreground:(Tokens.color_value `muted_foreground)
            ~value:footer []]))

let form_section ?key ?title ?footer children =
  Lui_elements.list_section ?key
    ?header:(Option.map (fun title -> Lui_elements.text ~role:`headline ~value:title []) title)
    ?footer:(Option.map (fun footer -> Lui_elements.text ~role:`footnote ~value:footer []) footer)
    (List.map (fun child -> Lui_elements.list_section_item [Lui_elements.column [child]]) children)

let form_field ?key ~label ?help ?help_signal ?error ?error_signal control =
  Lui_elements.scoped (fun context ->
    let paragraph color value =
      Lui_elements.paragraph ~role:`footnote ~foreground:(Tokens.color_value color) ~value []
    in
    let messages = match error_signal, help_signal with
      | None, None ->
        (match error, help with
         | Some error, _ -> [paragraph `destructive error]
         | None, Some help -> [paragraph `muted_foreground help]
         | None, None -> [])
      | _ ->
        let source signal value = match signal with
          | Some source -> source
          | None -> Signal.own_signal context.Lui_ui.ui_scope
              (Signal.constant context.Lui_ui.ui_scheduler value)
        in
        let message = Lui_ui.map2 context (fun error help ->
          match error, help with
          | Some error, _ -> Some (error, `destructive)
          | None, Some help -> Some (help, `muted_foreground)
          | None, None -> None)
          (source error_signal error) (source help_signal help)
        in
        [Lui_elements.if_
          ~test:(Lui_ui.map context Option.is_some message)
          (Lui_elements.paragraph ~role:`footnote
            ~value_signal:(Lui_ui.map context
              (function Some (value, _) -> value | None -> "") message)
            ~foreground_signal:(Lui_ui.map context
              (function Some (_, color) -> Tokens.color_value color
                | None -> Tokens.color_value `muted_foreground) message)
            [])]
    in
    vstack ?key ~gap:`xs
      ([Lui_elements.label ~role:`subheadline ~value:label []; control] @ messages))
let data_list ?key ~label ?empty children =
  let content = match children, empty with [], Some empty -> [empty] | _ -> children in
  Lui_elements.list ?key ~style:`inset_grouped
    [Lui_elements.list_section
      ~header:(Lui_elements.text ~role:`headline ~value:label [])
      (List.map (fun child -> Lui_elements.list_section_item [Lui_elements.column [child]]) content)]

let form_sheet ?key ?accessibility_identifier ~title ?on_dismiss ?cancel ?confirm
    ?confirm_disabled ?confirm_disabled_signal content =
  let confirm_disabled = match confirm_disabled_signal with
    | Some _ -> confirm_disabled_signal | None -> confirm_disabled
  in
  Lui_element_combine.form_sheet ?key ?accessibility_identifier ~title ?on_dismiss
    ?cancel ?confirm ?confirm_disabled
    ~content:[Lui_elements.list ~style:`inset_grouped content] ()

let confirmation = confirm_dialog
