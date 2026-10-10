(* Packaging and distribution for native apps, macOS first: .app bundle
   assembly, code signing, notarization, disk images and delta updates.

   The library is split into a pure core (file formats, command-line
   composition, binary diff) that runs on every OS, and a macOS
   implementation driving the platform tools (hdiutil, codesign,
   iconutil, sips, ditto, xcrun). Linux and Windows resolve to declared
   stubs that answer [Unsupported] so callers can code against one API.

   Credentials never pass through API parameters: notarization reads its
   secrets from named environment variables or from a keychain profile
   stored ahead of time on the machine. *)

(** {1 Results} *)

type platform = Macos | Linux | Windows | Unknown of string

type failure =
  | Tool_failed of {
      tool : string;
      args : string list;
      status : int;
      output : string;
    }
  | Missing of string  (** A required file or tool is absent. *)
  | Invalid of string  (** Input violates the format or the API. *)

type 'a outcome =
  | Ok of 'a
  | Skipped of string  (** A precondition is absent (credentials or a
                           tool); nothing was attempted. *)
  | Unsupported of string  (** The platform has no implementation yet. *)
  | Failed of failure  (** A tool ran and failed, or input was invalid. *)

let outcome_map f = function
  | Ok v -> Ok (f v)
  | Skipped s -> Skipped s
  | Unsupported s -> Unsupported s
  | Failed e -> Failed e

let tool_failed tool args status output =
  Failed (Tool_failed { tool; args; status; output })

let missing fmt = Printf.ksprintf (fun s -> Failed (Missing s)) fmt
let invalid fmt = Printf.ksprintf (fun s -> Failed (Invalid s)) fmt

let string_of_failure = function
  | Tool_failed { tool; args; status; output } ->
    Printf.sprintf "%s %s failed (%d): %s" tool
      (String.concat " " args) status output
  | Missing s -> Printf.sprintf "missing: %s" s
  | Invalid s -> Printf.sprintf "invalid: %s" s

let string_of_outcome to_s = function
  | Ok v -> Printf.sprintf "ok: %s" (to_s v)
  | Skipped s -> Printf.sprintf "skipped: %s" s
  | Unsupported s -> Printf.sprintf "unsupported: %s" s
  | Failed f -> Printf.sprintf "failed: %s" (string_of_failure f)

let fmt = Printf.sprintf

(** {1 Platform} *)

let uname arg =
  let ic = Unix.open_process_in (fmt "uname %s 2>/dev/null" arg) in
  let s = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  String.trim s

let host_platform () =
  match Sys.os_type with
  | "Win32" -> Windows
  | _ -> (
    match uname "-s" with
    | "Darwin" -> Macos
    | "Linux" -> Linux
    | s when String.length s >= 5 && String.sub s 0 5 = "MINGW" -> Windows
    | s when String.length s >= 4 && String.sub s 0 4 = "MSYS" -> Windows
    | s when String.length s >= 6 && String.sub s 0 6 = "CYGWIN" -> Windows
    | other -> Unknown other)

let string_of_platform = function
  | Macos -> "macos"
  | Linux -> "linux"
  | Windows -> "windows"
  | Unknown s -> s

let host_arch () =
  match uname "-m" with
  | "arm64" | "aarch64" -> "arm64"
  | "x86_64" | "AMD64" -> "x86_64"
  | other -> other

(** {1 Filesystem} *)

