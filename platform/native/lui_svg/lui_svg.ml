(* SVG subset decoding and CPU rasterization for the native backend.
   See lui_svg.mli for the contract and the supported subset.

   Layout of this file:
     utilities           float/byte helpers
     xml                 lenient XML-subset tokenizer/tree builder
     numbers             tolerant number scanners
     colors              sRGB value parsing + the named-color table
     matrices            2x3 affine transforms
     paths               d-attribute parser -> symbolic segments
     flattening          curves/arcs -> polylines at device tolerance
     css                 minimal style-sheet parser + selector match
     styles              the paint/style property cascade
     document            doc assembly: ids, style sheets, viewBox
     painter             fill/stroke paint sources -> per-pixel color
     coverage            signed-area scanline rasterizer + blending
     stroke              dash splitting + stroke-to-outline expansion
     render              the element walk: groups, use, clip, mask,
                         opacity layers, viewBox fitting
     api                 the public functions *)

(* ============================ utilities ============================ *)

let fmin = Float.min and fmax = Float.max
let ifloor v = int_of_float (Float.floor v)
let iceil v = int_of_float (Float.ceil v)
let clamp01 v = if v <= 0. then 0. else if v >= 1. then 1. else v
let to8 v = if v <= 0. then 0 else if v >= 1. then 255 else int_of_float (v *. 255. +. 0.5)
let finite v = v = v && v <> Float.infinity && v <> Float.neg_infinity

type pt = float * float

let pt_x = fst and pt_y = snd

(* Element-local name: strip a namespace prefix (svg:path -> path). *)
let trim s = String.trim s
let lower s = String.lowercase_ascii s

let local_name s =
  let s =
    match String.index_opt s ':' with
    | Some i -> String.sub s (i + 1) (String.length s - i - 1)
    | None -> s
  in
  lower s

let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r'


(* ============================ xml ============================ *)

type xml = {
  xtag : string;
  xattrs : (string * string) list;
  mutable xkids : xml list;
  xtext : Buffer.t;
}

let xattr e name =
  match List.find_opt (fun (k, _) -> k = name) e.xattrs with
  | Some (_, v) -> Some v
  | None -> None

let xtext_of e = Buffer.contents e.xtext

(* Decode the five predefined entities plus numeric character
   references; unknown entities stay literal. *)
let decode_entities s =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '&' then begin
      match String.index_from_opt s !i ';' with
      | Some j when j - !i <= 12 ->
        let ent = String.sub s (!i + 1) (j - !i - 1) in
        let decoded =
          match ent with
          | "amp" -> Some "&" | "lt" -> Some "<" | "gt" -> Some ">"
          | "quot" -> Some "\"" | "apos" -> Some "'"
          | _ ->
            if String.length ent > 1 && ent.[0] = '#' then
              let code =
                if String.length ent > 2 && (ent.[1] = 'x' || ent.[1] = 'X') then
                  int_of_string_opt ("0x" ^ String.sub ent 2 (String.length ent - 2))
                else int_of_string_opt (String.sub ent 1 (String.length ent - 1))
              in
              (match code with
               | Some c when c >= 0 && c <= 0x10FFFF ->
                 Some (String.init 1 (fun _ -> Char.chr (min c 0xFF)))
               | _ -> None)
            else None
        in
        (match decoded with
         | Some d -> Buffer.add_string b d; i := j + 1
         | None -> Buffer.add_char b s.[!i]; incr i)
      | _ -> Buffer.add_char b s.[!i]; incr i
    end
    else begin
      Buffer.add_char b s.[!i]; incr i
    end
  done;
  Buffer.contents b

exception Bad of string

let bad fmt = Printf.ksprintf (fun m -> raise (Bad m)) fmt

(* XML subset -> element tree. Accepts comments, PIs, DOCTYPE (with an
   internal subset), CDATA, self-closing tags and single/double quoted
   attributes. Errors on mismatched tags, unterminated constructs and
   stray markup. *)
