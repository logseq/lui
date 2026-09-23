(* OCaml-declared extension schemas for the gallery host apps — the single
   source of truth whose canonical fingerprints the host registration
   literals (e.g. GalleryExtensions.swift on Apple, any Flutter registry)
   mirror by hand. Lui_extension_check compares the literals against these
   schemas under `dune runtest`, so a drifted literal fails the test instead
   of surfacing as an "extension fingerprint mismatch" blank screen at
   runtime. *)

open Lui_protocol

let apple_profiles =
  [ profile IOS SwiftUIHost; profile MacOS SwiftUIHost ]

let all_profiles =
  [
    profile AndroidOS FlutterHost;
    profile IOS FlutterHost;
    profile IOS SwiftUIHost;
    profile LinuxOS FlutterHost;
    profile MacOS FlutterHost;
    profile MacOS SwiftUIHost;
    profile WebOS WebHost;
    profile WindowsOS FlutterHost;
  ]

let registry () =
  let registry = Lui_extension.registry () in
  Lui_extension.register_component registry
    (Lui_extension.component "apple-map" apple_profiles false
       [ "apple-map-marker" ]
       [
         Lui_extension.property "latitude" Lui_extension.FloatScalar true None;
         Lui_extension.property "longitude" Lui_extension.FloatScalar true None;
         Lui_extension.property "latitude-delta" Lui_extension.FloatScalar true None;
         Lui_extension.property "longitude-delta" Lui_extension.FloatScalar true None;
       ]
       []);
  Lui_extension.register_component registry
    (Lui_extension.component "apple-map-marker" apple_profiles false []
       [
         Lui_extension.property "title" Lui_extension.StringScalar true None;
         Lui_extension.property "latitude" Lui_extension.FloatScalar true None;
         Lui_extension.property "longitude" Lui_extension.FloatScalar true None;
       ]
       []);
  Lui_extension.register_tweak registry
    (Lui_extension.tweak "gallery-accent" all_profiles []);
  registry
