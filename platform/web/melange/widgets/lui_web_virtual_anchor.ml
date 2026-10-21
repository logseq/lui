module W = Webapi.Dom
module V = Lui_web_virtualizer

type snapshot = int * float

type t = {
  root : W.Element.t;
  mounted : (int, W.Element.t) Hashtbl.t;
  positions : (int, int) Hashtbl.t;
  virtualizer : V.t;
  mutable pending : snapshot option;
}

let create root mounted positions virtualizer =
  { root; mounted; positions; virtualizer; pending = None }

let capture t =
  let viewport = W.Element.getBoundingClientRect t.root in
  Hashtbl.fold
    (fun id wrapper current ->
      let bounds = W.Element.getBoundingClientRect wrapper in
      let top = W.DomRect.top bounds in
      if
        W.DomRect.bottom bounds <= W.DomRect.top viewport
        || top >= W.DomRect.bottom viewport
      then current
      else
        let candidate = (id, top -. W.DomRect.top viewport) in
        match current with
        | Some (_, offset) when offset <= snd candidate -> current
        | _ -> Some candidate)
    t.mounted None

let preserve t snapshot = t.pending <- snapshot
let cancel t = t.pending <- None

let restore t ~scrolled =
  match t.pending with
  | None -> ()
  | Some (id, offset) -> (
      match Hashtbl.find_opt t.positions id with
      | None -> cancel t
      | Some index -> (
          match Hashtbl.find_opt t.mounted id with
          | None ->
              V.scroll_to_index t.virtualizer index
                (V.scroll_to_index_options ~align:"start" ~behavior:"auto")
          | Some wrapper ->
              let delta =
                W.DomRect.top (W.Element.getBoundingClientRect wrapper)
                -. W.DomRect.top (W.Element.getBoundingClientRect t.root)
                -. offset
              in
              if abs_float delta > 0.5 then begin
                let destination = W.Element.scrollTop t.root +. delta in
                scrolled destination;
                W.Element.setScrollTop t.root destination
              end))
