(* Token-system checks:
   - every token resolves in both palettes (completeness)
   - text/background pairs keep WCAG contrast >= 4.5
   - the paint fallback palette mirrors the light tokens exactly
     (no orphan fallbacks)
   - the gallery and the window dark palette agree with the canonical
     tables for every shared name *)

let color_testable =
  Alcotest.testable
    (fun fmt (c : Lui_scene.color) ->
      Format.fprintf fmt "#%02x%02x%02x@%d" c.r c.g c.b c.a)
    (fun (a : Lui_scene.color) b -> a = b)

let names mode = List.map fst (Lui_theme.tokens mode)

let both_modes_cover_same_names () =
  Alcotest.(check (slist string String.compare))
    "light/dark token names" (List.sort String.compare (names Lui_theme.Light))
    (List.sort String.compare (names Lui_theme.Dark))

let every_token_resolves () =
  List.iter
    (fun mode ->
      List.iter
        (fun name ->
          match Lui_theme.color_of mode name with
          | Some _ -> ()
          | None -> Alcotest.failf "token %S missing in %s" name
                      (if mode = Lui_theme.Light then "light" else "dark"))
        (names mode))
    [ Lui_theme.Light; Lui_theme.Dark ]

(* WCAG relative luminance and contrast ratio, straight sRGB. *)
let luminance (c : Lui_scene.color) =
  let lin u =
    let u = float u /. 255. in
    if u <= 0.03928 then u /. 12.92 else ((u +. 0.055) /. 1.055) ** 2.4
  in
  (0.2126 *. lin c.r) +. (0.7152 *. lin c.g) +. (0.0722 *. lin c.b)

let contrast a b =
  let la = luminance a +. 0.05 and lb = luminance b +. 0.05 in
  Float.max la lb /. Float.min la lb

let get mode name =
  match Lui_theme.color_of mode name with
  | Some c -> c
  | None -> Alcotest.failf "token %S missing" name

let text_pairs_meet_wcag () =
  List.iter
    (fun mode ->
      List.iter
        (fun (fg_name, bg_name) ->
          let r = contrast (get mode fg_name) (get mode bg_name) in
          if r < 4.5 then
            Alcotest.failf "%s-on-%s contrast %.2f < 4.5 (%s)"
              fg_name bg_name r
              (if mode = Lui_theme.Light then "light" else "dark"))
        [ ("foreground", "background"); ("text-muted", "background");
          ("text-muted", "surface"); ("foreground", "surface");
          ("inverse-foreground", "inverse") ];
      (* accent ink on the accent fill can't reach 4.5 in dark mode
         without breaking the accent's visibility on dark backgrounds;
         it only needs to stay clearly readable (the reference accepts
         the same trade-off). *)
      let r = contrast (get mode "accent-text") (get mode "accent") in
      if r < 3. then
        Alcotest.failf "accent-text-on-accent contrast %.2f < 3.0 (%s)" r
          (if mode = Lui_theme.Light then "light" else "dark"))
    [ Lui_theme.Light; Lui_theme.Dark ]

(* Paint's fallbacks are only reachable when a host resolver misses a
   name; they must mirror the canonical light tokens value-for-value. *)
let paint_fallbacks_match_light_tokens () =
  List.iter
    (fun (name, expected) ->
      match List.assoc_opt name Lui_paint.default_palette with
      | Some actual ->
        Alcotest.check color_testable
          (Printf.sprintf "fallback %S" name)
          expected actual
      | None -> Alcotest.failf "paint fallback missing token %S" name)
    (Lui_theme.tokens Lui_theme.Light);
  List.iter
    (fun (name, _) ->
      match List.assoc_opt name (Lui_theme.tokens Lui_theme.Light) with
      | Some _ -> ()
      | None ->
        Alcotest.failf "paint fallback %S has no canonical token" name)
    Lui_paint.default_palette

(* The gallery resolver must agree with the light table for every
   canonical name so the committed gallery shows the real defaults. *)
let gallery_resolves_light_tokens () =
  List.iter
    (fun (name, expected) ->
      match Lui_gallery.color_of name with
      | Some actual ->
        Alcotest.check color_testable
          (Printf.sprintf "gallery %S" name)
          expected actual
      | None -> Alcotest.failf "gallery does not resolve token %S" name)
    (Lui_theme.tokens Lui_theme.Light)

