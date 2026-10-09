(* Direct bindings to the headless TanStack Virtual element virtualizer. *)
type t
type options
type item
type fn
type range
type rect

external element_scroll : fn = "elementScroll"
[@@mel.module "@tanstack/virtual-core"]

external observe_element_rect : fn = "observeElementRect"
[@@mel.module "@tanstack/virtual-core"]

external observe_element_offset : fn = "observeElementOffset"
[@@mel.module "@tanstack/virtual-core"]

external default_range : range -> int array = "defaultRangeExtractor"
[@@mel.module "@tanstack/virtual-core"]

external rect : width:float -> height:float -> rect = "" [@@mel.obj]

external options :
  count:int ->
  getScrollElement:(unit -> Dom.element Js.Nullable.t) ->
  estimateSize:(int -> float) ->
  getItemKey:(int -> string) ->
  scrollToFn:fn ->
  observeElementRect:fn ->
  observeElementOffset:fn ->
  onChange:(t -> bool -> unit) ->
  rangeExtractor:(range -> int array) ->
  initialRect:rect ->
  overscan:int ->
  gap:float ->
  unit ->
  options = ""
[@@mel.obj]

external make : options -> t = "Virtualizer"
[@@mel.new] [@@mel.module "@tanstack/virtual-core"]

external did_mount : t -> unit -> unit = "_didMount" [@@mel.send]
external will_update : t -> unit = "_willUpdate" [@@mel.send]
external set_options : t -> options -> unit = "setOptions" [@@mel.send]
external items : t -> item array = "getVirtualItems" [@@mel.send]
external total_size : t -> float = "getTotalSize" [@@mel.send]

external measure : t -> Dom.element Js.Nullable.t -> unit = "measureElement"
[@@mel.send]

external item_index : item -> int = "index" [@@mel.get]
external item_start : item -> float = "start" [@@mel.get]
external resize_item : t -> int -> float -> unit = "resizeItem" [@@mel.send]
