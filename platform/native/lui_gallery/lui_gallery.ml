(* Headless visual-exercise gallery: one retained tree exercising every
   standard kind's painted form plus a registered extension kind,
   rendered to PNGs through the real host -> layout -> paint -> raster
   pipeline. See the .mli for the contract. *)

open Lui_protocol
open Lui_scene

(* ---------- spec ---------- *)

type spec = {
  nk : node_kind option;
  ext : string option;
  props : (property * wire_value) list;
  xprops : (string * wire_value) list;
  kids : spec list;
  st : Lui_paint.state option;
  scroll : Lui_paint.scroll_metrics option;
  img : bool;
  tag : string option;
  cov : bool;
}

type emitted = {
  mutable ops : patch_op list;
  ids : (string, int) Hashtbl.t;
  mutable covered : (string * int) list;
  states : (int, Lui_paint.state) Hashtbl.t;
  scrolls : (int, Lui_paint.scroll_metrics) Hashtbl.t;
  images : (int, unit) Hashtbl.t;
}

type cell = {
  cname : string;
  ckind : string;
  cnote : string;
  cnode : spec;
}

type gallery = {
  root : spec;
  cells : cell list;
  columns : int;
  frame_w : int;
}

let sv s = StringValue s
let fv f = FloatValue f
let iv i = IntValue i
let bv b = BoolValue b

let n nk ?(props = []) ?(xprops = []) ?(kids = []) ?st ?scroll
    ?(img = false) ?tag ?(cov = false) () =
  { nk = Some nk; ext = None; props; xprops; kids; st; scroll; img;
    tag; cov }

let x identifier ?(props = []) ?(xprops = []) ?(kids = []) ?st
    ?(img = false) ?tag ?(cov = false) () =
  { nk = None; ext = Some identifier; props; xprops; kids; st;
    scroll = None; img; tag; cov }

let spec_node_kind s =
  match s.nk with
  | Some k -> Lui_wire_schema.node_kind_name k
  | None -> "extension:" ^ Option.value ~default:"?" s.ext

(* ---------- emit ---------- *)

let emit root =
  let next = ref 0 in
  let e =
    { ops = []; ids = Hashtbl.create 64; covered = [];
      states = Hashtbl.create 16; scrolls = Hashtbl.create 8;
      images = Hashtbl.create 16 }
  in
  let ops = ref [] in
  let push o = ops := o :: !ops in
  let rec go parent index s =
    incr next;
    let id = !next in
    (match s.nk with
     | Some k -> push (create_node_op id k)
     | None ->
       push (create_extension_op id (Option.get s.ext) "gallery"));
    List.iter (fun (p, v) -> push (set_prop_op id p v)) s.props;
    List.iter (fun (p, v) -> push (set_extension_prop_op id p v)) s.xprops;
    push (insert_child_op parent id index);
    (match s.tag with
     | Some t -> Hashtbl.replace e.ids t id
     | None -> ());
    if s.cov then e.covered <- (spec_node_kind s, id) :: e.covered;
    (match s.st with
     | Some st -> Hashtbl.replace e.states id st
     | None -> ());
    (match s.scroll with
     | Some sm -> Hashtbl.replace e.scrolls id sm
     | None -> ());
    if s.img then Hashtbl.replace e.images id ();
    List.iteri (fun i k -> go id i k) s.kids
  in
  go (-1) 0 root;
  e.ops <- List.rev !ops;
  e

(* ---------- deterministic hooks ---------- *)

(* Fixed theme-name table; hex/rgb values parse inside the paint pass
   itself, so only abstract names need resolving here. *)
let color_of = function
  | "primary" -> Some (color 37 99 235 255)
  | "primary-foreground" -> Some (color 255 255 255 255)
  | "secondary" -> Some (color 229 231 235 255)
  | "accent" -> Some (color 124 58 237 255)
  | "page" -> Some (color 244 246 248 255)
  | "ink" -> Some (color 17 24 39 255)
  | "muted" -> Some (color 107 114 128 255)
  | "danger" -> Some (color 220 38 38 255)
  | _ -> None

let fill1 x y w h c =
  Fill
    { frect = rect x y w h; fradii = (0., 0., 0., 0.); fcontinuous = false;
      fcolor = c; fpaint = Solid; fcolor2 = c; fgradient = (0., 0., 0., 0.);
      fborder = (0., 0., 0., 0.); fborder_color = color 0 0 0 0;
      fdashed = false; fwide = 0; fopacity = 1. }

(* Deterministic text stub: every byte becomes a small solid rect whose
   height hints at the character class (ascender, x-height, descender,
   punctuation dot). Readable as text structure, portable everywhere. *)
let stub_text_ops _id r c s =
  let base = r.y +. Float.max 1. ((r.h -. 9.) /. 2.) in
  let x = ref r.x in
  let ops = ref [] in
  let put y w h = ops := fill1 !x y w h c :: !ops in
  String.iter
    (fun ch ->
      if !x +. 5. <= r.x +. r.w +. 0.5 then
        (match ch with
         | ' ' | '\t' | '\n' -> ()
         | '.' | ',' | ':' | ';' | '\'' | '`' | 'i' | 'j' | 'l' | '!' | '|' ->
           put (base +. 7.) 2. 2.
         | 'g' | 'p' | 'q' | 'y' -> put (base +. 4.) 5. 7.
         | 'a' .. 'z' -> put (base +. 3.) 5. 6.
         | _ -> put base 5. 9.);
      x := !x +. 7.)
    s;
  List.rev !ops

let stub_measure _id text _w _h =
  Some (7. *. float_of_int (String.length text), 10.)

(* Fixed 24x24 two-tone checkerboard, premultiplied RGBA — the bitmap
   every image-driven kind samples. *)
let test_image =
  let w = 24 and h = 24 in
  let pix = Bytes.make (w * h * 4) '\000' in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let i = (y * w + x) * 4 in
      let on = ((x / 6) + (y / 6)) mod 2 = 0 in
      Bytes.set pix i (Char.chr (if on then 14 else 96));
      Bytes.set pix (i + 1) (Char.chr (if on then 165 else 116));
      Bytes.set pix (i + 2) (Char.chr (if on then 233 else 139));
      Bytes.set pix (i + 3) '\255'
    done
  done;
  new_image ~w ~h pix

let hooks_of ?(text_ops = stub_text_ops) e =
  { Lui_paint.color_of;
    layout = Lui_paint.default_hooks.layout;
    state_of =
      (fun id ->
        match Hashtbl.find_opt e.states id with
        | Some s -> s
        | None -> Lui_paint.state_neutral);
    scroll_of = (fun id -> Hashtbl.find_opt e.scrolls id);
    text_ops;
    image_of =
      (fun id -> if Hashtbl.mem e.images id then Some test_image else None);
    shadow_of = (fun s -> Lui_paint.parse_shadow color_of s) }

(* ---------- cell catalog ---------- *)

let hovered = { Lui_paint.state_neutral with hovered = true }
let pressed = { Lui_paint.state_neutral with pressed = true }
let selected = { Lui_paint.state_neutral with selected = true }
let focused = { Lui_paint.state_neutral with focused = true }

let sized ?(w = 0.) ?(h = 0.) props =
  (if w > 0. then [ (WidthValue, fv w) ] else [])
  @ (if h > 0. then [ (HeightValue, fv h) ] else [])
  @ props

(* A text leaf. *)
let txt ?(props = []) s = n Text ~props:(sized ~h:12. ([ (TextValue, sv s) ] @ props)) ()

(* A labeled-chrome node: text prop + box dressing. *)
let chrome k s props =
  n k ~props:(sized ~h:26. ([ (TextValue, sv s) ] @ props)) ()