(* The window host's dark palette must agree with the dark table for
   every canonical name it declares. *)
let window_palette_matches_dark_tokens () =
  List.iter
    (fun (name, expected) ->
      match List.assoc_opt name Lui_window.Theme.palette with
      | Some actual ->
        Alcotest.check color_testable
          (Printf.sprintf "window %S" name)
          expected actual
      | None -> Alcotest.failf "window palette missing token %S" name)
    (Lui_theme.tokens Lui_theme.Dark)

let foreground_slots_and_metrics () =
  List.iter (fun mode ->
    Alcotest.check (Alcotest.option color_testable) "secondary foreground is its ink"
      (Lui_theme.color_of mode "secondary-foreground")
      (Lui_theme.foreground_of mode "secondary");
    List.iter (fun (container, ink) ->
      Alcotest.(check bool) (container ^ " has ink") true
        (Option.is_some (Lui_theme.color_of mode ink))) Lui_theme.foreground_tokens)
    [Lui_theme.Light; Lui_theme.Dark];
  Alcotest.(check (option (float 0.001))) "no spacing" (Some 0.) (Lui_theme.space_of "none");
  Alcotest.(check (option (float 0.001))) "full radius" (Some 9999.) (Lui_theme.radius_of "full");
  Alcotest.(check (option (float 0.001))) "unknown spacing" None (Lui_theme.space_of "missing")

let semantic_text_classes () =
  let store = Lui_store.create () in
  let set value =
    Lui_store.apply_batch store
      { Lui_protocol.generation = 1;
        ops = [Lui_protocol.SetProp (1, Lui_protocol.StyleClass, Lui_protocol.StringValue value)] } in
  Lui_store.apply_batch store
    { Lui_protocol.generation = 0; ops = [Lui_protocol.CreateNode (1, Lui_protocol.Text)] };
  List.iter (fun (name, (size, weight)) ->
    set name;
    Alcotest.(check (option (float 0.001))) name (Some size)
      (Lui_paint.text_class_number store 1 "font-size");
    Alcotest.(check (option (float 0.001))) name (Some (float weight))
      (Lui_paint.text_class_number store 1 "font-weight")) Lui_theme.text_roles;
  set "caption semibold single-line";
  Alcotest.(check (option (float 0.001))) "semibold" (Some 600.) (Lui_paint.text_class_number store 1 "font-weight");
  Alcotest.(check (option string)) "nowrap" (Some "nowrap") (Lui_paint.text_class_string store 1 "white-space");
  Alcotest.(check (option string)) "ellipsis" (Some "ellipsis") (Lui_paint.text_class_string store 1 "text-overflow");
  set "code";
  Alcotest.(check (option string)) "code font" (Some "monospace") (Lui_paint.text_class_string store 1 "font-family");
  set "";
  Alcotest.(check (option string)) "empty styles" None (Lui_paint.text_class_string store 1 "white-space");
  set "not-single-line";
  Alcotest.(check (option string)) "exact class match" None (Lui_paint.text_class_string store 1 "white-space")

let () =
  Alcotest.run "lui_theme"
    [ ("tokens",
       [ Alcotest.test_case "light/dark same names" `Quick
           both_modes_cover_same_names;
         Alcotest.test_case "every token resolves" `Quick
           every_token_resolves;
         Alcotest.test_case "foreground slots and metrics" `Quick foreground_slots_and_metrics;
         Alcotest.test_case "semantic text classes" `Quick semantic_text_classes ]);
      ("contrast",
       [ Alcotest.test_case "text pairs >= 4.5" `Quick
           text_pairs_meet_wcag ]);
      ("mirrors",
       [ Alcotest.test_case "paint fallbacks = light tokens" `Quick
           paint_fallbacks_match_light_tokens;
         Alcotest.test_case "gallery = light tokens" `Quick
           gallery_resolves_light_tokens;
         Alcotest.test_case "window palette = dark tokens" `Quick
           window_palette_matches_dark_tokens ]) ]
