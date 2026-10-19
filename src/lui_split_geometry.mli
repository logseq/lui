val constrain_fraction :
  available:float ->
  first_min:float ->
  second_min:float ->
  ?first_max:float ->
  ?second_max:float ->
  float ->
  float
(** Resolve a split fraction against logical pane-width bounds. When the track
    cannot satisfy both minima or maxima, distribute it in proportion to those
    bounds. An empty track has a neutral fraction. *)

val handle_width : gap:float -> float option -> float
(** Resolve the hit width independently of pane spacing. A zero-gap split
    retains a three-point handle unless the caller specifies another width. *)

val handle_start : first:float -> gap:float -> width:float -> offset:float -> float
(** Position the handle around the gap center, shifted toward the second pane
    by the authored logical offset. *)