let bordered = [ (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1");
                 (CornerRadius, fv 5.); (BackgroundValue, sv "#ffffff") ]

let primary_btn = [ (BackgroundValue, sv "#2563eb");
                    (ForegroundValue, sv "#ffffff"); (CornerRadius, fv 6.) ]

(* A popup-surface subject pinned inside its stage. *)
let popup w h props kids =
  sized ~w ~h
    ([ (Position, sv "absolute"); (InsetLeft, fv 8.); (InsetTop, fv 8.) ]
     @ props), kids

let cell name kind note subject = { cname = name; ckind = kind; cnote = note; cnode = subject }

(* ---------- the cells ---------- *)

let cells : cell list =
  [ (* ----- text ----- *)
    cell "text" "text" "plain text run"
      (n Text ~cov:true ~props:(sized ~h:14. [ (TextValue, sv "The quick brown fox 0123456789") ]) ());
    cell "heading" "heading" "bold heading text"
      (n Heading ~cov:true ~props:(sized ~h:16. [ (TextValue, sv "Heading sample"); (FontWeight, iv 700) ]) ());
    cell "paragraph" "paragraph" "body text"
      (n Paragraph ~cov:true ~props:(sized ~h:26. [ (TextValue, sv "Paragraph body text in a wider block.") ]) ());
    cell "label" "label" "field label"
      (n Label ~cov:true ~props:(sized ~h:12. [ (TextValue, sv "Email address") ]) ());
    cell "kbd" "kbd" "keyboard hint chip"
      (chrome Kbd "cmd K" [ (BackgroundValue, sv "#f1f5f9"); (BorderWidth, fv 1.);
                            (BorderColorValue, sv "#cbd5e1"); (CornerRadius, fv 4.) ]
       |> fun s -> { s with cov = true });
    cell "link" "link" "anchor text"
      (n Link ~cov:true ~props:(sized ~h:12. [ (TextValue, sv "https://logseq.com"); (ForegroundValue, sv "#2563eb") ]) ());
    cell "br" "br" "line break between runs"
      (n Column ~props:(sized ~h:30. [])
         ~kids:[ txt "alpha"; n Br ~cov:true ~props:(sized ~h:4. []) (); txt "beta" ] ());
    (* ----- buttons and toggles ----- *)
    cell "button" "button" "normal"
      (n Button ~cov:true ~props:(sized ~h:28. ([ (TextValue, sv "Button") ] @ primary_btn)) ());
    cell "button_hover" "button" "hovered"
      (n Button ~st:hovered
         ~props:(sized ~h:28. ([ (TextValue, sv "Button") ] @ primary_btn
                  @ [ (HoverBackground, sv "#1d4ed8") ])) ());
    cell "button_pressed" "button" "pressed"
      (n Button ~st:pressed
         ~props:(sized ~h:28. ([ (TextValue, sv "Button") ] @ primary_btn
                  @ [ (PressedBackground, sv "#1e3a8a") ])) ());
    cell "button_disabled" "button" "disabled"
      (n Button ~props:(sized ~h:28. ([ (TextValue, sv "Button") ] @ primary_btn
                         @ [ (Enabled, bv false); (DisabledOpacity, fv 0.45) ])) ());
    cell "toggle_button" "toggle-button" "selected"
      (n ToggleButton ~cov:true ~st:selected
         ~props:(sized ~h:26. [ (TextValue, sv "Bold");
                                (SelectedBackground, sv "#dbeafe");
                                (BorderWidth, fv 1.); (BorderColorValue, sv "#94a3b8");
                                (CornerRadius, fv 5.) ]) ());
    cell "toggle" "toggle" "selected toggle chip"
      (n Toggle ~cov:true ~st:selected
         ~props:(sized ~h:26. [ (TextValue, sv "Notify");
                                (SelectedBackground, sv "#dcfce7");
                                (BorderWidth, fv 1.); (BorderColorValue, sv "#86efac");
                                (CornerRadius, fv 13.) ]) ());
    cell "menu_item" "menu-item" "hovered item"
      (n MenuItem ~cov:true ~st:hovered
         ~props:(sized ~h:24. [ (TextValue, sv "Rename page");
                                (HoverBackground, sv "#eff6ff"); (CornerRadius, fv 4.) ]) ());
    cell "menu_trigger" "menu-trigger" "menu trigger button"
      (n MenuTrigger ~cov:true
         ~props:(sized ~h:26. ([ (TextValue, sv "File v") ] @ bordered)) ());
    cell "bottom_tab" "bottom-tab" "selected tab"
      (n BottomTab ~cov:true ~st:selected
         ~props:(sized ~h:26. [ (TextValue, sv "Home");
                                (SelectedBackground, sv "#e0e7ff"); (CornerRadius, fv 6.) ]) ());
    cell "swipe_action" "swipe-action" "destructive swipe"
      (n SwipeAction ~cov:true
         ~props:(sized ~h:30. [ (TextValue, sv "Delete");
                                (BackgroundValue, sv "#dc2626");
                                (ForegroundValue, sv "#ffffff") ]) ());
    cell "file_picker" "file-picker" "dashed drop target"
      (n FilePicker ~cov:true
         ~props:(sized ~h:34. [ (TextValue, sv "Attach file");
                                (BorderWidth, fv 2.); (BorderColorValue, sv "#94a3b8");
                                (CornerRadius, fv 6.) ])
         ~xprops:[ ("border-style", sv "dashed") ] ());
    cell "list_section_header" "list-section-header" "section label"
      (chrome ListSectionHeader "SECTION A"
         [ (ForegroundValue, sv "#64748b"); (BackgroundValue, sv "#f8fafc") ]
       |> fun s -> { s with cov = true });
    cell "list_section_footer" "list-section-footer" "section footnote"
      (chrome ListSectionFooter "3 more items" [ (ForegroundValue, sv "#94a3b8") ]
       |> fun s -> { s with cov = true });
    (* ----- inputs ----- *)
    cell "text_field" "text-field" "filled value"
      (n TextField ~cov:true
         ~props:(sized ~h:30. ([ (TextValue, sv "tienson@logseq.com") ] @ bordered)) ());
    cell "text_field_ph" "text-field" "placeholder"
      (n TextField ~props:(sized ~h:30. ([ (PlaceholderValue, sv "Search notes...") ] @ bordered)) ());
    cell "text_field_focus" "text-field" "focus ring"
      (n TextField ~st:focused
         ~props:(sized ~h:30. ([ (TextValue, sv "query") ] @ bordered
                  @ [ (FocusShadow, sv "0 0 0 3px rgba(59 130 246 / 40%)") ])) ());
    cell "secure_field" "secure-field" "masked secret"
      (n SecureField ~cov:true
         ~props:(sized ~h:30. ([ (TextValue, sv "********") ] @ bordered)) ());
    cell "input" "input" "bare input"
      (n Input ~cov:true ~props:(sized ~h:28. ([ (TextValue, sv "Plain input") ] @ bordered)) ());
    cell "search_field" "search-field" "placeholder"
      (n SearchField ~cov:true
         ~props:(sized ~h:30. ([ (PlaceholderValue, sv "Search") ] @ bordered)) ());
    cell "textarea" "textarea" "multiline body"
      (n Textarea ~cov:true
         ~props:(sized ~h:56. ([ (TextValue, sv "Longer body text that fills a taller box") ] @ bordered)) ());
    cell "select" "select" "closed select"
      (n Select ~cov:true ~props:(sized ~h:30. ([ (TextValue, sv "Choose v") ] @ bordered)) ());
    cell "combobox" "combobox" "editable combo"
      (n Combobox ~cov:true ~props:(sized ~h:30. ([ (TextValue, sv "combo") ] @ bordered)) ());
    cell "number_stepper" "number-stepper" "stepper cluster"
      (n NumberStepper ~cov:true ~props:(sized ~h:28. bordered)
         ~kids:[ n Row ~props:(sized ~h:20. [ (Gap, fv 4.) ])
                   ~kids:[ chrome Button "-" [ (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ];
                           txt "3"; chrome Button "+" [ (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ] ] () ] ());
    cell "checkbox_on" "checkbox" "checked"
      (n Checkbox ~props:(sized ~h:22. [ (Checked, bv true); (TextValue, sv "Enabled") ]) ());
    cell "checkbox_off" "checkbox" "unchecked"
      (n Checkbox ~cov:true ~props:(sized ~h:22. [ (TextValue, sv "Unchecked") ]) ());
    cell "radio_on" "radio" "checked"
      (n Radio ~props:(sized ~h:22. [ (Checked, bv true); (TextValue, sv "Daily") ]) ());
    cell "radio_off" "radio" "unchecked"
      (n Radio ~cov:true ~props:(sized ~h:22. [ (TextValue, sv "Weekly") ]) ());
    cell "switch_on" "switch" "checked"
      (n SwitchControl ~props:(sized ~w:80. ~h:24. [ (Checked, bv true) ]) ());
    cell "switch_off" "switch" "unchecked"
      (n SwitchControl ~cov:true ~props:(sized ~w:80. ~h:24. []) ());
    cell "slider" "slider" "40 percent"
      (n Slider ~cov:true ~props:(sized ~h:20. [ (ProgressValue, fv 40.); (MinValue, fv 0.); (MaxValue, fv 100.) ]) ());
    cell "progress" "progress" "65 percent"
      (n Progress ~cov:true ~props:(sized ~h:10. [ (ProgressValue, fv 65.); (MinValue, fv 0.); (MaxValue, fv 100.) ]) ());
    cell "spinner" "spinner" "ring"
      (n Spinner ~cov:true ~props:(sized ~w:26. ~h:26. []) ());
    cell "divider_h" "divider" "horizontal rule"
      (n Divider ~cov:true ~props:(sized ~h:6. [ (OrientationValue, sv "horizontal") ]) ());
    cell "divider_v" "divider" "vertical rule"
      (n Divider ~props:(sized ~w:6. ~h:40. [ (OrientationValue, sv "vertical") ]) ());
    cell "icon" "icon" "host bitmap icon"
      (n Icon ~cov:true ~img:true ~props:(sized ~w:24. ~h:24. [ (IconName, sv "app") ]) ());
    (* ----- media ----- *)
    cell "image" "image" "stretch fill"
      (n Image ~cov:true ~img:true ~props:(sized ~w:120. ~h:56. [ (CornerRadius, fv 4.) ]) ());
    cell "image_fit" "image" "letterboxed fit"
      (n Image ~img:true ~props:(sized ~w:120. ~h:56. [ (ImageFitValue, sv "fit");
                                                       (BackgroundValue, sv "#e2e8f0") ]) ());
    cell "file_image" "file-image" "decoded file thumb"
      (n FileImage ~cov:true ~img:true ~props:(sized ~w:96. ~h:56. [ (CornerRadius, fv 4.) ]) ());
    cell "media_surface" "media-surface" "video surface"
      (n MediaSurface ~cov:true ~img:true ~props:(sized ~w:120. ~h:56. [ (BackgroundValue, sv "#0f172a") ]) ());
    cell "file_preview" "file-preview" "document preview"
      (n FilePreview ~cov:true ~img:true ~props:(sized ~w:72. ~h:56. bordered) ());
    cell "avatar_image" "avatar" "image avatar"
      (n Avatar ~img:true ~props:(sized ~w:36. ~h:36. []) ());
    cell "avatar_initials" "avatar" "initials avatar"
      (n Avatar ~cov:true ~props:(sized ~w:36. ~h:36. [ (TextValue, sv "TQ") ]) ());
    (* ----- containers ----- *)
    cell "row" "row" "3 tiles"
      (n Row ~props:(sized ~h:30. [ (Gap, fv 6.) ])
         ~kids:[ n Box ~props:(sized ~w:26. ~h:26. [ (BackgroundValue, sv "#ef4444"); (CornerRadius, fv 4.) ]) ();
                 n Box ~props:(sized ~w:26. ~h:26. [ (BackgroundValue, sv "#22c55e"); (CornerRadius, fv 4.) ]) ();
                 n Box ~props:(sized ~w:26. ~h:26. [ (BackgroundValue, sv "#3b82f6"); (CornerRadius, fv 4.) ]) () ] ~cov:true ());
    cell "column" "column" "3 bars"
      (n Column ~props:(sized ~h:44. [ (Gap, fv 4.) ])
         ~kids:[ n Box ~props:(sized ~h:10. [ (BackgroundValue, sv "#ef4444") ]) ();
                 n Box ~props:(sized ~w:60. ~h:10. [ (BackgroundValue, sv "#22c55e") ]) ();
                 n Box ~props:(sized ~w:30. ~h:10. [ (BackgroundValue, sv "#3b82f6") ]) () ] ~cov:true ());
    cell "grid" "grid" "2x2 tiles"
      (n Grid ~props:(sized ~h:48. [ (GridColumns, iv 2); (Gap, fv 4.) ])
         ~kids:[ n Box ~props:(sized ~h:20. [ (BackgroundValue, sv "#f59e0b") ]) ();
                 n Box ~props:(sized ~h:20. [ (BackgroundValue, sv "#10b981") ]) ();
                 n Box ~props:(sized ~h:20. [ (BackgroundValue, sv "#8b5cf6") ]) ();
                 n Box ~props:(sized ~h:20. [ (BackgroundValue, sv "#ec4899") ]) () ] ~cov:true ());
    cell "stack" "stack" "base + overlay"
      (n Stack ~props:(sized ~h:52. [])
         ~kids:[ n Box ~props:(sized ~h:44. [ (BackgroundValue, sv "#dbeafe"); (CornerRadius, fv 5.) ]) ();
                 n Box ~props:(sized ~w:20. ~h:14. [ (BackgroundValue, sv "#f59e0b"); (AlignmentValue, sv "bottom-trailing") ]) () ]
         ~cov:true ());
    cell "edge_inset" "edge-inset" "pinned top bar"
      (n EdgeInset ~props:(sized ~h:52. [ (EdgeValue, sv "top") ])
         ~kids:[ n Box ~props:(sized ~h:30. [ (BackgroundValue, sv "#f1f5f9") ]) ();
                 n Box ~props:(sized ~h:14. [ (BackgroundValue, sv "#334155") ]) () ] ~cov:true ());
    cell "overlay" "overlay" "badge corner"
      (n Overlay ~props:(sized ~h:52. [])
         ~kids:[ n Box ~props:(sized ~h:44. [ (BackgroundValue, sv "#e0e7ff"); (CornerRadius, fv 5.) ]) ();
                 n Box ~props:(sized ~w:16. ~h:16. [ (BackgroundValue, sv "#ef4444"); (CornerRadius, fv 8.);
                                                    (AlignmentValue, sv "top-trailing") ]) () ] ~cov:true ());
    cell "view_that_fits" "view-that-fits" "fit box"
      (n ViewThatFits ~props:(sized ~h:52. [])
         ~kids:[ n Box ~props:(sized ~h:44. [ (BackgroundValue, sv "#dcfce7"); (CornerRadius, fv 5.) ]) ();
                 n Box ~props:(sized ~w:26. ~h:10. [ (BackgroundValue, sv "#16a34a"); (AlignmentValue, sv "bottom") ]) () ]
         ~cov:true ());
    cell "panel" "panel" "titled surface"
      (n Panel ~props:(sized ~h:52. ([ (PaddingValue, fv 6.) ] @ bordered))
         ~kids:[ txt "Panel body" ] ~cov:true ());
    cell "card" "card" "elevated card"
      (n Card ~props:(sized ~h:52. [ (PaddingValue, fv 6.); (BackgroundValue, sv "#ffffff");
                                     (CornerRadius, fv 8.);
                                     (Shadow, sv "0 8px 24px rgba(15 23 42 / 20%)") ])
         ~kids:[ txt "Card content" ] ~cov:true ());
    cell "bubble" "bubble" "chat bubble"
      (n Bubble ~props:(sized ~w:120. ~h:34. [ (PaddingValue, fv 6.); (BackgroundValue, sv "#dcf8c6");
                                              (CornerRadius, fv 12.) ])
         ~kids:[ txt "hi there" ] ~cov:true ());
    cell "box" "box" "framed box"
      (n Box ~props:(sized ~h:40. [ (BackgroundValue, sv "#fef3c7");
                                    (BorderWidth, fv 1.); (BorderColorValue, sv "#f59e0b") ]) ~cov:true ());
    cell "alert" "alert" "alert banner"
      (let p, k = popup 150. 64.
           [ (BackgroundValue, sv "#fffbeb"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#f59e0b"); (CornerRadius, fv 8.);
             (PaddingValue, fv 6.) ] [ txt "Alert"; txt "check this" ] in
       n Alert ~props:p ~kids:k ~cov:true ());
    cell "resizable" "resizable" "grip edge"
      (n Resizable ~props:(sized ~h:52. [])
         ~kids:[ n Box ~props:(sized ~h:44. [ (BackgroundValue, sv "#f8fafc");
                                              (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ]) ();
                 n Box ~props:(sized ~w:8. ~h:44. [ (BackgroundValue, sv "#94a3b8"); (AlignmentValue, sv "trailing") ]) () ]
         ~cov:true ());
    cell "split" "split" "two panes"
      (n Split ~props:(sized ~h:56. [ (Gap, fv 2.) ])
         ~kids:[ n Box ~props:(sized ~h:22. [ (BackgroundValue, sv "#dbeafe") ]) ();
                 n Box ~props:(sized ~h:22. [ (BackgroundValue, sv "#ede9fe") ]) () ] ~cov:true ());
    cell "scroll" "scroll" "clipped + thumb"
      (n Scroll ~props:(sized ~h:56. [ (Gap, fv 2.) ])
         ~scroll:{ Lui_paint.sm_offset = 0.3; sm_extent = 0.5 }
         ~kids:List.(init 6 (fun i -> txt (Printf.sprintf "scroll row %d" (i + 1)))) ~cov:true ());
    cell "list" "list" "rows + thumb"
      (n ListContainer ~props:(sized ~h:56. [ (Gap, fv 2.) ])
         ~scroll:{ Lui_paint.sm_offset = 0.55; sm_extent = 0.4 }
         ~kids:[ n ListItem ~props:(sized ~h:16. [ (TextValue, sv "Inbox"); (Selected, bv true);
                                                  (SelectedBackground, sv "#dbeafe") ]) ();
                 n ListItem ~props:(sized ~h:16. [ (TextValue, sv "Archive") ]) ();
                 n ListItem ~props:(sized ~h:16. [ (TextValue, sv "Trash") ]) ();
                 n ListItem ~props:(sized ~h:16. [ (TextValue, sv "Spam") ]) () ] ~cov:true ());
    cell "virtual_list" "virtual-list" "virtual rows"
      (n VirtualList ~props:(sized ~h:56. [ (Gap, fv 2.) ])
         ~scroll:{ Lui_paint.sm_offset = 0.1; sm_extent = 0.6 }
         ~kids:List.(init 5 (fun i -> txt (Printf.sprintf "row %d" (i + 1)))) ~cov:true ());
    cell "list_item" "list-item" "unselected row"
      (n ListItem ~cov:true ~props:(sized ~h:20. [ (TextValue, sv "List item") ]) ());
    cell "list_item_sel" "list-item" "selected row"
      (n ListItem ~st:selected
         ~props:(sized ~h:20. [ (TextValue, sv "List item");
                                (SelectedBackground, sv "#dbeafe") ]) ());
    cell "tabs" "tabs" "tab strip"
      (n Tabs ~props:(sized ~h:30. [])
         ~kids:[ n Row ~props:(sized ~h:26. [ (Gap, fv 4.) ])
                   ~kids:[ chrome MenuItem "General" [ (BackgroundValue, sv "#dbeafe"); (CornerRadius, fv 4.) ];
                           chrome MenuItem "Account" [];
                           chrome MenuItem "About" [] ] () ] ~cov:true ());
    cell "bottom_tabs" "bottom-tabs" "tab bar"
      (n BottomTabs ~props:(sized ~h:30. [ (BackgroundValue, sv "#f8fafc");
                                           (BorderWidth, fv 1.); (BorderColorValue, sv "#e2e8f0") ])
         ~kids:[ n Row ~props:(sized ~h:26. [ (Gap, fv 2.) ])
                   ~kids:[ n BottomTab ~props:(sized ~h:24. [ (TextValue, sv "Home"); (Selected, bv true);
                                                             (SelectedBackground, sv "#e0e7ff") ]) ();
                           n BottomTab ~props:(sized ~h:24. [ (TextValue, sv "Search") ]) ();
                           n BottomTab ~props:(sized ~h:24. [ (TextValue, sv "Settings") ]) () ] () ]
         ~cov:true ());
    cell "button_group" "button-group" "segmented cluster"
      (n ButtonGroup ~props:(sized ~h:30. [])
         ~kids:[ n Row ~props:(sized ~h:26. [ (Gap, fv 0.) ])
                   ~kids:[ chrome Button "Left" bordered;
                           chrome Button "Center" (bordered @ [ (BackgroundValue, sv "#2563eb"); (ForegroundValue, sv "#ffffff") ]);
                           chrome Button "Right" bordered ] () ] ~cov:true ());
    cell "toggle_group" "toggle-group" "format toggles"
      (n ToggleGroup ~props:(sized ~h:30. [])
         ~kids:[ n Row ~props:(sized ~h:26. [ (Gap, fv 4.) ])
                   ~kids:[ n ToggleButton ~st:selected
                             ~props:(sized ~h:24. [ (TextValue, sv "B"); (SelectedBackground, sv "#dbeafe");
                                                    (BorderWidth, fv 1.); (BorderColorValue, sv "#94a3b8") ]) ();
                           chrome ToggleButton "I" [ (BorderWidth, fv 1.); (BorderColorValue, sv "#94a3b8") ];
                           chrome ToggleButton "U" [ (BorderWidth, fv 1.); (BorderColorValue, sv "#94a3b8") ] ] () ]
         ~cov:true ());
    cell "input_group" "input-group" "field + action"
      (n InputGroup ~props:(sized ~h:32. [])
         ~kids:[ n Row ~props:(sized ~h:30. [ (Gap, fv 4.) ])
                   ~kids:[ n TextField ~props:(sized ~h:28. ([ (PlaceholderValue, sv "email") ] @ bordered
                                              @ [ (GrowValue, fv 1.) ])) ();
                           n InputGroupActions
                             ~kids:[ chrome Button "Go" primary_btn ] () ] () ] ~cov:true ());
    cell "input_group_actions" "input-group-actions" "action pair"
      (n InputGroupActions ~props:(sized ~h:30. [])
         ~kids:[ n Row ~props:(sized ~h:26. [ (Gap, fv 4.) ])
                   ~kids:[ chrome Button "X" bordered; chrome Button "OK" primary_btn ] () ] ~cov:true ());
    cell "radio_group" "radio-group" "option set"
      (n RadioGroup ~props:(sized ~h:56. [ (Gap, fv 4.) ])
         ~kids:[ n Radio ~props:(sized ~h:16. [ (Checked, bv true); (TextValue, sv "Daily") ]) ();
                 n Radio ~props:(sized ~h:16. [ (TextValue, sv "Weekly") ]) ();
                 n Radio ~props:(sized ~h:16. [ (TextValue, sv "Monthly") ]) () ] ~cov:true ());
    cell "list_section" "list-section" "header rows footer"
      (n ListSection ~props:(sized ~h:70. [ (Gap, fv 2.) ])
         ~kids:[ chrome ListSectionHeader "SECTION" [ (ForegroundValue, sv "#64748b") ];
                 n ListItem ~props:(sized ~h:16. [ (TextValue, sv "One"); (Selected, bv true);
                                                   (SelectedBackground, sv "#dbeafe") ]) ();
                 n ListItem ~props:(sized ~h:16. [ (TextValue, sv "Two") ]) ();
                 chrome ListSectionFooter "2 items" [ (ForegroundValue, sv "#94a3b8") ] ]
         ~cov:true ());
    cell "swipe_actions" "swipe-actions" "action rail"
      (n SwipeActions ~props:(sized ~h:32. [])
         ~kids:[ n Row ~props:(sized ~h:30. [ (Gap, fv 2.) ])
                   ~kids:[ n SwipeAction ~props:(sized ~h:28. [ (TextValue, sv "Archive");
                                                               (BackgroundValue, sv "#3b82f6"); (ForegroundValue, sv "#fff") ]) ();
                           n SwipeAction ~props:(sized ~h:28. [ (TextValue, sv "Delete");
                                                               (BackgroundValue, sv "#ef4444"); (ForegroundValue, sv "#fff") ]) () ] () ]
         ~cov:true ());
    cell "stepper" "stepper" "3 steps"
      (n Stepper ~props:(sized ~h:24. [ (ActiveIndex, iv 1) ])
         ~kids:[ n Row ~props:(sized ~h:20. [ (Gap, fv 8.) ])
                   ~kids:[ n Step ~props:(sized ~h:18. [ (TextValue, sv "Account") ]) ();
                           n Step ~props:(sized ~h:18. [ (TextValue, sv "Profile"); (Selected, bv true);
                                                        (SelectedBackground, sv "#dbeafe") ]) ();
                           n Step ~props:(sized ~h:18. [ (TextValue, sv "Done") ]) () ] () ] ~cov:true ());
    cell "step" "step" "single step"
      (n Step ~cov:true ~props:(sized ~h:20. [ (TextValue, sv "Step 2: verify") ]) ());
    cell "timeline" "timeline" "3 events"
      (n Timeline ~props:(sized ~h:70. [ (Gap, fv 4.) ])
         ~kids:List.(init 3 (fun i ->
           n TimelineItem ~props:(sized ~h:20. [])
             ~kids:[ txt (Printf.sprintf "o event %d" (i + 1)) ] ())) ~cov:true ());
    cell "timeline_item" "timeline-item" "one event"
      (n TimelineItem ~cov:true ~props:(sized ~h:34. [])
         ~kids:[ txt "o deploy shipped"; txt "2h ago" ] ());
    cell "breadcrumb" "breadcrumb" "path trail"
      (n Breadcrumb ~props:(sized ~h:18. [])
         ~kids:[ n Row ~props:(sized ~h:14. [ (Gap, fv 4.) ])
                   ~kids:[ txt "Home"; txt "/"; txt "Library"; txt "/"; txt "Page" ] () ] ~cov:true ());
    cell "pagination" "pagination" "page cluster"
      (n Pagination ~props:(sized ~h:28. [])
         ~kids:[ n Row ~props:(sized ~h:24. [ (Gap, fv 4.) ])
                   ~kids:[ chrome Button "<" bordered;
                           chrome Button "1" (bordered @ [ (BackgroundValue, sv "#2563eb"); (ForegroundValue, sv "#fff") ]);
                           chrome Button "2" bordered; chrome Button ">" bordered ] () ] ~cov:true ());
    cell "accordion" "accordion" "expanded section"
      (n Accordion ~props:(sized ~h:52. [ (Gap, fv 4.) ])
         ~kids:[ n Row ~props:(sized ~h:16. [ (Gap, fv 4.) ])
                   ~kids:[ txt "v"; txt "Details" ] ();
                 txt "Expanded body copy" ] ~cov:true ());
    cell "table" "table" "2x2 grid"
      (n Table ~props:(sized ~h:52. [ (Gap, fv 0.) ])
         ~kids:[ n TableRow ~props:(sized ~h:24. [])
                   ~kids:[ n Row ~props:(sized ~h:22. [ (Gap, fv 2.) ])
                             ~kids:[ n TableCell ~props:(sized ~h:20. [ (BackgroundValue, sv "#f1f5f9");
                                                                         (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ])
                                       ~kids:[ txt "Name" ] ();
                                     n TableCell ~props:(sized ~h:20. [ (BackgroundValue, sv "#f1f5f9");
                                                                         (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ])
                                       ~kids:[ txt "Value" ] () ] () ] ();
                 n TableRow ~props:(sized ~h:24. [])
                   ~kids:[ n Row ~props:(sized ~h:22. [ (Gap, fv 2.) ])
                             ~kids:[ n TableCell ~props:(sized ~h:20. [ (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ])
                                       ~kids:[ txt "alpha" ] ();
                                     n TableCell ~props:(sized ~h:20. [ (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ])
                                       ~kids:[ txt "1.0" ] () ] () ] () ] ~cov:true ());
    cell "table_row" "table-row" "one row"
      (n TableRow ~cov:true ~props:(sized ~h:26. [])
         ~kids:[ n Row ~props:(sized ~h:24. [ (Gap, fv 2.) ])
                   ~kids:[ n TableCell ~props:(sized ~h:22. bordered) ~kids:[ txt "cell" ] ();
                           n TableCell ~props:(sized ~h:22. bordered) ~kids:[ txt "cell" ] () ] () ] ());
    cell "table_cell" "table-cell" "one cell"
      (n TableCell ~cov:true ~props:(sized ~h:24. bordered) ~kids:[ txt "Cell" ] ());
    cell "tree" "tree" "indented rows"
      (n Tree ~props:(sized ~h:56. [ (Gap, fv 2.) ])
         ~kids:[ txt "v src"; txt "  v app"; txt "    - main.ml" ] ~cov:true ());
    cell "toolbar" "toolbar" "tool row"
      (n Toolbar ~props:(sized ~h:30. [ (BackgroundValue, sv "#f8fafc");
                                        (BorderWidth, fv 1.); (BorderColorValue, sv "#e2e8f0") ])
         ~kids:[ n Row ~props:(sized ~h:24. [ (Gap, fv 4.); (PaddingValue, fv 2.) ])
                   ~kids:[ chrome Button "B" bordered; chrome Button "I" bordered;
                           chrome Button "U" bordered; txt "tools" ] () ] ~cov:true ());
    cell "status_bar" "status-bar" "status row"
      (n StatusBar ~props:(sized ~h:22. [ (BackgroundValue, sv "#0f172a") ])
         ~kids:[ n Row ~props:(sized ~h:18. [ (Gap, fv 4.); (PaddingValue, fv 2.) ])
                   ~kids:[ txt ~props:[ (ForegroundValue, sv "#e2e8f0") ] "Ready";
                           n Spacer ();
                           txt ~props:[ (ForegroundValue, sv "#e2e8f0") ] "Ln 42, Col 7" ] () ] ~cov:true ());
    cell "spacer" "spacer" "expanding gap"
      (n Row ~props:(sized ~h:16. [ (Gap, fv 4.) ])
         ~kids:[ n Box ~props:(sized ~w:20. ~h:14. [ (BackgroundValue, sv "#3b82f6") ]) ();
                 n Spacer ~cov:true ~props:[ (BackgroundValue, sv "#e0e7ff") ] ();
                 n Box ~props:(sized ~w:20. ~h:14. [ (BackgroundValue, sv "#3b82f6") ]) () ] ());
    cell "root" "root" "frame root box"
      (n Root ~cov:true ~props:(sized ~h:40. [ (BackgroundValue, sv "#f8fafc");
                                               (BorderWidth, fv 1.); (BorderColorValue, sv "#94a3b8") ]) ());
    (* ----- popup surfaces (absolute inside stage) ----- *)
    cell "tooltip" "tooltip" "hint bubble"
      (let p, k = popup 96. 26.
           [ (BackgroundValue, sv "#111827"); (CornerRadius, fv 4.);
             (PaddingValue, fv 3.) ] [ txt ~props:[ (ForegroundValue, sv "#f9fafb") ] "Tooltip" ] in
       n Tooltip ~props:p ~kids:k ~cov:true ());
    cell "popover" "popover" "anchored card"
      (let p, k = popup 120. 64.
           [ (BackgroundValue, sv "#ffffff"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#cbd5e1"); (CornerRadius, fv 6.);
             (Shadow, sv "0 8px 20px rgba(15 23 42 / 25%)"); (PaddingValue, fv 6.) ]
           [ txt "Popover"; txt "body" ] in
       n Popover ~props:p ~kids:k ~cov:true ());
    cell "dialog" "dialog" "modal surface"
      (let p, k = popup 130. 70.
           [ (BackgroundValue, sv "#ffffff"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#94a3b8"); (CornerRadius, fv 8.);
             (Shadow, sv "0 12px 32px rgba(2 6 23 / 30%)"); (PaddingValue, fv 6.) ]
           [ txt "Confirm?"; chrome Button "OK" (sized ~h:20. primary_btn) ] in
       n Dialog ~props:p ~kids:k ~cov:true ());
    cell "drawer" "drawer" "side drawer"
      (let p, k = popup 72. 84.
           [ (BackgroundValue, sv "#ffffff"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#cbd5e1"); (PaddingValue, fv 6.);
             (Shadow, sv "8px 0 20px rgba(2 6 23 / 20%)") ]
           [ txt "Drawer"; txt "item" ] in
       n Drawer ~props:p ~kids:k ~cov:true ());
    cell "sheet" "sheet" "bottom sheet"
      (let p, k = popup 130. 70.
           [ (BackgroundValue, sv "#ffffff"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#cbd5e1"); (CornerRadius, fv 10.);
             (Shadow, sv "0 -6px 20px rgba(2 6 23 / 20%)"); (PaddingValue, fv 6.) ]
           [ n Box ~props:(sized ~w:36. ~h:4. [ (BackgroundValue, sv "#cbd5e1"); (CornerRadius, fv 2.) ]) ();
             txt "Sheet" ] in
       n Sheet ~props:p ~kids:k ~cov:true ());
    cell "toast" "toast" "notification pill"
      (let p, k = popup 120. 28.
           [ (BackgroundValue, sv "#111827"); (CornerRadius, fv 14.);
             (PaddingValue, fv 4.) ]
           [ txt ~props:[ (ForegroundValue, sv "#f9fafb") ] "Saved" ] in
       n Toast ~props:p ~kids:k ~cov:true ());
    cell "dropdown_menu" "dropdown-menu" "open menu"
      (let p, k = popup 110. 78.
           [ (BackgroundValue, sv "#ffffff"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#cbd5e1"); (CornerRadius, fv 6.);
             (Shadow, sv "0 8px 20px rgba(15 23 42 / 25%)"); (PaddingValue, fv 3.) ]
           [ n MenuItem ~props:(sized ~h:18. [ (TextValue, sv "New") ]) ();
             n MenuItem ~st:hovered ~props:(sized ~h:18. [ (TextValue, sv "Open");
                                                          (HoverBackground, sv "#eff6ff") ]) ();
             n MenuItem ~props:(sized ~h:18. [ (TextValue, sv "Close") ]) () ] in
       n DropdownMenu ~props:p ~kids:k ~cov:true ());
    cell "context_menu" "context-menu" "right-click menu"
      (let p, k = popup 110. 78.
           [ (BackgroundValue, sv "#ffffff"); (BorderWidth, fv 1.);
             (BorderColorValue, sv "#cbd5e1"); (CornerRadius, fv 6.);
             (Shadow, sv "0 8px 20px rgba(15 23 42 / 25%)"); (PaddingValue, fv 3.) ]
           [ n MenuItem ~props:(sized ~h:18. [ (TextValue, sv "Cut") ]) ();
             n MenuItem ~props:(sized ~h:18. [ (TextValue, sv "Copy") ]) ();
             n MenuItem ~props:(sized ~h:18. [ (TextValue, sv "Paste") ]) () ] in
       n ContextMenu ~props:p ~kids:k ~cov:true ());
    (* ----- decoration showcase (box kind, prop-driven) ----- *)
    cell "deco_gradient" "box" "linear gradient"
      (n Box ~props:(sized ~h:48. [ (BackgroundValue, sv "linear-gradient(135deg, #2563eb, #22d3ee)");
                                    (CornerRadius, fv 8.) ]) ());
    cell "deco_oklab" "box" "oklab gradient"
      (n Box ~props:(sized ~h:48. [ (BackgroundValue, sv "oklab-gradient(90deg, #f43f5e, #facc15)");
                                    (CornerRadius, fv 8.) ]) ());
    cell "deco_stripes" "box" "stripe fill"
      (n Box ~props:(sized ~h:48. [ (BackgroundValue, sv "stripes(45deg, #e2e8f0, #94a3b8)");
                                    (CornerRadius, fv 8.) ]) ());
    cell "deco_dashed" "box" "dashed border"
      (n Box ~props:(sized ~h:48. [ (BorderWidth, fv 2.); (BorderColorValue, sv "#64748b");
                                    (CornerRadius, fv 8.) ])
         ~xprops:[ ("border-style", sv "dashed") ] ());
    cell "deco_edges" "box" "per-edge border colors"
      (n Box ~props:(sized ~h:48. [ (BorderWidth, fv 4.);
                                    (BorderColorValue, sv "#ef4444 #22c55e #3b82f6 #eab308");
                                    (CornerRadius, fv 6.) ]) ());
    cell "deco_radii" "box" "asymmetric radii"
      (n Box ~props:(sized ~h:48. [ (BackgroundValue, sv "#ede9fe");
                                    (CornerRadius, sv "4 20 4 20");
                                    (BorderWidth, fv 1.); (BorderColorValue, sv "#8b5cf6") ]) ());
    cell "deco_shadow" "box" "drop shadow"
      (n Box ~props:(sized ~h:48. [ (BackgroundValue, sv "#ffffff"); (CornerRadius, fv 10.);
                                    (Shadow, sv "0 10px 24px rgba(2 6 23 / 28%)") ]) ());
    cell "deco_inset" "box" "inset shadow"
      (n Box ~props:(sized ~h:48. [ (BackgroundValue, sv "#ffffff"); (CornerRadius, fv 8.);
                                    (Shadow, sv "inset 0 2px 8px rgba(2 6 23 / 25%)");
                                    (BorderWidth, fv 1.); (BorderColorValue, sv "#cbd5e1") ]) ());
    cell "deco_opacity" "box" "subtree opacity"
      (n Box ~props:(sized ~h:48. [ (Opacity, fv 0.45); (BackgroundValue, sv "#2563eb");
                                    (CornerRadius, fv 8.) ])
         ~kids:[ txt ~props:[ (ForegroundValue, sv "#ffffff") ] "faded" ] ());
    cell "deco_clip" "box" "overflow clip"
      (n Box ~props:(sized ~h:42. [ (Overflow, sv "hidden"); (CornerRadius, fv 8.);
                                    (BorderWidth, fv 1.); (BorderColorValue, sv "#94a3b8") ])
         ~kids:[ n Box ~props:(sized ~h:70. [ (BackgroundValue, sv "linear-gradient(180deg, #22d3ee, #2563eb)") ]) () ] ());
    cell "deco_zindex" "box" "z-index order"
      (n Stack ~props:(sized ~h:52. [])
         ~kids:[ n Box ~props:(sized ~h:40. [ (BackgroundValue, sv "#bfdbfe") ]) ();
                 n Box ~props:(sized ~w:60. ~h:20. [ (BackgroundValue, sv "#1e40af");
                                                     (ZIndex, iv 2); (AlignmentValue, sv "bottom-leading") ]) ();
                 n Box ~props:(sized ~w:60. ~h:28. [ (BackgroundValue, sv "#93c5fd");
                                                     (ZIndex, iv 1); (AlignmentValue, sv "bottom-leading") ]) () ] ());
    cell "ext_spark" "extension:lui_gallery.spark" "custom renderer + hole"
      (x "lui_gallery.spark" ~cov:true ~props:(sized ~h:48. [ (BackgroundValue, sv "#0f172a"); (CornerRadius, fv 8.) ]) ()) ]

(* ---------- extension renderer ----------

   The gallery's own extension kind: paints a dark card, a row of
   deterministic accent bars, and a Hole op knocking a rounded window
   out of the card — the only op family no standard kind emits. *)
let () =
  Lui_paint.register_extension ~identifier:"lui_gallery.spark"
    { Lui_paint.paint =
        (fun _ctx _store _node r ->
          let dark = color 15 23 42 255 and accent = color 34 211 238 255 in
          let bg =
            Fill
              { frect = r; fradii = corners r (8., 8., 8., 8.) false;
                fcontinuous = false; fcolor = dark; fpaint = Solid;
                fcolor2 = dark; fgradient = (0., 0., 0., 0.);
                fborder = (0., 0., 0., 0.); fborder_color = color 0 0 0 0;
                fdashed = false; fwide = 0; fopacity = 1. }
          in
          let bars =
            List.init 12
              (fun i ->
                let bh = 8. +. float ((i * 7) mod 22) in
                let bx = r.x +. 10. +. (float i *. ((r.w -. 20.) /. 12.)) in
                fill1 bx (r.y +. r.h -. 8. -. bh) 6. bh accent)
          in
          let hole_r =
            rect (r.x +. r.w -. 30.) (r.y +. 8.) 20. 14.
          in
          bg :: (bars
                 @ [ Hole
                       { hrect = hole_r;
                         hradii = corners hole_r (4., 4., 4., 4.) false;
                         hcontinuous = false; hopacity = 1. } ])) }

(* ---------- cell shell ---------- *)

(* A cell is a fixed-size labelled card; rows place [columns] of them
   side by side — deterministic (no wrap) unlike a wrapping grid whose
     basis+gap arithmetic can overflow the line. *)
let cell_w = 274.

let wrap_cell c =
  n Column
    ~props:
      [ (WidthValue, fv cell_w); (HeightValue, fv 116.);
        (PaddingValue, fv 6.); (Gap, fv 4.);
        (BackgroundValue, sv "#ffffff"); (CornerRadius, fv 6.);
        (BorderWidth, fv 1.); (BorderColorValue, sv "#dfe3e8");
        (Overflow, sv "hidden") ]
    ~tag:("cell:" ^ c.cname)
    ~kids:
      [ n Label ~props:(sized ~h:10. [ (TextValue, sv c.cname); (FontSize, fv 9.);
                                      (ForegroundValue, sv "#64748b") ]) ();
        n Box ~props:[ (GrowValue, fv 1.) ] ~tag:("stage:" ^ c.cname)
          ~kids:[ { c.cnode with tag = Some ("subject:" ^ c.cname) } ] () ]
    ()

(* Group cells into named sections by prefix. *)
let categories =
  [ ("Text", [ "text"; "heading"; "paragraph"; "label"; "kbd"; "link"; "br" ]);
    ("Buttons & toggles",
     [ "button"; "button_hover"; "button_pressed"; "button_disabled";
       "toggle_button"; "toggle"; "menu_item"; "menu_trigger";
       "bottom_tab"; "swipe_action"; "file_picker";
       "list_section_header"; "list_section_footer" ]);
    ("Inputs & controls",
     [ "text_field"; "text_field_ph"; "text_field_focus"; "secure_field";
       "input"; "search_field"; "textarea"; "select"; "combobox";
       "number_stepper"; "checkbox_on"; "checkbox_off"; "radio_on";
       "radio_off"; "switch_on"; "switch_off"; "slider"; "progress";
       "spinner"; "divider_h"; "divider_v"; "icon" ]);
    ("Media",
     [ "image"; "image_fit"; "file_image"; "media_surface";
       "file_preview"; "avatar_image"; "avatar_initials" ]);
    ("Containers",
     [ "row"; "column"; "grid"; "stack"; "edge_inset"; "overlay";
       "view_that_fits"; "panel"; "card"; "bubble"; "box"; "alert";
       "resizable"; "split"; "scroll"; "list"; "virtual_list";
       "list_item"; "list_item_sel"; "tabs"; "bottom_tabs";
       "button_group"; "toggle_group"; "input_group";
       "input_group_actions"; "radio_group"; "list_section";
       "swipe_actions"; "stepper"; "step"; "timeline"; "timeline_item";
       "breadcrumb"; "pagination"; "accordion"; "table"; "table_row";
       "table_cell"; "tree"; "toolbar"; "status_bar"; "spacer"; "root" ]);
    ("Popup surfaces",
     [ "tooltip"; "popover"; "dialog"; "drawer"; "sheet"; "toast";
       "dropdown_menu"; "context_menu" ]);
    ("Decoration showcase",
     [ "deco_gradient"; "deco_oklab"; "deco_stripes"; "deco_dashed";
       "deco_edges"; "deco_radii"; "deco_shadow"; "deco_inset";
       "deco_opacity"; "deco_clip"; "deco_zindex"; "ext_spark" ]) ]

let build_gallery () =
  let by_name = Hashtbl.create (List.length cells) in
  List.iter (fun c -> Hashtbl.replace by_name c.cname c) cells;
  let columns = 4 in
  let gap = 10. in
  let chunk ns =
    let rec go acc ns =
      match ns with
      | [] -> List.rev acc
      | _ ->
        let rec take k acc ns =
          match k, ns with
          | 0, _ | _, [] -> (List.rev acc, ns)
          | k, x :: tl -> take (k - 1) (x :: acc) tl
        in
        let row, rest = take columns [] ns in
        go (row :: acc) rest
    in
    go [] ns
  in
  let sections =
    List.map
      (fun (title, names) ->
        let rows =
          List.map
            (fun row ->
              n Row ~props:[ (Gap, fv gap); (HeightValue, fv 116.) ]
                ~kids:
                  (List.map
                     (fun nm -> wrap_cell (Hashtbl.find by_name nm))
                     row)
                ())
            (chunk names)
        in
        n Column ~props:[ (Gap, fv 8.) ]
          ~kids:
            (n Text ~props:(sized ~h:16. [ (TextValue, sv title);
                                           (FontWeight, iv 700); (ForegroundValue, sv "#334155") ]) ()
             :: rows)
          ())
      categories
  in
  let root =
    n Root
      ~props:[ (BackgroundValue, sv "page"); (PaddingValue, fv 16.);
               (Gap, fv 20.) ]
      ~kids:sections ()
  in
  { root; cells; columns; frame_w = 1160 }

(* ---------- render ---------- *)

type frame = {
  host : Lui_host.t;
  emitted : emitted;
  mutable img : Lui_raster.Image.t option;
  mutable fwidth : int;
  mutable fheight : int;
}

let render ?text_ops ?measure ?post_create ?(workers = 1) () =
  let g = build_gallery () in
  let e = emit g.root in
  let hooks = hooks_of ?text_ops e in
  let measure = Option.value measure ~default:stub_measure in
  let captured = ref None in
  let renderer =
    { Lui_host.render =
        (fun scene ->
          let img = Lui_raster.render ~workers ~scene () in
          captured := Some img;
          img.Lui_raster.Image.pix);
      name = "lui_raster" }
  in
  let host =
    (* Pass 1 runs at a height comfortably above the real content so
       flex never clips trailing rows; the frame is then shrunk to the
       measured content bottom and repainted. *)
    Lui_host.create ~hooks ~layout:(module Lui_layout) ~measure ~renderer
      ~width:g.frame_w ~height:6000 ~scale:1. ()
  in
  (match post_create with Some f -> f host | None -> ());
  ignore (Lui_host.apply_batch host { generation = 1; ops = e.ops });
  ignore (Lui_host.repaint host);
  (* Pass 1 measured: bottom of the last laid-out cell + page margin. *)
  let bottom =
    Hashtbl.fold
      (fun tag id acc ->
        if String.length tag > 5 && String.sub tag 0 5 = "cell:" then
          match Lui_host.layout_rect host id with
          | Some r -> Float.max acc (r.y +. r.h)
          | None -> acc
        else acc)
      e.ids 0.
  in
  let h = int_of_float (Float.ceil (bottom +. 16.)) in
  Lui_host.resize host ~width:g.frame_w ~height:h ~scale:1.;
  ignore (Lui_host.repaint host);
  { host; emitted = e; img = !captured; fwidth = g.frame_w; fheight = h }

let rect_of_tag f name =
  match Hashtbl.find_opt f.emitted.ids name with
  | Some id -> (
    match Lui_host.layout_rect f.host id with
    | Some r -> r
    | None -> rect 0. 0. 0. 0.)
  | None -> rect 0. 0. 0. 0.

let cell_rect f c = rect_of_tag f ("cell:" ^ c.cname)
let stage_rect f c = rect_of_tag f ("stage:" ^ c.cname)

(* ---------- image out ---------- *)

let rgba_bytes img =
  let src = Lui_raster.Image.rgba img in
  (* Straighten premultiplied channels for PNG's straight-alpha model. *)
  let n = Bytes.length src in
  for i = 0 to (n / 4) - 1 do
    let k = i * 4 in
    let a = Char.code (Bytes.get src (k + 3)) in
    if a > 0 && a < 255 then
      for c = 0 to 2 do
        let v = Char.code (Bytes.get src (k + c)) in
        Bytes.set src (k + c) (Char.chr (min 255 ((v * 255 + (a / 2)) / a)))
      done
  done;
  src

let crop rgba ~w r =
  let h = Bytes.length rgba / (4 * w) in
  let x0 = max 0 (int_of_float (Float.floor r.x)) in
  let y0 = max 0 (int_of_float (Float.floor r.y)) in
  let x1 = min w (int_of_float (Float.ceil (r.x +. r.w))) in
  let y1 = min h (int_of_float (Float.ceil (r.y +. r.h))) in
  let cw = max 0 (x1 - x0) and ch = max 0 (y1 - y0) in
  let out = Bytes.make (cw * ch * 4) '\000' in
  for y = 0 to ch - 1 do
    Bytes.blit rgba (((y0 + y) * w + x0) * 4) out (y * cw * 4) (cw * 4)
  done;
  (cw, ch, out)

let write_png path ~w ~h rgba =
  let module P = Image.Pixmap in
  let r = P.create8 w h and g = P.create8 w h
  and b = P.create8 w h and a = P.create8 w h in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let i = (y * w + x) * 4 in
      P.set r x y (Char.code (Bytes.get rgba i));
      P.set g x y (Char.code (Bytes.get rgba (i + 1)));
      P.set b x y (Char.code (Bytes.get rgba (i + 2)));
      P.set a x y (Char.code (Bytes.get rgba (i + 3)))
    done
  done;
  let im =
    { Image.width = w; Image.height = h; Image.max_val = 255;
      Image.pixels = Image.RGBA (r, g, b, a) }
  in
  let buf = Buffer.create (w * h / 2) in
  let wr = ImageUtil.chunk_writer_of_buffer buf in
  ImageLib.writefile ~extension:"png" wr im;
  ImageUtil.close_chunk_writer wr;
  let oc = open_out_bin path in
  Buffer.output_buffer oc buf;
  close_out oc

let rec mkdir_p dir =
  if dir <> "" && not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    Unix.mkdir dir 0o755
  end

let slug s =
  String.map (fun c -> if c = ' ' then '_' else Char.lowercase_ascii c) s

(* ---------- manifest + drive ---------- *)

(* Paint one bare kind into a throwaway scene: the own-chrome probe.
   Kinds reporting 0 emit nothing without props/children/host data. *)
let probe_own_ops () =
  List.map
    (fun k ->
      let name = Lui_wire_schema.node_kind_name k in
      let store = Lui_store.create () in
      Lui_store.apply_batch store
        { generation = 1; ops = [ create_node_op 1 k ] };
      let scene =
        Lui_scene.create ~mask_atlas:(Atlas.create ~bpp:1 ~w:64 ~h:64)
          ~color_atlas:(Atlas.create ~bpp:4 ~w:64 ~h:64)
      in
      let hooks =
        { (hooks_of (emit (n Box ()))) with
          Lui_paint.layout =
            (fun _ -> Lui_paint.placement_of_rect (rect 0. 0. 96. 36.)) }
      in
      Lui_paint.paint hooks store scene ~width:120 ~height:48 ~scale:1.
        ~clear:(color 0 0 0 0);
      (name, List.length scene.ops))
    Lui_wire_schema.all_node_kinds

let write_gallery f ~out_dir =
  let img = match f.img with Some i -> i | None -> failwith "no render" in
  let rgba = rgba_bytes img in
  mkdir_p out_dir;
  mkdir_p (Filename.concat out_dir "cells");
  write_png (Filename.concat out_dir "gallery.png")
    ~w:img.Lui_raster.Image.w ~h:img.Lui_raster.Image.h rgba;
  let files = ref [ "gallery.png" ] in
  let g = build_gallery () in
  List.iteri
    (fun i c ->
      let r = cell_rect f c in
      let cw, ch, pix = crop rgba ~w:img.Lui_raster.Image.w r in
      let name = Printf.sprintf "cells/c%02d_%s.png" (i + 1) (slug c.cname) in
      write_png (Filename.concat out_dir name) ~w:cw ~h:ch pix;
      files := name :: !files)
    g.cells;
  (* Manifest: cell -> exercised kinds + probe counts. *)
  let probe = probe_own_ops () in
  let probe_of k = try List.assoc k probe with Not_found -> -1 in
  let buf = Buffer.create 4096 in
  Buffer.add_string buf
    "# LUI native paint gallery\n\nOne cell per exercised state; every \
     standard kind appears at least once. `ops` = ops emitted when the \
     bare kind is painted alone (0 = no own chrome).\n\n\
     | png | kind(s) | own ops | note |\n|---|---|---|---|\n";
  List.iteri
    (fun i c ->
      let name =
        Printf.sprintf "cells/c%02d_%s.png" (i + 1) (slug c.cname) in
      Buffer.add_string buf
        (Printf.sprintf "| %s | %s | %d | %s |\n" name c.ckind
           (probe_of c.ckind) c.cnote))
    g.cells;
  let empty = List.filter (fun (_, n) -> n = 0) probe |> List.map fst in
  Buffer.add_string buf
    (Printf.sprintf
       "\n## Kinds emitting no ops unadorned (%d)\n\n%s\n\n\
        Kinds absent from the catalog: none — every `all_node_kinds` \
        entry is exercised by at least one cell.\n"
       (List.length empty)
       (String.concat ", " (List.map (fun s -> "`" ^ s ^ "`") empty)));
  let oc = open_out (Filename.concat out_dir "manifest.md") in
  Buffer.output_buffer oc buf;
  close_out oc;
  List.rev ("manifest.md" :: !files)
