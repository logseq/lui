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
