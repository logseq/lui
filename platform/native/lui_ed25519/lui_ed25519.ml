(* Lui_ed25519 — Ed25519 signature verification (RFC 8032), pure OCaml.

   Three layers, no external dependencies:

   - Sha512: the compression function over Int64 words, one-shot API
     (verification hashes the whole message anyway).
   - Field arithmetic: the public-domain TweetNaCl reference scheme —
     16 int64 limbs in radix 2^16 mod 2^255-19, ported operation by
     operation so encoding edge cases match the reference.
   - Scalars mod l (the group order): 4 little-endian u64 limbs with
     schoolbook shift-subtract reduction — slow but small and obviously
     correct, and only runs once per hash.

   verify ~pk ~signature ~msg checks [s]B - [h]A = R the way
   crypto_sign_open does: unpackneg decodes -A, then
   pack(s·B + h·(-A)) must equal the signature's R bytes. *)

(* ------------------------------------------------------------------ *)
(* SHA-512, FIPS 180-4. Same shape as Lui_pkg's SHA-256 on Int64. *)

module Sha512 = struct
  let iv = [|
    0x6a09e667f3bcc908L; 0xbb67ae8584caa73bL; 0x3c6ef372fe94f82bL;
    0xa54ff53a5f1d36f1L; 0x510e527fade682d1L; 0x9b05688c2b3e6c1fL;
    0x1f83d9abfb41bd6bL; 0x5be0cd19137e2179L;
  |]

  let k = [|
    0x428a2f98d728ae22L; 0x7137449123ef65cdL; 0xb5c0fbcfec4d3b2fL;
    0xe9b5dba58189dbbcL; 0x3956c25bf348b538L; 0x59f111f1b605d019L;
    0x923f82a4af194f9bL; 0xab1c5ed5da6d8118L; 0xd807aa98a3030242L;
    0x12835b0145706fbeL; 0x243185be4ee4b28cL; 0x550c7dc3d5ffb4e2L;
    0x72be5d74f27b896fL; 0x80deb1fe3b1696b1L; 0x9bdc06a725c71235L;
    0xc19bf174cf692694L; 0xe49b69c19ef14ad2L; 0xefbe4786384f25e3L;
    0x0fc19dc68b8cd5b5L; 0x240ca1cc77ac9c65L; 0x2de92c6f592b0275L;
    0x4a7484aa6ea6e483L; 0x5cb0a9dcbd41fbd4L; 0x76f988da831153b5L;
    0x983e5152ee66dfabL; 0xa831c66d2db43210L; 0xb00327c898fb213fL;
    0xbf597fc7beef0ee4L; 0xc6e00bf33da88fc2L; 0xd5a79147930aa725L;
    0x06ca6351e003826fL; 0x142929670a0e6e70L; 0x27b70a8546d22ffcL;
    0x2e1b21385c26c926L; 0x4d2c6dfc5ac42aedL; 0x53380d139d95b3dfL;
    0x650a73548baf63deL; 0x766a0abb3c77b2a8L; 0x81c2c92e47edaee6L;
    0x92722c851482353bL; 0xa2bfe8a14cf10364L; 0xa81a664bbc423001L;
    0xc24b8b70d0f89791L; 0xc76c51a30654be30L; 0xd192e819d6ef5218L;
    0xd69906245565a910L; 0xf40e35855771202aL; 0x106aa07032bbd1b8L;
    0x19a4c116b8d2d0c8L; 0x1e376c085141ab53L; 0x2748774cdf8eeb99L;
    0x34b0bcb5e19b48a8L; 0x391c0cb3c5c95a63L; 0x4ed8aa4ae3418acbL;
    0x5b9cca4f7763e373L; 0x682e6ff3d6b2b8a3L; 0x748f82ee5defb2fcL;
    0x78a5636f43172f60L; 0x84c87814a1f0ab72L; 0x8cc702081a6439ecL;
    0x90befffa23631e28L; 0xa4506cebde82bde9L; 0xbef9a3f7b2c67915L;
    0xc67178f2e372532bL; 0xca273eceea26619cL; 0xd186b8c721c0c207L;
    0xeada7dd6cde0eb1eL; 0xf57d4f7fee6ed178L; 0x06f067aa72176fbaL;
    0x0a637dc5a2c898a6L; 0x113f9804bef90daeL; 0x1b710b35131c471bL;
    0x28db77f523047d84L; 0x32caab7b40c72493L; 0x3c9ebe0a15c9bebcL;
    0x431d67c49c100d4cL; 0x4cc5d4becb3e42b6L; 0x597f299cfc657e2aL;
    0x5fcb6fab3ad6faecL; 0x6c44198c4a475817L;
  |]

  let ( +! ) = Int64.add
  let ror x n =
    Int64.logor (Int64.shift_right_logical x n)
      (Int64.shift_left x (64 - n))
  let shr = Int64.shift_right_logical

  (* big-endian u64 fetch *)
  let get s i =
    let b j = Int64.of_int (Char.code s.[j]) in
    Int64.logor (Int64.shift_left (b i) 56)
      (Int64.logor (Int64.shift_left (b (i + 1)) 48)
         (Int64.logor (Int64.shift_left (b (i + 2)) 40)
            (Int64.logor (Int64.shift_left (b (i + 3)) 32)
               (Int64.logor (Int64.shift_left (b (i + 4)) 24)
                  (Int64.logor (Int64.shift_left (b (i + 5)) 16)
                     (Int64.logor (Int64.shift_left (b (i + 6)) 8)
                        (b (i + 7))))))))

  let compress h s off =
    let w = Array.make 80 0L in
    for i = 0 to 15 do
      w.(i) <- get s (off + (8 * i))
    done;
    for i = 16 to 79 do
      let x = w.(i - 15) and y = w.(i - 2) in
      let s0 =
        Int64.logxor (ror x 1)
          (Int64.logxor (ror x 8) (shr x 7))
      and s1 =
        Int64.logxor (ror y 19)
          (Int64.logxor (ror y 61) (shr y 6))
      in
      w.(i) <- w.(i - 16) +! s0 +! w.(i - 7) +! s1
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2)
    and d = ref h.(3) and e = ref h.(4) and f = ref h.(5)
    and g = ref h.(6) and hh = ref h.(7) in
    for i = 0 to 79 do
      let s1 =
        Int64.logxor (ror !e 14)
          (Int64.logxor (ror !e 18) (ror !e 41))
      and ch =
        Int64.logxor
          (Int64.logand !e !f)
          (Int64.logand (Int64.lognot !e) !g)
      in
      let t1 = !hh +! s1 +! ch +! k.(i) +! w.(i) in
      let s0 =
        Int64.logxor (ror !a 28)
          (Int64.logxor (ror !a 34) (ror !a 39))
      and maj =
        Int64.logxor
          (Int64.logxor (Int64.logand !a !b) (Int64.logand !a !c))
          (Int64.logand !b !c)
      in
      let t2 = s0 +! maj in
      hh := !g; g := !f; f := !e;
      e := !d +! t1;
      d := !c; c := !b; b := !a;
      a := t1 +! t2
    done;
    h.(0) <- h.(0) +! !a; h.(1) <- h.(1) +! !b;
    h.(2) <- h.(2) +! !c; h.(3) <- h.(3) +! !d;
    h.(4) <- h.(4) +! !e; h.(5) <- h.(5) +! !f;
    h.(6) <- h.(6) +! !g; h.(7) <- h.(7) +! !hh

  (* Streaming: [init] → [update]* → [finalize]. [buf] holds the
     partial tail block; [total] counts fed bytes for the pad. *)
  type ctx = {
    h : int64 array;
    buf : Bytes.t;
    mutable buflen : int;
    mutable total : int;
  }

  let init () =
    { h = Array.copy iv; buf = Bytes.create 128; buflen = 0; total = 0 }

  let update c b off len =
    c.total <- c.total + len;
    let off = ref off and left = ref len in
    while !left > 0 do
      let room = 128 - c.buflen in
      let n = min room !left in
      Bytes.blit b !off c.buf c.buflen n;
      c.buflen <- c.buflen + n;
      off := !off + n;
      left := !left - n;
      if c.buflen = 128 then begin
        compress c.h (Bytes.unsafe_to_string c.buf) 0;
        c.buflen <- 0
      end
    done

  let update_string c s = update c (Bytes.unsafe_of_string s) 0 (String.length s)

  let finalize c =
    let rest = c.buflen in
    let tail = Bytes.make (if rest < 112 then 128 else 256) '\000' in
    Bytes.blit c.buf 0 tail 0 rest;
    Bytes.set tail rest '\x80';
    let bits = Int64.mul (Int64.of_int c.total) 8L in
    let last = Bytes.length tail - 8 in
    for i = 0 to 7 do
      Bytes.set tail (last + i)
        (Char.chr
           (Int64.to_int
              (Int64.logand (Int64.shift_right_logical bits (56 - (8 * i)))
                 0xffL)))
    done;
    (* the length field's high 64 bits stay zero for any input an
       OCaml string can hold (< 2^61 bytes) *)
    compress c.h (Bytes.unsafe_to_string tail) 0;
    if Bytes.length tail = 256 then
      compress c.h (Bytes.unsafe_to_string tail) 128;
    String.init 64 (fun i ->
        Char.chr
          (Int64.to_int
             (Int64.logand
                (Int64.shift_right_logical c.h.(i lsr 3)
                   (56 - (8 * (i land 7))))
                0xffL)))

  (* One-shot digest of [s]. *)
  let string s =
    let c = init () in
    update_string c s;
    finalize c
end

let sha512 = Sha512.string

(* ------------------------------------------------------------------ *)
(* Field arithmetic mod 2^255-19: TweetNaCl gf = 16 limbs of 16 bits
   each in int64, loosely normalized by car25519. *)

type gf = int64 array (* 16 limbs *)

let gf0 () = Array.make 16 0L
let gf1 () = [| 1L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L; 0L |]

(* carries ripple limb to limb; the top limb wraps mod p via the 38x
   fold into limb 0 *)
let car25519 (o : gf) =
  for i = 0 to 15 do
    o.(i) <- Int64.add o.(i) 0x10000L;
    let c = Int64.shift_right o.(i) 16 in
    let next = if i < 15 then i + 1 else 0 in
    let addend =
      Int64.add (Int64.sub c 1L)
        (if i = 15 then Int64.mul 37L (Int64.sub c 1L) else 0L)
    in
    o.(next) <- Int64.add o.(next) addend;
    o.(i) <- Int64.sub o.(i) (Int64.shift_left c 16)
  done

let sel25519 (p : gf) (q : gf) (b : int64) =
  let c = Int64.lognot (Int64.sub b 1L) in
  for i = 0 to 15 do
    let t = Int64.logand c (Int64.logxor p.(i) q.(i)) in
    p.(i) <- Int64.logxor p.(i) t;
    q.(i) <- Int64.logxor q.(i) t
  done

let add (o : gf) (a : gf) (b : gf) =
  for i = 0 to 15 do
    o.(i) <- Int64.add a.(i) b.(i)
  done

let sub (o : gf) (a : gf) (b : gf) =
  for i = 0 to 15 do
    o.(i) <- Int64.sub a.(i) b.(i)
  done

let mul (o : gf) (a : gf) (b : gf) =
  let t = Array.make 31 0L in
  for i = 0 to 15 do
    for j = 0 to 15 do
      t.(i + j) <- Int64.add t.(i + j) (Int64.mul a.(i) b.(j))
    done
  done;
  for i = 0 to 14 do
    t.(i) <- Int64.add t.(i) (Int64.mul 38L t.(i + 16))
  done;
  Array.blit t 0 o 0 16;
  car25519 o;
  car25519 o

let sqr (o : gf) (a : gf) = mul o a a

(* allocating variants for expression-style call sites *)
let sq (a : gf) : gf =
  let o = gf0 () in
  sqr o a;
  o

let prod (a : gf) (b : gf) : gf =
  let o = gf0 () in
  mul o a b;
  o

let inv25519 (i : gf) : gf =
  let c = Array.copy i in
  for a = 253 downto 0 do
    sqr c c;
    if a <> 2 && a <> 4 then mul c c i
  done;
  c

(* x^((p-5)/8), the exponent used to take square roots mod p *)
let pow2523 (i : gf) : gf =
  let c = Array.copy i in
  for a = 250 downto 0 do
    sqr c c;
    if a <> 1 then mul c c i
  done;
  c

let unpack25519 (n : string) : gf =
  Array.init 16 (fun i ->
      Int64.logor
        (Int64.of_int (Char.code n.[2 * i]))
        (Int64.shift_left (Int64.of_int (Char.code n.[(2 * i) + 1])) 8))

let pack25519 (n : gf) : string =
  let t = Array.copy n in
  car25519 t;
  car25519 t;
  car25519 t;
  for _j = 0 to 1 do
    let m = Array.make 16 0L in
    m.(0) <- Int64.sub t.(0) 0xffedL;
    for i = 1 to 14 do
      m.(i) <-
        Int64.sub (Int64.sub t.(i) 0xffffL)
          (Int64.logand (Int64.shift_right m.(i - 1) 16) 1L);
      m.(i - 1) <- Int64.logand m.(i - 1) 0xffffL
    done;
    m.(15) <-
      Int64.sub (Int64.sub t.(15) 0x7fffL)
        (Int64.logand (Int64.shift_right m.(14) 16) 1L);
    let b = Int64.logand (Int64.shift_right m.(15) 16) 1L in
    m.(14) <- Int64.logand m.(14) 0xffffL;
    sel25519 t m (Int64.sub 1L b)
  done;
  String.init 32 (fun i ->
      Char.chr
        (Int64.to_int
           (Int64.logand
              (Int64.shift_right_logical t.(i lsr 1) (8 * (i land 1)))
              0xffL)))

let par25519 (p : gf) = Char.code (pack25519 p).[0] land 1

let neq25519 (a : gf) (b : gf) =
  not (String.equal (pack25519 a) (pack25519 b))

(* ------------------------------------------------------------------ *)
(* Scalars mod l, l = 2^252 + 27742317777372353535851937790883648493.
   4 little-endian u64 limbs, always kept < l. *)

module Sc = struct
  type t = int64 array (* 4 limbs, little-endian *)

  let l_limbs =
    [| 0x5812631a5cf5d3edL; 0x14def9dea2f79cd6L;
       0x0000000000000000L; 0x1000000000000000L |]

  let zero () = [| 0L; 0L; 0L; 0L |]
  let one () = [| 1L; 0L; 0L; 0L |]

  (* a < b, both < 2^256 *)
  let lt (a : t) (b : t) =
    let r = ref false and done_ = ref false in
    for i = 3 downto 0 do
      if not !done_ then begin
        let ai = a.(i) and bi = b.(i) in
        if ai <> bi then begin
          (* unsigned compare *)
          r := Int64.unsigned_compare ai bi < 0;
          done_ := true
        end
      end
    done;
    !r

  let ge a b = not (lt a b)

  (* a - b, assumes a >= b *)
  let sub (a : t) (b : t) : t =
    let out = Array.make 4 0L and borrow = ref 0L in
    for i = 0 to 3 do
      let ai = a.(i) and bi = Int64.add b.(i) !borrow in
      (* unsigned comparison: ai < b.(i)+borrow *)
      let b' = bi in
      let bor =
        if Int64.unsigned_compare ai b' < 0 then 1L else 0L
      in
      out.(i) <- Int64.sub ai b';
      borrow := bor
    done;
    out

  (* (a + b) mod l; a,b < l so the sum is < 2^254 and no top carry
     escapes *)
  let add_mod (a : t) (b : t) : t =
    let out = Array.make 4 0L and carry = ref 0L in
    for i = 0 to 3 do
      let s = Int64.add (Int64.add a.(i) b.(i)) !carry in
      let c =
        (* carry when a_i+b_i+carry wrapped past 2^64 *)
        if
          Int64.unsigned_compare s a.(i) < 0
          || (!carry = 1L && Int64.unsigned_compare s a.(i) <= 0
              && Int64.unsigned_compare b.(i) 0L = 0
              && Int64.unsigned_compare s a.(i) = 0)
        then 1L
        else 0L
      in
      out.(i) <- s;
      carry := c
    done;
    if ge out l_limbs then sub out l_limbs else out

  (* schoolbook reduce: any little-endian byte string -> value mod l *)
  let reduce (s : string) : t =
    let r = ref (zero ()) in
    for i = (8 * String.length s) - 1 downto 0 do
      r := add_mod !r !r;
      if (Char.code s.[i lsr 3] lsr (i land 7)) land 1 = 1 then
        r := add_mod !r (one ())
    done;
    !r

  let of_bytes_le (s : string) : t =
    Array.init 4 (fun i ->
        let acc = ref 0L in
        for j = 0 to 7 do
          acc :=
            Int64.logor !acc
              (Int64.shift_left (Int64.of_int (Char.code s.[(8 * i) + j]))
                 (8 * j))
        done;
        !acc)

  let to_bytes_le (a : t) : string =
    String.init 32 (fun i ->
        Char.chr
          (Int64.to_int
             (Int64.logand
                (Int64.shift_right_logical a.(i lsr 3) (8 * (i land 7)))
                0xffL)))

  let lt_l (s : string) = lt (of_bytes_le s) l_limbs

  (* (a * b) mod l by double-and-add on the bits of b; a,b < l *)
  let mul_mod (a : t) (b : t) : t =
    let r = ref (zero ()) in
    for i = 255 downto 0 do
      r := add_mod !r !r;
      if
        Int64.logand
          (Int64.shift_right_logical b.(i lsr 6) (i land 63))
          1L
        <> 0L
      then r := add_mod !r a
    done;
    !r
end

(* ------------------------------------------------------------------ *)
(* The curve: extended twisted-Edwards points (X:Y:Z:T). Constants are
   TweetNaCl's: the group equation constants D and D2 = 2d, the base
   point (X,Y), and I = sqrt(-1) mod p. *)

type point = { x : gf; y : gf; z : gf; t : gf }

let d_const =
  [| 0x78a3L; 0x1359L; 0x4dcaL; 0x75ebL; 0xd8abL; 0x4141L; 0x0a4dL;
     0x0070L; 0xe898L; 0x7779L; 0x4079L; 0x8cc7L; 0xfe73L; 0x2b6fL;
     0x6ceeL; 0x5203L |]

let d2 =
  [| 0xf159L; 0x26b2L; 0x9b94L; 0xebd6L; 0xb156L; 0x8283L; 0x149aL;
     0x00e0L; 0xd130L; 0xeef3L; 0x80f2L; 0x198eL; 0xfce7L; 0x56dfL;
     0xd9dcL; 0x2406L |]

let base_x =
  [| 0xd51aL; 0x8f25L; 0x2d60L; 0xc956L; 0xa7b2L; 0x9525L; 0xc760L;
     0x692cL; 0xdc5cL; 0xfdd6L; 0xe231L; 0xc0a4L; 0x53feL; 0xcd6eL;
     0x36d3L; 0x2169L |]

let base_y =
  [| 0x6658L; 0x6666L; 0x6666L; 0x6666L; 0x6666L; 0x6666L; 0x6666L;
     0x6666L; 0x6666L; 0x6666L; 0x6666L; 0x6666L; 0x6666L; 0x6666L;
     0x6666L; 0x6666L |]

let sqrt_m1 =
  [| 0xa0b0L; 0x4a0eL; 0x1b27L; 0xc4eeL; 0xe478L; 0xad2fL; 0x1806L;
     0x2f43L; 0xd7a7L; 0x3dfbL; 0x0099L; 0x2b4dL; 0xdf0bL; 0x4fc1L;
     0x2480L; 0x2b83L |]

let point_identity () =
  { x = gf0 (); y = gf1 (); z = gf1 (); t = gf0 () }

let point_copy p = { x = Array.copy p.x; y = Array.copy p.y;
                     z = Array.copy p.z; t = Array.copy p.t }

let point_base () =
  let t = gf0 () in
  mul t base_x base_y;
  { x = Array.copy base_x; y = Array.copy base_y; z = gf1 (); t }

(* p += q, the a=-1 addition formulas *)
let point_add (p : point) (q : point) =
  let a = gf0 () and b = gf0 () and c = gf0 () and d = gf0 ()
  and e = gf0 () and f = gf0 () and g = gf0 () and h = gf0 ()
  and tmp = gf0 () in
  sub a p.y p.x;
  sub tmp q.y q.x;
  mul a a tmp;
  add b p.x p.y;
  add tmp q.x q.y;
  mul b b tmp;
  mul c p.t q.t;
  mul c c d2;
  mul d p.z q.z;
  add d d d;
  sub e b a;
  sub f d c;
  add g d c;
  add h b a;
  mul p.x e f;
  mul p.y h g;
  mul p.z g f;
  mul p.t e h

let point_sel (p : point) (q : point) (b : int64) =
  sel25519 p.x q.x b;
  sel25519 p.y q.y b;
  sel25519 p.z q.z b;
  sel25519 p.t q.t b

(* p = s * q, the tweetnacl ladder: 256 swap-add-double rounds *)
let scalarmult (q : point) (s : string) : point =
  let p = point_identity () and q = point_copy q in
  for i = 255 downto 0 do
    let b =
      Int64.of_int ((Char.code s.[i lsr 3] lsr (i land 7)) land 1)
    in
    point_sel p q b;
    point_add q p;
    point_add p p;
    point_sel p q b
  done;
  p

let scalarbase (s : string) : point = scalarmult (point_base ()) s

(* affine encoding: y with the x parity in the top bit *)
let point_pack (p : point) : string =
  let zi = inv25519 p.z in
  let tx = gf0 () and ty = gf0 () in
  mul tx p.x zi;
  mul ty p.y zi;
  let b = Bytes.of_string (pack25519 ty) in
  Bytes.set b 31
    (Char.chr (Char.code (Bytes.get b 31) lxor (par25519 tx lsl 7)));
  Bytes.unsafe_to_string b

(* unpackneg: decode a compressed point to the NEGATIVE of the standard
   decoding (the sign bit selects the opposite x), or None when the
   encoding is not on the curve — exactly crypto_sign_open's q:
   x = ((y²-1)/(dy²+1))^((p+3)/8), multiplied by I when that candidate
   is not a square root; a second failed check means no such x. *)
let point_neg_decode (enc : string) : point option =
  if String.length enc <> 32 then None
  else begin
    let y = unpack25519 enc in
    let num = sq y in
    let den = prod num d_const in
    sub num num (gf1 ());
    add den (gf1 ()) den;
    (* x² = num/den; raise (num/den) via den's powers and pow2523 *)
    let den2 = sq den in
    let den4 = sq den2 in
    let den6 = prod den4 den2 in
    let t = prod den6 num in
    mul t t den;
    let t' = pow2523 t in
    mul t' t' num;
    mul t' t' den;
    mul t' t' den;
    let x = prod t' den in
    let chk = sq x in
    mul chk chk den;
    if neq25519 chk num then mul x x sqrt_m1;
    let chk = sq x in
    mul chk chk den;
    if neq25519 chk num then None
    else begin
      let sign = (Char.code enc.[31] lsr 7) land 1 in
      if par25519 x = sign then sub x (gf0 ()) x;
      let txy = prod x y in
      Some { x; y; z = gf1 (); t = txy }
    end
  end

(* y < p = 2^255-19 with the sign bit masked out — a canonical-field
   check on the key encoding. *)
let p_limbs =
  [| 0xffffffffffffffedL; 0xffffffffffffffffL; 0xffffffffffffffffL;
     0x7fffffffffffffffL |]

let canonical_y (enc : string) =
  let y = Sc.of_bytes_le enc in
  y.(3) <- Int64.logand y.(3) 0x7fffffffffffffffL;
  Sc.lt y p_limbs

(* ------------------------------------------------------------------ *)
(* RFC 8032 §5.1.7: check [s]B - [h]A = R via pack(s·B + h·(-A)) = R. *)

type pending = {
  neg_a : point;
  r_bytes : string;
  s_bytes : string;
  sha : Sha512.ctx;
}

let verify_begin ~pk ~signature =
  if String.length pk <> 32 || String.length signature <> 64 then None
  else begin
    let r_bytes = String.sub signature 0 32
    and s_bytes = String.sub signature 32 32 in
    (* reject non-canonical S and non-canonical key encodings up
       front, then the group equation decides *)
    if not (Sc.lt_l s_bytes && canonical_y pk) then None
    else
      match point_neg_decode pk with
      | None -> None
      | Some neg_a ->
        let sha = Sha512.init () in
        Sha512.update_string sha r_bytes;
        Sha512.update_string sha pk;
        Some { neg_a; r_bytes; s_bytes; sha }
  end

let verify_feed p b off len = Sha512.update p.sha b off len

let verify_finish p =
  let h = Sc.reduce (Sha512.finalize p.sha) in
  let q = scalarmult p.neg_a (Sc.to_bytes_le h) in
  let q2 = scalarbase p.s_bytes in
  point_add q q2;
  String.equal (point_pack q) p.r_bytes

let verify ~pk ~signature ~msg =
  match verify_begin ~pk ~signature with
  | None -> false
  | Some p ->
    verify_feed p (Bytes.unsafe_of_string msg) 0 (String.length msg);
    verify_finish p

(* ------------------------------------------------------------------ *)
(* Keys and signing — for tests, fixtures, and offline tooling. *)

let clamp (h : string) : string =
  let a = Bytes.of_string (String.sub h 0 32) in
  Bytes.set a 0 (Char.chr (Char.code (Bytes.get a 0) land 248));
  Bytes.set a 31
    (Char.chr ((Char.code (Bytes.get a 31) land 63) lor 64));
  Bytes.unsafe_to_string a

let public_key ~sk =
  if String.length sk <> 32 then None
  else
    let a = clamp (Sha512.string sk) in
    Some (point_pack (scalarbase a))

let sign ~sk ~msg =
  if String.length sk <> 32 then None
  else begin
    let h = Sha512.string sk in
    let a = clamp h in
    let prefix = String.sub h 32 32 in
    let pk = point_pack (scalarbase a) in
    let r = Sc.reduce (Sha512.string (prefix ^ msg)) in
    let rb = point_pack (scalarbase (Sc.to_bytes_le r)) in
    let k = Sc.reduce (Sha512.string (rb ^ pk ^ msg)) in
    let s = Sc.add_mod r (Sc.mul_mod k (Sc.reduce a)) in
    Some (rb ^ Sc.to_bytes_le s)
  end

(* ------------------------------------------------------------------ *)
(* Encodings: hex and base64. *)

let hexdigit = "0123456789abcdef"

let encode_hex s =
  let b = Bytes.create (2 * String.length s) in
  String.iteri
    (fun i c ->
       let v = Char.code c in
       Bytes.set b (2 * i) hexdigit.[v lsr 4];
       Bytes.set b ((2 * i) + 1) hexdigit.[v land 0xf])
    s;
  Bytes.unsafe_to_string b

let hex_value c =
  if c >= '0' && c <= '9' then Char.code c - Char.code '0'
  else if c >= 'a' && c <= 'f' then 10 + Char.code c - Char.code 'a'
  else if c >= 'A' && c <= 'F' then 10 + Char.code c - Char.code 'A'
  else -1

let decode_hex s =
  let n = String.length s in
  if n land 1 = 1 then None
  else begin
    let out = Bytes.create (n / 2) and ok = ref true in
    for i = 0 to (n / 2) - 1 do
      let hi = hex_value s.[2 * i] and lo = hex_value s.[(2 * i) + 1] in
      if hi < 0 || lo < 0 then ok := false
      else Bytes.set out i (Char.chr ((hi lsl 4) lor lo))
    done;
    if !ok then Some (Bytes.unsafe_to_string out) else None
  end

let b64_alphabet =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

let encode_base64 s =
  let n = String.length s in
  let out_len = 4 * ((n + 2) / 3) in
  let b = Bytes.make out_len '=' in
  let idx = ref 0 in
  let emit v =
    Bytes.set b !idx b64_alphabet.[v];
    incr idx
  in
  for i = 0 to (n / 3) - 1 do
    let v =
      (Char.code s.[3 * i] lsl 16)
      lor (Char.code s.[(3 * i) + 1] lsl 8)
      lor Char.code s.[(3 * i) + 2]
    in
    emit ((v lsr 18) land 63);
    emit ((v lsr 12) land 63);
    emit ((v lsr 6) land 63);
    emit (v land 63)
  done;
  (match n mod 3 with
   | 1 ->
     let v = Char.code s.[n - 1] lsl 16 in
     emit ((v lsr 18) land 63);
     emit ((v lsr 12) land 63)
   | 2 ->
     let v =
       (Char.code s.[n - 2] lsl 16) lor (Char.code s.[n - 1] lsl 8)
     in
     emit ((v lsr 18) land 63);
     emit ((v lsr 12) land 63);
     emit ((v lsr 6) land 63)
   | _ -> ());
  Bytes.unsafe_to_string b

let b64_value c =
  if c >= 'A' && c <= 'Z' then Char.code c - Char.code 'A'
  else if c >= 'a' && c <= 'z' then 26 + Char.code c - Char.code 'a'
  else if c >= '0' && c <= '9' then 52 + Char.code c - Char.code '0'
  else if c = '+' then 62
  else if c = '/' then 63
  else -1

let decode_base64 s =
  (* tolerate whitespace, nothing else *)
  let clean =
    String.concat ""
      (List.map (String.make 1)
         (List.of_seq
            (Seq.filter
               (fun c -> c <> ' ' && c <> '\n' && c <> '\r' && c <> '\t')
               (String.to_seq s))))
  in
  let n = String.length clean in
  if n = 0 || n mod 4 <> 0 then None
  else begin
    let pad =
      if n >= 2 && clean.[n - 2] = '=' then 2
      else if n >= 1 && clean.[n - 1] = '=' then 1
      else 0
    in
    let dlen = n - pad in
    let full = dlen / 4 in
    let rem = dlen mod 4 in
    (* pad=1 leaves a 3-char tail group, pad=2 a 2-char tail *)
    if (pad = 0 && rem <> 0) || (pad = 1 && rem <> 3) || (pad = 2 && rem <> 2)
    then None
    else begin
      let out = Buffer.create 64 and ok = ref true in
      for i = 0 to full - 1 do
        let v j = b64_value clean.[(4 * i) + j] in
        let a = v 0 and b = v 1 and c = v 2 and d = v 3 in
        if a < 0 || b < 0 || c < 0 || d < 0 then ok := false
        else begin
          let x = (a lsl 18) lor (b lsl 12) lor (c lsl 6) lor d in
          Buffer.add_char out (Char.chr ((x lsr 16) land 0xff));
          Buffer.add_char out (Char.chr ((x lsr 8) land 0xff));
          Buffer.add_char out (Char.chr (x land 0xff))
        end
      done;
      if rem > 0 then begin
        let i = 4 * full in
        let a = b64_value clean.[i] and b = b64_value clean.[i + 1] in
        if a < 0 || b < 0 then ok := false
        else if rem = 2 then begin
          let x = (a lsl 18) lor (b lsl 12) in
          Buffer.add_char out (Char.chr ((x lsr 16) land 0xff))
        end
        else begin
          let c = b64_value clean.[i + 2] in
          if c < 0 then ok := false
          else begin
            let x = (a lsl 18) lor (b lsl 12) lor (c lsl 6) in
            Buffer.add_char out (Char.chr ((x lsr 16) land 0xff));
            Buffer.add_char out (Char.chr ((x lsr 8) land 0xff))
          end
        end
      end;
      if !ok then Some (Buffer.contents out) else None
    end
  end

let all_hex s =
  String.for_all (fun c -> hex_value c >= 0) s

let decode_key s =
  match
    (if String.length s = 64 && all_hex s then decode_hex s
     else decode_base64 s)
  with
  | Some b when String.length b = 32 -> Some b
  | _ -> None

let decode_signature s =
  match
    (if String.length s = 128 && all_hex s then decode_hex s
     else decode_base64 s)
  with
  | Some b when String.length b = 64 -> Some b
  | _ -> None
