(* The pre-decompress DEFLATE implementation, vendored verbatim from
   pre-L4 lui_pkg.ml so the suite can prove wire compat in both
   directions: packages written by an old encoder must still apply
   under the new decoder, and packages written now must still apply
   under the old one. Test-only; keep frozen. *)

let adler32 s =
  let a = ref 1 and b = ref 0 in
  String.iter
    (fun c ->
       a := (!a + Char.code c) mod 65521;
       b := (!b + !a) mod 65521)
    s;
  Int32.logor (Int32.shift_left (Int32.of_int !b) 16) (Int32.of_int !a)
  let hash_bits = 15
  let hash_size = 1 lsl hash_bits
  let window_size = 32768
  let max_match = 258
  let min_match = 3
  let max_chain = 96

  let hash3 data i =
    ((Char.code data.[i] lsl 10)
     lxor (Char.code data.[i + 1] lsl 5)
     lxor Char.code data.[i + 2])
    land (hash_size - 1)

  (* code index 0..28 ↔ lengths 3..258 *)
  let length_base = [|
    3; 4; 5; 6; 7; 8; 9; 10; 11; 13; 15; 17; 19; 23; 27; 31; 35; 43; 51;
    59; 67; 83; 99; 115; 131; 163; 195; 227; 258
  |]

  let length_extra = [|
    0; 0; 0; 0; 0; 0; 0; 0; 1; 1; 1; 1; 2; 2; 2; 2; 3; 3; 3; 3; 4; 4; 4;
    4; 5; 5; 5; 5; 0
  |]

  let dist_base = [|
    1; 2; 3; 4; 5; 7; 9; 13; 17; 25; 33; 49; 65; 97; 129; 193; 257; 385;
    513; 769; 1025; 1537; 2049; 3073; 4097; 6145; 8193; 12289; 16385;
    24577
  |]

  let dist_extra = [|
    0; 0; 0; 0; 1; 1; 2; 2; 3; 3; 4; 4; 5; 5; 6; 6; 7; 7; 8; 8; 9; 9;
    10; 10; 11; 11; 12; 12; 13; 13
  |]

  (* LSB-first bit writer. *)
  type bitw = { mutable acc : int; mutable nbits : int; buf : Buffer.t }

  let bitw () = { acc = 0; nbits = 0; buf = Buffer.create 4096 }

  let put_bits w v n =
    let v = v land ((1 lsl n) - 1) in
    w.acc <- w.acc lor (v lsl w.nbits);
    w.nbits <- w.nbits + n;
    while w.nbits >= 8 do
      Buffer.add_char w.buf (Char.chr (w.acc land 0xff));
      w.acc <- w.acc lsr 8;
      w.nbits <- w.nbits - 8
    done

  (* Huffman codes are packed MSB-first. *)
  let put_code w code n =
    for i = n - 1 downto 0 do
      put_bits w ((code lsr i) land 1) 1
    done

  let flush_bits w =
    if w.nbits > 0 then begin
      Buffer.add_char w.buf (Char.chr (w.acc land 0xff));
      w.acc <- 0;
      w.nbits <- 0
    end

  let fixed_lit_code sym =
    if sym <= 143 then (0x30 + sym, 8)
    else if sym <= 255 then (0x190 + sym - 144, 9)
    else if sym <= 279 then (sym - 256, 7)
    else (0xc0 + sym - 280, 8)

  let emit_lit w sym =
    let code, n = fixed_lit_code sym in
    put_code w code n

  let emit_match w ~len ~dist =
    let li = ref 0 in
    while !li < 28 && len >= length_base.(!li + 1) do
      incr li
    done;
    let code, n = fixed_lit_code (257 + !li) in
    put_code w code n;
    put_bits w (len - length_base.(!li)) length_extra.(!li);
    let di = ref 0 in
    while !di < 29 && dist >= dist_base.(!di + 1) do
      incr di
    done;
    put_code w !di 5;
    put_bits w (dist - dist_base.(!di)) dist_extra.(!di)

  (** [deflate data] compresses to raw DEFLATE: a single final fixed
      block. *)
  let deflate data =
    let n = String.length data in
    let w = bitw () in
    put_bits w 1 1;
    (* BFINAL *)
    put_bits w 1 2;
    (* BTYPE fixed *)
    if n > 0 then begin
      let head = Array.make hash_size (-1) in
      let prev = Array.make n (-1) in
      let i = ref 0 in
      while !i < n do
        let best_len = ref 0 and best_pos = ref (-1) in
        if !i + 2 < n then begin
          let h = hash3 data !i in
          let cand = ref head.(h) and steps = ref 0 in
          while
            !cand >= 0 && !steps < max_chain && !i - !cand <= window_size
          do
            let l = ref 0 in
            while
              !l < max_match && !cand + !l < n && !i + !l < n
              && data.[!cand + !l] = data.[!i + !l]
            do
              incr l
            done;
            if !l > !best_len then begin
              best_len := !l;
              best_pos := !cand;
              if !l >= max_match then steps := max_chain
            end;
            cand := prev.(!cand);
            incr steps
          done;
          prev.(!i) <- head.(h);
          head.(h) <- !i
        end;
        if !best_len >= min_match then begin
          emit_match w ~len:!best_len ~dist:(!i - !best_pos);
          let stop = min (!i + !best_len) n in
          for j = !i + 1 to stop - 1 do
            if j + 2 < n then begin
              let h = hash3 data j in
              prev.(j) <- head.(h);
              head.(h) <- j
            end
          done;
          i := stop
        end
        else begin
          emit_lit w (Char.code data.[!i]);
          incr i
        end
      done
    end;
    emit_lit w 256;
    flush_bits w;
    Buffer.contents w.buf

  exception Bad_stream of string

  (* LSB-first bit reader. *)
  type bitr = {
    data : string;
    mutable pos : int;
    mutable acc : int;
    mutable nbits : int;
  }

  let bitr data = { data; pos = 0; acc = 0; nbits = 0 }

  let get_bit r =
    if r.nbits = 0 then begin
      if r.pos >= String.length r.data then raise (Bad_stream "truncated");
      r.acc <- Char.code r.data.[r.pos];
      r.pos <- r.pos + 1;
      r.nbits <- 8
    end;
    let b = r.acc land 1 in
    r.acc <- r.acc lsr 1;
    r.nbits <- r.nbits - 1;
    b

  let get_bits r n =
    let v = ref 0 in
    for i = 0 to n - 1 do
      v := !v lor (get_bit r lsl i)
    done;
    !v

  let align_byte r =
    r.acc <- 0;
    r.nbits <- 0

  (* Canonical Huffman table: counts per length + sorted symbols. *)
  type table = { counts : int array; symbols : int array }

  let build_table lengths =
    let counts = Array.make 16 0 in
    Array.iter (fun l -> counts.(l) <- counts.(l) + 1) lengths;
    counts.(0) <- 0;
    let offs = Array.make 16 0 in
    for i = 1 to 15 do
      offs.(i) <- offs.(i - 1) + counts.(i - 1)
    done;
    let symbols = Array.make (Array.length lengths) 0 in
    Array.iteri
      (fun sym l ->
         if l > 0 then begin
           symbols.(offs.(l)) <- sym;
           offs.(l) <- offs.(l) + 1
         end)
      lengths;
    { counts; symbols }

  let decode r t =
    let code = ref 0 and first = ref 0 and index = ref 0 in
    let len = ref 1 and found = ref (-1) in
    while !len <= 15 && !found < 0 do
      code := (!code lsl 1) lor get_bit r;
      let count = t.counts.(!len) in
      if !code - !first >= 0 && !code - !first < count then
        found := t.symbols.(!index + !code - !first)
      else begin
        index := !index + count;
        first := (!first + count) lsl 1;
        incr len
      end
    done;
    if !found < 0 then raise (Bad_stream "bad huffman code");
    !found

  let fixed_lit_table =
    lazy
      (let lengths = Array.make 288 0 in
       for i = 0 to 143 do lengths.(i) <- 8 done;
       for i = 144 to 255 do lengths.(i) <- 9 done;
       for i = 256 to 279 do lengths.(i) <- 7 done;
       for i = 280 to 287 do lengths.(i) <- 8 done;
       build_table lengths)

  let fixed_dist_table = lazy (build_table (Array.make 32 5))

  let clen_order = [|
    16; 17; 18; 0; 8; 7; 9; 6; 10; 5; 11; 4; 12; 3; 13; 2; 14; 1; 15
  |]

  (** [inflate ~off ~len data] decodes a raw DEFLATE stream into a
      string. Raises [Bad_stream] on damaged input. *)
  let inflate ?(off = 0) ?len data =
    let len = match len with Some l -> l | None -> String.length data - off in
    let sub = String.sub data off len in
    let r = bitr sub in
    let arr = ref (Bytes.create (min (max (2 * len) 4096) (1 lsl 26))) in
    let out_len = ref 0 in
    let put_byte b =
      if !out_len = Bytes.length !arr then begin
        let bigger = Bytes.create (2 * Bytes.length !arr) in
        Bytes.blit !arr 0 bigger 0 !out_len;
        arr := bigger
      end;
      Bytes.set !arr !out_len (Char.chr b);
      incr out_len
    in
    let copy ~dist ~length =
      if dist <= 0 || dist > !out_len then raise (Bad_stream "bad distance");
      for _ = 1 to length do
        put_byte (Char.code (Bytes.get !arr (!out_len - dist)))
      done
    in
    let rec decode_block lit_t dist_t =
      let sym = decode r lit_t in
      if sym = 256 then ()
      else if sym < 256 then begin
        put_byte sym;
        decode_block lit_t dist_t
      end
      else begin
        let li = sym - 257 in
        if li > 28 then raise (Bad_stream "bad length code");
        let length = length_base.(li) + get_bits r length_extra.(li) in
        let di = decode r dist_t in
        if di > 29 then raise (Bad_stream "bad distance code");
        let dist = dist_base.(di) + get_bits r dist_extra.(di) in
        copy ~dist ~length;
        decode_block lit_t dist_t
      end
    in
    let done_ = ref false in
    while not !done_ do
      let final = get_bit r = 1 in
      (match get_bits r 2 with
       | 0 ->
         align_byte r;
         if r.pos + 4 > String.length sub then raise (Bad_stream "stored");
         let l =
           Char.code sub.[r.pos] lor (Char.code sub.[r.pos + 1] lsl 8)
         in
         let nl =
           Char.code sub.[r.pos + 2] lor (Char.code sub.[r.pos + 3] lsl 8)
         in
         if l <> nl lxor 0xffff then raise (Bad_stream "stored length");
         r.pos <- r.pos + 4;
         if r.pos + l > String.length sub then raise (Bad_stream "stored data");
         for _ = 1 to l do
           put_byte (Char.code sub.[r.pos]);
           r.pos <- r.pos + 1
         done
       | 1 ->
         decode_block (Lazy.force fixed_lit_table)
           (Lazy.force fixed_dist_table)
       | 2 ->
         let hlit = get_bits r 5 + 257 in
         let hdist = get_bits r 5 + 1 in
         let hclen = get_bits r 4 + 4 in
         let cl = Array.make 19 0 in
         for i = 0 to hclen - 1 do
           cl.(clen_order.(i)) <- get_bits r 3
         done;
         let cl_t = build_table cl in
         let lengths = Array.make (hlit + hdist) 0 in
         let i = ref 0 in
         while !i < hlit + hdist do
           let sym = decode r cl_t in
           (match sym with
            | _ when sym <= 15 ->
              lengths.(!i) <- sym;
              incr i
            | 16 ->
              if !i = 0 then raise (Bad_stream "repeat with no previous");
              let rep = get_bits r 2 + 3 in
              if !i + rep > hlit + hdist then raise (Bad_stream "clen overflow");
              let prev = lengths.(!i - 1) in
              for _ = 1 to rep do
                lengths.(!i) <- prev;
                incr i
              done
            | 17 ->
              let rep = get_bits r 3 + 3 in
              if !i + rep > hlit + hdist then raise (Bad_stream "clen overflow");
              i := !i + rep
            | 18 ->
              let rep = get_bits r 7 + 11 in
              if !i + rep > hlit + hdist then raise (Bad_stream "clen overflow");
              i := !i + rep
            | _ -> raise (Bad_stream "bad clen symbol"))
         done;
         let lit_t = build_table (Array.sub lengths 0 hlit)
         and dist_t = build_table (Array.sub lengths hlit hdist) in
         decode_block lit_t dist_t
       | _ -> raise (Bad_stream "bad block type"));
      if final then done_ := true
    done;
    Bytes.sub_string !arr 0 !out_len

  (** zlib wrapper: 0x78 0x9C + raw deflate + adler32 — what
      [zlib.decompress]/[unzip -t] understand. *)
  let zlib data =
    let cmf_flg = "\x78\x9c" in
    let body = deflate data in
    let a = adler32 data in
    let b = Buffer.create (6 + String.length body) in
    Buffer.add_string b cmf_flg;
    Buffer.add_string b body;
    for sft = 3 downto 0 do
      Buffer.add_char b
        (Char.chr
           (Int32.to_int
              (Int32.logand (Int32.shift_right_logical a (8 * sft)) 0xffl)))
    done;
    Buffer.contents b