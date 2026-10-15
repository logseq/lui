(* Tests for Lui_ed25519: SHA-512 known answers, the RFC 8032 Ed25519
   vectors (verify + deterministic sign + public_key derivation), the
   wire encodings, and every rejection path — wrong sig/key/msg, bad
   lengths, non-canonical S and point encodings. *)

module E = Lui_ed25519

let check = Alcotest.check
let bool = Alcotest.bool
let string = Alcotest.string

(* hex helper on the test side: reuse the library's decoder so the
   vectors exercise the same path manifests use *)
let hex s =
  let n = String.length s in
  let b = Bytes.create (n / 2) in
  let v c =
    if c >= '0' && c <= '9' then Char.code c - Char.code '0'
    else 10 + Char.code c - Char.code 'a'
  in
  for i = 0 to (n / 2) - 1 do
    Bytes.set b i (Char.chr ((v s.[2 * i] lsl 4) lor v s.[(2 * i) + 1]))
  done;
  Bytes.unsafe_to_string b

(* ------------------------------------------------------------ sha512 *)

let test_sha512 () =
  let digest s = E.encode_hex (E.sha512 s) in
  check string "empty"
    "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"
    (digest "");
  check string "abc"
    "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
    (digest "abc");
  (* 112-byte message: exercises the two-block tail path *)
  check string "112 bytes"
    "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"
    (digest
       "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu")

(* ------------------------------------------------------ rfc 8032 *)
(* RFC 8032 §7.1: TEST 1, 2, 3 and the 1024-octet test (the message is
   1023 bytes long in the RFC text). *)

let rfc1_sk =
  "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
let rfc1_pk =
  "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
let rfc1_msg = ""
let rfc1_sig =
  "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e06522490155\
   5fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"

let rfc2_sk =
  "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb"
let rfc2_pk =
  "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
let rfc2_msg = "72"
let rfc2_sig =
  "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da\
   085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"

let rfc3_sk =
  "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7"
let rfc3_pk =
  "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025"
let rfc3_msg = "af82"
let rfc3_sig =
  "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac\
   18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"

let rfc1024_sk =
  "f5e5767cf153319517630f226876b86c8160cc583bc013744c6bf255f5cc0ee5"
let rfc1024_pk =
  "278117fc144c72340f67d0f2316e8386ceffbf2b2428c9c51fef7c597f1d426e"
let rfc1024_msg =
  "08b8b2b733424243760fe426a4b54908632110a66c2f6591eabd3345e3e4eb98\
   fa6e264bf09efe12ee50f8f54e9f77b1e355f6c50544e23fb1433ddf73be84d8\
   79de7c0046dc4996d9e773f4bc9efe5738829adb26c81b37c93a1b270b20329d\
   658675fc6ea534e0810a4432826bf58c941efb65d57a338bbd2e26640f89ffbc\
   1a858efcb8550ee3a5e1998bd177e93a7363c344fe6b199ee5d02e82d522c4fe\
   ba15452f80288a821a579116ec6dad2b3b310da903401aa62100ab5d1a36553e\
   06203b33890cc9b832f79ef80560ccb9a39ce767967ed628c6ad573cb116dbef\
   efd75499da96bd68a8a97b928a8bbc103b6621fcde2beca1231d206be6cd9ec7\
   aff6f6c94fcd7204ed3455c68c83f4a41da4af2b74ef5c53f1d8ac70bdcb7ed1\
   85ce81bd84359d44254d95629e9855a94a7c1958d1f8ada5d0532ed8a5aa3fb2\
   d17ba70eb6248e594e1a2297acbbb39d502f1a8c6eb6f1ce22b3de1a1f40cc24\
   554119a831a9aad6079cad88425de6bde1a9187ebb6092cf67bf2b13fd65f270\
   88d78b7e883c8759d2c4f5c65adb7553878ad575f9fad878e80a0c9ba63bcbcc\
   2732e69485bbc9c90bfbd62481d9089beccf80cfe2df16a2cf65bd92dd597b07\
   07e0917af48bbb75fed413d238f5555a7a569d80c3414a8d0859dc65a46128ba\
   b27af87a71314f318c782b23ebfe808b82b0ce26401d2e22f04d83d1255dc51a\
   ddd3b75a2b1ae0784504df543af8969be3ea7082ff7fc9888c144da2af58429e\
   c96031dbcad3dad9af0dcbaaaf268cb8fcffead94f3c7ca495e056a9b47acdb7\
   51fb73e666c6c655ade8297297d07ad1ba5e43f1bca32301651339e22904cc8c\
   42f58c30c04aafdb038dda0847dd988dcda6f3bfd15c4b4c4525004aa06eeff8\
   ca61783aacec57fb3d1f92b0fe2fd1a85f6724517b65e614ad6808d6f6ee34df\
   f7310fdc82aebfd904b01e1dc54b2927094b2db68d6f903b68401adebf5a7e08\
   d78ff4ef5d63653a65040cf9bfd4aca7984a74d37145986780fc0b16ac451649\
   de6188a7dbdf191f64b5fc5e2ab47b57f7f7276cd419c17a3ca8e1b939ae49e4\
   88acba6b965610b5480109c8b17b80e1b7b750dfc7598d5d5011fd2dcc5600a3\
   2ef5b52a1ecc820e308aa342721aac0943bf6686b64b2579376504ccc493d97e\
   6aed3fb0f9cd71a43dd497f01f17c0e2cb3797aa2a2f256656168e6c496afc5f\
   b93246f6b1116398a346f1a641f3b041e989f7914f90cc2c7fff357876e506b5\
   0d334ba77c225bc307ba537152f3f1610e4eafe595f6d9d90d11faa933a15ef1\
   369546868a7f3a45a96768d40fd9d03412c091c6315cf4fde7cb68606937380d\
   b2eaaa707b4c4185c32eddcdd306705e4dc1ffc872eeee475a64dfac86aba41c\
   0618983f8741c5ef68d3a101e8a3b8cac60c905c15fc910840b94c00a0b9d0"
