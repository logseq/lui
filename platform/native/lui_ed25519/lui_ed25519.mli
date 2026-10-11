(** Lui_ed25519 — Ed25519 signature verification (RFC 8032) in pure
    OCaml.

    Used by the self-update client ({!Lui_updater}) to authenticate
    release artifacts: a feed publishes a public key, each artifact a
    detached signature over its raw bytes, and this module answers one
    question — did the holder of the matching secret key sign exactly
    these bytes.

    Zero external dependencies: SHA-512 and the curve arithmetic are
    implemented directly below, the latter following the public-domain
    TweetNaCl reference algorithm (radix-2^16 field elements, extended
    twisted-Edwards point ops) so the wire format matches every other
    Ed25519 implementation. {!verify} is what production code calls;
    {!public_key} and {!sign} exist for tests, tooling, and key
    ceremonies. *)

val verify : pk:string -> signature:string -> msg:string -> bool
(** Whether [signature] is a valid Ed25519 signature of [msg] under the
    public key [pk]. [pk] is the 32-byte encoding, [signature] the
    64-byte [R || S] encoding; anything else, an undecodable key, a
    non-canonical [S >= l], or a mismatched signature returns [false]. *)

(** {1 Streaming verify}

    The same check over a message fed in chunks — for callers
    authenticating a large artifact without holding it in memory.
    [verify pk sig msg] is [begin + feed msg + finish]. *)

type pending
(** An in-progress verification. *)

val verify_begin : pk:string -> signature:string -> pending option
(** Decodes the key and signature and starts hashing [R || pk], or
    [None] when either fails the upfront checks {!verify} describes. *)

val verify_feed : pending -> bytes -> int -> int -> unit
(** Feeds [verify_feed p b off len]: the next [len] message bytes from
    [b] at [off]. *)

val verify_finish : pending -> bool
(** The verdict once the whole message has been fed. *)

(** {1 Encodings}

    Manifests carry keys and signatures as text. Hex and base64 are
    both accepted on decode so feeds can use either convention. *)

val decode_key : string -> string option
(** Hex (64 chars) or base64 (44 chars) of a 32-byte public key, or
    [None] when the text decodes to anything else. *)

val decode_signature : string -> string option
(** Hex (128 chars) or base64 (88 chars) of a 64-byte signature, or
    [None] when the text decodes to anything else. *)

val encode_hex : string -> string
(** Lowercase hex of the given bytes. *)

val decode_hex : string -> string option
(** Bytes of an even-length hex string, or [None]. *)

val encode_base64 : string -> string
(** RFC 4648 base64 with [=] padding, no line breaks. *)

val decode_base64 : string -> string option
(** Bytes of a padded base64 string (whitespace tolerated), or [None]
    for bad characters, bad padding, or bad length. *)

val sha512 : string -> string
(** The 64-byte SHA-512 digest — exposed mainly for known-answer tests
    and to keep the hashing primitive inspectable on its own. *)

(** {1 Keys and signing}

    For tests, fixtures, and offline tooling — the verifier above is
    all a running app needs. The secret key [sk] is the 32-byte seed
    form (RFC 8032 / openssl raw private key), not a PEM file. *)

val public_key : sk:string -> string option
(** The 32-byte public key for [sk], or [None] when [sk] is not 32
    bytes. *)

val sign : sk:string -> msg:string -> string option
(** The deterministic RFC 8032 signature of [msg] under [sk], or [None]
    when [sk] is not 32 bytes. *)