module Fs = struct
  type kind = Dir | File | Link | Other | Absent

  let kind_of path =
    try
      match (Unix.lstat path).Unix.st_kind with
      | Unix.S_DIR -> Dir
      | Unix.S_REG -> File
      | Unix.S_LNK -> Link
      | _ -> Other
    with Unix.Unix_error (Unix.ENOENT, _, _) -> Absent

  let exists path = kind_of path <> Absent
  let is_dir path = kind_of path = Dir

  let rec mkdir_p ?(perm = 0o755) dir =
    if dir <> "" && not (is_dir dir) then begin
      mkdir_p ~perm (Filename.dirname dir);
      try Unix.mkdir dir perm
      with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
    end

  let rec rm_rf path =
    match kind_of path with
    | Dir ->
      Array.iter
        (fun e -> if e <> "." && e <> ".." then rm_rf (Filename.concat path e))
        (Sys.readdir path);
      (try Unix.rmdir path with Unix.Unix_error _ -> ())
    | File | Link | Other -> (try Sys.remove path with Sys_error _ -> ())
    | Absent -> ()

  let read_file path =
    let ic = open_in_bin path in
    let n = in_channel_length ic in
    let s = really_input_string ic n in
    close_in ic;
    s

  let write_file ?(perm = 0o644) path data =
    let oc = open_out_bin path in
    output_string oc data;
    close_out oc;
    (try Unix.chmod path perm with Unix.Unix_error _ -> ())

  let copy_file ~src ~dst =
    mkdir_p (Filename.dirname dst);
    let ic = open_in_bin src in
    let oc = open_out_bin dst in
    let buf = Bytes.create (256 * 1024) in
    let rec loop () =
      match input ic buf 0 (Bytes.length buf) with
      | 0 -> ()
      | n ->
        output oc buf 0 n;
        loop ()
    in
    loop ();
    close_in ic;
    close_out oc;
    (try
       let mode = (Unix.stat src).Unix.st_perm in
       Unix.chmod dst mode
     with Unix.Unix_error _ -> ())

  (** [walk root] lists every entry below [root] (not [root] itself) as
      [(relative_path, kind)] in depth-first order. Links are listed, not
      followed; dot files are kept: a bundle's hidden files ship too. *)
  let walk root =
    let out = ref [] in
    let rec go rel =
      let here = Filename.concat root rel in
      let entries = try Sys.readdir here with Sys_error _ -> [||] in
      Array.iter
        (fun name ->
           let r = if rel = "" then name else Filename.concat rel name in
           let k = kind_of (Filename.concat root r) in
           out := (r, k) :: !out;
           if k = Dir then go r)
        entries
    in
    go "";
    List.rev !out

  (** [install ~src ~dst] copies a file, a link or a whole directory tree
      like [cp -R]: [src] itself is followed when a link, links inside a
      tree stay links, modes are preserved. *)
  let rec install ~src ~dst =
    match (Unix.stat src).Unix.st_kind with
    | Unix.S_REG -> copy_file ~src ~dst
    | Unix.S_DIR ->
      mkdir_p dst;
      Array.iter (fun e -> install_child ~src ~dst e) (Sys.readdir src)
    | Unix.S_LNK ->
      (try Unix.symlink (Unix.readlink src) dst
       with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    | _ -> ()
  and install_child ~src ~dst name =
    let s = Filename.concat src name and d = Filename.concat dst name in
    match (Unix.lstat s).Unix.st_kind with
    | Unix.S_LNK ->
      (try Unix.symlink (Unix.readlink s) d
       with Unix.Unix_error (Unix.EEXIST, _, _) -> ())
    | Unix.S_DIR ->
      mkdir_p d;
      Array.iter (fun e -> install_child ~src:s ~dst:d e) (Sys.readdir s)
    | Unix.S_REG -> copy_file ~src:s ~dst:d
    | _ -> ()

  let file_size path =
    try Some (Unix.stat path).Unix.st_size
    with Unix.Unix_error _ -> None

  let temp_dir ?(prefix = "lui_pkg-") ?(parent = Filename.get_temp_dir_name ()) () =
    let rec try_one n =
      let d = fmt "%s%s%d-%d" parent prefix (Unix.getpid ()) n in
      match kind_of d with
      | Absent ->
        Unix.mkdir d 0o700;
        d
      | _ -> try_one (n + 1)
    in
    try_one (int_of_float (Unix.gettimeofday () *. 1000.) mod 1_000_000)
end

(** {1 Processes} *)

module Proc = struct
  type ran = { status : int; stdout : string; stderr : string }

  (** Runs [prog args], capturing stdout and stderr into temp files so a
      chatty child cannot deadlock on a full pipe. The parent's PATH is
      searched (create_process goes through execvp). *)
  let run ?(stdin = "/dev/null") prog args =
    let dir = Fs.temp_dir ~prefix:"lui_pkg-proc-" () in
    let out_p = Filename.concat dir "out"
    and err_p = Filename.concat dir "err" in
    let out_oc = open_out_bin out_p and err_oc = open_out_bin err_p in
    let in_fd = Unix.openfile stdin [ Unix.O_RDONLY ] 0 in
    let pid =
      Unix.create_process prog (Array.of_list (prog :: args)) in_fd
        (Unix.descr_of_out_channel out_oc)
        (Unix.descr_of_out_channel err_oc)
    in
    Unix.close in_fd;
    close_out out_oc;
    close_out err_oc;
    let _, st = Unix.waitpid [] pid in
    let stdout = Fs.read_file out_p and stderr = Fs.read_file err_p in
    Fs.rm_rf dir;
    let status =
      match st with
      | Unix.WEXITED n -> n
      | Unix.WSIGNALED n -> 128 + n
      | Unix.WSTOPPED n -> 128 + n
    in
    { status; stdout; stderr }

  let which prog =
    match run "sh" [ "-c"; fmt "command -v %s" prog ] with
    | { status = 0; stdout; _ } -> (
      match String.trim stdout with "" -> None | p -> Some p)
    | _ -> None

  (** [check prog args] runs and returns the capture on exit status 0,
      a [Tool_failed] error otherwise. *)
  let check prog args =
    let r = run prog args in
    if r.status = 0 then Stdlib.Ok r
    else Error (Tool_failed { tool = prog; args; status = r.status;
                              output = r.stdout ^ r.stderr })

  let check_o prog args =
    match check prog args with Ok r -> Ok r.stdout | Error e -> Failed e
end

(** {1 SHA-256} *)

module Sha256 = struct
  let k = [|
    0x428a2f98l; 0x71374491l; 0xb5c0fbcfl; 0xe9b5dba5l; 0x3956c25bl;
    0x59f111f1l; 0x923f82a4l; 0xab1c5ed5l; 0xd807aa98l; 0x12835b01l;
    0x243185bel; 0x550c7dc3l; 0x72be5d74l; 0x80deb1fel; 0x9bdc06a7l;
    0xc19bf174l; 0xe49b69c1l; 0xefbe4786l; 0x0fc19dc6l; 0x240ca1ccl;
    0x2de92c6fl; 0x4a7484aal; 0x5cb0a9dcl; 0x76f988dal; 0x983e5152l;
    0xa831c66dl; 0xb00327c8l; 0xbf597fc7l; 0xc6e00bf3l; 0xd5a79147l;
    0x06ca6351l; 0x14292967l; 0x27b70a85l; 0x2e1b2138l; 0x4d2c6dfcl;
    0x53380d13l; 0x650a7354l; 0x766a0abbl; 0x81c2c92el; 0x92722c85l;
    0xa2bfe8a1l; 0xa81a664bl; 0xc24b8b70l; 0xc76c51a3l; 0xd192e819l;
    0xd6990624l; 0xf40e3585l; 0x106aa070l; 0x19a4c116l; 0x1e376c08l;
    0x2748774cl; 0x34b0bcb5l; 0x391c0cb3l; 0x4ed8aa4al; 0x5b9cca4fl;
    0x682e6ff3l; 0x748f82eel; 0x78a5636fl; 0x84c87814l; 0x8cc70208l;
    0x90befffal; 0xa4506cebl; 0xbef9a3f7l; 0xc67178f2l
  |]

  let init = [|
    0x6a09e667l; 0xbb67ae85l; 0x3c6ef372l; 0xa54ff53al;
    0x510e527fl; 0x9b05688cl; 0x1f83d9abl; 0x5be0cd19l
  |]

  let ror32 x n =
    Int32.logor (Int32.shift_right_logical x n) (Int32.shift_left x (32 - n))

  let get32 s i =
    Int32.logor
      (Int32.shift_left (Int32.of_int (Char.code s.[i])) 24)
      (Int32.logor
         (Int32.shift_left (Int32.of_int (Char.code s.[i + 1])) 16)
         (Int32.logor
            (Int32.shift_left (Int32.of_int (Char.code s.[i + 2])) 8)
            (Int32.of_int (Char.code s.[i + 3]))))

  (* One compression over the 64-byte block of [s] at [off]. *)
  let compress h s off =
    let w = Array.make 64 0l in
    for i = 0 to 15 do
      w.(i) <- get32 s (off + (4 * i))
    done;
    for i = 16 to 63 do
      let x = w.(i - 15) and y = w.(i - 2) in
      let s0 =
        Int32.logxor (ror32 x 7)
          (Int32.logxor (ror32 x 18) (Int32.shift_right_logical x 3))
      in
      let s1 =
        Int32.logxor (ror32 y 17)
          (Int32.logxor (ror32 y 19) (Int32.shift_right_logical y 10))
      in
      w.(i) <- Int32.add w.(i - 16) (Int32.add s0 (Int32.add w.(i - 7) s1))
    done;
    let a = ref h.(0) and b = ref h.(1) and c = ref h.(2) and d = ref h.(3) in
    let e = ref h.(4) and f = ref h.(5) and g = ref h.(6) and hh = ref h.(7) in
    for i = 0 to 63 do
      let s1 =
        Int32.logxor (ror32 !e 6) (Int32.logxor (ror32 !e 11) (ror32 !e 25))
      in
      let ch =
        Int32.logxor (Int32.logand !e !f) (Int32.logand (Int32.lognot !e) !g)
      in
      let t1 =
        Int32.add !hh (Int32.add s1 (Int32.add ch (Int32.add k.(i) w.(i))))
      in
      let s0 =
        Int32.logxor (ror32 !a 2) (Int32.logxor (ror32 !a 13) (ror32 !a 22))
      in
      let maj =
        Int32.logxor (Int32.logand !a !b)
          (Int32.logxor (Int32.logand !a !c) (Int32.logand !b !c))
      in
      let t2 = Int32.add s0 maj in
      hh := !g;
      g := !f;
      f := !e;
      e := Int32.add !d t1;
      d := !c;
      c := !b;
      b := !a;
      a := Int32.add t1 t2
    done;
    h.(0) <- Int32.add h.(0) !a;
    h.(1) <- Int32.add h.(1) !b;
    h.(2) <- Int32.add h.(2) !c;
    h.(3) <- Int32.add h.(3) !d;
    h.(4) <- Int32.add h.(4) !e;
    h.(5) <- Int32.add h.(5) !f;
    h.(6) <- Int32.add h.(6) !g;
    h.(7) <- Int32.add h.(7) !hh

  let of_state h =
    let b = Buffer.create 32 in
    Array.iter
      (fun v ->
         for sft = 3 downto 0 do
           Buffer.add_char b
             (Char.chr
                (Int32.to_int
                   (Int32.logand (Int32.shift_right_logical v (8 * sft)) 0xffl)))
         done)
      h;
    Buffer.contents b

  let hex_of s =
    let b = Buffer.create (2 * String.length s) in
    String.iter (fun c -> Buffer.add_string b (fmt "%02x" (Char.code c))) s;
    Buffer.contents b

  let digest_string data =
    let h = Array.copy init in
    let total = String.length data in
    let whole = total / 64 in
    for blk = 0 to whole - 1 do
      compress h data (blk * 64)
    done;
    let rem = total mod 64 in
    let pad = Bytes.make 128 '\x00' in
    Bytes.blit_string data (whole * 64) pad 0 rem;
    Bytes.set pad rem '\x80';
    let padlen = if rem <= 55 then 64 else 128 in
    let bitlen = Int64.mul (Int64.of_int total) 8L in
    for i = 0 to 7 do
      Bytes.set pad (padlen - 8 + i)
        (Char.chr
           (Int64.to_int
              (Int64.logand (Int64.shift_right_logical bitlen (8 * (7 - i))) 0xffL)))
    done;
    compress h (Bytes.unsafe_to_string pad) 0;
    if padlen = 128 then compress h (Bytes.unsafe_to_string pad) 64;
    of_state h

  let string data = hex_of (digest_string data)

  let digest_file path =
    let h = Array.copy init in
    let ic = open_in_bin path in
    let buf = Bytes.create (64 * 1024) in
    let total = ref 0 in
    let carry = Bytes.create 64 and carry_len = ref 0 in
    let rec go () =
      match input ic buf 0 (Bytes.length buf) with
      | 0 -> ()
      | n ->
        total := !total + n;
        let off = ref 0 in
        while !off < n do
          let take = min (64 - !carry_len) (n - !off) in
          Bytes.blit buf !off carry !carry_len take;
          carry_len := !carry_len + take;
          off := !off + take;
          if !carry_len = 64 then begin
            compress h (Bytes.unsafe_to_string carry) 0;
            carry_len := 0
          end
        done;
        go ()
    in
    go ();
    close_in ic;
    let rem = !carry_len in
    let pad = Bytes.make 128 '\x00' in
    Bytes.blit carry 0 pad 0 rem;
    Bytes.set pad rem '\x80';
    let padlen = if rem <= 55 then 64 else 128 in
    let bitlen = Int64.mul (Int64.of_int !total) 8L in
    for i = 0 to 7 do
      Bytes.set pad (padlen - 8 + i)
        (Char.chr
           (Int64.to_int
              (Int64.logand (Int64.shift_right_logical bitlen (8 * (7 - i))) 0xffL)))
    done;
    let padstr = Bytes.unsafe_to_string pad in
    compress h padstr 0;
    if padlen = 128 then compress h padstr 64;
    of_state h

  let file path = hex_of (digest_file path)
end

(** {1 CRC-32 and Adler-32} *)

module Crc32 = struct
  let table =
    Array.init 256 (fun i ->
        let c = ref (Int32.of_int i) in
        for _ = 0 to 7 do
          c :=
            if Int32.logand !c 1l <> 0l then
              Int32.logxor 0xedb88320l (Int32.shift_right_logical !c 1)
            else Int32.shift_right_logical !c 1
        done;
        !c)

  let string s =
    let c = ref 0xffffffffl in
    String.iter
      (fun ch ->
         let idx =
           Int32.to_int
             (Int32.logand
                (Int32.logxor !c (Int32.of_int (Char.code ch))) 0xffl)
         in
         c := Int32.logxor table.(idx) (Int32.shift_right_logical !c 8))
      s;
    Int32.logxor !c 0xffffffffl
end

module Adler32 = struct
  let string s =
    let a = ref 1 and b = ref 0 in
    String.iter
      (fun c ->
         a := (!a + Char.code c) mod 65521;
         b := (!b + !a) mod 65521)
      s;
    Int32.logor (Int32.shift_left (Int32.of_int !b) 16) (Int32.of_int !a)
end

(** {1 LEB128 varints (delta format)} *)

module Varint = struct
  let append_uvarint buf v =
    if v < 0 then invalid_arg "uvarint of negative";
    let rec go v =
      if v < 0x80 then Buffer.add_char buf (Char.chr v)
      else begin
        Buffer.add_char buf (Char.chr ((v land 0x7f) lor 0x80));
        go (v lsr 7)
      end
    in
    go v

  (* Signed varint: the low bit carries the sign. *)
  let append_varint buf v =
    let ux = if v < 0 then (lnot v lsl 1) lor 1 else v lsl 1 in
    append_uvarint buf ux

  (** [uvarint data off] decodes to [(value, next_off)] or [None] on a
      truncated or overlong encoding. *)
  let uvarint data off =
    let rec go i acc shift =
      if i >= String.length data || shift > 63 then None
      else
        let b = Char.code data.[i] in
        let acc = acc lor ((b land 0x7f) lsl shift) in
        if b land 0x80 = 0 then Some (acc, i + 1)
        else go (i + 1) acc (shift + 7)
    in
    go off 0 0

  let varint data off =
    match uvarint data off with
    | None -> None
    | Some (ux, next) ->
      let v = if ux land 1 = 0 then ux lsr 1 else lnot (ux lsr 1) in
      Some (v, next)
end

(** {1 DEFLATE (RFC 1951)}

    A fixed-Huffman compressor with greedy LZ77 matching, and a full
    inflater (stored, fixed and dynamic blocks) so streams produced by
    any compressor round-trip. *)

module Deflate = struct
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
    let a = Adler32.string data in
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
end

(** {1 Binary diff (bsdiff)} *)

module Bsdiff = struct
  (* Patches follow bsdiff: the new file is a sequence of blocks, each
     adding bytes of the old file to difference bytes (mostly zeros where
     only addresses moved) followed by extra bytes. The patch is

       number of blocks (uvarint), lengths of the control and difference
       streams (uvarints), then three DEFLATE streams:
       control (per block: diff len uvarint, extra len uvarint, seek varint),
       difference bytes, extra bytes. *)

  exception Bad_patch

  (* Doubling suffix array, O(n log^2 n): enough for app binaries. *)
  let suffix_array s =
    let n = String.length s in
    let sa = Array.init n (fun i -> i) in
    let rank = Array.init n (fun i -> Char.code s.[i]) in
    let tmp = Array.make n 0 in
    let k = ref 1 in
    while !k < n do
      let kk = !k in
      let cmp a b =
        let c = compare rank.(a) rank.(b) in
        if c <> 0 then c
        else
          let ra = if a + kk < n then rank.(a + kk) else -1 in
          let rb = if b + kk < n then rank.(b + kk) else -1 in
          compare ra rb
      in
      Array.sort cmp sa;
      tmp.(sa.(0)) <- 0;
      for i = 1 to n - 1 do
        tmp.(sa.(i)) <-
          tmp.(sa.(i - 1)) + (if cmp sa.(i - 1) sa.(i) <> 0 then 1 else 0)
      done;
      Array.blit tmp 0 rank 0 n;
      k := !k * 2
    done;
    sa

  let match_len old_data old_off new_data new_off =
    let n =
      min (String.length old_data - old_off)
        (String.length new_data - new_off)
    in
    let i = ref 0 in
    while !i < n && old_data.[old_off + !i] = new_data.[new_off + !i] do
      incr i
    done;
    !i

  (* Longest prefix of [new_data[new_off..]] found in [old_data], and
     where, by binary search of the suffix array. *)
  let search sa old_data new_data new_off =
    let n = String.length old_data in
    let compare_suffix_at si =
      let o = sa.(si) in
      let lo = String.length old_data - o in
      let lb = String.length new_data - new_off in
      let m = min lo lb in
      let rec go i =
        if i >= m then compare lo lb
        else
          let c =
            Char.compare old_data.[o + i] new_data.[new_off + i]
          in
          if c <> 0 then c else go (i + 1)
      in
      go 0
    in
    if n = 0 then (0, 0)
    else begin
      let lo = ref 0 and hi = ref (n - 1) in
      while !hi - !lo >= 2 do
        let mid = (!lo + !hi) / 2 in
        if compare_suffix_at mid < 0 then lo := mid else hi := mid
      done;
      let x = match_len old_data sa.(!lo) new_data new_off in
      let y = match_len old_data sa.(!hi) new_data new_off in
      if x > y then (x, sa.(!lo)) else (y, sa.(!hi))
    end

  (** [diff old new] returns the patch turning [old] into [new]. *)
  let diff old_data new_data =
    let old_len = String.length old_data and new_len = String.length new_data in
    let sa = suffix_array old_data in
    let blocks = ref [] in
    (* reversed: (diff_len, extra_len, seek) *)
    let diff_buf = Buffer.create 256 and extra_buf = Buffer.create 256 in
    let scan = ref 0 and pos = ref 0 and length = ref 0 in
    let last_scan = ref 0 and last_pos = ref 0 and last_offset = ref 0 in
    while !scan < new_len do
      let old_score = ref 0 in
      scan := !scan + !length;
      let scsc = ref !scan in
      let go_on = ref true in
      while !go_on && !scan < new_len do
        let l, p = search sa old_data new_data !scan in
        length := l;
        pos := p;
        while !scsc < !scan + !length do
          if !scsc + !last_offset < old_len
             && old_data.[!scsc + !last_offset] = new_data.[!scsc]
          then incr old_score;
          incr scsc
        done;
        if (!length = !old_score && !length <> 0) || !length > !old_score + 8
        then go_on := false
        else begin
          if !scan + !last_offset < old_len
             && old_data.[!scan + !last_offset] = new_data.[!scan]
          then decr old_score;
          incr scan
        end
      done;
      (* Skip emitting unless a block was found at the end. *)
      if not (!length = !old_score && !scan <> new_len) then begin
        (* Extend the previous match forward and this one backward while
           at least half of the bytes match. *)
        let lenf = ref 0 in
        let i = ref 0 and s = ref 0 and best = ref 0 in
        while
          !last_scan + !i < !scan && !last_pos + !i < old_len
        do
          if old_data.[!last_pos + !i] = new_data.[!last_scan + !i] then incr s;
          incr i;
          if !s * 2 - !i > !best * 2 - !lenf then begin
            best := !s;
            lenf := !i
          end
        done;
        let lenb = ref 0 in
        if !scan < new_len then begin
          let i = ref 1 and s = ref 0 and best = ref 0 in
          while !scan >= !last_scan + !i && !pos >= !i do
            if old_data.[!pos - !i] = new_data.[!scan - !i] then incr s;
            if !s * 2 - !i > !best * 2 - !lenb then begin
              best := !s;
              lenb := !i
            end;
            incr i
          done
        end;
        let overlap = !last_scan + !lenf - (!scan - !lenb) in
        if overlap > 0 then begin
          let s = ref 0 and best = ref 0 and lens = ref 0 in
          for i = 0 to overlap - 1 do
            if
              new_data.[!last_scan + !lenf - overlap + i]
              = old_data.[!last_pos + !lenf - overlap + i]
            then incr s;
            if
              new_data.[!scan - !lenb + i] = old_data.[!pos - !lenb + i]
            then decr s;
            if !s > !best then begin
              best := !s;
              lens := i + 1
            end
          done;
          lenf := !lenf + !lens - overlap;
          lenb := !lenb - !lens
        end;
        for i = 0 to !lenf - 1 do
          Buffer.add_char diff_buf
            (Char.chr
               ((Char.code new_data.[!last_scan + i]
                 - Char.code old_data.[!last_pos + i])
                land 0xff))
        done;
        Buffer.add_string extra_buf
          (String.sub new_data (!last_scan + !lenf)
             (!scan - !lenb - (!last_scan + !lenf)));
        let bdiff = !lenf
        and bextra = !scan - !lenb - (!last_scan + !lenf)
        and bseek = !pos - !lenb - (!last_pos + !lenf) in
        (match !blocks with
         | (d, e, sk) :: rest when bdiff = 0 && bextra = 0 ->
           (* A pure move: the previous block already made these bytes. *)
           blocks := (d, e, sk + bseek) :: rest
         | _ -> blocks := (bdiff, bextra, bseek) :: !blocks);
        last_scan := !scan - !lenb;
        last_pos := !pos - !lenb;
        last_offset := !pos - !scan
      end
    done;
    let ctrl = Buffer.create 64 in
    List.iter
      (fun (d, e, sk) ->
         Varint.append_uvarint ctrl d;
         Varint.append_uvarint ctrl e;
         Varint.append_varint ctrl sk)
      (List.rev !blocks);
    let cdef = Deflate.deflate (Buffer.contents ctrl)
    and ddef = Deflate.deflate (Buffer.contents diff_buf)
    and edef = Deflate.deflate (Buffer.contents extra_buf) in
    let out = Buffer.create 64 in
    Varint.append_uvarint out (List.length !blocks);
    Varint.append_uvarint out (String.length cdef);
    Varint.append_uvarint out (String.length ddef);
    Buffer.add_string out cdef;
    Buffer.add_string out ddef;
    Buffer.add_string out edef;
    Buffer.contents out

  (** [patch ~old_data ~patch_data new_size] returns the [new_size]-byte
      string [patch_data] makes of [old_data]. Bytes read beyond the old
      file count as zeros, as in bspatch; the caller verifies the result.
      Raises [Bad_patch] on damage. *)
  let patch ~old_data ~patch_data new_size =
    let patch_size = String.length patch_data
    and old_size = String.length old_data in
    if new_size < 0 then raise Bad_patch;
    let uv off = match Varint.uvarint patch_data off with
      | Some v -> v | None -> raise Bad_patch
    in
    let nb, o1 = uv 0 in
    let clen, o2 = uv o1 in
    let dlen, start = uv o2 in
    if nb > new_size + 1 || clen > patch_size - start
       || dlen > patch_size - start - clen
    then raise Bad_patch;
    let extra_start = start + clen + dlen in
    if extra_start > patch_size then raise Bad_patch;
    let ctrl =
      try Deflate.inflate ~off:start ~len:clen patch_data
      with Deflate.Bad_stream _ -> raise Bad_patch
    and diffb =
      try Deflate.inflate ~off:(start + clen) ~len:dlen patch_data
      with Deflate.Bad_stream _ -> raise Bad_patch
    and extra =
      try
        Deflate.inflate ~off:extra_start ~len:(patch_size - extra_start)
          patch_data
      with Deflate.Bad_stream _ -> raise Bad_patch
    in
    let out = Buffer.create new_size in
    let cpos = ref 0 and dpos = ref 0 and epos = ref 0 in
    let old_pos = ref 0 and left = ref new_size in
    let read_uv () =
      match Varint.uvarint ctrl !cpos with
      | Some (v, n) ->
        cpos := n;
        v
      | None -> raise Bad_patch
    and read_v () =
      match Varint.varint ctrl !cpos with
      | Some (v, n) ->
        cpos := n;
        v
      | None -> raise Bad_patch
    in
    for _ = 1 to nb do
      let d = read_uv () and e = read_uv () and sk = read_v () in
      if d > !left || e > !left - d then raise Bad_patch;
      left := !left - (d + e);
      if !dpos + d > String.length diffb || !epos + e > String.length extra
      then raise Bad_patch;
      for i = 0 to d - 1 do
        let ob =
          let p = !old_pos + i in
          if p >= 0 && p < old_size then Char.code old_data.[p] else 0
        in
        Buffer.add_char out
          (Char.chr ((Char.code diffb.[!dpos + i] + ob) land 0xff))
      done;
      dpos := !dpos + d;
      old_pos := !old_pos + d;
      Buffer.add_string out (String.sub extra !epos e);
      epos := !epos + e;
      old_pos := !old_pos + sk;
      if !old_pos < -(1 lsl 40) || !old_pos > 1 lsl 40 then raise Bad_patch
    done;
    if !left <> 0 then raise Bad_patch;
    Buffer.contents out
end

(** {1 Property lists} *)

type pvalue =
  | P_string of string
  | P_bool of bool
  | P_int of int
  | P_real of float
  | P_data of string
  | P_array of pvalue list
  | P_dict of (string * pvalue) list

module Plist = struct
  type value = pvalue

  let xml_escape s =
    let b = Buffer.create (String.length s + 8) in
    String.iter
      (fun c ->
         match c with
         | '&' -> Buffer.add_string b "&amp;"
         | '<' -> Buffer.add_string b "&lt;"
         | '>' -> Buffer.add_string b "&gt;"
         | '"' -> Buffer.add_string b "&quot;"
         | '\'' -> Buffer.add_string b "&apos;"
         | c -> Buffer.add_char b c)
      s;
    Buffer.contents b

  let base64 s =
    let enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
    let b = Buffer.create (4 * ((String.length s + 2) / 3)) in
    let n = String.length s in
    let i = ref 0 in
    while !i < n do
      let get j = if j < n then Char.code s.[j] else 0 in
      let v = (get !i lsl 16) lor (get (!i + 1) lsl 8) lor get (!i + 2) in
      let pad = if !i + 2 >= n then if !i + 1 >= n then 2 else 1 else 0 in
      Buffer.add_char b enc.[(v lsr 18) land 63];
      Buffer.add_char b enc.[(v lsr 12) land 63];
      Buffer.add_char b (if pad >= 2 then '=' else enc.[(v lsr 6) land 63]);
      Buffer.add_char b (if pad >= 1 then '=' else enc.[v land 63]);
      i := !i + 3
    done;
    Buffer.contents b

  let rec value_xml indent buf v =
    match v with
    | P_string s ->
      Buffer.add_string buf (fmt "%s<string>%s</string>\n" indent (xml_escape s))
    | P_bool true -> Buffer.add_string buf (indent ^ "<true/>\n")
    | P_bool false -> Buffer.add_string buf (indent ^ "<false/>\n")
    | P_int n -> Buffer.add_string buf (fmt "%s<integer>%d</integer>\n" indent n)
    | P_real f -> Buffer.add_string buf (fmt "%s<real>%g</real>\n" indent f)
    | P_data d ->
      Buffer.add_string buf (fmt "%s<data>%s</data>\n" indent (base64 d))
    | P_array items ->
      Buffer.add_string buf (indent ^ "<array>\n");
      List.iter (value_xml (indent ^ "\t") buf) items;
      Buffer.add_string buf (indent ^ "</array>\n")
    | P_dict pairs ->
      let pairs =
        List.sort (fun (a, _) (b, _) -> String.compare a b) pairs
      in
      Buffer.add_string buf (indent ^ "<dict>\n");
      List.iter
        (fun (k, v) ->
           Buffer.add_string buf (fmt "%s\t<key>%s</key>\n" indent (xml_escape k));
           value_xml (indent ^ "\t") buf v)
        pairs;
      Buffer.add_string buf (indent ^ "</dict>\n")

  (** [xml pairs] is an XML property list document of a top-level
      dictionary. *)
  let xml pairs =
    let b = Buffer.create 512 in
    Buffer.add_string b
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
       <!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \
       \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n\
       <plist version=\"1.0\">\n";
    value_xml "" b (P_dict pairs);
    Buffer.add_string b "</plist>\n";
    Buffer.contents b

  let is_ascii s =
    let ok = ref true in
    String.iter (fun c -> if Char.code c >= 0x80 then ok := false) s;
    !ok

  (* UTF-8 → UTF-16BE units (for .DS_Store names and binary plists). *)
  let utf16_units s =
    let n = String.length s in
    let i = ref 0 in
    let units = ref [] in
    let next () =
      let c = Char.code s.[!i] in
      if c < 0x80 then begin
        incr i;
        c
      end
      else if c land 0xe0 = 0xc0 && !i + 1 < n then begin
        let v = ((c land 0x1f) lsl 6) lor (Char.code s.[!i + 1] land 0x3f) in
        i := !i + 2;
        v
      end
      else if c land 0xf0 = 0xe0 && !i + 2 < n then begin
        let v =
          ((c land 0x0f) lsl 12)
          lor ((Char.code s.[!i + 1] land 0x3f) lsl 6)
          lor (Char.code s.[!i + 2] land 0x3f)
        in
        i := !i + 3;
        v
      end
      else if c land 0xf8 = 0xf0 && !i + 3 < n then begin
        let v =
          ((c land 0x07) lsl 18)
          lor ((Char.code s.[!i + 1] land 0x3f) lsl 12)
          lor ((Char.code s.[!i + 2] land 0x3f) lsl 6)
          lor (Char.code s.[!i + 3] land 0x3f)
        in
        i := !i + 4;
        v
      end
      else begin
        incr i;
        Char.code '?'
      end
    in
    while !i < n do
      let cp = next () in
      if cp < 0x10000 then units := cp :: !units
      else begin
        let v = cp - 0x10000 in
        units := (0xdc00 lor (v land 0x3ff)) :: (0xd800 lor (v lsr 10)) :: !units
      end
    done;
    List.rev !units

  (** [binary pairs] is a binary property list of a flat dictionary of
      scalars (strings, bools, ints, floats) — the shape .DS_Store
      view-option records take. *)
  let binary pairs =
    let pairs = List.sort (fun (a, _) (b, _) -> String.compare a b) pairs in
    let objs = ref [ `Dict ] in
    let refs = Hashtbl.create 16 in
    let ref_of v =
      match Hashtbl.find_opt refs v with
      | Some i -> i
      | None ->
        let i = List.length !objs in
        objs := !objs @ [ `Val v ];
        Hashtbl.add refs v i;
        i
    in
    let key_refs = List.map (fun (k, _) -> ref_of (P_string k)) pairs in
    let val_refs = List.map (fun (_, v) -> ref_of v) pairs in
    let nobjs = List.length !objs in
    let size_of n =
      if n < 0x100 then 1 else if n < 0x10000 then 2 else if n < 0x100000000 then 4 else 8
    in
    let ref_size = size_of nobjs in
    let buf = Buffer.create 512 in
    Buffer.add_string buf "bplist00";
    let put_uint size v =
      for i = size - 1 downto 0 do
        Buffer.add_char buf (Char.chr ((v lsr (8 * i)) land 0xff))
      done
    in
    let add_int v =
      if v < 0 then begin
        Buffer.add_char buf '\x13';
        put_uint 8 v
      end
      else if v < 0x100 then begin
        Buffer.add_char buf '\x10';
        Buffer.add_char buf (Char.chr v)
      end
      else if v < 0x10000 then begin
        Buffer.add_char buf '\x11';
        put_uint 2 v
      end
      else if v < 0x100000000 then begin
        Buffer.add_char buf '\x12';
        put_uint 4 v
      end
      else begin
        Buffer.add_char buf '\x13';
        put_uint 8 v
      end
    in
    let add_size marker n =
      if n < 15 then Buffer.add_char buf (Char.chr (marker lor n))
      else begin
        Buffer.add_char buf (Char.chr (marker lor 0x0f));
        add_int n
      end
    in
    let offsets = Array.make nobjs 0 in
    List.iteri
      (fun i o ->
         offsets.(i) <- Buffer.length buf;
         match o with
         | `Dict ->
           add_size 0xd0 (List.length pairs);
           List.iter (put_uint ref_size) key_refs;
           List.iter (put_uint ref_size) val_refs
         | `Val (P_string s) ->
           if is_ascii s then begin
             add_size 0x50 (String.length s);
             Buffer.add_string buf s
           end
           else begin
             let units = utf16_units s in
             add_size 0x60 (List.length units);
             List.iter (put_uint 2) units
           end
         | `Val (P_bool v) -> Buffer.add_char buf (if v then '\x09' else '\x08')
         | `Val (P_int v) -> add_int v
         | `Val (P_real f) ->
           Buffer.add_char buf '\x23';
           let bits = Int64.bits_of_float f in
           for sft = 7 downto 0 do
             Buffer.add_char buf
               (Char.chr
                  (Int64.to_int
                     (Int64.logand (Int64.shift_right_logical bits (8 * sft)) 0xffL)))
           done
         | `Val _ -> invalid_arg "binary plist: unsupported value")
      !objs;
    let table_off = Buffer.length buf in
    let off_size = size_of table_off in
    Array.iter (fun off -> put_uint off_size off) offsets;
    Buffer.add_string buf (String.make 6 '\x00');
    Buffer.add_char buf (Char.chr off_size);
    Buffer.add_char buf (Char.chr ref_size);
    put_uint 8 nobjs;
    put_uint 8 0;
    (* top object *)
    put_uint 8 table_off;
    Buffer.contents buf
end

(** {1 .DS_Store (disk image window layout)} *)

module Ds_store = struct
  type record = {
    name : string;
    code : string;   (* four characters *)
    kind : string;   (* "long", "blob" or "type" *)
    value : string;
  }

  let ds_long name code v =
    let b = Buffer.create 4 in
    for sft = 3 downto 0 do
      Buffer.add_char b (Char.chr ((v lsr (8 * sft)) land 0xff))
    done;
    { name; code; kind = "long"; value = Buffer.contents b }

  let ds_blob name code b = { name; code; kind = "blob"; value = b }

  let ds_icon_location name x y =
    let b = Buffer.create 16 in
    List.iter
      (fun v ->
         for sft = 3 downto 0 do
           Buffer.add_char b (Char.chr ((v lsr (8 * sft)) land 0xff))
         done)
      [ x; y ];
    Buffer.add_string b "\xff\xff\xff\xff\xff\xff\x00\x00";
    ds_blob name "Iloc" (Buffer.contents b)

  let put_u32 buf v =
    for sft = 3 downto 0 do
      Buffer.add_char buf (Char.chr ((v lsr (8 * sft)) land 0xff))
    done

  let encode_record buf r =
    let units = Plist.utf16_units r.name in
    put_u32 buf (List.length units);
    List.iter (fun u -> Buffer.add_char buf (Char.chr (u lsr 8)); Buffer.add_char buf (Char.chr (u land 0xff))) units;
    Buffer.add_string buf r.code;
    Buffer.add_string buf r.kind;
    if r.kind = "blob" then put_u32 buf (String.length r.value);
    Buffer.add_string buf r.value

  (** [store records] is a .DS_Store file: a buddy-allocated address
      space with a single B-tree leaf at 0x2000. Records must fit in one
      page, plenty for a disk image window. *)
  let store records =
    let records =
      List.sort
        (fun a b ->
           match
             String.compare
               (String.lowercase_ascii a.name)
               (String.lowercase_ascii b.name)
           with
           | 0 -> String.compare a.code b.code
           | c -> c)
        records
    in
    let node = Buffer.create 512 in
    put_u32 node 0;
    (* a leaf *)
    put_u32 node (List.length records);
    List.iter (encode_record node) records;
    let page_size = 0x1000 in
    if Buffer.length node > page_size then
      invalid_arg ".DS_Store records exceed one page";
    let dsdb_addr = 0x20 and root_addr = 0x800 and node_addr = 0x2000 in
    let file = Bytes.make (4 + 0x4000) '\x00' in
    Bytes.set file 3 '\x01';
    let set32 addr v =
      Bytes.set file (4 + addr + 0) (Char.chr ((v lsr 24) land 0xff));
      Bytes.set file (4 + addr + 1) (Char.chr ((v lsr 16) land 0xff));
      Bytes.set file (4 + addr + 2) (Char.chr ((v lsr 8) land 0xff));
      Bytes.set file (4 + addr + 3) (Char.chr (v land 0xff))
    in
    let seti32 addr v =
      let off = 4 + addr in
      Bytes.set file (off + 0) (Char.chr ((v lsr 24) land 0xff));
      Bytes.set file (off + 1) (Char.chr ((v lsr 16) land 0xff));
      Bytes.set file (off + 2) (Char.chr ((v lsr 8) land 0xff));
      Bytes.set file (off + 3) (Char.chr (v land 0xff))
    in
    Bytes.blit_string "Bud1" 0 file 4 4;
    set32 4 root_addr;
    set32 8 0x800;
    set32 12 root_addr;
    Bytes.blit_string
      "\x00\x00\x10\x0c\x00\x00\x00\x87\x00\x00\x20\x0b\x00\x00\x00\x00" 0
      file (4 + 16) 16;
    set32 dsdb_addr 2;
    set32 (dsdb_addr + 4) 0;
    set32 (dsdb_addr + 8) (List.length records);
    set32 (dsdb_addr + 12) 1;
    set32 (dsdb_addr + 16) page_size;
    seti32 root_addr 3;
    List.iteri
      (fun i addr -> seti32 (root_addr + 8 + (4 * i)) addr)
      [ root_addr lor 11; dsdb_addr lor 5; node_addr lor 13 ];
    let p = root_addr + 8 + (256 * 4) in
    seti32 p 1;
    Bytes.set file (4 + p + 4) '\x04';
    Bytes.blit_string "DSDB" 0 file (4 + p + 5) 4;
    seti32 (p + 9) 1;
    let p = p + 13 in
    (* Free lists by block size: carving the blocks above out of the
       initial 2 GiB leaves one free block of each other size at an
       offset equal to its size. *)
    let p = ref p in
    for width = 0 to 31 do
      if width < 6 || width = 11 || width = 13 || width = 31 then p := !p + 4
      else begin
        seti32 !p 1;
        seti32 (!p + 4) (1 lsl width);
        p := !p + 8
      end
    done;
    Bytes.blit_string (Buffer.contents node) 0 file (4 + node_addr)
      (Buffer.length node);
    Bytes.unsafe_to_string file

  (* Finder window of a disk image: the app on the left, a link to
     /Applications on the right. *)
  let dmg_window_x = 200
  and dmg_window_y = 400
  and dmg_window_width = 660
  and dmg_window_height = 400
  and dmg_icon_size = 128
  and dmg_app_x = 180
  and dmg_app_y = 190
  and dmg_apps_x = 480
  and dmg_apps_y = 185

  let dmg_store app =
    let bwsp =
      Plist.binary
        [
          ("ShowStatusBar", P_bool false);
          ("WindowBounds",
           P_string
             (fmt "{{%d, %d}, {%d, %d}}" dmg_window_x dmg_window_y
                dmg_window_width dmg_window_height));
          ("ContainerShowSidebar", P_bool false);
          ("PreviewPaneVisibility", P_bool false);
          ("SidebarWidth", P_int 180);
          ("ShowTabView", P_bool false);
          ("ShowToolbar", P_bool false);
          ("ShowPathbar", P_bool false);
          ("ShowSidebar", P_bool false);
        ]
    in
    let icvp =
      Plist.binary
        [
          ("viewOptionsVersion", P_int 1);
          ("backgroundType", P_int 0);
          ("backgroundColorRed", P_real 1.0);
          ("backgroundColorGreen", P_real 1.0);
          ("backgroundColorBlue", P_real 1.0);
          ("gridOffsetX", P_real 0.0);
          ("gridOffsetY", P_real 0.0);
          ("gridSpacing", P_real 100.0);
          ("arrangeBy", P_string "none");
          ("showIconPreview", P_bool false);
          ("showItemInfo", P_bool false);
          ("labelOnBottom", P_bool true);
          ("textSize", P_real 16.0);
          ("iconSize", P_real (float dmg_icon_size));
          ("scrollPositionX", P_real 0.0);
          ("scrollPositionY", P_real 0.0);
        ]
    in
    store
      [
        ds_long "." "vSrn" 1;
        ds_blob "." "bwsp" bwsp;
        ds_blob "." "icvp" icvp;
        { name = "."; code = "icvl"; kind = "type"; value = "icnv" };
        ds_icon_location app dmg_app_x dmg_app_y;
        ds_icon_location "Applications" dmg_apps_x dmg_apps_y;
      ]
end

(** {1 Mach-O detection (nested code)} *)

module Mach_o = struct
  (* Magic numbers: thin 32/64-bit (little- and big-endian views) and
     universal (fat) binaries. *)
  let magic u32 =
    match u32 with
    | 0xfeedfacel | 0xfeedfacfl | 0xcefaedfel | 0xcffaedfel -> `Thin
    | 0xcafebabel | 0xcafebabfl -> `Fat
    | _ -> `No

  (* Whether the Mach-O at [off] in [ic] has an LC_CODE_SIGNATURE
     load command (0x1d). *)
  let thin_signed ic off =
    try
      seek_in ic off;
      let head = really_input_string ic 28 in
      let m0 =
        Char.code head.[0] lor (Char.code head.[1] lsl 8)
        lor (Char.code head.[2] lsl 16) lor (Char.code head.[3] lsl 24)
      in
      let big =
        match Int32.of_int m0 with
        | 0xcefaedfel | 0xcffaedfel -> true
        | _ -> false
      in
      let u32 i =
        let b0 = Char.code head.[i] and b1 = Char.code head.[i + 1]
        and b2 = Char.code head.[i + 2] and b3 = Char.code head.[i + 3] in
        if big then (b0 lsl 24) lor (b1 lsl 16) lor (b2 lsl 8) lor b3
        else b0 lor (b1 lsl 8) lor (b2 lsl 16) lor (b3 lsl 24)
      in
      let size =
        match Int32.of_int (u32 0) with
        | 0xfeedfacel -> Some 28
        | 0xfeedfacfl -> Some 32
        | _ -> None
      in
      (match size with
       | None -> false
       | Some hsize ->
         let ncmds = u32 16 and sizeofcmds = u32 20 in
         if sizeofcmds > 1 lsl 24 then false
         else begin
           seek_in ic (off + hsize);
           let cmds = really_input_string ic (min sizeofcmds (1 lsl 24)) in
           let rec scan i =
             if i + 8 > String.length cmds then false
             else
               let c0 = Char.code cmds.[i] and c1 = Char.code cmds.[i + 1]
               and c2 = Char.code cmds.[i + 2] and c3 = Char.code cmds.[i + 3] in
               let cmd =
                 if big then (c0 lsl 24) lor (c1 lsl 16) lor (c2 lsl 8) lor c3
                 else c0 lor (c1 lsl 8) lor (c2 lsl 16) lor (c3 lsl 24)
               and cmdsize =
                 if big then
                   (c2 lsl 24) lor (c3 lsl 16)
                   lor (Char.code cmds.[i + 4] lsl 8) lor Char.code cmds.[i + 5]
                 else
                   Char.code cmds.[i + 4] lor (Char.code cmds.[i + 5] lsl 8)
                   lor (Char.code cmds.[i + 6] lsl 16)
                   lor (Char.code cmds.[i + 7] lsl 24)
               in
               let cmdsize =
                 if big then
                   (Char.code cmds.[i + 4] lsl 24)
                   lor (Char.code cmds.[i + 5] lsl 16)
                   lor (Char.code cmds.[i + 6] lsl 8)
                   lor Char.code cmds.[i + 7]
                 else cmdsize
               in
               if cmd = 0x1d then true
               else if cmdsize < 8 then false
               else scan (i + cmdsize)
           in
           ncmds >= 0 && scan 0
         end)
    with End_of_file -> false

  (** [(is_macho, signed) of path]: every thin header in the file must
      carry a code signature for [signed]. *)
  let inspect path =
    try
      let ic = open_in_bin path in
      let head = really_input_string ic 8 in
      let u32be i =
        (Char.code head.[i] lsl 24) lor (Char.code head.[i + 1] lsl 16)
        lor (Char.code head.[i + 2] lsl 8) lor Char.code head.[i + 3]
      in
      let result =
        match magic (Int32.of_int (u32be 0)) with
        | `Thin -> (true, thin_signed ic 0)
        | `No -> (false, false)
        | `Fat ->
          let n = u32be 4 in
          let fat64 =
            Int32.of_int (u32be 0) = 0xcafebabfl
          in
          if n >= 20 then (false, false) (* java class shares the magic *)
          else begin
            let size = if fat64 then 32 else 20 in
            let signed = ref (n > 0) in
            for i = 0 to n - 1 do
              seek_in ic (8 + (i * size));
              let arch = really_input_string ic size in
              let u32o o =
                (Char.code arch.[o] lsl 24) lor (Char.code arch.[o + 1] lsl 16)
                lor (Char.code arch.[o + 2] lsl 8) lor Char.code arch.[o + 3]
              in
              let off =
                if fat64 then
                  (* fat_arch_64.offset is u64 at byte 8 *)
                  (u32o 8 lsl 32) lor u32o 12
                else u32o 8
              in
              signed := !signed && thin_signed ic off
            done;
            (true, !signed)
          end
      in
      close_in ic;
      result
    with Sys_error _ | End_of_file -> (false, false)

  let is_macho path = fst (inspect path)
  let is_signed path = snd (inspect path)
end

(** {1 Application specification} *)

type signing_identity =
  | Adhoc  (** ad-hoc signature ("-"); runs anywhere, no notarization *)
  | Certificate of string  (** keychain identity, e.g.
                               "Developer ID Application: X" *)

(** Notarization credentials. Raw secrets are never API parameters:
    [Apple_id_env] names the environment variables read at submit time,
    [Keychain_profile] is a profile stored with
    [xcrun notarytool store-credentials]. *)
type notarization =
  | Keychain_profile of { profile : string; keychain : string option }
  | Apple_id_env of {
      apple_id_var : string;   (** e.g. "LUI_PKG_APPLE_ID" *)
      password_var : string;   (** app-specific password env var *)
      team_id : string;
    }

type doc_type = {
  doc_name : string option;  (** default: "<EXT> file" of the first ext *)
  role : string;             (** default "Editor" *)
  extensions : string list;
  mime : string list;
}

type resource = {
  res_name : string;  (** install path relative to Contents/Resources *)
  res_src : string;   (** source file, directory or link *)
}

type app_spec = {
  name : string;
  bundle_id : string;
  version : string;            (** semver for CFBundleShortVersionString *)
  build : string option;       (** CFBundleVersion; default [version] *)
  icon : string option;        (** source PNG (square) *)
  executable : string;         (** the built binary *)
  resources : resource list;
  entitlements : (string * pvalue) list;
  helper_entitlements : (string * (string * pvalue) list) list;
    (** per-path overrides for nested code, keyed by path inside the
        bundle (e.g. "Resources/bin/helper"). *)
  identity : signing_identity;
  notarization : notarization option;
  min_system : string;         (** LSMinimumSystemVersion *)
  url_schemes : string list;
  doc_types : doc_type list;
  copyright : string option;
  info_extra : (string * pvalue) list;
  production : bool;           (** hardened runtime + secure timestamp
                                   when signing with a real identity *)
}

type tool_check_unit = {
  tc_tool : string;
  tc_ran : bool;
  tc_ok : bool;
  tc_output : string;
}

type sign_report = {
  signed : string list;       (** bundle-relative paths signed *)
  codesign_verify : tool_check_unit;
  spctl : tool_check_unit option;
}

type notarize_report = {
  nz_submission_id : string option;
  nz_status : string;
  nz_stapled : bool;
  nz_log : string;
}

(** The per-platform packager record: one real implementation, declared
    stubs elsewhere. [disk_image] is macOS's DMG step; [update_pkg] is
    platform-independent and lives at top level. *)
type packager = {
  pkg_platform : platform;
  pkg_bundle : app_spec -> string -> string outcome;
  pkg_sign : app_spec -> string -> sign_report outcome;
  pkg_notarize : app_spec -> string -> notarize_report outcome;
  pkg_disk_image : app_spec -> string -> string -> string outcome;
}

(** {1 Info.plist} *)

module Info_plist = struct
  let build spec ~exe_name ~icon_name =
    let base =
      [
        ("CFBundleName", P_string spec.name);
        ("CFBundleDisplayName", P_string spec.name);
        ("CFBundleIdentifier", P_string spec.bundle_id);
        ("CFBundleVersion", P_string (Option.value ~default:spec.version spec.build));
        ("CFBundleShortVersionString", P_string spec.version);
        ("CFBundleExecutable", P_string exe_name);
        ("CFBundlePackageType", P_string "APPL");
        ("CFBundleInfoDictionaryVersion", P_string "6.0");
        ("LSMinimumSystemVersion", P_string spec.min_system);
        ("NSPrincipalClass", P_string "NSApplication");
        ("NSHighResolutionCapable", P_bool true);
        ("NSSupportsAutomaticGraphicsSwitching", P_bool true);
      ]
    in
    let base =
      match icon_name with
      | Some i -> base @ [ ("CFBundleIconFile", P_string i) ]
      | None -> base
    in
    let base =
      match spec.copyright with
      | Some c -> base @ [ ("NSHumanReadableCopyright", P_string c) ]
      | None -> base
    in
    let base =
      match spec.doc_types with
      | [] -> base
      | docs ->
        let doc d =
          let name =
            match d.doc_name with
            | Some n -> n
            | None -> (
              match d.extensions with
              | e :: _ -> String.uppercase_ascii e ^ " file"
              | [] -> "file")
          in
          let pairs =
            [
              ("CFBundleTypeName", P_string name);
              ("CFBundleTypeRole", P_string d.role);
              ("LSHandlerRank", P_string "Default");
              ("CFBundleTypeExtensions",
               P_array (List.map (fun e -> P_string e) d.extensions));
            ]
          in
          let pairs =
            match d.mime with
            | [] -> pairs
            | ms ->
              pairs
              @ [ ("CFBundleTypeMIMETypes",
                   P_array (List.map (fun m -> P_string m) ms)) ]
          in
          P_dict pairs
        in
        base @ [ ("CFBundleDocumentTypes", P_array (List.map doc docs)) ]
    in
    let base =
      match spec.url_schemes with
      | [] -> base
      | ss ->
        base
        @ [
            ("CFBundleURLTypes",
             P_array
               [
                 P_dict
                   [
                     ("CFBundleURLName", P_string spec.bundle_id);
                     ("CFBundleURLSchemes",
                      P_array (List.map (fun s -> P_string s) ss));
                   ];
               ]);
          ]
    in
    (* The app's own keys win. *)
    let tbl = Hashtbl.create 32 in
    List.iter (fun (k, v) -> Hashtbl.replace tbl k v) base;
    List.iter (fun (k, v) -> Hashtbl.replace tbl k v) spec.info_extra;
    Hashtbl.fold (fun k v acc -> (k, v) :: acc) tbl []

  let plist spec ~exe_name ~icon_name =
    Plist.xml (build spec ~exe_name ~icon_name)
end

(** {1 Icons} *)

module Iconset = struct
  (** Standard .iconset member names and pixel sizes. *)
  let entries =
    [
      ("icon_16x16.png", 16);
      ("icon_16x16@2x.png", 32);
      ("icon_32x32.png", 32);
      ("icon_32x32@2x.png", 64);
      ("icon_128x128.png", 128);
      ("icon_128x128@2x.png", 256);
      ("icon_256x256.png", 256);
      ("icon_256x256@2x.png", 512);
      ("icon_512x512.png", 512);
      ("icon_512x512@2x.png", 1024);
    ]

  (** [icns ~src ~dst] builds [dst.icns] from [src] PNG via sips +
      iconutil. macOS only. *)
  let icns ~src ~dst =
    match Proc.which "iconutil", Proc.which "sips" with
    | None, _ -> missing "iconutil not found"
    | _, None -> missing "sips not found"
    | Some _, Some _ ->
      let work = Fs.temp_dir ~prefix:"lui_pkg-icon-" () in
      let iconset = Filename.concat work "app.iconset" in
      let rec loop = function
        | [] -> (
          match Proc.check "iconutil" [ "-c"; "icns"; iconset; "-o"; dst ] with
          | Ok _ -> Fs.rm_rf work; Ok dst
          | Error e -> Fs.rm_rf work; Failed e)
        | (name, px) :: rest -> (
          let out = Filename.concat iconset name in
          match
            Proc.check "sips" [ "-z"; string_of_int px; string_of_int px; src; "--out"; out ]
          with
          | Ok _ -> loop rest
          | Error e -> Fs.rm_rf work; Failed e)
      in
      Fs.mkdir_p iconset;
      if Fs.kind_of src <> Fs.File then missing "icon source %s" src
      else loop entries
end

(** {1 Bundle assembly} *)

module Bundle = struct
  let bundle_icon = "AppIcon.icns"

  let validate_spec spec =
    if spec.name = "" || String.contains spec.name '/' then
      invalid "app name %S" spec.name
    else if spec.bundle_id = "" then invalid "empty bundle id"
    else if Fs.kind_of spec.executable <> Fs.File then
      missing "executable %s" spec.executable
    else Ok ()

  (** Assemble [<dir>/<name>.app] around [spec.executable]. *)
  let write spec ~dir =
    match validate_spec spec with
    | (Failed _ | Skipped _ | Unsupported _) as e -> e
    | Ok () ->
      let app = Filename.concat dir (spec.name ^ ".app") in
      Fs.rm_rf app;
      let contents = Filename.concat app "Contents" in
      Fs.mkdir_p (Filename.concat contents "MacOS");
      Fs.mkdir_p (Filename.concat contents "Resources");
      Fs.mkdir_p (Filename.concat contents "Frameworks");
      let exe_name = spec.name in
      let dst_exe = Filename.concat (Filename.concat contents "MacOS") exe_name in
      Fs.copy_file ~src:spec.executable ~dst:dst_exe;
      (try
         Unix.chmod dst_exe ((Unix.stat dst_exe).Unix.st_perm lor 0o111)
       with Unix.Unix_error _ -> ());
      (* Icon *)
      let icon_o =
        match spec.icon with
        | None -> Ok None
        | Some src -> (
          if Fs.kind_of src <> Fs.File then missing "icon %s" src
          else
            let dst = Filename.concat (Filename.concat contents "Resources") bundle_icon in
            outcome_map (fun _ -> Some bundle_icon) (Iconset.icns ~src ~dst))
      in
      (match icon_o with
       | Failed _ | Skipped _ | Unsupported _ as e ->
         (match e with
          | Failed f -> Failed f
          | Skipped s -> missing "%s" s
          | Unsupported s -> missing "%s" s
          | Ok _ -> assert false)
       | Ok icon_name ->
         (* Resources *)
         let rec res_loop = function
           | [] -> Stdlib.Ok ()
           | r :: rest ->
             if String.contains r.res_name '\x00' || String.length r.res_name = 0
             then Error (Invalid (fmt "bad resource name %S" r.res_name))
             else if Fs.kind_of r.res_src = Fs.Absent then
               Error (Missing (fmt "resource %s" r.res_src))
             else begin
               Fs.install ~src:r.res_src
                 ~dst:(Filename.concat (Filename.concat contents "Resources") r.res_name);
               res_loop rest
             end
         in
         (match res_loop spec.resources with
          | Error f -> Failed f
          | Ok () ->
            Fs.write_file (Filename.concat contents "Info.plist")
              (Info_plist.plist spec ~exe_name ~icon_name);
            Fs.write_file (Filename.concat contents "PkgInfo") "APPL????";
            Ok app))
end

(** {1 Code signing} *)

module Sign = struct
  let bundle_extensions = [ ".app"; ".appex"; ".bundle"; ".framework"; ".plugin"; ".xpc" ]

  let is_bundle_dir path =
    let ext = String.lowercase_ascii (Filename.extension path) in
    List.mem ext bundle_extensions
    && Fs.is_dir path
    && List.exists
         (fun p -> Fs.exists (Filename.concat path p))
         [ "Contents/Info.plist"; "Resources/Info.plist"; "Info.plist" ]

  type signable = { s_path : string; s_rel : string; s_bundle : bool; s_signed : bool }

  (* Signable contents of a bundle: Mach-O files and code-holding
     bundles under the code and resource directories, deepest first so a
     bundle signs after its contents. *)
  let code_dirs = [ "MacOS"; "Frameworks"; "PlugIns"; "XPCServices"; "SharedSupport"; "Resources"; "Helpers" ]

  let enumerate app =
    let contents = Filename.concat app "Contents" in
    let files = ref [] and bundles = ref [] in
    List.iter
      (fun d ->
         let dir = Filename.concat contents d in
         if Fs.is_dir dir then
           List.iter
             (fun (rel, kind) ->
                match kind with
                | Fs.File ->
                  let path = Filename.concat dir rel in
                  if Mach_o.is_macho path then
                    files :=
                      { s_path = path;
                        s_rel = d ^ "/" ^ rel;
                        s_bundle = false;
                        s_signed = Mach_o.is_signed path }
                      :: !files
                | Fs.Dir ->
                  let path = Filename.concat dir rel in
                  if is_bundle_dir path then
                    bundles :=
                      { s_path = path;
                        s_rel = d ^ "/" ^ rel;
                        s_bundle = true;
                        s_signed = false }
                      :: !bundles
                | _ -> ())
             (Fs.walk dir))
      code_dirs;
    (* Keep only bundles that hold code; localizations are resources. *)
    let has_code b =
      List.exists
        (fun (f : signable) ->
           String.length f.s_rel > String.length b.s_rel
           && String.sub f.s_rel 0 (String.length b.s_rel + 1) = b.s_rel ^ "/")
        !files
    in
    let all = !files @ List.filter has_code !bundles in
    (* Deepest first: a bundle after its contents. *)
    List.sort
      (fun a b ->
         let depth s =
           String.fold_left (fun n c -> if c = '/' then n + 1 else n) 0 s
         in
         compare (depth b.s_rel) (depth a.s_rel))
      all

  let identity_string = function
    | Adhoc -> "-"
    | Certificate s -> s

  (** codesign arguments for the bundle itself. *)
  let codesign_args ~identity ~entitlements ~production path =
    let args = [ "--force"; "--deep"; "--sign"; identity_string identity ] in
    let args =
      if production && identity <> Adhoc then
        args @ [ "--options"; "runtime"; "--timestamp" ]
      else args
    in
    let args =
      match entitlements with
      | Some f -> args @ [ "--entitlements"; f ]
      | None -> args
    in
    args @ [ path ]

  (** codesign arguments for nested code: no --deep (each file signs
      alone); entitlements of the previous signature are kept unless
      overridden. *)
  let nested_args ~identity ~entitlements ~production =
    let args = [ "--force"; "--sign"; identity_string identity ] in
    let args =
      if production && identity <> Adhoc then
        args @ [ "--options"; "runtime"; "--timestamp" ]
      else args
    in
    match entitlements with
    | Some f -> args @ [ "--entitlements"; f ]
    | None -> args @ [ "--preserve-metadata=entitlements" ]

  let run_check tc_tool args =
    let r = Proc.run tc_tool args in
    { tc_tool; tc_ran = true; tc_ok = r.status = 0;
      tc_output = r.stdout ^ r.stderr }

  let entitlements_file pairs =
    match pairs with
    | [] -> None
    | _ ->
      let d = Fs.temp_dir ~prefix:"lui_pkg-ent-" () in
      let p = Filename.concat d "entitlements.plist" in
      Fs.write_file p (Plist.xml pairs);
      Some p

  (** Sign [app] per [spec]: nested code inside-out (adhoc keeps valid
      existing signatures), then the bundle with --deep, then verify. *)
  let sign spec app =
    if host_platform () <> Macos then
      Unsupported "code signing is implemented for macOS only"
    else if not (Fs.is_dir app) then missing "bundle %s" app
    else begin
      let production = spec.production in
      let signed = ref [] in
      let signed_child s =
        List.exists
          (fun rel ->
             String.length rel > String.length s.s_rel
             && String.sub rel 0 (String.length s.s_rel + 1)
                = s.s_rel ^ "/")
          !signed
      in
      let rec nested = function
        | [] -> Stdlib.Ok ()
        | s :: rest -> (
          let skip =
            match spec.identity, s with
            | Adhoc, { s_bundle = false; s_signed = true; _ } -> true
            | Adhoc, { s_bundle = true; _ } ->
              (* keep a sealed bundle's own signature *)
              (not (signed_child s))
              && (match Proc.run "codesign" [ "--verify"; s.s_path ] with
                  | { status = 0; _ } -> true
                  | _ -> false)
            | _ -> false
          in
          if skip then nested rest
          else begin
            let ent =
              match List.assoc_opt s.s_rel spec.helper_entitlements with
              | Some pairs -> entitlements_file pairs
              | None -> None
            in
            let args = nested_args ~identity:spec.identity ~entitlements:ent ~production in
            match Proc.check "codesign" (args @ [ s.s_path ]) with
            | Ok _ ->
              signed := s.s_rel :: !signed;
              nested rest
            | Error e -> Error e
          end)
      in
      match nested (enumerate app) with
      | Error e -> Failed e
      | Ok () -> (
        let ent = entitlements_file spec.entitlements in
        match
          Proc.check "codesign"
            (codesign_args ~identity:spec.identity ~entitlements:ent
               ~production app)
        with
        | Error e -> Failed e
        | Ok _ ->
          let verify =
            run_check "codesign"
              [ "--verify"; "--deep"; "--strict"; "--verbose=2"; app ]
          in
          let spctl =
            (* Gatekeeper assessment only means something for real
               identities; ad-hoc signatures can never pass it. *)
            match spec.identity, Proc.which "spctl" with
            | Adhoc, _ | _, None -> None
            | Certificate _, Some _ ->
              Some (run_check "spctl" [ "-a"; "-t"; "exec"; "-vv"; app ])
          in
          Ok { signed = !signed; codesign_verify = verify; spctl })
    end
end

(** {1 Notarization} *)

module Notarize = struct
  (** Credentials → notarytool flags, or the reason the submission is
      skipped. A [Keychain_profile] is always available (its secrets live
      in the keychain); [Apple_id_env] resolves the named environment
      variables at submit time. *)
  let creds_args = function
    | None -> Error `No_creds
    | Some (Keychain_profile { profile; keychain }) ->
      Ok ([ "--keychain-profile"; profile ]
          @ (match keychain with Some k -> [ "--keychain"; k ] | None -> []))
    | Some (Apple_id_env { apple_id_var; password_var; team_id }) -> (
      let get v = try Some (Sys.getenv v) with Not_found -> None in
      match get apple_id_var, get password_var with
      | Some id, Some pw ->
        Ok [ "--apple-id"; id; "--password"; pw; "--team-id"; team_id ]
      | _ ->
        Error (`Missing_env (List.filter_map (fun (v, o) -> if o = None then Some v else None)
                              [ (apple_id_var, get apple_id_var);
                                (password_var, get password_var) ])))

  (** Make a zip of a directory/bundle for submission; [path] is
      already a file it is returned unchanged. *)
  let submission_payload path =
    match Fs.kind_of path with
    | Fs.Dir -> (
      let dst = Filename.concat (Fs.temp_dir ~prefix:"lui_pkg-nz-" ()) "submit.zip" in
      match Proc.check "ditto" [ "-c"; "-k"; "--keepParent"; path; dst ] with
      | Ok _ -> Ok dst
      | Error e -> Failed e)
    | Fs.File -> Ok path
    | _ -> missing "nothing to notarize at %s" path

  (* Validate that the payload is a zip archive or a disk image, the
     shapes the notary service accepts. *)
  let payload_valid path =
    match Fs.kind_of path with
    | Fs.File -> (
      match
        (let ic = open_in_bin path in
         let b = really_input_string ic (min 4 (in_channel_length ic)) in
         close_in ic;
         b)
      with
      | b when String.length b >= 4 && String.sub b 0 2 = "PK" -> true
      | b when String.length b >= 4 ->
        (* disk images are zlib/ULxx streams or raw images — accept any
           non-zip file the caller produced; hdiutil would reject junk. *)
        true
      | _ -> false)
    | _ -> false

  let parse_submission out =
    (* The JSON object is the last '{' of the output. *)
    let rec find i =
      if i < 0 then None
      else if out.[i] = '{' then Some i
      else find (i - 1)
    in
    match find (String.length out - 1) with
    | None -> ("", "", "")
    | Some i -> (
      try
        let j = Yojson.Safe.from_string (String.sub out i (String.length out - i)) in
        let open Yojson.Safe.Util in
        let get k = try j |> member k |> to_string with _ -> "" in
        (get "id", get "status", get "message")
      with _ -> ("", "", ""))

  (** [notarize spec path] submits [path] to the notary service and
      staples the ticket on success. With no configured or resolvable
      credentials the payload is still validated and [Skipped] returned
      — never a fake success. *)
  let notarize spec path =
    if host_platform () <> Macos then
      Unsupported "notarization is implemented for macOS only"
    else begin
      match submission_payload path with
      | Failed _ | Skipped _ | Unsupported _ as e -> e
      | Ok payload -> (
        if not (payload_valid payload) then
          invalid "payload %s is not a zip archive or disk image" payload
        else
          match creds_args spec.notarization with
          | Error `No_creds ->
            Skipped
              (fmt "no notarization credentials configured; \
                    set a keychain profile (xcrun notarytool \
                    store-credentials) or Apple-id env vars. \
                    Payload ready at %s" payload)
          | Error (`Missing_env vars) ->
            Skipped
              (fmt "notarization env vars unset: %s. Payload ready at %s"
                 (String.concat ", " vars) payload)
          | Ok cred_args -> (
            match
              Proc.run "xcrun"
                ([ "notarytool"; "submit"; payload ] @ cred_args
                 @ [ "--wait"; "--output-format"; "json" ])
            with
            | r ->
              let id, status, msg = parse_submission r.stdout in
              if r.status <> 0 || status <> "Accepted" then
                tool_failed "xcrun" [ "notarytool"; "submit"; payload ] r.status
                  (fmt "%s %s%s" status msg
                     (if id = "" then "" else fmt " (submission %s)" id)
                     ^ r.stdout ^ r.stderr)
              else (
                let stapled =
                  match Proc.run "xcrun" [ "stapler"; "staple"; path ] with
                  | { status = 0; _ } -> true
                  | _ -> false
                in
                Ok
                  {
                    nz_submission_id = (if id = "" then None else Some id);
                    nz_status = status;
                    nz_stapled = stapled;
                    nz_log = r.stdout ^ r.stderr;
                  })))
    end
end

(** {1 Disk images} *)

module Dmg = struct
  let fs_name s =
    String.map (fun c -> if c = '/' || Char.code c < 0x20 then '-' else c) s

  let dmg_name spec ~arch =
    fs_name spec.name ^ " " ^ fs_name spec.version ^
    (if arch = "" || arch = "universal" then "" else " " ^ arch) ^ ".dmg"

  let contains_sub s sub =
    let n = String.length s and m = String.length sub in
    let rec go i =
      i + m <= n
      && (String.sub s i m = sub || go (i + 1))
    in
    m = 0 || go 0

  let hdiutil_busy output = contains_sub output "Resource busy"

  (* hdiutil can lose to Spotlight/antivirus holding a file: retry with
     the usual 2,4,8,16 s backoff. *)
  let retry_busy ~times prog args =
    let rec go i =
      let r = Proc.run prog args in
      if r.status = 0 || not (hdiutil_busy (r.stdout ^ r.stderr)) then r
      else if i >= times - 1 then r
      else begin
        Unix.sleepf (2. ** float i);
        go (i + 1)
      end
    in
    go 0

  let set_finder_flags path flags =
    (* com.apple.FinderInfo xattr: 32 bytes, finder flags at offset 8. *)
    let b = Bytes.make 32 '\x00' in
    Bytes.set b 8 (Char.chr ((flags lsr 8) land 0xff));
    Bytes.set b 9 (Char.chr (flags land 0xff));
    let hex = Buffer.create 64 in
    Bytes.iter (fun c -> Buffer.add_string hex (fmt "%02x" (Char.code c))) b;
    Proc.check "/usr/bin/xattr" [ "-wx"; "com.apple.FinderInfo";
                                  Buffer.contents hex; path ]

  let detach mnt =
    let rec go i =
      let args =
        if i >= 4 then [ "detach"; "-force"; mnt ] else [ "detach"; mnt ]
      in
      match Proc.check "hdiutil" args with
      | Ok _ -> Stdlib.Ok ()
      | Error e ->
        if i >= 9 then Error e
        else begin
          Unix.sleepf (float (i + 1) *. 0.5);
          go (i + 1)
        end
    in
    go 0

  exception Step_failed of failure

  (** [create spec app ~dir ~arch] builds the compressed disk image in
      [dir] and returns its path. Layout: the app beside an /Applications
      symlink, Finder layout from a generated .DS_Store, volume icon when
      the bundle carries one. *)
  let create spec app ~dir ~arch =
    match Proc.which "hdiutil" with
    | None ->
      (* Zip fallback: same artifact, less pretty. *)
      let z =
        Filename.concat dir
          (fs_name spec.name ^ " " ^ fs_name spec.version ^ ".zip")
      in
      (match Proc.check "ditto" [ "-c"; "-k"; "--keepParent"; app; z ] with
       | Ok _ -> Ok z
       | Error e -> Failed e)
    | Some _ ->
      let work = Fs.temp_dir ~prefix:".dmg-" ~parent:dir () in
      let result =
        try
          let app_name = Filename.basename app in
          let src = Filename.concat work "src" in
          Fs.mkdir_p src;
          (match Proc.check "ditto" [ "--noclone"; app; Filename.concat src app_name ] with
           | Error e -> raise (Step_failed e)
           | Ok _ -> ());
          Unix.symlink "/Applications" (Filename.concat src "Applications");
          Fs.write_file (Filename.concat src ".DS_Store") (Ds_store.dmg_store app_name);
          let icon =
            Filename.concat
              (Filename.concat (Filename.concat app "Contents") "Resources")
              Bundle.bundle_icon
          in
          let has_icon = Fs.exists icon in
          if has_icon then
            Fs.copy_file ~src:icon ~dst:(Filename.concat src ".VolumeIcon.icns");
          let rw = Filename.concat work "rw.dmg" in
          let r =
            retry_busy ~times:5 "hdiutil"
              [ "create"; "-ov"; "-volname"; spec.name; "-srcfolder"; src;
                "-fs"; "HFS+"; "-fsargs"; "-c c=64,a=16,e=16";
                "-format"; "UDRW"; rw ]
          in
          if r.Proc.status <> 0 then
            raise
              (Step_failed
                 (Tool_failed { tool = "hdiutil"; args = [ "create" ];
                                status = r.Proc.status;
                                output = r.Proc.stdout ^ r.Proc.stderr }));
          let mnt = Filename.concat work "mnt" in
          Fs.mkdir_p mnt;
          (match
             Proc.check "hdiutil"
               [ "attach"; "-readwrite"; "-noverify"; "-noautoopen";
                 "-nobrowse"; "-mountpoint"; mnt; rw ]
           with
           | Error e -> raise (Step_failed e)
           | Ok _ -> ());
          let attached = ref true in
          (try
             (if has_icon then
                match set_finder_flags mnt 0x0400 with
                | Ok _ -> ()
                | Error e -> raise (Step_failed e));
             Fs.rm_rf (Filename.concat mnt ".fseventsd");
             Fs.rm_rf (Filename.concat mnt ".Trashes");
             (match detach mnt with
              | Error e -> raise (Step_failed e)
              | Ok () -> attached := false);
             let out = Filename.concat dir (dmg_name spec ~arch) in
             (match
                Proc.check "hdiutil"
                  [ "convert"; rw; "-format"; "ULMO"; "-ov"; "-o"; out ]
              with
              | Error e -> raise (Step_failed e)
              | Ok _ -> ());
             (* Sign the image itself when a real identity is configured. *)
             (match spec.identity with
              | Certificate _ as id -> (
                match
                  Proc.check "codesign"
                    [ "--force"; "--timestamp"; "--sign";
                      Sign.identity_string id; out ]
                with
                | Ok _ -> ()
                | Error e -> raise (Step_failed e))
              | Adhoc -> ());
             Ok out
           with e ->
             if !attached then
               ignore (Proc.run "hdiutil" [ "detach"; "-force"; mnt ]);
             raise e)
        with
        | Step_failed f -> Failed f
        | Unix.Unix_error (e, _, _) -> Failed (Invalid (Unix.error_message e))
      in
      Fs.rm_rf work;
      result
end

(** {1 Delta updates}

    Wire format, ported: ["lui delta 1\n"], a uvarint index length, the
    DEFLATE-compressed JSON index, then the data of the files in index
    order — a binary patch, or the whole file DEFLATE-compressed. The
    index lists the new app's tree: directories, links and files with
    their size and SHA-256; each file copies an old file (from, no data),
    patches it (from + data) or is new (data only). *)

module Delta = struct
  let magic = "lui delta 1\n"
  let max_diff = 256 lsl 20
  let max_index = 16 lsl 20

  type entry = {
    path : string;
    dir : bool;
    link : string;
    mode : int;
    size : int;
    sha256 : string;
    from : string;
    data : int;
  }

  let is_file e = (not e.dir) && e.link = ""

  exception Damaged of string

  let valid_rel_path p =
    p <> "" && p <> "." && p.[0] <> '/' && p.[0] <> '\\'
    && (try
          List.iter
            (fun seg -> if seg = "" || seg = "." || seg = ".." then raise Exit)
            (String.split_on_char '/' p);
          true
        with Exit -> false)

  let entry_json e =
    let fields = [ ("path", `String e.path) ] in
    let fields = if e.dir then fields @ [ ("dir", `Bool true) ] else fields in
    let fields = if e.link <> "" then fields @ [ ("link", `String e.link) ] else fields in
    let fields = if e.mode <> 0 then fields @ [ ("mode", `Int e.mode) ] else fields in
    let fields = if e.size <> 0 then fields @ [ ("size", `Int e.size) ] else fields in
    let fields = if e.sha256 <> "" then fields @ [ ("sha256", `String e.sha256) ] else fields in
    let fields = if e.from <> "" then fields @ [ ("from", `String e.from) ] else fields in
    let fields = if e.data <> 0 then fields @ [ ("data", `Int e.data) ] else fields in
    `Assoc fields

  let entry_of_json j =
    let open Yojson.Safe.Util in
    {
      path = j |> member "path" |> to_string_option |> Option.value ~default:"";
      dir = j |> member "dir" |> to_bool_option |> Option.value ~default:false;
      link = j |> member "link" |> to_string_option |> Option.value ~default:"";
      mode = j |> member "mode" |> to_int_option |> Option.value ~default:0;
      size = j |> member "size" |> to_int_option |> Option.value ~default:0;
      sha256 = j |> member "sha256" |> to_string_option |> Option.value ~default:"";
      from = j |> member "from" |> to_string_option |> Option.value ~default:"";
      data = j |> member "data" |> to_int_option |> Option.value ~default:0;
    }

  (** Hash every regular file under [root]: rel path → (sha, size),
      and first path per content for move/copy detection. *)
  let scan_tree root =
    let by_path = Hashtbl.create 64 and by_sum = Hashtbl.create 64 in
    List.iter
      (fun (rel, kind) ->
         if kind = Fs.File then begin
           let p = Filename.concat root rel in
           let sum = Sha256.file p in
           let size = Option.value ~default:0 (Fs.file_size p) in
           Hashtbl.replace by_path rel (sum, size);
           if not (Hashtbl.mem by_sum sum) then Hashtbl.add by_sum sum rel
         end)
      (Fs.walk root);
    (by_path, by_sum)

  let slashify = String.map (fun c -> if c = Filename.dir_sep.[0] then '/' else c)

  (** [write ~from ~to_ ~old_dir ~new_dir out] writes the delta file to
      [out] and returns the index entries (the manifest). *)
  let write ~from ~to_ ~old_dir ~new_dir out =
    let old_by_path, old_by_sum = scan_tree old_dir in
    let entries = ref [] in
    let blobs = Buffer.create 4096 in
    List.iter
      (fun (rel, kind) ->
         let rel = slashify rel in
         let p = Filename.concat new_dir rel in
         match kind with
         | Fs.Dir -> entries := { path = rel; dir = true; link = ""; mode = 0; size = 0; sha256 = ""; from = ""; data = 0 } :: !entries
         | Fs.Link ->
           let target =
             try Unix.readlink p with Unix.Unix_error _ -> ""
           in
           entries :=
             { path = rel; dir = false; link = slashify target; mode = 0;
               size = 0; sha256 = ""; from = ""; data = 0 }
             :: !entries
         | Fs.File ->
           let data = Fs.read_file p in
           let size = String.length data and sum = Sha256.string data in
           let mode = (try (Unix.stat p).Unix.st_perm with _ -> 0o644) in
           let e =
             match Hashtbl.find_opt old_by_path rel with
             | Some (osum, _) when osum = sum ->
               { path = rel; dir = false; link = ""; mode; size; sha256 = sum;
                 from = rel; data = 0 }
             | Some (_, osize) -> (
               match Hashtbl.find_opt old_by_sum sum with
               | Some src ->
                 { path = rel; dir = false; link = ""; mode; size;
                   sha256 = sum; from = src; data = 0 }
               | None ->
                 let blob = Deflate.deflate data in
                 let use_patch, blob =
                   if osize > 0 && osize <= max_diff && size <= max_diff then
                     let prev =
                       Fs.read_file (Filename.concat old_dir (String.map (fun c -> if c = '/' then Filename.dir_sep.[0] else c) rel))
                     in
                     let patch = Bsdiff.diff prev data in
                     if String.length patch < String.length blob then (true, patch)
                     else (false, blob)
                   else (false, blob)
                 in
                 Buffer.add_string blobs blob;
                 { path = rel; dir = false; link = ""; mode; size;
                   sha256 = sum;
                   from = (if use_patch then rel else "");
                   data = String.length blob })
             | None ->
               (match Hashtbl.find_opt old_by_sum sum with
                | Some src ->
                  { path = rel; dir = false; link = ""; mode; size;
                    sha256 = sum; from = src; data = 0 }
                | None ->
                  let blob = Deflate.deflate data in
                  Buffer.add_string blobs blob;
                  { path = rel; dir = false; link = ""; mode; size;
                    sha256 = sum; from = ""; data = String.length blob })
           in
           entries := e :: !entries
         | _ -> ())
      (List.sort (fun (a, _) (b, _) -> compare a b) (Fs.walk new_dir));
    let entries = List.rev !entries in
    let index =
      `Assoc
        [
          ("from", `String from);
          ("version", `String to_);
          ("entries", `List (List.map entry_json entries));
        ]
    in
    let js = Deflate.deflate (Yojson.Safe.to_string index) in
    let oc = open_out_bin out in
    output_string oc magic;
    let head = Buffer.create 16 in
    Varint.append_uvarint head (String.length js);
    Buffer.output_buffer oc head;
    output_string oc js;
    Buffer.output_buffer oc blobs;
    close_out oc;
    entries

  (** Parse a delta file into (index, data section offset). *)
  let parse_index delta =
    if String.length delta < String.length magic
       || String.sub delta 0 (String.length magic) <> magic
    then raise (Damaged "not a delta update");
    match Varint.uvarint delta (String.length magic) with
    | None -> raise (Damaged "truncated index length")
    | Some (index_len, start) ->
      if index_len > String.length delta - start || index_len > max_index
      then raise (Damaged "index length out of range");
      let js =
        try Deflate.inflate ~off:start ~len:index_len delta
        with Deflate.Bad_stream _ -> raise (Damaged "index stream damaged")
      in
      (try
         let j = Yojson.Safe.from_string js in
         let open Yojson.Safe.Util in
         let idx_from = j |> member "from" |> to_string in
         let idx_to = j |> member "version" |> to_string in
         let entries =
           j |> member "entries" |> to_list |> List.map entry_of_json
         in
         (idx_from, idx_to, entries, start + index_len)
       with _ -> raise (Damaged "index is not valid JSON"))

  (* Validate the index before writing anything: paths unique and
     inside the app, sizes sane, data offsets cover the file exactly. *)
  let check_index entries ~data_start ~size =
    let seen = Hashtbl.create 64 in
    let offset = ref data_start in
    List.iter
      (fun e ->
        let ok =
          valid_rel_path e.path
          && not (Hashtbl.mem seen e.path)
          && e.size >= 0 && e.data >= 0
          && Int64.of_int e.data <= Int64.sub (Int64.of_int size) (Int64.of_int !offset)
          && not (e.dir && e.link <> "")
          && (is_file e || (e.size = 0 && e.data = 0 && e.from = ""))
          && (e.from = "" || valid_rel_path e.from)
          && not (is_file e && e.from = "" && e.data = 0)
        in
        if not ok then raise (Damaged (fmt "bad index entry %s" e.path));
        if e.link <> "" then begin
          let target_dir = Filename.dirname e.path in
          let joined = Filename.concat target_dir e.link in
          if Filename.is_relative e.link && not (valid_rel_path joined) then
            raise (Damaged (fmt "link %s points outside the app" e.path));
          if not (Filename.is_relative e.link) && e.link.[0] = '/' then
            raise (Damaged (fmt "link %s points outside the app" e.path))
        end;
        Hashtbl.replace seen e.path ();
        offset := !offset + e.data)
      entries;
    if !offset <> size then raise (Damaged "delta size does not match index")

  (** [apply ~delta ~from ~to_ ~old_dir ~new_dir] rebuilds the app of
      [to_] into [new_dir] (which must not exist), checking every file it
      makes against the index's size and SHA-256. *)
  let apply ~delta ~from ~to_ ~old_dir ~new_dir =
    let data = Fs.read_file delta in
    let size = String.length data in
    let idx_from, idx_to, entries, data_start = parse_index data in
    if idx_from <> from || idx_to <> to_ then
      invalid "the delta updates %s to %s, not %s to %s" idx_from idx_to from to_
    else if Fs.exists new_dir then invalid "target %s already exists" new_dir
    else begin
      match
        (try check_index entries ~data_start ~size; Stdlib.Ok ()
         with Damaged m -> Error (Invalid m))
      with
      | Error f -> Failed f
      | Ok () ->
        Fs.mkdir_p new_dir;
        let offset = ref data_start in
        let put e =
          let name =
            String.map (fun c -> if c = '/' then Filename.dir_sep.[0] else c) e.path
          in
          let dst = Filename.concat new_dir name in
          let dir = Filename.dirname dst in
          if dir <> new_dir && dir <> "." then Fs.mkdir_p dir;
          if e.dir then Fs.mkdir_p dst
          else if e.link <> "" then Unix.symlink e.link dst
          else begin
            let content =
              if e.from = "" then Deflate.inflate ~off:!offset ~len:e.data data
              else begin
                let src =
                  Filename.concat old_dir
                    (String.map
                       (fun c -> if c = '/' then Filename.dir_sep.[0] else c)
                       e.from)
                in
                if e.data = 0 then Fs.read_file src
                else
                  Bsdiff.patch ~old_data:(Fs.read_file src)
                    ~patch_data:(String.sub data !offset e.data) e.size
              end
            in
            offset := !offset + e.data;
            if String.length content <> e.size || Sha256.string content <> e.sha256
            then raise (Damaged (fmt "the delta made %s wrong" e.path));
            Fs.write_file ~perm:(if e.mode = 0 then 0o644 else e.mode) dst content
          end
        in
        (try List.iter put entries; Ok ()
         with
         | Damaged m -> Failed (Invalid m)
         | Bsdiff.Bad_patch -> Failed (Invalid "bad delta patch")
         | Deflate.Bad_stream m -> Failed (Invalid m)
         | Unix.Unix_error (e, _, _) -> Failed (Invalid (Unix.error_message e))
         | Sys_error m -> Failed (Invalid m))
    end
end

(** {1 Spec constructor} *)

(** [v_spec ...] assembles an {!app_spec} with the fields a CLI or a
    build script usually leaves alone defaulted. *)
let v_spec ~name ~bundle_id ~version ?build ?icon ~executable
    ?(resources = []) ?(entitlements = []) ?(helper_entitlements = [])
    ?(identity = Adhoc) ?notarization ?(min_system = "11.0")
    ?(url_schemes = []) ?(doc_types = []) ?copyright ?(info_extra = [])
    ?(production = false) () =
  {
    name; bundle_id; version; build; icon; executable; resources;
    entitlements; helper_entitlements; identity; notarization;
    min_system; url_schemes; doc_types; copyright; info_extra; production;
  }

(** {1 Packagers} *)

let macos_packager =
  {
    pkg_platform = Macos;
    pkg_bundle = (fun spec dir -> Bundle.write spec ~dir);
    pkg_sign = Sign.sign;
    pkg_notarize = Notarize.notarize;
    pkg_disk_image =
      (fun spec app dir -> Dmg.create spec app ~dir ~arch:(host_arch ()));
  }

(** Declared stub: the record exists so callers shape their code for a
    platform before its implementation lands. Every call answers
    [Unsupported]. *)
let stub_packager platform =
  let msg what =
    fmt "%s is not implemented for %s yet" what
      (string_of_platform platform)
  in
  {
    pkg_platform = platform;
    pkg_bundle = (fun _ _ -> Unsupported (msg "app bundles"));
    pkg_sign = (fun _ _ -> Unsupported (msg "code signing"));
    pkg_notarize = (fun _ _ -> Unsupported (msg "notarization"));
    pkg_disk_image = (fun _ _ _ -> Unsupported (msg "disk images"));
  }

let packager_for = function
  | Macos -> macos_packager
  | (Linux | Windows | Unknown _) as p -> stub_packager p

let host_packager () = packager_for (host_platform ())

(** {1 Top-level API} *)

(** [bundle spec ~dir] builds [<dir>/<name>.app] and returns its path. *)
let bundle spec ~dir = (host_packager ()).pkg_bundle spec dir

(** [sign spec app] signs the bundle inside-out and verifies it. *)
let sign spec app = (host_packager ()).pkg_sign spec app

(** [notarize spec path] submits a dmg/zip and staples; [Skipped] when no
    credentials are configured — never a fake success. *)
let notarize spec path = (host_packager ()).pkg_notarize spec path

(** [dmg spec app ~dir] creates the disk image (or zip fallback) in [dir]. *)
let dmg spec app ~dir = (host_packager ()).pkg_disk_image spec app dir

(** [update_pkg ~from ~to_ ~old_dir ~new_dir out] writes the delta file
    [out] that updates version [from]'s tree at [old_dir] to [to_]'s at
    [new_dir]. Platform-independent: a delta is a file format, applied by
    the updater inside the next version of the app. *)
let update_pkg ~from ~to_ ~old_dir ~new_dir out =
  try
    let _ = Delta.write ~from ~to_ ~old_dir ~new_dir out in
    Ok ()
  with
  | Sys_error m -> Failed (Missing m)
  | Unix.Unix_error (e, _, _) -> Failed (Invalid (Unix.error_message e))

(** [apply_delta ~delta ~from ~to_ ~old_dir ~new_dir] is the verifier half:
    rebuilds [to_]'s tree at [new_dir] and checks every produced file
    against the index's SHA-256. *)
let apply_delta ~delta ~from ~to_ ~old_dir ~new_dir =
  Delta.apply ~delta ~from ~to_ ~old_dir ~new_dir

(** [delta_info delta] returns the (from, to, entry-count) of a delta file. *)
let delta_info delta =
  try
    let data = Fs.read_file delta in
    let f, t, entries, _ = Delta.parse_index data in
    Ok (f, t, List.length entries)
  with
  | Delta.Damaged m -> Failed (Invalid m)
  | Sys_error m -> Failed (Missing m)

(** Internals exposed to the test suite; not part of the API contract. *)
module Private = struct
  module Fs = Fs
  module Proc = Proc
  module Sha256 = Sha256
  module Crc32 = Crc32
  module Adler32 = Adler32
  module Varint = Varint
  module Deflate = Deflate
  module Bsdiff = Bsdiff
  module Plist = Plist
  module Ds_store = Ds_store
  module Mach_o = Mach_o
  module Info_plist = Info_plist
  module Iconset = Iconset
  module Bundle = Bundle
  module Sign = Sign
  module Notarize = Notarize
  module Dmg = Dmg
  module Delta = Delta
end