let rfc1024_sig =
  "0aab4c900501b3e24d7cdf4663326a3a87df5e4843b2cbdb67cbf6e460fec350\
   aa5371b1508f9f4528ecea23c436d94b5e8fcd4f681e30a6ac00a9704a188a03"

let check_vector name ~sk ~pk ~msg ~signature =
  let sk = hex sk and pk = hex pk and msg = hex msg
  and signature = hex signature in
  check bool (name ^ " pk derive") true
    (E.public_key ~sk = Some pk);
  check bool (name ^ " verify") true
    (E.verify ~pk ~signature ~msg);
  (* deterministic signing reproduces the RFC signature exactly *)
  check bool (name ^ " sign") true
    (E.sign ~sk ~msg = Some signature)

let test_rfc () =
  check_vector "TEST1" ~sk:rfc1_sk ~pk:rfc1_pk ~msg:rfc1_msg
    ~signature:rfc1_sig;
  check_vector "TEST2" ~sk:rfc2_sk ~pk:rfc2_pk ~msg:rfc2_msg
    ~signature:rfc2_sig;
  check_vector "TEST3" ~sk:rfc3_sk ~pk:rfc3_pk ~msg:rfc3_msg
    ~signature:rfc3_sig;
  check_vector "TEST1024" ~sk:rfc1024_sk ~pk:rfc1024_pk ~msg:rfc1024_msg
    ~signature:rfc1024_sig

(* ------------------------------------------------------- negatives *)

let flip s i =
  let b = Bytes.of_string s in
  Bytes.set b i (Char.chr (Char.code (Bytes.get b i) lxor 1));
  Bytes.unsafe_to_string b

let test_negatives () =
  let pk = hex rfc1_pk and sig1 = hex rfc1_sig and msg = hex rfc1_msg in
  (* one flipped bit anywhere in the signature or the message *)
  check bool "sig bit flip" false (E.verify ~pk ~signature:(flip sig1 0) ~msg);
  check bool "sig bit flip S" false
    (E.verify ~pk ~signature:(flip sig1 63) ~msg);
  check bool "wrong key" false
    (E.verify ~pk:(hex rfc2_pk) ~signature:sig1 ~msg);
  check bool "pk bit flip" false
    (E.verify ~pk:(flip pk 0) ~signature:sig1 ~msg);
  check bool "wrong msg" false
    (E.verify ~pk ~signature:sig1 ~msg:"x");
  let sig2 = hex rfc2_sig and msg2 = hex rfc2_msg in
  check bool "cross msg" false
    (E.verify ~pk ~signature:sig2 ~msg:msg2);
  (* sign-verify roundtrip on a derived key *)
  let sk = hex rfc2_sk in
  let sig' = Option.get (E.sign ~sk ~msg:"hello updater") in
  check bool "roundtrip" true
    (E.verify ~pk:(Option.get (E.public_key ~sk)) ~signature:sig'
       ~msg:"hello updater");
  check bool "roundtrip msg" false
    (E.verify ~pk:(Option.get (E.public_key ~sk)) ~signature:sig'
       ~msg:"hello updater!")

(* -------------------------------------------------- malformed input *)

