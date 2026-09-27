(* Extension adapter plumbing: JS-implemented components behind the retained
   extension node type. *)

open Lui_protocol
open Lui_web_types
module Store = Lui_web_store

let extension_adapter renderer identifier =
  match Hashtbl.find_opt renderer.web_extension_adapters identifier with
  | Some adapter -> adapter
  | None -> invalid_arg "web extension adapter is not registered"

let extension_platform_node renderer node identifier =
  let adapter = extension_adapter renderer identifier in
  let emit name values =
    ignore
      (!(renderer.web_event_handler)
         (ExtensionEvent (node, identifier, name, values)))
  in
  adapter.web_extension_create node renderer.web_document emit

(* A property write can arrive for a node dropped earlier in the same batch —
   the store already skipped it, so skip the DOM write too. *)
let apply_extension_property renderer node property value =
  match Store.node renderer.web_store node with
  | Some current -> (
      match Store.extension_identity current with
      | Some (identifier, _) ->
          (extension_adapter renderer identifier).web_extension_set_property
            current.platform_node property value
      | None -> invalid_arg "extension property targets standard DOM node")
  | None -> ()

let remove_extension_property renderer node property =
  match Store.node renderer.web_store node with
  | Some current -> (
      match Store.extension_identity current with
      | Some (identifier, _) ->
          (extension_adapter renderer identifier).web_extension_remove_property
            current.platform_node property
      | None -> invalid_arg "extension property targets standard DOM node")
  | None -> ()

let cleanup_extension_node renderer previous_nodes node =
  match Hashtbl.find_opt previous_nodes node with
  | Some current -> (
      match Store.extension_identity current with
      | Some (identifier, _) ->
          (extension_adapter renderer identifier).web_extension_cleanup
            current.platform_node
      | None -> ())
  | None -> ()