let parse_xml (src : string) : (xml, string) result =
  let n = String.length src in
  let s = src in
  let i = ref 0 in
  let is_name_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_' || c = '-' || c = ':' || c = '.'
  in
  let skip_space () = while !i < n && is_space s.[!i] do incr i done in
  let take_name () =
    let j = !i in
    while !i < n && is_name_char s.[!i] do incr i done;
    String.sub s j (!i - j)
  in
  (* skip until [stop] string; false when unterminated *)
  let skip_past stop =
    let sl = String.length stop in
    let rec find k =
      if k + sl > n then false
      else if String.sub s k sl = stop then (i := k + sl; true)
      else find (k + 1)
    in
    find !i
  in
  (* skip an <! ... > declaration, honoring a [ ] internal subset *)
  let skip_decl () =
    let depth = ref 0 and done_ = ref false in
    while not !done_ && !i < n do
      match s.[!i] with
      | '[' -> incr depth; incr i
      | ']' -> decr depth; incr i
      | '>' when !depth <= 0 -> done_ := true; incr i
      | _ -> incr i
    done;
    !done_
  in
  let stack = ref [] in
  let roots = ref [] in
  let push tag attrs =
    stack := { xtag = tag; xattrs = attrs; xkids = []; xtext = Buffer.create 16 } :: !stack
  in
  let emit tag attrs =
    (* a finished element joins its parent's children *)
    let e = { xtag = tag; xattrs = attrs; xkids = []; xtext = Buffer.create 0 } in
    match !stack with
    | [] -> roots := e :: !roots
    | top :: _ -> top.xkids <- e :: top.xkids
  in
  let add_text t =
    match !stack with
    | top :: _ -> Buffer.add_string top.xtext t
    | [] -> ()
  in
  let pop name =
    match !stack with
    | [] -> bad "unexpected </%s>" name
    | top :: rest ->
      if top.xtag <> name then bad "mismatched </%s>, expected </%s>" name top.xtag;
      stack := rest;
      let top = { top with xkids = List.rev top.xkids } in
      (match rest with
       | [] -> roots := top :: !roots
       | p :: _ -> p.xkids <- top :: p.xkids)
  in
  (try
     while !i < n do
       if s.[!i] = '<' && !i + 1 < n then begin
         match s.[!i + 1] with
         | '?' ->
           i := !i + 2;
           if not (skip_past "?>") then bad "unterminated processing instruction"
         | '!' ->
           if !i + 3 < n && s.[!i + 2] = '-' && s.[!i + 3] = '-' then begin
             i := !i + 4;
             if not (skip_past "-->") then bad "unterminated comment"
           end
           else if !i + 8 < n && String.sub s (!i + 2) 7 = "[CDATA[" then begin
             i := !i + 9;
             let start = !i in
             if not (skip_past "]]>") then bad "unterminated CDATA";
             add_text (String.sub s start (!i - start - 3))
           end
           else begin
             i := !i + 2;
             if not (skip_decl ()) then bad "unterminated declaration"
           end
         | '/' ->
           i := !i + 2;
           let name = take_name () in
           if name = "" then bad "empty closing tag";
           skip_space ();
           if !i >= n || s.[!i] <> '>' then bad "malformed closing tag";
           incr i;
           pop name
         | _ ->
           incr i;
           let tag = take_name () in
           if tag = "" then bad "expected element name";
           let attrs = ref [] in
           let selfclose = ref false in
           let rec attr_loop () =
             skip_space ();
             if !i >= n then bad "unterminated <%s>" tag;
             match s.[!i] with
             | '/' ->
               incr i;
               if !i >= n || s.[!i] <> '>' then bad "malformed <%s/>" tag;
               incr i;
               selfclose := true
             | '>' -> incr i
             | _ ->
               let k = take_name () in
               if k = "" then bad "bad attribute in <%s>" tag;
               skip_space ();
               let v =
                 if !i < n && s.[!i] = '=' then begin
                   incr i;
                   skip_space ();
                   if !i >= n then bad "unterminated attribute";
                   match s.[!i] with
                   | '"' | '\'' as q ->
                     let q = q in
                     incr i;
                     let start = !i in
                     while !i < n && s.[!i] <> q do incr i done;
                     if !i >= n then bad "unterminated attribute value";
                     let v = decode_entities (String.sub s start (!i - start)) in
                     incr i;
                     v
                   | _ ->
                     (* unquoted value: take until space or > *)
                     let start = !i in
                     while !i < n && (not (is_space s.[!i])) && s.[!i] <> '>' do incr i done;
                     decode_entities (String.sub s start (!i - start))
                 end
                 else ""
               in
               attrs := (k, v) :: !attrs;
               attr_loop ()
           in
           attr_loop ();
           if !selfclose then emit tag (List.rev !attrs)
           else push tag (List.rev !attrs)
       end
       else begin
         (* a lone < at end of input is malformed *)
         if s.[!i] = '<' then bad "lone '<' at end of input";
         let start = !i in
         while !i < n && s.[!i] <> '<' do incr i done;
         add_text (decode_entities (String.sub s start (!i - start)))
       end
     done;
     (match !stack with
      | top :: _ -> bad "unclosed <%s>" top.xtag
      | [] ->
        match List.rev !roots with
        | [ r ] -> Ok r
        | [] -> Error "no root element"
        | _ :: _ -> Error "multiple top-level elements")
   with
   | Bad m -> Error m)

(* ============================ numbers ============================ *)

(* Scan a float at [i]: optional sign, digits with optional '.',
   optional exponent. Returns (value, next_index). *)
let scan_num s i =
  let n = String.length s in
  let j = ref i in
  let isd k = s.[k] >= '0' && s.[k] <= '9' in
  if !j < n && (s.[!j] = '+' || s.[!j] = '-') then incr j;
  let mdig = ref 0 in
  while !j < n && isd !j do incr j; incr mdig done;
  if !j < n && s.[!j] = '.' then begin
    incr j;
    while !j < n && isd !j do incr j; incr mdig done
  end;
  if !mdig = 0 then None
  else begin
    (* exponent only when digits follow *)
    if !j < n && (s.[!j] = 'e' || s.[!j] = 'E') then begin
      let e = !j in
      incr j;
      if !j < n && (s.[!j] = '+' || s.[!j] = '-') then incr j;
      let d0 = !j in
      while !j < n && isd !j do incr j done;
      if !j = d0 then j := e
    end;
    match float_of_string_opt (String.sub s i (!j - i)) with
    | Some v when finite v -> Some (v, !j)
    | _ -> None
  end

let is_sep c = is_space c || c = ','

let skip_sep s i =
  let n = String.length s in
  let j = ref i in
  while !j < n && is_sep s.[!j] do incr j done;
  !j

(* All numbers of [s] separated by space/comma. [Bad] on trailing junk. *)
let num_list s =
  let n = String.length s in
  let rec go i acc =
    let i = skip_sep s i in
    if i >= n then List.rev acc
    else match scan_num s i with
      | Some (v, j) -> go j (v :: acc)
      | None -> bad "malformed number list '%s'" s
  in
  go 0 []

let num_list_opt s = try Some (num_list s) with Bad _ -> None

(* A CSS <length>: number plus optional unit. [%] resolves against
   [pct_base]. em/ex use the 16px default font size. *)
let parse_length ?(pct_base = 1.) ?(default = Float.nan) s =
  let s = trim s in
  match scan_num s 0 with
  | None -> default
  | Some (v, j) ->
    let u = trim (String.sub s j (String.length s - j)) in
    (match lower u with
     | "" | "px" -> v
     | "%" -> v *. pct_base /. 100.
     | "pt" -> v *. 4. /. 3.
     | "pc" -> v *. 16.
     | "mm" -> v *. 96. /. 25.4
     | "cm" -> v *. 96. /. 2.54
     | "in" -> v *. 96.
     | "em" -> v *. 16.
     | "ex" -> v *. 8.
     | _ -> default)

(* ============================ colors ============================ *)

(* Straight sRGB, 0..1 floats. *)
type color = float * float * float * float

let black = (0., 0., 0., 1.)
let clear_c = (0., 0., 0., 0.)

let c8 v = float v /. 255.

let named_colors : (string * int) list = [
  ("aliceblue", 0xF0F8FF); ("antiquewhite", 0xFAEBD7); ("aqua", 0x00FFFF);
  ("aquamarine", 0x7FFFD4); ("azure", 0xF0FFFF); ("beige", 0xF5F5DC);
  ("bisque", 0xFFE4C4); ("black", 0x000000); ("blanchedalmond", 0xFFEBCD);
  ("blue", 0x0000FF); ("blueviolet", 0x8A2BE2); ("brown", 0xA52A2A);
  ("burlywood", 0xDEB887); ("cadetblue", 0x5F9EA0); ("chartreuse", 0x7FFF00);
  ("chocolate", 0xD2691E); ("coral", 0xFF7F50); ("cornflowerblue", 0x6495ED);
  ("cornsilk", 0xFFF8DC); ("crimson", 0xDC143C); ("cyan", 0x00FFFF);
  ("darkblue", 0x00008B); ("darkcyan", 0x008B8B); ("darkgoldenrod", 0xB8860B);
  ("darkgray", 0xA9A9A9); ("darkgreen", 0x006400); ("darkgrey", 0xA9A9A9);
  ("darkkhaki", 0xBDB76B); ("darkmagenta", 0x8B008B); ("darkolivegreen", 0x556B2F);
  ("darkorange", 0xFF8C00); ("darkorchid", 0x9932CC); ("darkred", 0x8B0000);
  ("darksalmon", 0xE9967A); ("darkseagreen", 0x8FBC8F); ("darkslateblue", 0x483D8B);
  ("darkslategray", 0x2F4F4F); ("darkslategrey", 0x2F4F4F); ("darkturquoise", 0x00CED1);
  ("darkviolet", 0x9400D3); ("deeppink", 0xFF1493); ("deepskyblue", 0x00BFFF);
  ("dimgray", 0x696969); ("dimgrey", 0x696969); ("dodgerblue", 0x1E90FF);
  ("firebrick", 0xB22222); ("floralwhite", 0xFFFAF0); ("forestgreen", 0x228B22);
  ("fuchsia", 0xFF00FF); ("gainsboro", 0xDCDCDC); ("ghostwhite", 0xF8F8FF);
  ("gold", 0xFFD700); ("goldenrod", 0xDAA520); ("gray", 0x808080);
  ("green", 0x008000); ("greenyellow", 0xADFF2F); ("grey", 0x808080);
  ("honeydew", 0xF0FFF0); ("hotpink", 0xFF69B4); ("indianred", 0xCD5C5C);
  ("indigo", 0x4B0082); ("ivory", 0xFFFFF0); ("khaki", 0xF0E68C);
  ("lavender", 0xE6E6FA); ("lavenderblush", 0xFFF0F5); ("lawngreen", 0x7CFC00);
  ("lemonchiffon", 0xFFFACD); ("lightblue", 0xADD8E6); ("lightcoral", 0xF08080);
  ("lightcyan", 0xE0FFFF); ("lightgoldenrodyellow", 0xFAFAD2); ("lightgray", 0xD3D3D3);
  ("lightgreen", 0x90EE90); ("lightgrey", 0xD3D3D3); ("lightpink", 0xFFB6C1);
  ("lightsalmon", 0xFFA07A); ("lightseagreen", 0x20B2AA); ("lightskyblue", 0x87CEFA);
  ("lightslategray", 0x778899); ("lightslategrey", 0x778899); ("lightsteelblue", 0xB0C4DE);
  ("lightyellow", 0xFFFFE0); ("lime", 0x00FF00); ("limegreen", 0x32CD32);
  ("linen", 0xFAF0E6); ("magenta", 0xFF00FF); ("maroon", 0x800000);
  ("mediumaquamarine", 0x66CDAA); ("mediumblue", 0x0000CD); ("mediumorchid", 0xBA55D3);
  ("mediumpurple", 0x9370DB); ("mediumseagreen", 0x3CB371); ("mediumslateblue", 0x7B68EE);
  ("mediumspringgreen", 0x00FA9A); ("mediumturquoise", 0x48D1CC); ("mediumvioletred", 0xC71585);
  ("midnightblue", 0x191970); ("mintcream", 0xF5FFFA); ("mistyrose", 0xFFE4E1);
  ("moccasin", 0xFFE4B5); ("navajowhite", 0xFFDEAD); ("navy", 0x000080);
  ("oldlace", 0xFDF5E6); ("olive", 0x808000); ("olivedrab", 0x6B8E23);
  ("orange", 0xFFA500); ("orangered", 0xFF4500); ("orchid", 0xDA70D6);
  ("palegoldenrod", 0xEEE8AA); ("palegreen", 0x98FB98); ("paleturquoise", 0xAFEEEE);
  ("palevioletred", 0xDB7093); ("papayawhip", 0xFFEFD5); ("peachpuff", 0xFFDAB9);
  ("peru", 0xCD853F); ("pink", 0xFFC0CB); ("plum", 0xDDA0DD);
  ("powderblue", 0xB0E0E6); ("purple", 0x800080); ("rebeccapurple", 0x663399);
  ("red", 0xFF0000); ("rosybrown", 0xBC8F8F); ("royalblue", 0x4169E1);
  ("saddlebrown", 0x8B4513); ("salmon", 0xFA8072); ("sandybrown", 0xF4A460);
  ("seagreen", 0x2E8B57); ("seashell", 0xFFF5EE); ("sienna", 0xA0522D);
  ("silver", 0xC0C0C0); ("skyblue", 0x87CEEB); ("slateblue", 0x6A5ACD);
  ("slategray", 0x708090); ("slategrey", 0x708090); ("snow", 0xFFFAFA);
  ("springgreen", 0x00FF7F); ("steelblue", 0x4682B4); ("tan", 0xD2B48C);
  ("teal", 0x008080); ("thistle", 0xD8BFD8); ("tomato", 0xFF6347);
  ("turquoise", 0x40E0D0); ("violet", 0xEE82EE); ("wheat", 0xF5DEB3);
  ("white", 0xFFFFFF); ("whitesmoke", 0xF5F5F5); ("yellow", 0xFFFF00);
  ("yellowgreen", 0x9ACD32);
]

let hex_nibble c =
  if c >= Char.code '0' && c <= Char.code '9' then c - Char.code '0'
  else if c >= Char.code 'a' && c <= Char.code 'f' then c - Char.code 'a' + 10
  else if c >= Char.code 'A' && c <= Char.code 'F' then c - Char.code 'A' + 10
  else -1

let parse_color (s : string) : color option =
  let s = trim s in
  let n = String.length s in
  if n = 0 then None
  else if s.[0] = '#' then begin
    let h = String.sub s 1 (n - 1) in
    let ok = String.for_all (fun c -> hex_nibble (Char.code c) >= 0) h in
    if not ok then None
    else match String.length h with
      | 3 | 4 ->
        let d i = hex_nibble (Char.code h.[i]) in
        let r = d 0 * 17 and g = d 1 * 17 and b = d 2 * 17 in
        let a = if String.length h = 4 then d 3 * 17 else 255 in
        Some (c8 r, c8 g, c8 b, c8 a)
      | 6 | 8 ->
        let d i = hex_nibble (Char.code h.[i]) * 16 + hex_nibble (Char.code h.[i + 1]) in
        let a = if String.length h = 8 then d 6 else 255 in
        Some (c8 (d 0), c8 (d 2), c8 (d 4), c8 a)
      | _ -> None
  end
  else if n > 4 && String.sub s 0 3 = "rgb" then begin
    (* rgb()/rgba(): comma or space separated, optional / alpha *)
    let inner =
      match String.index_opt s '(', String.rindex_opt s ')' with
      | Some a, Some b when b > a -> String.sub s (a + 1) (b - a - 1)
      | _ -> ""
    in
    if inner = "" then None
    else begin
      let inner = String.map (fun c -> if c = ',' then ' ' else c) inner in
      let parts =
        inner |> String.split_on_char '/'
        |> List.concat_map (String.split_on_char ' ')
        |> List.filter (fun p -> p <> "")
      in
      let chan p =
        let p = trim p in
        if String.length p > 0 && p.[String.length p - 1] = '%' then
          match float_of_string_opt (String.sub p 0 (String.length p - 1)) with
          | Some v -> Some (clamp01 (v /. 100.))
          | None -> None
        else match float_of_string_opt p with
          | Some v -> Some (clamp01 (v /. 255.))
          | None -> None
      in
      let alpha p =
        let p = trim p in
        if String.length p > 0 && p.[String.length p - 1] = '%' then
          match float_of_string_opt (String.sub p 0 (String.length p - 1)) with
          | Some v -> Some (clamp01 (v /. 100.))
          | None -> None
        else match float_of_string_opt p with
          | Some v -> Some (clamp01 v)
          | None -> None
      in
      match parts with
      | [ r; g; b ] ->
        (match chan r, chan g, chan b with
         | Some r, Some g, Some b -> Some (r, g, b, 1.)
         | _ -> None)
      | [ r; g; b; a ] ->
        (match chan r, chan g, chan b, alpha a with
         | Some r, Some g, Some b, Some a -> Some (r, g, b, a)
         | _ -> None)
      | _ -> None
    end
  end
  else if s = "transparent" then Some clear_c
  else
    match List.assoc_opt (lower s) named_colors with
    | Some v -> Some (c8 ((v lsr 16) land 255), c8 ((v lsr 8) land 255), c8 (v land 255), 1.)
    | None -> None

(* ============================ matrices ============================ *)

(* [a c e; b d f]: x' = a x + c y + e, y' = b x + d y + f. *)
type mat = { a : float; b : float; c : float; d : float; e : float; f : float }

let mat_id = { a = 1.; b = 0.; c = 0.; d = 1.; e = 0.; f = 0. }
let mat_translate x y = { mat_id with e = x; f = y }
let mat_scale sx sy = { a = sx; b = 0.; c = 0.; d = sy; e = 0.; f = 0. }
let mat_rotate t =
  let c = cos t and s = sin t in
  { a = c; b = s; c = -.s; d = c; e = 0.; f = 0. }
let mat_skewx t = { mat_id with c = tan t }
let mat_skewy t = { mat_id with b = tan t }

(* m1 ∘ m2: apply m2 first. *)
let mat_mul m1 m2 =
  { a = m1.a *. m2.a +. m1.c *. m2.b;
    b = m1.b *. m2.a +. m1.d *. m2.b;
    c = m1.a *. m2.c +. m1.c *. m2.d;
    d = m1.b *. m2.c +. m1.d *. m2.d;
    e = m1.a *. m2.e +. m1.c *. m2.f +. m1.e;
    f = m1.b *. m2.e +. m1.d *. m2.f +. m1.f }

let mat_map m (x, y) = (m.a *. x +. m.c *. y +. m.e, m.b *. x +. m.d *. y +. m.f)

let mat_det m = m.a *. m.d -. m.b *. m.c

let mat_inv m =
  let det = mat_det m in
  if det = 0. || not (finite det) then None
  else
    Some { a = m.d /. det; b = -.m.b /. det;
           c = -.m.c /. det; d = m.a /. det;
           e = (m.c *. m.f -. m.d *. m.e) /. det;
           f = (m.b *. m.e -. m.a *. m.f) /. det }

(* A rough scale estimate of [m]: the largest axis scale. *)
let mat_scale_hint m =
  fmax (sqrt (m.a *. m.a +. m.b *. m.b)) (sqrt (m.c *. m.c +. m.d *. m.d))

let parse_transform s =
  let n = String.length s in
  let rec go i m =
    let i = skip_sep s i in
    if i >= n then m
    else begin
      (* name( args ) *)
      let j = ref i in
      while !j < n && (s.[!j] >= 'a' && s.[!j] <= 'z' || s.[!j] >= 'A' && s.[!j] <= 'Z') do incr j done;
      let name = lower (String.sub s i (!j - i)) in
      let j = skip_sep s !j in
      if j >= n || s.[j] <> '(' then bad "malformed transform '%s'" s;
      let k =
        match String.index_from_opt s j ')' with
        | Some k -> k
        | None -> bad "unterminated transform '%s'" s
      in
      let args = num_list (String.sub s (j + 1) (k - j - 1)) in
      let t =
        match name, args with
        | "matrix", [ a; b; c; d; e; f ] -> { a; b; c; d; e; f }
        | "translate", [ x ] -> mat_translate x 0.
        | "translate", [ x; y ] -> mat_translate x y
        | "scale", [ x ] -> mat_scale x x
        | "scale", [ x; y ] -> mat_scale x y
        | "rotate", [ a ] -> mat_rotate (a *. Float.pi /. 180.)
        | "rotate", [ a; x; y ] ->
          mat_mul (mat_translate x y)
            (mat_mul (mat_rotate (a *. Float.pi /. 180.)) (mat_translate (-.x) (-.y)))
        | "skewx", [ a ] -> mat_skewx (a *. Float.pi /. 180.)
        | "skewy", [ a ] -> mat_skewy (a *. Float.pi /. 180.)
        | _ -> bad "bad transform '%s' in '%s'" name s
      in
      go (k + 1) (mat_mul m t)
    end
  in
  go 0 mat_id

let parse_transform_opt s = try Some (parse_transform s) with Bad _ -> None

(* ============================ paths ============================ *)

(* Symbolic path commands, all absolute. *)
type pcmd =
  | PMove of pt
  | PLine of pt
  | PCubic of pt * pt * pt
  | PQuad of pt * pt
  | PArc of float * float * float * bool * bool * pt  (* rx ry phi large sweep end *)
  | PClose

(* Parse path data [s]. Raises [Bad] on malformed input — per spec the
   doc fails with Error rather than silently ignoring path garbage. *)
let parse_path_d s : pcmd list list =
  let n = String.length s in
  let i = ref 0 in
  let peek () = if !i < n then Some s.[!i] else None in
  let skip_ws () = i := skip_sep s !i in
  let num () =
    skip_ws ();
    match scan_num s !i with
    | Some (v, j) -> i := j; v
    | None -> bad "expected number in path data near '%s'"
                (String.sub s !i (Int.min 8 (n - !i)))
  in
  let iscmd = function
    | 'M' | 'm' | 'L' | 'l' | 'H' | 'h' | 'V' | 'v' | 'C' | 'c' | 'S' | 's'
    | 'Q' | 'q' | 'T' | 't' | 'A' | 'a' | 'Z' | 'z' -> true
    | _ -> false
  in
  let subpaths = ref [] in  (* reversed list of reversed pcmd lists *)
  let cur = ref [] in
  let emit c = cur := c :: !cur in
  let close_sub () =
    if !cur <> [] then begin subpaths := List.rev !cur :: !subpaths; cur := [] end
  in
  let x = ref 0. and y = ref 0. in        (* current point *)
  let x0 = ref 0. and y0 = ref 0. in      (* subpath start *)
  let prev_ctrl = ref None in             (* last cubic ctrl2 *)
  let prev_qctrl = ref None in            (* last quad ctrl *)
  let open_sub mx my = x0 := mx; y0 := my in
  let finished = ref false in
  while not !finished do
    skip_ws ();
    match peek () with
    | None -> finished := true
    | Some c when iscmd c ->
      incr i;
      let rel = c >= 'a' && c <= 'z' in
      let cmd = Char.uppercase_ascii c in
      let dx = if rel then !x else 0. and dy = if rel then !y else 0. in
      (match cmd with
       | 'M' ->
         let px = num () +. dx and py = num () +. dy in
         emit (PMove (px, py)); x := px; y := py; open_sub px py;
         prev_ctrl := None; prev_qctrl := None;
         (* implicit lineto repetition *)
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let px = num () +. dx and py = num () +. dy in
             emit (PLine (px, py)); x := px; y := py; more ()
           | _ -> ()
         in
         more ()
       | 'L' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let px = num () +. dx and py = num () +. dy in
             emit (PLine (px, py)); x := px; y := py; more ()
           | _ -> ()
         in
         more (); prev_ctrl := None; prev_qctrl := None
       | 'H' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let px = num () +. dx in
             emit (PLine (px, !y)); x := px; more ()
           | _ -> ()
         in
         more (); prev_ctrl := None; prev_qctrl := None
       | 'V' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let py = num () +. dy in
             emit (PLine (!x, py)); y := py; more ()
           | _ -> ()
         in
         more (); prev_ctrl := None; prev_qctrl := None
       | 'C' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let x1 = num () +. dx and y1 = num () +. dy in
             let x2 = num () +. dx and y2 = num () +. dy in
             let px = num () +. dx and py = num () +. dy in
             emit (PCubic ((x1, y1), (x2, y2), (px, py)));
             prev_ctrl := Some (x2, y2); x := px; y := py; more ()
           | _ -> ()
         in
         more (); prev_qctrl := None
       | 'S' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let x1, y1 =
               match !prev_ctrl with
               | Some (cx, cy) -> (2. *. !x -. cx, 2. *. !y -. cy)
               | None -> (!x, !y)
             in
             let x2 = num () +. dx and y2 = num () +. dy in
             let px = num () +. dx and py = num () +. dy in
             emit (PCubic ((x1, y1), (x2, y2), (px, py)));
             prev_ctrl := Some (x2, y2); x := px; y := py; more ()
           | _ -> ()
         in
         more (); prev_qctrl := None
       | 'Q' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let x1 = num () +. dx and y1 = num () +. dy in
             let px = num () +. dx and py = num () +. dy in
             emit (PQuad ((x1, y1), (px, py)));
             prev_qctrl := Some (x1, y1); x := px; y := py; more ()
           | _ -> ()
         in
         more (); prev_ctrl := None
       | 'T' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let x1, y1 =
               match !prev_qctrl with
               | Some (cx, cy) -> (2. *. !x -. cx, 2. *. !y -. cy)
               | None -> (!x, !y)
             in
             let px = num () +. dx and py = num () +. dy in
             emit (PQuad ((x1, y1), (px, py)));
             prev_qctrl := Some (x1, y1); x := px; y := py; more ()
           | _ -> ()
         in
         more (); prev_ctrl := None
       | 'A' ->
         let rec more () =
           skip_ws ();
           match peek () with
           | Some c2 when not (iscmd c2) ->
             let rx = num () and ry = num () in
             let phi = num () in
             let fa = num () and fs = num () in
             let px = num () +. dx and py = num () +. dy in
             emit (PArc (rx, ry, phi, fa <> 0., fs <> 0., (px, py)));
             x := px; y := py; more ()
           | _ -> ()
         in
         more (); prev_ctrl := None; prev_qctrl := None
       | 'Z' ->
         emit PClose;
         x := !x0; y := !y0;
         prev_ctrl := None; prev_qctrl := None;
         close_sub ()
       | _ -> ())
    | Some c -> bad "unexpected char '%c' in path data" c
  done;
  close_sub ();
  List.rev !subpaths

(* [flatten_subpath cmds tol] turns one subpath into a polygon
   (list of points, last == first when closed). [tol] is the device-space
   flatness tolerance. *)
type poly = { pts : pt array; closed : bool }

let rec flatten_cubic_d p0 p1 p2 p3 tol depth acc =
  (* flatness: max distance of control points to chord *)
  let x0, y0 = p0 and x3, y3 = p3 in
  let dx = x3 -. x0 and dy = y3 -. y0 in
  let d = sqrt (dx *. dx +. dy *. dy) in
  let flat =
    if d = 0. then begin
      let dist (x, y) = sqrt ((x -. x0) ** 2. +. (y -. y0) ** 2.) in
      fmax (dist p1) (dist p2) <= tol
    end else begin
      let dist (x, y) = Float.abs ((x -. x0) *. dy -. (y -. y0) *. dx) /. d in
      fmax (dist p1) (dist p2) <= tol
    end
  in
  if flat || depth >= 14 || not (finite dx && finite dy) then p3 :: acc
  else begin
    (* de Casteljau midpoint split *)
    let mid (ax, ay) (bx, by) = ((ax +. bx) /. 2., (ay +. by) /. 2.) in
    let p01 = mid p0 p1 and p12 = mid p1 p2 and p23 = mid p2 p3 in
    let p012 = mid p01 p12 and p123 = mid p12 p23 in
    let p0123 = mid p012 p123 in
    let acc = flatten_cubic_d p0123 p123 p23 p3 tol (depth + 1) acc in
    flatten_cubic_d p0 p01 p012 p0123 tol (depth + 1) acc
  end

let flatten_cubic p0 p1 p2 p3 tol acc = flatten_cubic_d p0 p1 p2 p3 tol 0 acc

let flatten_quad p0 p1 p2 tol acc =
  (* promote to cubic *)
  let c1 = (pt_x p0 +. 2. /. 3. *. (pt_x p1 -. pt_x p0),
            pt_y p0 +. 2. /. 3. *. (pt_y p1 -. pt_y p0)) in
  let c2 = (pt_x p2 +. 2. /. 3. *. (pt_x p1 -. pt_x p2),
            pt_y p2 +. 2. /. 3. *. (pt_y p1 -. pt_y p2)) in
  flatten_cubic p0 c1 c2 p2 tol acc

(* Endpoint-to-center arc parameterization per SVG spec F.6.5. *)
let flatten_arc (x1, y1) rx ry phi large sweep (x2, y2) tol acc =
  let rx = Float.abs rx and ry = Float.abs ry in
  if rx = 0. || ry = 0. || (x1 = x2 && y1 = y2) then (x2, y2) :: acc
  else begin
    let cphi = cos phi and sphi = sin phi in
    let x1' = cphi *. (x1 -. x2) /. 2. +. sphi *. (y1 -. y2) /. 2. in
    let y1' = -.sphi *. (x1 -. x2) /. 2. +. cphi *. (y1 -. y2) /. 2. in
    (* radii correction *)
    let lam = (x1' *. x1') /. (rx *. rx) +. (y1' *. y1') /. (ry *. ry) in
    let rx, ry =
      if lam > 1. then (rx *. sqrt lam, ry *. sqrt lam) else (rx, ry)
    in
    let num = fmax 0. (rx *. rx *. ry *. ry -. rx *. rx *. y1' *. y1'
                       -. ry *. ry *. x1' *. x1') in
    let den = rx *. rx *. y1' *. y1' +. ry *. ry *. x1' *. x1' in
    let co = if den = 0. then 0. else sqrt (num /. den) in
    let co = if large = sweep then -.co else co in
    let cx' = co *. rx *. y1' /. ry in
    let cy' = -.co *. ry *. x1' /. rx in
    let cx = cphi *. cx' -. sphi *. cy' +. (x1 +. x2) /. 2. in
    let cy = sphi *. cx' +. cphi *. cy' +. (y1 +. y2) /. 2. in
    let ang (ux, uy) (vx, vy) =
      let d = ux *. vx +. uy *. vy in
      let n = sqrt ((ux *. ux +. uy *. uy) *. (vx *. vx +. vy *. vy)) in
      let s = if ux *. vy -. uy *. vx >= 0. then 1. else -.1. in
      s *. Float.acos (clamp01 ((d /. n +. 1.) /. 2.) *. 2. -. 1.)
    in
    let th1 = ang (1., 0.) ((x1' -. cx') /. rx, (y1' -. cy') /. ry) in
    let dth = ang ((x1' -. cx') /. rx, (y1' -. cy') /. ry)
                  ((-.x1' -. cx') /. rx, (-.y1' -. cy') /. ry) in
    let dth =
      if sweep && dth < 0. then dth +. 2. *. Float.pi
      else if (not sweep) && dth > 0. then dth -. 2. *. Float.pi
      else dth
    in
    (* step count from angular tolerance: for error e at radius r,
       step = 2 acos(1 - e/r). Cap at 90deg min steps for sanity. *)
    let r_max = fmax rx ry in
    let step =
      let e = fmin tol r_max in
      fmax (Float.pi /. 32.) (2. *. Float.acos (fmax (-1.) (fmin 1. (1. -. e /. r_max))))
    in
    let segs = Int.min 4096 (Int.max 1 (ifloor (Float.abs dth /. step) + 1)) in
    let rec loop k acc =
      if k = segs then (x2, y2) :: acc
      else begin
        let th = th1 +. dth *. float k /. float segs in
        let xe = cos th *. rx and ye = sin th *. ry in
        let px = cx +. cphi *. xe -. sphi *. ye in
        let py = cy +. sphi *. xe +. cphi *. ye in
        loop (k + 1) ((px, py) :: acc)
      end
    in
    loop 1 acc
  end

let flatten_subpath (cmds : pcmd list) tol : poly option =
  let pts = ref [] in
  let cur = ref (0., 0.) in
  let start = ref (0., 0.) in
  let closed = ref false in
  List.iter (fun c ->
      match c with
      | PMove p -> cur := p; start := p
      | PLine p -> pts := p :: !pts; cur := p
      | PCubic (c1, c2, p) ->
        pts := flatten_cubic !cur c1 c2 p tol !pts; cur := p
      | PQuad (c1, p) ->
        pts := flatten_quad !cur c1 p tol !pts; cur := p
      | PArc (rx, ry, phi, l, s, p) ->
        pts := flatten_arc !cur rx ry phi l s p tol !pts; cur := p
      | PClose ->
        if !cur <> !start then pts := !start :: !pts;
        closed := true)
    cmds;
  match !pts with
  | [] -> None
  | _ ->
    (* first point of the polygon is the last emitted *)
    let first, rest_rev =
      match List.rev !pts with
      | f :: tl -> f, tl
      | [] -> assert false
    in
    (* ensure the start point is present *)
    let arr = Array.of_list (!start :: first :: rest_rev) in
    Some { pts = arr; closed = !closed }

(* ============================ css ============================ *)

(* Tiny stylesheet support: element, #id, .class, universal selectors,
   descendant and child combinators, comma groups, and declaration
   blocks — enough for the stylesheets real-world icons carry. *)

type compound = {
  c_tag : string option;      (* None = '*' *)
  c_id : string option;
  c_classes : string list;
}

type comb = Self | Desc | Child

(* selector = compounds ordered target-first; the comb stored with a
   compound relates it to the next compound toward the target. *)
type selector = (compound * comb) list

type rule = {
  r_sel : selector;
  r_ids : int;                (* specificity *)
  r_classes : int;
  r_tags : int;
  r_order : int;              (* document order *)
  r_decls : (string * string) list;
}

let split_top sep s =
  (* split on sep not inside parens/quotes *)
  let n = String.length s in
  let rec go i depth acc cur =
    if i >= n then List.rev (Buffer.contents cur :: acc)
    else begin
      let c = s.[i] in
      if c = sep && depth = 0 then
        go (i + 1) 0 (Buffer.contents cur :: acc) (Buffer.create 16)
      else begin
        Buffer.add_char cur c;
        match c with
        | '(' -> go (i + 1) (depth + 1) acc cur
        | ')' -> go (i + 1) (Int.max 0 (depth - 1)) acc cur
        | '"' | '\'' ->
          let q = c in
          let j = ref (i + 1) in
          while !j < n && s.[!j] <> q do Buffer.add_char cur s.[!j]; incr j done;
          if !j < n then Buffer.add_char cur q;
          go (min n (!j + 1)) depth acc cur
        | _ -> go (i + 1) depth acc cur
      end
    end
  in
  go 0 0 [] (Buffer.create 16)

let parse_decls s =
  s |> split_top ';'
  |> List.filter_map (fun d ->
      match String.index_opt d ':' with
      | None -> None
      | Some k ->
        let p = trim (String.sub d 0 k) in
        let v = trim (String.sub d (k + 1) (String.length d - k - 1)) in
        if p = "" then None else Some (lower p, v))

let parse_compound s =
  let n = String.length s in
  let rec go i tag id classes =
    if i >= n then (tag, id, List.rev classes)
    else match s.[i] with
      | '#' ->
        let j = ref (i + 1) in
        while !j < n && (s.[!j] <> '.' && s.[!j] <> '#') do incr j done;
        go !j tag (Some (String.sub s (i + 1) (!j - i - 1))) classes
      | '.' ->
        let j = ref (i + 1) in
        while !j < n && (s.[!j] <> '.' && s.[!j] <> '#') do incr j done;
        go !j tag id (String.sub s (i + 1) (!j - i - 1) :: classes)
      | _ ->
        let j = ref i in
        while !j < n && (s.[!j] <> '.' && s.[!j] <> '#') do incr j done;
        go !j (Some (lower (String.sub s i (!j - i)))) id classes
  in
  let tag, id, classes = go 0 None None [] in
  { c_tag = tag; c_id = id; c_classes = classes }

let parse_selector s =
  (* split keeping combinators: '>' and whitespace *)
  let n = String.length s in
  let toks = ref [] in
  let i = ref 0 in
  while !i < n do
    while !i < n && is_space s.[!i] do incr i done;
    if !i < n then begin
      if s.[!i] = '>' then begin toks := ">" :: !toks; incr i end
      else if s.[!i] = '+' || s.[!i] = '~' then begin
        (* sibling combinators unsupported: mark and drop rule *)
        toks := "x" :: !toks; incr i
      end
      else begin
        let j = ref !i in
        while !j < n && (not (is_space s.[!j])) && s.[!j] <> '>' && s.[!j] <> '+' && s.[!j] <> '~' do
          incr j
        done;
        toks := String.sub s !i (!j - !i) :: !toks;
        i := !j
      end
    end
  done;
  let toks = List.rev !toks in
  if List.mem "x" toks then None
  else begin
    (* compounds left-to-right, combs the relation between neighbours *)
    let comps = ref [] and combs = ref [] and pending = ref false in
    List.iter (fun t ->
        if t = ">" then pending := true
        else begin
          if !comps <> [] then combs := (if !pending then Child else Desc) :: !combs;
          pending := false;
          comps := parse_compound t :: !comps
        end)
      toks;
    let comps = List.rev !comps and combs = List.rev !combs in
    (* target-first items: (compound, comb relating it to the next
       compound toward the target). *)
    match List.rev comps with
    | [] -> None
    | target :: upward ->
      let rec zip upward combs =
        match upward, combs with
        | [], [] -> []
        | c :: crest, k :: krest -> (c, k) :: zip crest krest
        | _ -> []
      in
      Some ((target, Self) :: zip upward combs)
  end

let match_compound (e : xml) c =
  (match c.c_tag with
   | None -> true
   | Some t -> local_name e.xtag = t) &&
  (match c.c_id with
   | None -> true
   | Some id -> (match xattr e "id" with Some v -> v = id | None -> false)) &&
  (match c.c_classes with
   | [] -> true
   | want ->
     match xattr e "class" with
     | None -> false
     | Some v ->
       let have = String.split_on_char ' ' v
                  |> List.map trim |> List.filter (fun s -> s <> "") in
       List.for_all (fun k -> List.mem k have) want)

(* Match selector items above the target. [ancs] = ancestors
   nearest-first; each item's comb relates it to the next compound
   toward the target (Child = must be the immediate parent). *)
let rec match_selector ancs (sel : selector) =
  match sel with
  | [] -> true
  | (c, comb) :: rest ->
    let rec try_from ancs =
      match ancs with
      | [] -> false
      | a :: up ->
        if match_compound a c && match_selector up rest then true
        else (match comb with Child -> false | _ -> try_from up)
    in
    try_from ancs

let parse_stylesheet s order0 =
  (* strip comments *)
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if !i + 1 < n && s.[!i] = '/' && s.[!i + 1] = '*' then begin
      i := !i + 2;
      while !i + 1 < n && not (s.[!i] = '*' && s.[!i + 1] = '/') do incr i done;
      i := min n (!i + 2)
    end else begin Buffer.add_char b s.[!i]; incr i end
  done;
  let s = Buffer.contents b in
  let n = String.length s in
  let rec go i acc order =
    let i = skip_sep s i in
    if i >= n then List.rev acc
    else begin
      (* at-rules: skip their block *)
      if s.[i] = '@' then begin
        let rec j k depth =
          if k >= n then n
          else if s.[k] = '{' then j (k + 1) (depth + 1)
          else if s.[k] = '}' then if depth = 1 then k + 1 else j (k + 1) (depth - 1)
          else if depth = 0 && s.[k] = ';' then k + 1
          else j (k + 1) depth
        in
        go (j i 0) acc order
      end
      else match String.index_from_opt s i '{' with
        | None -> List.rev acc
        | Some b0 ->
          let b1 =
            match String.index_from_opt s b0 '}' with
            | Some b1 -> b1
            | None -> String.length s
          in
          let sels = String.sub s i (b0 - i) |> split_top ','
                     |> List.map trim |> List.filter (fun x -> x <> "") in
          let decls = parse_decls (String.sub s (b0 + 1) (b1 - b0 - 1)) in
          let rules =
            sels |> List.filter_map (fun sel ->
                match parse_selector sel with
                | None -> None
                | Some sl ->
                  let ids, classes, tags =
                    List.fold_left (fun (i_, c_, t_) (c, _) ->
                        (i_ + (if c.c_id <> None then 1 else 0),
                         c_ + List.length c.c_classes,
                         t_ + (if c.c_tag <> None then 1 else 0)))
                      (0, 0, 0) sl
                  in
                  Some { r_sel = sl; r_ids = ids; r_classes = classes;
                         r_tags = tags; r_order = order + 1; r_decls = decls })
          in
          go (b1 + 1) (List.rev_append rules acc) (order + List.length rules)
    end
  in
  go 0 [] order0

(* ============================ style ============================ *)

(* Paint as written in a property (unresolved). *)
type pspec =
  | PInherit
  | PNone
  | PColor of color
  | PCurrent
  | PUrl of string * color option

type style = {
  mutable st_fill : pspec;
  mutable st_fill_a : float;
  mutable st_fill_rule : [ `Nonzero | `Evenodd ];
  mutable st_stroke : pspec;
  mutable st_stroke_a : float;
  mutable st_stroke_w : float;
  mutable st_linecap : [ `Butt | `Round | `Square ];
  mutable st_linejoin : [ `Miter | `Jround | `Bevel ];
  mutable st_miter : float;
  mutable st_dash : float array;
  mutable st_dash_off : float;
  mutable st_opacity : float;
  mutable st_display : bool;
  mutable st_visible : bool;
  mutable st_color : color;
  mutable st_clip : string option;
  mutable st_clip_rule : [ `Nonzero | `Evenodd ];
  mutable st_mask : string option;
  mutable st_stop_c : color;
  mutable st_stop_a : float;
}

let default_style () = {
  st_fill = PColor black; st_fill_a = 1.; st_fill_rule = `Nonzero;
  st_stroke = PNone; st_stroke_a = 1.; st_stroke_w = 1.;
  st_linecap = `Butt; st_linejoin = `Miter; st_miter = 4.;
  st_dash = [||]; st_dash_off = 0.;
  st_opacity = 1.; st_display = true; st_visible = true;
  st_color = black; st_clip = None; st_clip_rule = `Nonzero;
  st_mask = None; st_stop_c = black; st_stop_a = 1.;
}

(* Props that inherit down the tree. *)
let inherit_style ~from:p ~into:s =
  s.st_fill <- p.st_fill; s.st_fill_a <- p.st_fill_a;
  s.st_fill_rule <- p.st_fill_rule;
  s.st_stroke <- p.st_stroke; s.st_stroke_a <- p.st_stroke_a;
  s.st_stroke_w <- p.st_stroke_w;
  s.st_linecap <- p.st_linecap; s.st_linejoin <- p.st_linejoin;
  s.st_miter <- p.st_miter;
  s.st_dash <- p.st_dash;
  s.st_dash_off <- p.st_dash_off;
  s.st_visible <- p.st_visible;
  s.st_color <- p.st_color;
  s.st_clip_rule <- p.st_clip_rule;
  s.st_stop_c <- p.st_stop_c; s.st_stop_a <- p.st_stop_a

let url_of s =
  let s = trim s in
  if String.length s > 4 && String.sub s 0 4 = "url(" then begin
    let inner =
      match String.index_opt s ')' with
      | Some k -> String.sub s 4 (k - 4)
      | None -> ""
    in
    let inner = trim inner in
    let inner =
      let n = String.length inner in
      if n > 1 && (inner.[0] = '"' || inner.[0] = '\'') then
        String.sub inner 1 (n - 2)
      else inner
    in
    if String.length inner > 1 && inner.[0] = '#' then
      Some (String.sub inner 1 (String.length inner - 1))
    else None
  end
  else None

let parse_pspec s : pspec =
  let s = trim s in
  match url_of s with
  | Some id ->
    (* optional fallback color after url(...) *)
    let fb =
      match String.index_opt s ')' with
      | Some k -> parse_color (String.sub s (k + 1) (String.length s - k - 1))
      | None -> None
    in
    PUrl (id, fb)
  | None ->
    (match lower s with
     | "none" -> PNone
     | "inherit" -> PInherit
     | "currentcolor" -> PCurrent
     | _ -> match parse_color s with Some c -> PColor c | None -> PInherit)

let fattr ?(pct_base = 1.) d s = parse_length ~pct_base ~default:d s

let apply_decl (st : style) (prop : string) (v : string) (pct : float) =
  let vl = lower (trim v) in
  if vl = "inherit" then ()   (* parent value already cascaded in *)
  else match prop with
  | "fill" -> st.st_fill <- parse_pspec v
  | "fill-opacity" -> st.st_fill_a <- fattr st.st_fill_a ~pct_base:1. vl
  | "fill-rule" ->
    st.st_fill_rule <- if vl = "evenodd" then `Evenodd else `Nonzero
  | "stroke" -> st.st_stroke <- parse_pspec v
  | "stroke-opacity" -> st.st_stroke_a <- fattr st.st_stroke_a ~pct_base:1. vl
  | "stroke-width" ->
    st.st_stroke_w <- fattr st.st_stroke_w ~pct_base:pct vl
  | "stroke-linecap" ->
    st.st_linecap <- (match vl with "round" -> `Round | "square" -> `Square | _ -> `Butt)
  | "stroke-linejoin" ->
    st.st_linejoin <- (match vl with
        | "round" -> `Jround | "bevel" -> `Bevel | _ -> `Miter)
  | "stroke-miterlimit" -> st.st_miter <- fattr st.st_miter vl
  | "stroke-dasharray" ->
    if vl = "none" then st.st_dash <- [||]
    else begin
      let items =
        String.map (fun c -> if c = ',' then ' ' else c) v
        |> String.split_on_char ' '
        |> List.filter (fun t -> t <> "")
      in
      st.st_dash <-
        Array.of_list
          (List.map (fun t -> parse_length ~pct_base:pct ~default:0. t) items)
    end
  | "stroke-dashoffset" -> st.st_dash_off <- fattr st.st_dash_off ~pct_base:pct vl
  | "opacity" -> st.st_opacity <- clamp01 (fattr st.st_opacity vl)
  | "display" -> if vl = "none" then st.st_display <- false
  | "visibility" ->
    if vl = "hidden" || vl = "collapse" then st.st_visible <- false
  | "color" -> (match parse_color v with Some c -> st.st_color <- c | None -> ())
  | "clip-path" -> st.st_clip <- url_of v
  | "clip-rule" -> st.st_clip_rule <- if vl = "evenodd" then `Evenodd else `Nonzero
  | "mask" -> st.st_mask <- url_of v
  | "stop-color" -> (match parse_color v with Some c -> st.st_stop_c <- c | None -> ())
  | "stop-opacity" -> st.st_stop_a <- clamp01 (fattr st.st_stop_a ~pct_base:1. vl)
  | _ -> ()

(* Presentation attributes that map to properties. *)
let present_attrs = [
  "fill"; "fill-opacity"; "fill-rule";
  "stroke"; "stroke-opacity"; "stroke-width"; "stroke-linecap";
  "stroke-linejoin"; "stroke-miterlimit"; "stroke-dasharray";
  "stroke-dashoffset";
  "opacity"; "display"; "visibility"; "color";
  "clip-path"; "clip-rule"; "mask"; "stop-color"; "stop-opacity";
]

(* Compute the element style. [ancs] nearest-first ancestors of [e]. *)
let style_of rules ~parent (ancs : xml list) (e : xml) (pct : float) : style =
  let st = default_style () in
  inherit_style ~from:parent ~into:st;
  let spec_cmp (a : rule) (b : rule) =
    let c = compare a.r_ids b.r_ids in
    if c <> 0 then c
    else let c = compare a.r_classes b.r_classes in
      if c <> 0 then c
      else let c = compare a.r_tags b.r_tags in
        if c <> 0 then c else compare a.r_order b.r_order
  in
  let matching =
    rules
    |> List.filter (fun r ->
        match r.r_sel with
        | (tc, _) :: rest ->
          match_compound e tc && match_selector ancs rest
        | [] -> false)
    |> List.stable_sort spec_cmp
  in
  List.iter (fun r -> List.iter (fun (p, v) -> apply_decl st p v pct) r.r_decls)
    matching;
  List.iter (fun a ->
      match xattr e a with
      | Some v -> apply_decl st a v pct
      | None -> ())
    present_attrs;
  (match xattr e "style" with
   | Some s ->
     List.iter (fun (p, v) -> apply_decl st p v pct) (parse_decls s)
   | None -> ());
  st

(* ============================ document ============================ *)

type doc = {
  root : xml;
  ids : (string, xml) Hashtbl.t;
  rules : rule list;
  vb : (float * float * float * float) option;
  dwidth : float option;
  dheight : float option;
  par : string;
}

let collect_doc (root : xml) =
  let ids = Hashtbl.create 32 in
  let rules = ref [] in
  let order = ref 0 in
  let rec walk e =
    (match xattr e "id" with
     | Some id -> Hashtbl.replace ids id e
     | None -> ());
    if local_name e.xtag = "style" then begin
      let rs = parse_stylesheet (xtext_of e) !order in
      order := !order + List.length rs;
      rules := List.rev_append rs !rules
    end;
    List.iter walk e.xkids
  in
  walk root;
  (ids, List.rev !rules)

let parse_vb e =
  match xattr e "viewBox" with
  | None -> None
  | Some v ->
    (match num_list_opt v with
     | Some [ x; y; w; h ] when w > 0. && h > 0. -> Some (x, y, w, h)
     | _ -> None)

let parse_dim e name =
  match xattr e name with
  | None -> None
  | Some v ->
    let f = parse_length ~default:Float.nan v in
    if finite f && f > 0. then Some f else None

(* Validate the path data eagerly: malformed [d] is the one hard parse
   error we honour. *)
let validate_paths (root : xml) =
  let rec walk e =
    (match local_name e.xtag with
     | "path" ->
       (match xattr e "d" with
        | Some d -> ignore (parse_path_d d)
        | None -> ())
     | _ -> ());
    List.iter walk e.xkids
  in
  walk root

let parse src : (doc, string) result =
  match parse_xml src with
  | Error m -> Error m
  | Ok root ->
    if local_name root.xtag <> "svg" then Error "root element is not <svg>"
    else
      (try
         validate_paths root;
         let ids, rules = collect_doc root in
         let vb = parse_vb root in
         let dwidth = parse_dim root "width" in
         let dheight = parse_dim root "height" in
         let par =
           match xattr root "preserveAspectRatio" with
           | Some v -> v | None -> "xMidYMid meet"
         in
                Ok { root; ids; rules; vb; dwidth; dheight; par }
       with
       | Bad m -> Error m)

let view_box d = d.vb
let intrinsic_size d =
  match d.dwidth, d.dheight with
  | Some w, Some h -> Some (w, h)
  | _ -> None

(* ============================ shapes ============================ *)

let el e name d = parse_length ~default:d (match xattr e name with Some v -> v | None -> "")
let el_opt e name =
  match xattr e name with
  | None -> None
  | Some v -> let f = parse_length ~default:Float.nan v in if finite f then Some f else None

(* pct_base for x/y lengths is handled by the caller via [pct] — for
   simplicity percentages on shapes resolve against the viewport
   diagonal. *)

let shape_to_subpaths (e : xml) (pct : float) : pcmd list list =
  let lp name d = parse_length ~pct_base:pct ~default:d
      (match xattr e name with Some v -> v | None -> "") in
  match local_name e.xtag with
  | "rect" ->
    let x = lp "x" 0. and y = lp "y" 0. in
    let w = lp "width" 0. and h = lp "height" 0. in
    if w <= 0. || h <= 0. then []
    else begin
      let rx0 = el_opt e "rx" and ry0 = el_opt e "ry" in
      let rx, ry =
        match rx0, ry0 with
        | Some r, None | None, Some r -> r, r
        | Some r, Some s -> r, s
        | None, None -> 0., 0.
      in
      let rx = fmin rx (w /. 2.) and ry = fmin ry (h /. 2.) in
      if rx <= 0. || ry <= 0. then
        [ [ PMove (x, y); PLine (x +. w, y); PLine (x +. w, y +. h);
            PLine (x, y +. h); PClose ] ]
      else
        [ [ PMove (x +. rx, y);
            PLine (x +. w -. rx, y);
            PArc (rx, ry, 0., false, true, (x +. w, y +. ry));
            PLine (x +. w, y +. h -. ry);
            PArc (rx, ry, 0., false, true, (x +. w -. rx, y +. h));
            PLine (x +. rx, y +. h);
            PArc (rx, ry, 0., false, true, (x, y +. h -. ry));
            PLine (x, y +. ry);
            PArc (rx, ry, 0., false, true, (x +. rx, y));
            PClose ] ]
    end
  | "circle" ->
    let cx = lp "cx" 0. and cy = lp "cy" 0. and r = lp "r" 0. in
    if r <= 0. then []
    else [ [ PMove (cx +. r, cy);
             PArc (r, r, 0., false, true, (cx -. r, cy));
             PArc (r, r, 0., false, true, (cx +. r, cy));
             PClose ] ]
  | "ellipse" ->
    let cx = lp "cx" 0. and cy = lp "cy" 0. in
    let rx = lp "rx" 0. and ry = lp "ry" 0. in
    if rx <= 0. || ry <= 0. then []
    else [ [ PMove (cx +. rx, cy);
             PArc (rx, ry, 0., false, true, (cx -. rx, cy));
             PArc (rx, ry, 0., false, true, (cx +. rx, cy));
             PClose ] ]
  | "line" ->
    let x1 = lp "x1" 0. and y1 = lp "y1" 0. in
    let x2 = lp "x2" 0. and y2 = lp "y2" 0. in
    [ [ PMove (x1, y1); PLine (x2, y2) ] ]
  | "polyline" | "polygon" ->
    (match xattr e "points" with
     | None -> []
     | Some v ->
       (match num_list_opt v with
        | Some l ->
          let rec pairs = function
            | x :: y :: rest -> (x, y) :: pairs rest
            | _ -> []
          in
          (match pairs l with
           | [] -> []
           | p0 :: rest ->
             [ PMove p0 :: List.map (fun p -> PLine p) rest
               @ (if local_name e.xtag = "polygon" then [ PClose ] else []) ])
        | None -> []))
  | "path" ->
    (match xattr e "d" with
     | Some d -> (try parse_path_d d with Bad _ -> [])
     | None -> [])
  | _ -> []

let is_shape tag =
  match local_name tag with
  | "rect" | "circle" | "ellipse" | "line" | "polyline" | "polygon" | "path" -> true
  | _ -> false

(* ============================ painter ============================ *)

(* Resolved paint server pieces. *)
type grad = {
  g_radial : bool;
  g_u2g : mat;            (* user space -> gradient space *)
  g_p : float * float * float * float;  (* x1 y1 x2 y2 | fx fy cx cy *)
  g_r : float;
  g_spread : [ `Pad | `Reflect | `Repeat ];
  g_stops : (float * color) array;
}

let href_of e =
  let raw =
    match xattr e "href" with
    | Some v -> Some v
    | None -> xattr e "xlink:href"
  in
  match raw with
  | None -> None
  | Some v ->
    let v = trim v in
    if String.length v > 1 && v.[0] = '#' then
      Some (String.sub v 1 (String.length v - 1))
    else url_of v

let find_attr_in (elems : xml list) name =
  List.find_map (fun e -> xattr e name) elems

let gradient_stops rules ~pct (e : xml) : (float * color) array =
  let stop_elems =
    List.filter (fun k -> local_name k.xtag = "stop") e.xkids in
  let acc = ref [] in
  List.iter (fun se ->
      let st = style_of rules ~parent:(default_style ()) [ e ] se pct in
      let off =
        match xattr se "offset" with
        | None -> 0.
        | Some v ->
          let v = trim v in
          if String.length v > 0 && v.[String.length v - 1] = '%' then
            parse_length ~pct_base:1. ~default:0. v
          else parse_length ~default:0. v
      in
      let (_, _, _, a) = st.st_stop_c in
      let (r, g, b, _) = st.st_stop_c in
      acc := (clamp01 off, (r, g, b, a *. st.st_stop_a)) :: !acc)
    stop_elems;
  let a = Array.of_list (List.rev !acc) in
  Array.sort (fun (a, _) (b, _) -> compare a b) a;
  a

(* Follow href chains for attrs/stops; stops come from the nearest
   ancestor-or-self that defines any. *)
let gradient_of doc rules ~(pct : float) (e : xml) ~(bb : float * float * float * float)
    : grad option =
  let rec chain depth e acc =
    if depth > 8 then acc
    else
      match href_of e with
      | Some id ->
        (match Hashtbl.find_opt doc.ids id with
         | Some p -> chain (depth + 1) p (e :: acc)
         | None -> e :: acc)
      | None -> e :: acc
  in
  let elems = chain 0 e [] in   (* self first *)
  let radial = local_name e.xtag = "radialgradient" in
  let units =
    match find_attr_in elems "gradientUnits" with
    | Some v when lower (trim v) = "userspaceonuse" -> `UserSpace
    | _ -> `Obbox
  in
  let gtrans =
    match find_attr_in elems "gradientTransform" with
    | Some v -> (match parse_transform_opt v with Some m -> m | None -> mat_id)
    | None -> mat_id
  in
  let stops =
    match
      List.find_map (fun ge ->
          let s = gradient_stops rules ~pct ge in
          if Array.length s > 0 then Some s else None)
        elems
    with
    | Some s -> s
    | None -> [||]
  in
  if Array.length stops = 0 then None
  else begin
    let gnum name d =
      match find_attr_in elems name with
      | None -> d
      | Some v ->
        let v = trim v in
        (match units with
         | `Obbox ->
           (* plain numbers, or % of the bbox *)
           parse_length ~pct_base:1. ~default:d v
         | `UserSpace -> parse_length ~pct_base:pct ~default:d v)
    in
    let spread =
      match find_attr_in elems "spreadMethod" with
      | Some v ->
        (match lower (trim v) with
         | "reflect" -> `Reflect | "repeat" -> `Repeat | _ -> `Pad)
      | None -> `Pad
    in
    let (bx, by, bw, bh) = bb in
    let u2g =
      match units with
      | `Obbox ->
        if bw <= 0. || bh <= 0. then None
        else begin
          let norm = mat_mul (mat_scale (1. /. bw) (1. /. bh))
              (mat_translate (-.bx) (-.by)) in
          match mat_inv gtrans with
          | Some gi -> Some (mat_mul gi norm)
          | None -> Some norm
        end
      | `UserSpace ->
        (match mat_inv gtrans with
         | Some gi -> Some gi
         | None -> Some mat_id)
    in
    match u2g with
    | None -> None
    | Some u2g ->
      if radial then begin
        let cx = gnum "cx" 0.5 and cy = gnum "cy" 0.5 in
        let r = gnum "r" 0.5 in
        let fx = gnum "fx" cx and fy = gnum "fy" cy in
        if r <= 0. then None
        else Some { g_radial = true; g_u2g = u2g; g_p = (fx, fy, cx, cy);
                    g_r = r; g_spread = spread; g_stops = stops }
      end
      else begin
        let x1 = gnum "x1" 0. and y1 = gnum "y1" 0. in
        let x2 = gnum "x2" 1. and y2 = gnum "y2" 0. in
        Some { g_radial = false; g_u2g = u2g; g_p = (x1, y1, x2, y2);
               g_r = 0.; g_spread = spread; g_stops = stops }
      end
  end

let spread_t spread t =
  match spread with
  | `Pad -> clamp01 t
  | `Repeat -> t -. Float.floor t
  | `Reflect ->
    let m = Float.rem t 2. in
    let m = if m < 0. then m +. 2. else m in
    if m > 1. then 2. -. m else m

let stop_color (stops : (float * color) array) t =
  let n = Array.length stops in
  if n = 0 then clear_c
  else if t <= fst stops.(0) then snd stops.(0)
  else if t >= fst stops.(n - 1) then snd stops.(n - 1)
  else begin
    let rec bin lo hi =
      if hi - lo <= 1 then lo
      else let mid = (lo + hi) / 2 in
        if fst stops.(mid) <= t then bin mid hi else bin lo mid
    in
    let i = bin 0 (n - 1) in
    let o0, c0 = stops.(i) and o1, c1 = stops.(i + 1) in
    if o1 -. o0 <= 0. then c1
    else begin
      let u = (t -. o0) /. (o1 -. o0) in
      let (r0, g0, b0, a0) = c0 and (r1, g1, b1, a1) = c1 in
      (r0 +. u *. (r1 -. r0), g0 +. u *. (g1 -. g0),
       b0 +. u *. (b1 -. b0), a0 +. u *. (a1 -. a0))
    end
  end

let grad_color g ux uy =
  let qx, qy = mat_map g.g_u2g (ux, uy) in
  let t =
    if g.g_radial then begin
      let (fx, fy, cx, cy) = g.g_p in
      let dx = cx -. fx and dy = cy -. fy in
      let vx = qx -. fx and vy = qy -. fy in
      (* solve |v - t d|^2 = (t r)^2 → a t^2 - 2b t + c = 0 *)
      let a = dx *. dx +. dy *. dy -. g.g_r *. g.g_r in
      let b = vx *. dx +. vy *. dy in
      let c = vx *. vx +. vy *. vy in
      if Float.abs a < 1e-12 then begin
        if Float.abs b < 1e-12 then Float.nan else c /. (2. *. b)
      end
      else begin
        let disc = b *. b -. a *. c in
        if disc < 0. then Float.nan
        else (b +. sqrt disc) /. a
      end
    end
    else begin
      let (x1, y1, x2, y2) = g.g_p in
      let dx = x2 -. x1 and dy = y2 -. y1 in
      let dd = dx *. dx +. dy *. dy in
      if dd = 0. then Float.nan
      else ((qx -. x1) *. dx +. (qy -. y1) *. dy) /. dd
    end
  in
  if not (finite t) then clear_c
  else stop_color g.g_stops (spread_t g.g_spread t)

(* Resolve a style paint spec to a straight-color function of a
   user-space point; [bb] is the element's user-space bounding box. *)
let paint_fn doc rules ~pct ~(bb : float * float * float * float)
    ~(color : color) (ps : pspec) : (float -> float -> color) option =
  match ps with
  | PNone -> None
  | PInherit -> None
  | PColor (r, g, b, a) -> Some (fun _ _ -> (r, g, b, a))
  | PCurrent ->
    let (r, g, b, a) = color in
    Some (fun _ _ -> (r, g, b, a))
  | PUrl (id, fb) ->
    (match Hashtbl.find_opt doc.ids id with
     | Some ge when local_name ge.xtag = "lineargradient"
                 || local_name ge.xtag = "radialgradient" ->
       (match gradient_of doc rules ~pct ge ~bb with
        | Some g -> Some (fun ux uy -> grad_color g ux uy)
        | None -> (match fb with
            | Some (r, g, b, a) -> Some (fun _ _ -> (r, g, b, a))
            | None -> None))
     | _ ->
       (* unresolved paint server: fallback color or none *)
       (match fb with
        | Some (r, g, b, a) -> Some (fun _ _ -> (r, g, b, a))
        | None -> None))

(* ============================ rasterizer ============================ *)

(* Same blend convention as lui_raster: premultiplied BGRA bytes,
   pixel centers at x+0.5, source-over with coverage. *)
let byte_f p i = float (Char.code (Bytes.get p i)) /. 255.

let blend p i (r_, g_, b_, a_) cov =
  let a = a_ *. cov in
  if a <= 0. then ()
  else begin
    let inv = 1. -. a in
    Bytes.set p i (Char.chr (to8 (b_ *. cov +. byte_f p i *. inv)));
    Bytes.set p (i + 1) (Char.chr (to8 (g_ *. cov +. byte_f p (i + 1) *. inv)));
    Bytes.set p (i + 2) (Char.chr (to8 (r_ *. cov +. byte_f p (i + 2) *. inv)));
    Bytes.set p (i + 3) (Char.chr (to8 (a +. byte_f p (i + 3) *. inv)))
  end

type redge = {
  re_y0 : float; re_y1 : float;   (* re_y0 < re_y1 *)
  re_x0 : float;                  (* x at re_y0 *)
  re_dxdy : float;
  re_dir : float;                 (* +1 when the original edge went down *)
}

let redges_of_poly (pts : pt array) (closed : bool) (m : mat) : redge list =
  let n = Array.length pts in
  if n < 2 then []
  else begin
    let acc = ref [] in
    let last = if closed then n else n - 1 in
    for k = 0 to last - 1 do
      let a = mat_map m pts.(k) in
      let b = mat_map m pts.((k + 1) mod n) in
      let (x0, y0) = a and (x1, y1) = b in
      if y0 <> y1 then begin
        let (x0, y0, x1, y1, dir) =
          if y0 < y1 then (x0, y0, x1, y1, 1.) else (x1, y1, x0, y0, -1.)
        in
        acc := { re_y0 = y0; re_y1 = y1; re_x0 = x0;
                 re_dxdy = (x1 -. x0) /. (y1 -. y0); re_dir = dir } :: !acc
      end
    done;
    !acc
  end

(* Fill [edges] into [surf] under the winding/evenodd rule. AA is the
   coverage-span scheme: [ss] vertical sub-scanlines per pixel row,
   exact horizontal interval coverage — the same half-pixel edge
   quality class lui_raster's coverage math produces. *)
let ss = 8

let fill_edges ~(surf : Bytes.t) ~w ~h ~(cmask : float array)
    ~clipr:(clipx0, clipy0, clipx1, clipy1)
    (edges : redge list) (evenodd : bool)
    (paint : float -> float -> color)
    (paint_a : float) (inv_ctm : mat option) =
  if edges = [] || paint_a <= 0. then ()
  else begin
    (* device-space bounds of all edges *)
    let y0e = List.fold_left (fun a e -> fmin a e.re_y0) Float.infinity edges in
    let y1e = List.fold_left (fun a e -> fmax a e.re_y1) Float.neg_infinity edges in
    let x0e = List.fold_left (fun a e -> fmin a (fmin e.re_x0 (e.re_x0 +. e.re_dxdy *. (e.re_y1 -. e.re_y0)))) Float.infinity edges in
    let x1e = List.fold_left (fun a e -> fmax a (fmax e.re_x0 (e.re_x0 +. e.re_dxdy *. (e.re_y1 -. e.re_y0)))) Float.neg_infinity edges in
    let py0 = max 0 (max clipy0 (ifloor y0e)) in
    let py1 = min h (min clipy1 (iceil y1e)) in
    let px0 = max 0 (max clipx0 (ifloor (x0e -. 1.))) in
    let px1 = min w (min clipx1 (iceil (x1e +. 1.))) in
    if py0 < py1 && px0 < px1 then begin
      (* bucket edges by covered sub-scanline *)
      let nsubs = h * ss in
      let buckets = Array.make (nsubs + 1) [] in
      List.iter (fun e ->
          let lo = max 0 (iceil (e.re_y0 *. float ss -. 0.5)) in
          let hi = min nsubs (iceil (e.re_y1 *. float ss -. 0.5)) in
          for si = lo to hi - 1 do
            buckets.(si) <- e :: buckets.(si)
          done)
        edges;
      let cov = Array.make w 0. in
      let xs = Array.make (List.length edges * 2 + 2) 0. in
      let ds = Array.make (Array.length xs) 0. in
      for y = py0 to py1 - 1 do
        Array.fill cov 0 w 0.;
        for s = 0 to ss - 1 do
          let si = y * ss + s in
          let ys = float y +. (float s +. 0.5) /. float ss in
          (* crossings on this sub-scanline *)
          let nx = ref 0 in
          List.iter (fun e ->
              if e.re_y0 <= ys && ys < e.re_y1 then begin
                xs.(!nx) <- e.re_x0 +. (ys -. e.re_y0) *. e.re_dxdy;
                ds.(!nx) <- e.re_dir;
                incr nx
              end)
            buckets.(si);
          let n = !nx in
          if n > 1 then begin
            (* sort by x *)
            let idx = Array.init n (fun i -> i) in
            Array.sort (fun a b -> compare xs.(a) xs.(b)) idx;
            (* build interior runs and add horizontal coverage *)
            let wind = ref 0. and inside = ref false in
            let run_x = ref Float.nan in
            let add_cov xa xb =
              (* overlap of [xa,xb] with pixel columns px0..px1 *)
              let a = fmax xa (float px0) and b = fmin xb (float px1) in
              if b > a then begin
                let i0 = max px0 (ifloor a) and i1 = min px1 (iceil b) in
                for x = i0 to i1 - 1 do
                  let l = fmax a (float x) and r = fmin b (float x +. 1.) in
                  if r > l then cov.(x) <- cov.(x) +. (r -. l) /. float ss
                done
              end
            in
            for k = 0 to n - 1 do
              let x = xs.(idx.(k)) and d = ds.(idx.(k)) in
              if !inside then add_cov !run_x x;
              wind := !wind +. d;
              inside := if evenodd then not !inside else !wind <> 0.;
              if !inside then run_x := x
            done
          end
        done;
        (* paint the row *)
        let row = y * (4 * w) in
        for x = px0 to px1 - 1 do
          let c = cov.(x) in
          if c > 0. then begin
            let m = cmask.(y * w + x) in
            let ce = c *. m in
            if ce > 0. then begin
              let ux, uy =
                match inv_ctm with
                | Some m -> mat_map m (float x +. 0.5, float y +. 0.5)
                | None -> (float x +. 0.5, float y +. 0.5)
              in
              let (r, g, b, a) = paint ux uy in
              let at = a *. paint_a in
              if at > 0. then
                blend surf (row + 4 * x)
                  (r *. at, g *. at, b *. at, at) (fmin 1. ce)
            end
          end
        done
      done
    end
  end

(* ============================ stroke ============================ *)

(* Remove consecutive near-duplicate points. *)
let dedupe_pts (pts : pt list) : pt list =
  let rec go acc = function
    | (x, y) :: ((x2, y2) :: _ as rest) ->
      if Float.abs (x -. x2) < 1e-9 && Float.abs (y -. y2) < 1e-9 then go acc rest
      else go ((x, y) :: acc) rest
    | p :: rest -> go (p :: acc) rest
    | [] -> List.rev acc
  in
  go [] pts

(* Split an open/closed polyline into dash-on sub-polylines.
   [pat] is the resolved (even-length) pattern, [off] the dash offset. *)
let dash_split (pts : pt list) (closed : bool) (pat : float array) (off : float)
    : (pt list * bool) list =
  let n = Array.length pat in
  if n = 0 || List.length pts < 2 then [ (pts, closed) ]
  else begin
    let total = Array.fold_left ( +. ) 0. pat in
    if total <= 0. then [ (pts, closed) ]
    else begin
      let path_pts = if closed then pts @ [ List.hd pts ] else pts in
      (* walk segments, tracking distance along the pattern *)
      let off = Float.rem off total in
      let off = if off < 0. then off +. total else off in
      (* di = pattern index, dpos = pos within pattern element *)
      let di = ref 0 and dpos = ref off in
      while !dpos >= pat.(!di) do
        dpos := !dpos -. pat.(!di);
        di := (!di + 1) mod n
      done;
      let on () = !di mod 2 = 0 in
      let out = ref [] in
      let cur = ref [] in
      let emit () =
        if List.length !cur >= 2 then out := (List.rev !cur, false) :: !out;
        cur := []
      in
      let rec walk segs =
        match segs with
        | a :: (b :: _ as rest) ->
          let (ax, ay) = a and (bx, by) = b in
          let dx = bx -. ax and dy = by -. ay in
          let len = sqrt (dx *. dx +. dy *. dy) in
          if len < 1e-9 then walk rest
          else begin
            (* advance through this segment in pattern steps *)
            let seg_left = ref len and seg_pos = ref 0. in
            if on () && !cur = [] then cur := [ a ];
            while !seg_left > 0. do
              let step = fmin !seg_left (pat.(!di) -. !dpos) in
              seg_pos := !seg_pos +. step;
              seg_left := !seg_left -. step;
              dpos := !dpos +. step;
              if !dpos >= pat.(!di) -. 1e-12 then begin
                (* boundary *)
                let t = !seg_pos /. len in
                let p = (ax +. dx *. t, ay +. dy *. t) in
                if on () then begin cur := p :: !cur; emit () end
                else cur := [ p ];
                di := (!di + 1) mod n; dpos := 0.
              end
              else if on () then begin
                let t = !seg_pos /. len in
                cur := (ax +. dx *. t, ay +. dy *. t) :: !cur
              end
            done;
            if on () && !cur = [] then cur := [ b ];
            walk rest
          end
        | _ -> ()
      in
      let on_end = on () in
      walk path_pts;
      emit ();
      let spans = List.rev !out in
      (* A dash continuing across a closed path's start merges the two
         wrap-around spans. *)
      let on_start =
        let di0 = ref 0 and dp = ref off in
        (try
           while !dp >= pat.(!di0) do
             dp := !dp -. pat.(!di0); di0 := (!di0 + 1) mod n
           done;
           !di0 mod 2 = 0
         with _ -> false)
      in
      (match closed, on_start, on_end, spans with
       | true, true, true, (f_pts, _) :: rest ->
         (match List.rev rest with
          | (l_pts, _) :: mid_rev ->
            List.rev mid_rev @ [ (l_pts @ List.tl f_pts, false) ]
          | [] ->
            (* a single dash covering the whole loop stays closed *)
            [ (f_pts, true) ])
       | _ -> spans)
    end
  end

let unit (x, y) =
  let d = sqrt (x *. x +. y *. y) in
  if d < 1e-12 then (1., 0.) else (x /. d, y /. d)

(* Arc fan around [c] radius [r] from angle of [a] to angle of [b]
   going the short way on the outer side. *)
let arc_pts (cx, cy) r a0 a1 =
  let d = a1 -. a0 in
  let d = if d > Float.pi then d -. 2. *. Float.pi
          else if d < -.Float.pi then d +. 2. *. Float.pi else d in
  let nseg = Int.max 2 (iceil (Float.abs d /. (Float.pi /. 8.))) in
  List.init (nseg + 1) (fun i ->
      let t = a0 +. d *. float i /. float nseg in
      (cx +. r *. cos t, cy +. r *. sin t))

let angle_of (x, y) = Float.atan2 y x

(* Arc points radius [r] around [c] starting at angle [a0] sweeping
   [sweep] radians (sign sets direction; |sweep| <= pi). *)
let fan_pts (cx, cy) r a0 sweep =
  let nseg = Int.max 2 (iceil (Float.abs sweep /. (Float.pi /. 8.))) in
  List.init (nseg + 1) (fun i ->
      let t = a0 +. sweep *. float i /. float nseg in
      (cx +. r *. cos t, cy +. r *. sin t))

(* Expand one open/closed polyline to closed outline polygons in user
   space: per-segment quads plus join/cap wedges — the union under the
   nonzero rule is the stroke shape. *)
let expand_stroke (pts : pt list) (closed : bool) ~w ~cap ~join ~miter =
  let h = w /. 2. in
  let pts = dedupe_pts pts in
  let quads = ref [] and wedges = ref [] in
  let add_poly p = quads := p :: !quads in
  let add_wedge p = wedges := p :: !wedges in
  (match pts with
   | [] | [ _ ] ->
     (* degenerate: a point — dots for round/square caps *)
     (match pts, cap with
      | [ (x, y) ], `Round ->
        add_poly (arc_pts (x, y) h 0. (2. *. Float.pi))
      | [ (x, y) ], `Square ->
        add_poly [ (x -. h, y -. h); (x +. h, y -. h);
                   (x +. h, y +. h); (x -. h, y +. h) ]
      | _ -> ())
   | _ ->
     let arr = Array.of_list pts in
     let n = Array.length arr in
     let nseg = if closed then n else n - 1 in
     let dir i = unit (fst arr.((i + 1) mod n) -. fst arr.(i),
                       snd arr.((i + 1) mod n) -. snd arr.(i)) in
     let nrm (dx, dy) = (-.dy, dx) in
     for i = 0 to nseg - 1 do
       let a = arr.(i) and b = arr.((i + 1) mod n) in
       let d = dir i in
       let nx, ny = nrm d in
       let ax, ay = a and bx, by = b in
       let (ux, uy) = (nx *. h, ny *. h) in
       add_poly [ (ax +. ux, ay +. uy); (bx +. ux, by +. uy);
                  (bx -. ux, by -. uy); (ax -. ux, ay -. uy) ]
     done;
     (* joins at interior vertices *)
     let joins =
       if closed then List.init n (fun i -> i)
       else List.init (Int.max 0 (n - 2)) (fun i -> i + 1)
     in
     List.iter (fun vi ->
         let v = arr.(vi) in
         let d0 = dir (vi - 1 + n |> (fun k -> k mod n)) in
         let d1 = dir (vi mod n) in
         let n0 = nrm d0 and n1 = nrm d1 in
         let cross = fst d0 *. snd d1 -. snd d0 *. fst d1 in
         if Float.abs cross > 1e-9 then begin
           (* outer side = the side the path turns away from *)
           let sgn = if cross > 0. then -1. else 1. in
           let ox0 = (fst v +. sgn *. fst n0 *. h, snd v +. sgn *. snd n0 *. h) in
           let ox1 = (fst v +. sgn *. fst n1 *. h, snd v +. sgn *. snd n1 *. h) in
           (match join with
            | `Bevel -> add_wedge [ v; ox0; ox1 ]
            | `Jround ->
              let a0 = angle_of (fst ox0 -. fst v, snd ox0 -. snd v) in
              let a1 = angle_of (fst ox1 -. fst v, snd ox1 -. snd v) in
              add_wedge (v :: arc_pts v h a0 a1)
            | `Miter ->
              (* miter point = intersection of the outer offset lines *)
              let mx, my =
                let u = unit (fst n0 +. fst n1, snd n0 +. snd n1) in
                (* |n0+n1|/2 = sin(θ/2) magnitude *)
                let s = sqrt (Float.abs (1. +. fst d0 *. fst d1 +. snd d0 *. snd d1) /. 2.) in
                let s = fmax s 1e-6 in
                let mlen = h /. s in
                (fst v +. sgn *. fst u *. mlen, snd v +. sgn *. snd u *. mlen)
              in
              let mlen_ratio =
                let s = sqrt (Float.abs (1. +. fst d0 *. fst d1 +. snd d0 *. snd d1) /. 2.) in
                if s < 1e-6 then Float.infinity else 1. /. (2. *. s)
              in
              if mlen_ratio <= miter then add_wedge [ v; ox0; (mx, my); ox1 ]
              else add_wedge [ v; ox0; ox1 ])
         end)
       joins;
     (* caps *)
     if not closed && n >= 2 then begin
       let v0 = arr.(0) and v1 = arr.(n - 1) in
       let d0 = dir 0 and d1 = dir (n - 2) in
       (match cap with
        | `Butt -> ()
        | `Square ->
          List.iter (fun (v, d, flip) ->
              let nx, ny = nrm d in
              let e = h *. flip in
              let ux, uy = (nx *. h, ny *. h) in
              let vx, vy = v in
              add_poly [ (vx +. ux, vy +. uy); (vx +. ux +. fst d *. e, vy +. uy +. snd d *. e);
                         (vx -. ux +. fst d *. e, vy -. uy +. snd d *. e);
                         (vx -. ux, vy -. uy) ])
            [ (v0, d0, -1.); (v1, d1, 1.) ]
        | `Round ->
          List.iter (fun (v, d, flip) ->
              (* semicircle of radius h around endpoint v, spanning the
                 outside: from +n*h to -n*h passing through the outward
                 direction (flip * d). *)
              let nx, ny = nrm d in
              let vx, vy = v in
              let out = (fst d *. flip, snd d *. flip) in
              let a0 = angle_of (nx *. flip, ny *. flip) in
              let ad = angle_of out in
              let diff = ad -. a0 in
              let diff = if diff > Float.pi then diff -. 2. *. Float.pi
                         else if diff <= -.Float.pi then diff +. 2. *. Float.pi
                         else diff in
              let sweep = if diff >= 0. then Float.pi else -.Float.pi in
              add_wedge (fan_pts (vx, vy) h a0 sweep))
            [ (v0, d0, -1.); (v1, d1, 1.) ])
     end);
  List.rev_append !quads !wedges

(* ============================ render ============================ *)

type env = {
  d : doc;
  ew : int; eh : int;             (* device pixels *)
  pct : float;                    (* percent base: viewport diagonal *)
}

let no_render = [
  "defs"; "symbol"; "clippath"; "mask"; "lineargradient";
  "radialgradient"; "pattern"; "marker"; "style"; "title"; "desc";
  "metadata"; "text"; "tspan"; "textpath"; "tref"; "altglyph";
  "altglyphdef"; "altglyphitem"; "glyphref"; "image"; "foreignobject";
  "script"; "view"; "cursor"; "color-profile"; "font"; "font-face";
  "font-face-src"; "font-face-uri"; "font-face-format";
  "font-face-name"; "missing-glyph"; "glyph"; "hkern"; "vkern";
  "animate"; "animatecolor"; "animatemotion"; "animatetransform";
  "animation"; "set"; "filter"; "fegaussianblur"; "fecolormatrix";
  "feoffset"; "feblend"; "feflood"; "fecomposite"; "femerge";
  "femergenode"; "fedropshadow"; "femorphology"; "feturbulence";
  "fedisplacementmap"; "feimage"; "fetile"; "feconvolvematrix";
  "fediffuselighting"; "fespecularlighting"; "fedistantlight";
  "fepointlight"; "fespotlight"; "fefunca"; "fefuncb"; "fefuncg";
  "fefuncr"; "fecomponenttransfer"; "handler"; "listener";
  "prefetch"; "solidcolor"; "hatch"; "hatchpath"; "mesh";
  "meshgradient"; "meshpatch"; "meshrow"; "unknown"; "discard";
  "audio"; "video"; "iframe"; "canvas";
]

(* User-space bbox of a flattened polygon list. *)
let polys_bbox (polys : poly list) =
  List.fold_left (fun (x0, y0, x1, y1) p ->
      Array.fold_left (fun (ax0, ay0, ax1, ay1) (x, y) ->
          (fmin ax0 x, fmin ay0 y, fmax ax1 x, fmax ay1 y))
        (x0, y0, x1, y1) p.pts)
    (Float.infinity, Float.infinity, Float.neg_infinity, Float.neg_infinity)
    polys

let bb_of_subpaths subs tol =
  let polys = List.filter_map (fun sp -> flatten_subpath sp tol) subs in
  polys_bbox polys

(* Bbox of [e]'s geometry subtree mapped by [m]: [e]'s own transform
   composes first, then descendants' through containers. *)
let rec geom_bbox env (e : xml) (m : mat) : float * float * float * float =
  let lt =
    match xattr e "transform" with
    | Some v -> (match parse_transform_opt v with Some t -> t | None -> mat_id)
    | None -> mat_id
  in
  let m = mat_mul m lt in
  let tag = local_name e.xtag in
  if is_shape tag then begin
    let subs = shape_to_subpaths e env.pct in
    let (x0, y0, x1, y1) = bb_of_subpaths subs 0.5 in
    if not (finite x0) then (0., 0., 0., 0.)
    else begin
      (* bbox of the transformed bbox corners — wrong under rotation;
         map the points instead: recompute via corner transform of each
         poly would be ideal; corners of the local bbox mapped is a
         reasonable approximation for clip/mask use. *)
      let corners = [ (x0, y0); (x1, y0); (x0, y1); (x1, y1) ] in
      List.fold_left (fun (ax0, ay0, ax1, ay1) p ->
          let x, y = mat_map m p in
          (fmin ax0 x, fmin ay0 y, fmax ax1 x, fmax ay1 y))
        (Float.infinity, Float.infinity, Float.neg_infinity, Float.neg_infinity)
        corners
    end
  end
  else if List.mem tag no_render then
    (Float.infinity, Float.infinity, Float.neg_infinity, Float.neg_infinity)
  else
    List.fold_left (fun (ax0, ay0, ax1, ay1) k ->
        let (x0, y0, x1, y1) = geom_bbox env k m in
        if not (finite x0) then (ax0, ay0, ax1, ay1)
        else (fmin ax0 x0, fmin ay0 y0, fmax ax1 x1, fmax ay1 y1))
      (Float.infinity, Float.infinity, Float.neg_infinity, Float.neg_infinity)
      e.xkids

(* Bbox of [e]'s geometry in [e]'s own local user space (the space
   its geometry attributes live in, past its transform attribute —
   where paint, clip and mask evaluate). *)
let elem_bbox env (e : xml) : float * float * float * float =
  let tag = local_name e.xtag in
  if is_shape tag then bb_of_subpaths (shape_to_subpaths e env.pct) 0.5
  else
    List.fold_left (fun (ax0, ay0, ax1, ay1) k ->
        let (x0, y0, x1, y1) = geom_bbox env k mat_id in
        if not (finite x0) then (ax0, ay0, ax1, ay1)
        else (fmin ax0 x0, fmin ay0 y0, fmax ax1 x1, fmax ay1 y1))
      (Float.infinity, Float.infinity, Float.neg_infinity, Float.neg_infinity)
      e.xkids

(* viewBox + preserveAspectRatio fit matrix. *)
let fit_mat (vx, vy, vw, vh) (w, h) par =
  let par = lower (trim par) in
  let none = String.length par >= 4 && String.sub par 0 4 = "none" in
  if none then mat_mul (mat_scale (w /. vw) (h /. vh)) (mat_translate (-.vx) (-.vy))
  else begin
    let slice = String.length par >= 5
                && String.sub par (String.length par - 5) 5 = "slice" in
    let sx = w /. vw and sy = h /. vh in
    let s = if slice then fmax sx sy else fmin sx sy in
    let dw = w -. vw *. s and dh = h -. vh *. s in
    let ax, ay =
      if String.length par >= 4 then begin
        let a = String.sub par 0 4 in
        ((match a.[1] with 'i' -> (match a.[3] with 'n' -> 0. | 'd' -> 0.5 | _ -> 1.) | _ -> 0.5),
         (match a.[2] with 'i' -> (match a.[3] with 'n' -> 0. | 'd' -> 0.5 | _ -> 1.) | _ -> 0.5))
      end else (0.5, 0.5)
    in
    mat_mul (mat_translate (ax *. dw) (ay *. dh))
      (mat_mul (mat_scale s s) (mat_translate (-.vx) (-.vy)))
  end

(* src premultiplied BGRA over dst, with extra alpha. *)
let composite ~dst ~src ~w ~h ~alpha =
  for i = 0 to w * h - 1 do
    let o = 4 * i in
    let sa = byte_f src (o + 3) *. alpha in
    if sa > 0. then begin
      let inv = 1. -. sa in
      Bytes.set dst o (Char.chr (to8 (byte_f src o *. alpha +. byte_f dst o *. inv)));
      Bytes.set dst (o + 1) (Char.chr (to8 (byte_f src (o + 1) *. alpha +. byte_f dst (o + 1) *. inv)));
      Bytes.set dst (o + 2) (Char.chr (to8 (byte_f src (o + 2) *. alpha +. byte_f dst (o + 2) *. inv)));
      Bytes.set dst (o + 3) (Char.chr (to8 (sa +. byte_f dst (o + 3) *. inv)))
    end
  done

let extract_alpha ~src ~w ~h =
  Array.init (w * h) (fun i -> byte_f src (4 * i + 3))

let extract_mask ~src ~w ~h ~alpha_type =
  Array.init (w * h) (fun i ->
      let a = byte_f src (4 * i + 3) in
      if alpha_type then a
      else begin
        (* luminance of the premultiplied color ≈ premul-weighted luma *)
        let b = byte_f src (4 * i) and g = byte_f src (4 * i + 1) and r = byte_f src (4 * i + 2) in
        (0.2126 *. r +. 0.7152 *. g +. 0.0722 *. b) (* already includes alpha *)
      end)

(* Recursion guards. *)
let max_depth = 64

let rec render_elem env ~surf ~cmask ~clipr ~ctm ~pst ~ancs ~depth (e : xml) : unit =
  if depth > max_depth then ()
  else
    let tag = local_name e.xtag in
    if List.mem tag no_render then ()
    else begin
      let lt =
        match xattr e "transform" with
        | Some v -> (match parse_transform_opt v with Some t -> t | None -> mat_id)
        | None -> mat_id
      in
      let ctm2 = mat_mul ctm lt in
      let st = style_of env.d.rules ~parent:pst ancs e env.pct in
      if st.st_display && st.st_visible then begin
        (* clip + mask fold into the pixel coverage mask *)
        let cmask2 =
          match st.st_clip with
          | None -> cmask
          | Some id ->
            (match Hashtbl.find_opt env.d.ids id with
             | Some cpe when local_name cpe.xtag = "clippath" ->
               let cctm =
                 match xattr cpe "clipPathUnits" with
                 | Some v when lower (trim v) = "objectboundingbox" ->
                   let (bx, by, bw, bh) = elem_bbox env e in
                   if finite bx && bw > 0. && bh > 0. then
                     mat_mul ctm2 (mat_mul (mat_translate bx by) (mat_scale bw bh))
                   else ctm2
                 | _ -> ctm2
               in
               let tmp = Bytes.make (4 * env.ew * env.eh) '\000' in
               let ones = Array.make (env.ew * env.eh) 1. in
               List.iter
                 (render_elem env ~surf:tmp ~cmask:ones
                    ~clipr:(0, 0, env.ew, env.eh)
                    ~ctm:cctm ~pst:(default_style ())
                    ~ancs:[ cpe ] ~depth:(depth + 1))
                 cpe.xkids;
               let am = extract_alpha ~src:tmp ~w:env.ew ~h:env.eh in
               Array.mapi (fun i m -> m *. am.(i)) cmask
             | _ -> cmask)
        in
        let cmask2 =
          match st.st_mask with
          | None -> cmask2
          | Some id ->
            (match Hashtbl.find_opt env.d.ids id with
             | Some me when local_name me.xtag = "mask" ->
               let bb = elem_bbox env e in
               let ulen name d base =
                 match xattr me name with
                 | Some v -> parse_length ~pct_base:base ~default:d v
                 | None -> d *. base
               in
               (* mask region in the element's local user space *)
               let (rx, ry, rw, rh) =
                 match xattr me "maskUnits" with
                 | Some v when lower (trim v) = "userspaceonuse" ->
                   (ulen "x" (-0.1) env.pct, ulen "y" (-0.1) env.pct,
                    ulen "width" 1.2 env.pct, ulen "height" 1.2 env.pct)
                 | _ ->
                   let (bx, by, bw, bh) = bb in
                   if not (finite bx) || bw <= 0. || bh <= 0. then
                     (0., 0., env.pct, env.pct)
                   else
                     (bx +. ulen "x" (-0.1) 1. *. bw,
                      by +. ulen "y" (-0.1) 1. *. bh,
                      ulen "width" 1.2 1. *. bw,
                      ulen "height" 1.2 1. *. bh)
               in
               let cctm =
                 match xattr me "maskContentUnits" with
                 | Some v when lower (trim v) = "objectboundingbox" ->
                   let (bx, by, bw, bh) = bb in
                   if finite bx && bw > 0. && bh > 0. then
                     mat_mul ctm2 (mat_mul (mat_translate bx by) (mat_scale bw bh))
                   else ctm2
                 | _ -> ctm2
               in
               let tmp = Bytes.make (4 * env.ew * env.eh) '\000' in
               let ones = Array.make (env.ew * env.eh) 1. in
               List.iter
                 (render_elem env ~surf:tmp ~cmask:ones
                    ~clipr:(0, 0, env.ew, env.eh)
                    ~ctm:cctm ~pst:(default_style ())
                    ~ancs:[ me ] ~depth:(depth + 1))
                 me.xkids;
               let alpha_type =
                 match xattr me "mask-type" with
                 | Some v -> lower (trim v) = "alpha"
                 | None -> false
               in
               let mv = extract_mask ~src:tmp ~w:env.ew ~h:env.eh
                          ~alpha_type in
               (* region rect: outside it the mask is transparent *)
               let corners =
                 [ (rx, ry); (rx +. rw, ry); (rx, ry +. rh);
                   (rx +. rw, ry +. rh) ]
               in
               let (dx0, dy0, dx1, dy1) =
                 List.fold_left (fun (ax0, ay0, ax1, ay1) p ->
                     let x, y = mat_map ctm2 p in
                     (fmin ax0 x, fmin ay0 y, fmax ax1 x, fmax ay1 y))
                   (Float.infinity, Float.infinity,
                    Float.neg_infinity, Float.neg_infinity)
                   corners
               in
               let rx0 = max 0 (ifloor dx0) and rx1 = min env.ew (iceil dx1) in
               let ry0 = max 0 (ifloor dy0) and ry1 = min env.eh (iceil dy1) in
               Array.init (env.ew * env.eh) (fun i ->
                   let y = i / env.ew and x = i mod env.ew in
                   if x >= rx0 && x < rx1 && y >= ry0 && y < ry1
                   then cmask.(i) *. mv.(i)
                   else 0.)
             | _ -> cmask2)
        in
        (* group opacity / all element dispatch *)
        let dispatch ~surf ~cmask =
          if is_shape tag then
            draw_shape env ~surf ~cmask ~clipr ~ctm:ctm2 ~st e
          else
            match tag with
            | "use" -> render_use env ~surf ~cmask ~clipr ~ctm:ctm2 ~st
                          ~ancs:(e :: ancs) ~depth:(depth + 1) e
            | "svg" ->
              render_svg env ~surf ~cmask ~clipr ~ctm:ctm2 ~st
                ~ancs:(e :: ancs) ~depth:(depth + 1) e
            | "switch" ->
              (* first child without extension/feature requirements *)
              (match
                 List.find_opt (fun k ->
                     xattr k "requiredExtensions" = None
                     && xattr k "requiredFeatures" = None)
                   e.xkids
               with
               | Some k ->
                 render_elem env ~surf ~cmask ~clipr ~ctm:ctm2 ~pst:st
                   ~ancs:(e :: ancs) ~depth:(depth + 1) k
               | None -> ())
            | _ ->
              (* containers and unknown wrappers render their children *)
              List.iter
                (render_elem env ~surf ~cmask ~clipr ~ctm:ctm2 ~pst:st
                   ~ancs:(e :: ancs) ~depth:(depth + 1))
                e.xkids
        in
        if st.st_opacity < 1. then begin
          let tmp = Bytes.make (4 * env.ew * env.eh) '\000' in
          dispatch ~surf:tmp ~cmask:cmask2;
          composite ~dst:surf ~src:tmp ~w:env.ew ~h:env.eh
            ~alpha:st.st_opacity
        end
        else dispatch ~surf ~cmask:cmask2
      end
    end

and draw_shape env ~surf ~cmask ~clipr ~ctm ~st (e : xml) : unit =
  let subs = shape_to_subpaths e env.pct in
  if subs = [] then ()
  else begin
    let scale = fmax 1e-6 (mat_scale_hint ctm) in
    let tol_u = 0.4 /. scale in
    let polys = List.filter_map (fun sp -> flatten_subpath sp tol_u) subs in
    if polys = [] then ()
    else begin
      let bb = polys_bbox polys in
      let inv = mat_inv ctm in
      let resolve ps =
        match inv with
        | None -> None
        | Some _ -> paint_fn env.d env.d.rules ~pct:env.pct ~bb
                      ~color:st.st_color ps
      in
      (* fill *)
      (match resolve st.st_fill with
       | Some paint ->
         let edges =
           List.concat_map
             (fun p -> redges_of_poly p.pts true ctm) polys
         in
         fill_edges ~surf ~w:env.ew ~h:env.eh ~cmask ~clipr
           edges (st.st_fill_rule = `Evenodd) paint st.st_fill_a inv
       | None -> ());
      (* stroke *)
      if st.st_stroke_w > 0. then begin
        match resolve st.st_stroke with
        | Some paint ->
          let pat =
            let n = Array.length st.st_dash in
            if n = 0 then [||]
            else if n mod 2 = 1 then Array.append st.st_dash st.st_dash
            else st.st_dash
          in
          let stroke_polys =
            List.concat_map (fun p ->
                let pts = Array.to_list p.pts in
                let pts, closed =
                  if p.closed && List.length pts > 1 then
                    (* drop the duplicated closing point *)
                    match List.rev pts with
                    | _ :: tl -> List.rev tl, true
                    | [] -> pts, true
                  else pts, false
                in
                let spans =
                  if Array.length pat > 0 then
                    dash_split pts closed pat st.st_dash_off
                  else [ (pts, closed) ]
                in
                List.concat_map (fun (sp, cl) ->
                    expand_stroke sp cl ~w:st.st_stroke_w ~cap:st.st_linecap
                      ~join:st.st_linejoin ~miter:st.st_miter)
                  spans)
              polys
          in
          let edges =
            List.concat_map
              (fun pts -> redges_of_poly pts true ctm)
              (List.map Array.of_list stroke_polys)
          in
          fill_edges ~surf ~w:env.ew ~h:env.eh ~cmask ~clipr
            edges false paint st.st_stroke_a inv
        | None -> ()
      end
    end
  end

and render_use env ~surf ~cmask ~clipr ~ctm ~st ~ancs ~depth (e : xml) : unit =
  match href_of e with
  | None -> ()
  | Some id ->
    (match Hashtbl.find_opt env.d.ids id with
     | None -> ()
     | Some t ->
       let x = el e "x" 0. and y = el e "y" 0. in
       let base = mat_mul ctm (mat_translate x y) in
       let ttag = local_name t.xtag in
       if ttag = "symbol" || ttag = "svg" then begin
         (* a viewport: w/h (default = the referenced viewBox size or
            the current viewport), viewBox fit, clip to the rect *)
         let tvb = parse_vb t in
         let w, h =
           match el_opt e "width", el_opt e "height" with
           | Some w, Some h -> w, h
           | _ ->
             (match tvb with
              | Some (_, _, vw, vh) -> vw, vh
              | None -> env.pct, env.pct)
         in
         let ctm3 =
           match tvb with
           | Some vb ->
             let par =
               match xattr t "preserveAspectRatio" with
               | Some v -> v | None -> "xMidYMid meet"
             in
             mat_mul base (fit_mat vb (w, h) par)
           | None -> base
         in
         (* clip to the viewport rect in device space *)
         let clipr2 =
           let corners = [ (0., 0.); (w, 0.); (0., h); (w, h) ] in
           let (x0, y0, x1, y1) =
             List.fold_left (fun (ax0, ay0, ax1, ay1) p ->
                 let cx, cy = mat_map base p in
                 (fmin ax0 cx, fmin ay0 cy, fmax ax1 cx, fmax ay1 cy))
               (Float.infinity, Float.infinity,
                Float.neg_infinity, Float.neg_infinity)
               corners
           in
           let (cx0, cy0, cx1, cy1) = clipr in
           (max cx0 (ifloor x0), max cy0 (ifloor y0),
            min cx1 (iceil x1), min cy1 (iceil y1))
         in
         List.iter
           (render_elem env ~surf ~cmask ~clipr:clipr2 ~ctm:ctm3 ~pst:st
              ~ancs ~depth:(depth + 1))
           t.xkids
       end
       else
         render_elem env ~surf ~cmask ~clipr ~ctm:base ~pst:st
           ~ancs ~depth:(depth + 1) t)

and render_svg env ~surf ~cmask ~clipr ~ctm ~st ~ancs ~depth (e : xml) : unit =
  let x = el e "x" 0. and y = el e "y" 0. in
  let w =
    match el_opt e "width" with Some w -> w | None -> env.pct
  and h =
    match el_opt e "height" with Some h -> h | None -> env.pct
  in
  if w > 0. && h > 0. then begin
    let base = mat_mul ctm (mat_translate x y) in
    let ctm3 =
      match parse_vb e with
      | Some vb ->
        let par =
          match xattr e "preserveAspectRatio" with
          | Some v -> v | None -> "xMidYMid meet"
        in
        mat_mul base (fit_mat vb (w, h) par)
      | None -> base
    in
    let clipr2 =
      let corners = [ (0., 0.); (w, 0.); (0., h); (w, h) ] in
      let (x0, y0, x1, y1) =
        List.fold_left (fun (ax0, ay0, ax1, ay1) p ->
            let cx, cy = mat_map base p in
            (fmin ax0 cx, fmin ay0 cy, fmax ax1 cx, fmax ay1 cy))
          (Float.infinity, Float.infinity,
           Float.neg_infinity, Float.neg_infinity)
          corners
      in
      let (cx0, cy0, cx1, cy1) = clipr in
      (max cx0 (ifloor x0), max cy0 (ifloor y0),
       min cx1 (iceil x1), min cy1 (iceil y1))
    in
    List.iter
      (render_elem env ~surf ~cmask ~clipr:clipr2 ~ctm:ctm3 ~pst:st
         ~ancs ~depth:(depth + 1))
      e.xkids
  end

(* ============================ api ============================ *)

let rasterize doc ~w ~h : Bytes.t =
  if w <= 0 || h <= 0 then Bytes.empty
  else begin
    let surf = Bytes.make (4 * w * h) '\000' in
    let (vw, vh) =
      match doc.vb with
      | Some (_, _, vw, vh) -> (vw, vh)
      | None ->
        (match doc.dwidth, doc.dheight with
         | Some dw, Some dh -> (dw, dh)
         | _ -> (float w, float h))
    in
    let env = {
      d = doc; ew = w; eh = h;
      pct = sqrt (vw *. vw +. vh *. vh) /. sqrt 2.
    } in
    (* root viewport: the pixel surface; viewBox fits inside it *)
    let ctm =
      match doc.vb with
      | Some vb -> fit_mat vb (float w, float h) doc.par
      | None -> mat_id
    in
    let cmask = Array.make (w * h) 1. in
    let root = doc.root in
    let st = style_of doc.rules ~parent:(default_style ()) [] root env.pct in
    if st.st_display && st.st_visible then begin
      (* the root svg clips to its viewport *)
      List.iter
        (render_elem env ~surf ~cmask ~clipr:(0, 0, w, h)
           ~ctm ~pst:st ~ancs:[ root ] ~depth:0)
        root.xkids
    end;
    surf
  end

let to_scene_image ~w ~h (pix : Bytes.t) : Lui_scene.image =
  let n = w * h * 4 in
  let out = Bytes.make n '\000' in
  let src = Bytes.sub pix 0 (min n (Bytes.length pix)) in
  for i = 0 to (Bytes.length src / 4) - 1 do
    let o = 4 * i in
    Bytes.set out o (Bytes.get src (o + 2));
    Bytes.set out (o + 1) (Bytes.get src (o + 1));
    Bytes.set out (o + 2) (Bytes.get src o);
    Bytes.set out (o + 3) (Bytes.get src (o + 3))
  done;
  Lui_scene.new_image ~w ~h out

let render src ~w ~h : (Lui_scene.image, string) result =
  match parse src with
  | Error m -> Error m
  | Ok d ->
    if w <= 0 || h <= 0 then Error "non-positive size"
    else Ok (to_scene_image ~w ~h (rasterize d ~w ~h))