(* the group order l as 32 little-endian bytes: any S >= l is rejected *)
let l_bytes =
  hex
    "edd3f55c1a631258d69cf7a2def9de140000000000000000000000000000000010"

let test_malformed () =
  let pk = hex rfc1_pk and sig1 = hex rfc1_sig and msg = hex rfc1_msg in
  (* bad lengths *)
  check bool "pk 31" false
    (E.verify ~pk:(String.sub pk 0 31) ~signature:sig1 ~msg);
  check bool "pk 33" false
    (E.verify ~pk:(pk ^ "x") ~signature:sig1 ~msg);
  check bool "sig 63" false
    (E.verify ~pk ~signature:(String.sub sig1 0 63) ~msg);
  check bool "sig 65" false
    (E.verify ~pk ~signature:(sig1 ^ "x") ~msg);
  check bool "empty" false
    (E.verify ~pk:"" ~signature:"" ~msg);
  (* S = l exactly and S = 2^256-1: both >= l *)
  let s_is_l = String.sub sig1 0 32 ^ l_bytes in
  check bool "S = l" false (E.verify ~pk ~signature:s_is_l ~msg);
  let s_max = String.sub sig1 0 32 ^ String.make 32 '\xff' in
  check bool "S = 2^256-1" false (E.verify ~pk ~signature:s_max ~msg);
  (* a public key whose y is >= p (all 0xff) *)
  check bool "y >= p" false
    (E.verify ~pk:(String.make 32 '\xff') ~signature:sig1 ~msg);
  (* arbitrary off-curve-ish keys just can't verify *)
  check bool "garbage pk" false
    (E.verify ~pk:(String.make 32 '\xab') ~signature:sig1 ~msg);
  check bool "garbage pk 2" false
    (E.verify ~pk:(String.make 32 '\x01') ~signature:sig1 ~msg);
  (* helpers reject bad input shapes *)
  check bool "public_key len" true (E.public_key ~sk:"short" = None);
  check bool "sign len" true (E.sign ~sk:"short" ~msg = None)

(* ------------------------------------------------------- encodings *)

let test_encodings () =
  let pk = hex rfc1_pk and sig1 = hex rfc1_sig in
  check string "hex roundtrip" rfc1_pk (E.encode_hex pk);
  (* decode_key accepts hex and base64 *)
  check bool "key hex" true (E.decode_key rfc1_pk = Some pk);
  check bool "key b64" true
    (E.decode_key (E.encode_base64 pk) = Some pk);
  check bool "key b64 padded text" true
    (E.decode_key (E.encode_base64 pk ^ "\n") = Some pk);
  check bool "sig hex" true (E.decode_signature rfc1_sig = Some sig1);
  check bool "sig b64" true
    (E.decode_signature (E.encode_base64 sig1) = Some sig1);
  (* rejects *)
  check bool "key short b64" true (E.decode_key "AAAA" = None);
  check bool "key hex garbage" true
    (E.decode_key (String.make 64 'z') = None);
  check bool "key bad b64" true (E.decode_key "!!!" = None);
  check bool "key wrong len" true
    (E.decode_key (E.encode_base64 "tooshort") = None);
  check bool "sig 128-hex garbage" true
    (E.decode_signature (String.make 128 'z') = None);
  check bool "sig wrong len" true
    (E.decode_signature (E.encode_base64 pk) = None);
  (* hex decoded sig also verifies *)
  check bool "verify via decode" true
    (match (E.decode_key rfc1_pk, E.decode_signature rfc1_sig) with
     | Some k, Some s ->
       E.verify ~pk:k ~signature:s ~msg:(hex rfc1_msg)
     | _ -> false);
  (* base64 against a reference: "hello world" -> aGVsbG8gd29ybGQ= *)
  check string "b64 known" "aGVsbG8gd29ybGQ=" (E.encode_base64 "hello world");
  check bool "b64 decode known" true
    (E.decode_base64 "aGVsbG8gd29ybGQ=" = Some "hello world");
  check bool "b64 unpadded reject" true
    (E.decode_base64 "aGVsbG8gd29ybGQ" = None)

let () =
  Alcotest.run "lui_ed25519"
    [ ("sha512", [ Alcotest.test_case "kat" `Quick test_sha512 ]);
      ("rfc8032", [ Alcotest.test_case "vectors" `Quick test_rfc ]);
      ("verify", [ Alcotest.test_case "negatives" `Quick test_negatives;
                   Alcotest.test_case "malformed" `Quick test_malformed ]);
      ("wire", [ Alcotest.test_case "encodings" `Quick test_encodings ]) ]
