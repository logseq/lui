let constrain_fraction ~available ~first_min ~second_min ?first_max ?second_max
    value =
  if available <= 0. then 0.5
  else if first_min +. second_min > available then
    first_min /. (first_min +. second_min)
  else
    let first_max = Option.value first_max ~default:available
    and second_max = Option.value second_max ~default:available in
    if first_max +. second_max < available then
      if first_max +. second_max = 0. then 0.5
      else first_max /. (first_max +. second_max)
    else
      let lower = Float.max first_min (available -. second_max)
      and upper = Float.min first_max (available -. second_min) in
      Float.max lower (Float.min upper (value *. available)) /. available
