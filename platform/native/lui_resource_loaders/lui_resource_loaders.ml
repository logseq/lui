(* Typed resource loaders on top of Lui_resource. *)

open Lui_resource

type source =
  | Path of string
  | Bytes of bytes
  | Fetch of Lui_plugin_fetch.request

let url u = Fetch (Lui_plugin_fetch.request u)

(* Canonical key parts for a fetch request. *)
let key_of_fetch (req : Lui_plugin_fetch.request) =
  let body = Digest.to_hex (Digest.string req.Lui_plugin_fetch.body) in
  let headers =
    req.Lui_plugin_fetch.headers
    |> List.map (fun (k, v) -> k ^ ":" ^ v)
    |> List.sort compare
    |> String.concat ";"
  in
  Printf.sprintf "fetch:%s %s %s %s" req.Lui_plugin_fetch.meth
    req.Lui_plugin_fetch.url body headers

let key_of_source ~kind = function
  | Path p -> "file:" ^ kind ^ ":" ^ p
  | Bytes b ->
      "bytes:" ^ kind ^ ":" ^ Digest.to_hex (Digest.string (Bytes.unsafe_to_string b))
  | Fetch r -> "fetch:" ^ kind ^ ":" ^ key_of_fetch r

let read_file path =
  try
    let ic = open_in_bin path in
    let b =
      try
        let n = in_channel_length ic in
        let buf = Bytes.create n in
        really_input ic buf 0 n;
        buf
      with exn ->
        close_in_noerr ic;
        raise exn
    in
    close_in ic;
    Ok b
  with Sys_error msg -> Error msg

let bytes_of_source task src =
  match src with
  | Bytes b -> Ok b
  | Path p ->
      if task_cancelled task then Error "cancelled" else read_file p
  | Fetch r ->
      if task_cancelled task then Error "cancelled"
      else (
        match Lui_plugin_fetch.perform r with
        | Error msg -> Error msg
        | Ok resp when resp.Lui_plugin_fetch.status / 100 = 2 ->
            Ok (Bytes.of_string resp.Lui_plugin_fetch.body)
        | Ok resp ->
            Error (Printf.sprintf "http %d" resp.Lui_plugin_fetch.status))

(* Generic decode-from-source: fetch bytes, check cancellation, decode. *)
let load_of_source ~decode task src =
  match bytes_of_source task src with
  | Error msg -> Error msg
  | Ok b ->
      if task_cancelled task then Error "cancelled" else decode b

module Image = struct
  type value = Lui_scene.image

  let create = Lui_resource.create
  let key_of src = key_of_source ~kind:"img" src

  let load src task =
    load_of_source
      ~decode:(fun b ->
        match Lui_image.decode b with
        | Error _ as e -> e
        | Ok img -> Ok (Lui_image.to_scene_image img))
      task src

  let request c ~scope ?on_state src =
    Lui_resource.request c ~scope ?on_state (key_of src) ~load:(load src)

  let reload c ~scope ?on_state src =
    Lui_resource.reload c ~scope ?on_state (key_of src) ~load:(load src)
end

module Svg = struct
  type value = Lui_svg.doc

  let create = Lui_resource.create
  let key_of src = key_of_source ~kind:"svg" src

  let load src task =
    load_of_source
      ~decode:(fun b -> Lui_svg.parse (Bytes.unsafe_to_string b))
      task src

  let request c ~scope ?on_state src =
    Lui_resource.request c ~scope ?on_state (key_of src) ~load:(load src)

  let reload c ~scope ?on_state src =
    Lui_resource.reload c ~scope ?on_state (key_of src) ~load:(load src)
end

module Fetch = struct
  type value = Lui_plugin_fetch.response

  let create = Lui_resource.create
  let key_of r = key_of_fetch r

  let request c ~scope ?on_state req =
    let load task =
      if task_cancelled task then Error "cancelled"
      else Lui_plugin_fetch.perform req
    in
    Lui_resource.request c ~scope ?on_state (key_of req) ~load

  let reload c ~scope ?on_state req =
    let load task =
      if task_cancelled task then Error "cancelled"
      else Lui_plugin_fetch.perform req
    in
    Lui_resource.reload c ~scope ?on_state (key_of req) ~load
end

module Media = struct
  type value = Lui_media.pcm

  let create = Lui_resource.create
  let key_of ~path = "media:audio:" ^ path

  let load ~path task =
    if task_cancelled task then Error "cancelled"
    else Lui_media.decode path

  let request c ~scope ?on_state ~path () =
    Lui_resource.request c ~scope ?on_state (key_of ~path) ~load:(load ~path)

  let reload c ~scope ?on_state ~path () =
    Lui_resource.reload c ~scope ?on_state (key_of ~path) ~load:(load ~path)
end

module Plugin = struct
  type value = string

  let create = Lui_resource.create

  let key_of ~service ~method_ ~payload =
    service ^ "\n" ^ method_ ^ "\n" ^ payload

  let request c ~scope ?on_state ~service ~method_ ~payload () =
    let load task =
      if task_cancelled task then Error "cancelled"
      else Lui_plugin.call ~service ~method_ payload
    in
    Lui_resource.request c ~scope ?on_state
      (key_of ~service ~method_ ~payload)
      ~load

  let reload c ~scope ?on_state ~service ~method_ ~payload () =
    let load task =
      if task_cancelled task then Error "cancelled"
      else Lui_plugin.call ~service ~method_ payload
    in
    Lui_resource.reload c ~scope ?on_state
      (key_of ~service ~method_ ~payload)
      ~load
end

module Fonts = struct
  type spec = {
    families : string list;
    weight : int;
    italic : bool;
    size : float;
  }

  let spec ?(families = []) ?(weight = 400) ?(italic = false) ~size () =
    { families; weight; italic; size }

  let key_of s =
    Printf.sprintf "font:%s|%d|%b|%g"
      (String.concat "," s.families)
      s.weight s.italic s.size

  let request c ~scope ?on_state ~load spec =
    Lui_resource.request c ~scope ?on_state (key_of spec)
      ~load:(fun task ->
        if task_cancelled task then Error "cancelled"
        else
          try Ok (load spec)
          with exn -> Error (Printexc.to_string exn))

  let reload c ~scope ?on_state ~load spec =
    Lui_resource.reload c ~scope ?on_state (key_of spec)
      ~load:(fun task ->
        if task_cancelled task then Error "cancelled"
        else
          try Ok (load spec)
          with exn -> Error (Printexc.to_string exn))
end
