(* Lui_ed25519 — Ed25519 (RFC 8032) helpers for the self-update client.

   All curve arithmetic, point decoding, and the hashing inside
   sign/verify is delegated to [Mirage_crypto_ec.Ed25519] — a mature,
   maintained implementation built on fiat-crypto generated field code —
   and SHA-512 to [Digestif]. Nothing in this file implements
   cryptography itself; it supplies the hex/base64 text encodings feeds
   use for keys and signatures, plus a chunked-feed verify front end so
   callers can stream a file through the verifier. *)

module E = Mirage_crypto_ec.Ed25519
module H = Digestif.SHA512

let sha512 msg = H.(to_raw_string (digest_string msg))

(* ------------------------------------------------------------------ *)
(* Verification. *)

let verify ~pk ~signature ~msg =
  match E.pub_of_octets pk with
  | Error _ -> false
  | Ok pub -> E.verify ~key:pub signature ~msg

(* The underlying verify is whole-message, so a pending verification
   buffers what it is fed and answers at [verify_finish]. *)
type pending = { buf : Buffer.t; pub : E.pub; signature : string }

let verify_begin ~pk ~signature =
  match E.pub_of_octets pk with
  | Error _ -> None
  | Ok pub ->
    if String.length signature = 64
    then Some { buf = Buffer.create 4096; pub; signature }
    else None

let verify_feed p b off len = Buffer.add_subbytes p.buf b off len

let verify_finish p =
  E.verify ~key:p.pub p.signature ~msg:(Buffer.contents p.buf)

(* ------------------------------------------------------------------ *)
(* Keys and signing — for tests, fixtures, and offline tooling. *)

let public_key ~sk =
  match E.priv_of_octets sk with
  | Error _ -> None
  | Ok priv -> Some (E.pub_to_octets (E.pub_of_priv priv))

let sign ~sk ~msg =
  match E.priv_of_octets sk with
  | Error _ -> None
  | Ok priv -> Some (E.sign ~key:priv msg)

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
