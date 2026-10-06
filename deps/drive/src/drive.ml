(* drive — headless UI driver for LUI apps.
   - Session: mount an app in-process against a recording backend.
   - Ffi: dlopen a shared lib exporting the lui_ocaml_* bridge ABI.
   - Scenario: run .drive scripts over either path.
   - Model: queryable node tree replayed from patch ops. *)

module Model = Model
module Session = Session
module Scenario = Scenario
module Ffi = Ffi
module Live = Live
module Ws = Ws

open Lui_protocol

let profile_generic = { profile_os = GenericOS; profile_host = GenericHost }
let profile_macos_swiftui = { profile_os = MacOS; profile_host = SwiftUIHost }
