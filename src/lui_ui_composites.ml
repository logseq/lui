include Lui_element_combine

module Tokens = Lui_tokens
type color = Tokens.color
type space = Tokens.space
type radius = Tokens.radius
type text_role = Tokens.text_role

let hstack ?key ?accessibility_identifier ?background ?foreground ?border_color
    ?corner_radius ?(gap = `sm) ?(padding = `none) ?(cross = `center)
    ?(main = `start) children =
  Lui_elements.scoped (fun context ->
    let os = Lui_ui.platform context in
    Lui_elements.row ?key ?accessibility_identifier
      ?background:(Option.map Tokens.color_value background)
      ?foreground:(Option.map Tokens.color_value foreground)
      ?border_color:(Option.map Tokens.color_value border_color)
      ?corner_radius:(Option.map Tokens.radius_value corner_radius)
      ~gap:(Tokens.space_value_for os gap)
      ~padding:(Tokens.space_value_for os padding)
      ~cross ~main ~min_width:0 ~style_class:"hstack" children)

let vstack ?key ?accessibility_identifier ?background ?foreground ?border_color
    ?corner_radius ?(gap = `md) ?(padding = `none) ?(cross = `stretch)
    ?(main = `start) children =
  Lui_elements.scoped (fun context ->
    let os = Lui_ui.platform context in
    Lui_elements.column ?key ?accessibility_identifier
      ?background:(Option.map Tokens.color_value background)
      ?foreground:(Option.map Tokens.color_value foreground)
      ?border_color:(Option.map Tokens.color_value border_color)
      ?corner_radius:(Option.map Tokens.radius_value corner_radius)
      ~gap:(Tokens.space_value_for os gap)
      ~padding:(Tokens.space_value_for os padding)
      ~cross ~main ~min_height:0 ~style_class:"vstack" children)

let nav_bar ?key ~title ?(leading = []) ?(trailing = []) () =
  Lui_elements.toolbar ?key ~label:title ~placement:`navigation
    (leading @ [Lui_elements.text ~role:`headline ~value:title []] @ trailing)

let page ?key ?background ?foreground ?(gap = `md) ?(padding = `page) ~title
    ?navigation ?(actions = []) children =
  vstack ?key ?background ?foreground ~gap ~padding
    ((match navigation with
      | Some navigation -> [navigation]
      | None -> [Lui_elements.heading ~role:`title ~value:title []])
     @ children @ actions)

let section ?key ?background ?foreground ?border_color ?corner_radius
    ?(gap = `md) ?(padding = `none) ?title ?footer children =
  vstack ?key ?background ?foreground ?border_color ?corner_radius ~gap ~padding
    ((match title with
      | None -> []
      | Some title -> [Lui_elements.heading ~role:`headline ~value:title []])
     @ children
     @ (match footer with
        | None -> []
        | Some footer ->
            [Lui_elements.paragraph ~role:`footnote
               ~foreground:(Tokens.color_value `muted_foreground)
               ~value:footer []]))

let form_row ?key child =
  Lui_elements.list_section_item ?key [Lui_elements.column [child]]

let data_row = form_row

let form_section ?key ?title ?footer children =
  Lui_elements.list_section ?key
    ?header:(Option.map (fun title -> Lui_elements.text ~role:`headline ~value:title []) title)
    ?footer:(Option.map (fun footer -> Lui_elements.text ~role:`footnote ~value:footer []) footer)
    children

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
      content]

let form_sheet ?key ?accessibility_identifier ~title ?on_dismiss ?cancel ?confirm
    ?confirm_disabled ?confirm_disabled_signal content =
  match confirm_disabled_signal, confirm_disabled with
  | Some signal, _ ->
      Lui_element_combine.form_sheet ?key ?accessibility_identifier ~title ?on_dismiss
        ?cancel ?confirm ~confirm_disabled:signal
        ~content:[Lui_elements.list ~style:`inset_grouped content] ()
  | None, Some disabled ->
      Lui_elements.scoped (fun context ->
        let signal =
          Signal.own_signal context.Lui_ui.ui_scope
            (Signal.constant context.Lui_ui.ui_scheduler disabled)
        in
        Lui_element_combine.form_sheet ?key ?accessibility_identifier ~title ?on_dismiss
          ?cancel ?confirm ~confirm_disabled:signal
          ~content:[Lui_elements.list ~style:`inset_grouped content] ())
  | None, None ->
      Lui_element_combine.form_sheet ?key ?accessibility_identifier ~title ?on_dismiss
        ?cancel ?confirm
        ~content:[Lui_elements.list ~style:`inset_grouped content] ()

let confirmation = confirm_dialog
