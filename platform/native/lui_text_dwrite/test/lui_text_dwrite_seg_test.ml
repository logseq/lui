(* Grapheme cluster boundaries as raw UTF-8 byte offsets.

   Runs on every platform: [graphemes] is pure OCaml over Uuseg and
   needs no DirectWrite host. The contract under test is the byte-offset
   mapping — boundaries index bytes, so a multibyte prefix shifts every
   later boundary, and a segmenter bug shows up as an offset that is not
   a UTF-8 character start (or a split cluster). *)

open Lui_text_dwrite

let check s want =
  Alcotest.(check (array int))
    (Printf.sprintf "%S" (String.escaped s)) want (graphemes s)

let test_ascii () =
  check "" [| 0 |];
  check "abc" [| 0; 1; 2; 3 |]

let test_multibyte_offsets () =
  (* boundaries count bytes, not code points *)
  check "\xC3\xA9" [| 0; 2 |];              (* U+00E9 *)
  check "\xC3\xA9x" [| 0; 2; 3 |];
  check "e\xCC\x81" [| 0; 3 |];            (* e + U+0301, one cluster *)
  check "\xE4\xBD\xA0\xE5\xA5\xBD" [| 0; 3; 6 |]  (* 你好 *)

let test_crlf () =
  (* GB3: CR x LF is one cluster *)
  check "a\r\nb" [| 0; 1; 3; 4 |]

let test_emoji_zwj () =
  (* family emoji: 3 emoji + 2 ZWJ = 18 bytes, one cluster *)
  check
    "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7"
    [| 0; 18 |]

let test_regional_indicators () =
  let ri = "\xF0\x9F\x87\xA8\xF0\x9F\x87\xB3" in (* flag, 8 bytes *)
  check ri [| 0; 8 |];
  (* GB12/13 pairs RIs: an odd run breaks before its last flag *)
  check (ri ^ String.sub ri 0 4) [| 0; 8; 12 |];
  check (ri ^ ri) [| 0; 8; 16 |]

let test_indic_conjunct () =
  (* GB9c: consonant + virama + consonant is one cluster, ZWJ or not *)
  check "\xE0\xA4\x95\xE0\xA5\x8D\xE0\xA4\xB7" [| 0; 9 |];
  check "\xE0\xA4\x95\xE0\xA5\x8D\xE2\x80\x8D\xE0\xA4\xB7" [| 0; 12 |]

let test_boundaries_on_char_starts () =
  (* every reported boundary is a UTF-8 character start or the end *)
  let s =
    "a\xC3\xA9e\xCC\x81\xE4\xBD\xA0\xF0\x9F\x87\xA8\xF0\x9F\x87\xB3z"
  in
  Array.iter
    (fun b ->
       Alcotest.(check bool)
         (Printf.sprintf "boundary %d on char start" b) true
         (b = String.length s
          || Char.code s.[b] land 0xC0 <> 0x80))
    (graphemes s)

let () =
  Alcotest.run "lui_text_dwrite_seg"
    [ ( "graphemes",
        [ Alcotest.test_case "ascii" `Quick test_ascii;
          Alcotest.test_case "multibyte offsets" `Quick
            test_multibyte_offsets;
          Alcotest.test_case "crlf" `Quick test_crlf;
          Alcotest.test_case "emoji zwj" `Quick test_emoji_zwj;
          Alcotest.test_case "regional indicators" `Quick
            test_regional_indicators;
          Alcotest.test_case "indic conjunct" `Quick test_indic_conjunct;
          Alcotest.test_case "boundaries on char starts" `Quick
            test_boundaries_on_char_starts ] ) ]
