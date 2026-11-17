(* lui_plugin_sqlite tests: typed values, named params, transactions,
   the JSON service round-trip through the plugin descriptor, error
   surfacing, and handle independence. *)

module S = Lui_plugin_sqlite

let ok_exn = function
  | Ok v -> v
  | Error m -> failwith m

let err = function
  | Error m -> m
  | Ok _ -> Alcotest.fail "expected Error"

let exec db sql = ignore (ok_exn (S.exec db sql))
let execp db params sql = ignore (ok_exn (S.exec ~params db sql))

(* Everything below requires a resolvable system SQLite library. *)
let need_sqlite () =
  if not (S.available ()) then
    Alcotest.(check bool) "sqlite unavailable — skipping" true true;
  S.available ()

let memdb () = ok_exn (S.open_db ~path:":memory:" ())

let value_eq a b =
  match a, b with
  | S.Real x, S.Real y -> Float.equal x y
  | _ -> a = b

let row_lookup r k = snd (List.find (fun (n, _) -> n = k) r)

(* ---------- basic open/close ---------- *)

let test_open_memory () =
  if need_sqlite () then begin
    let db = memdb () in
    Alcotest.(check bool) "open ok" true true;
    ignore (ok_exn (S.close db));
    Alcotest.(check bool) "version" true (Option.is_some (S.version ()))
  end

(* ---------- typed values ---------- *)

let test_typed_values () =
  if need_sqlite () then begin
    let db = memdb () in
    exec db "CREATE TABLE t (i INTEGER, r REAL, x TEXT, b BLOB, n TEXT)";
    execp db
      [ S.Pos (S.Int 4611686018427387904L);
        S.Pos (S.Real 2.5);
        S.Pos (S.Text "hello");
        S.Pos (S.Blob "\x00\x01\x02\xff");
        S.Pos S.Null ]
      "INSERT INTO t VALUES (?, ?, ?, ?, ?)";
    let rows = ok_exn (S.query db "SELECT i, r, x, b, n FROM t") in
    Alcotest.(check int) "rows" 1 (List.length rows);
    let r = List.hd rows in
    Alcotest.(check bool) "int" true
      (value_eq (row_lookup r "i") (S.Int 4611686018427387904L));
    Alcotest.(check bool) "real" true
      (value_eq (row_lookup r "r") (S.Real 2.5));
    Alcotest.(check bool) "text" true
      (value_eq (row_lookup r "x") (S.Text "hello"));
    Alcotest.(check bool) "blob" true
      (value_eq (row_lookup r "b") (S.Blob "\x00\x01\x02\xff"));
    Alcotest.(check bool) "null" true
      (value_eq (row_lookup r "n") S.Null);
    ignore (ok_exn (S.close db))
  end

(* ---------- named parameters ---------- *)

let test_named_params () =
  if need_sqlite () then begin
    let db = memdb () in
    exec db "CREATE TABLE n (a INTEGER, b TEXT)";
    execp db
      [ S.Named (":a", S.Int 7L); S.Named (":b", S.Text "seven") ]
      "INSERT INTO n VALUES (:a, :b)";
    let rows =
      ok_exn
        (S.query db
           ~params:[ S.Named ("@want", S.Int 7L) ]
           "SELECT b FROM n WHERE a = @want")
    in
    Alcotest.(check bool) "named select" true
      (value_eq (row_lookup (List.hd rows) "b") (S.Text "seven"));
    ignore (ok_exn (S.close db))
  end

(* ---------- transactions ---------- *)

let test_transaction_commit () =
  if need_sqlite () then begin
    let db = memdb () in
    exec db "CREATE TABLE tx (v INTEGER)";
    ok_exn
      (S.transaction db (fun () ->
           execp db [ S.Pos (S.Int 1L) ] "INSERT INTO tx VALUES (?)";
           execp db [ S.Pos (S.Int 2L) ] "INSERT INTO tx VALUES (?)";
           Ok ()));
    let rows = ok_exn (S.query db "SELECT v FROM tx ORDER BY v") in
    Alcotest.(check int) "committed rows" 2 (List.length rows);
    ignore (ok_exn (S.close db))
  end

let test_transaction_rollback () =
  if need_sqlite () then begin
    let db = memdb () in
    exec db "CREATE TABLE tx (v INTEGER)";
    let res =
      S.transaction db (fun () ->
          execp db [ S.Pos (S.Int 1L) ] "INSERT INTO tx VALUES (?)";
          Error "abort")
    in
    Alcotest.(check string) "abort surfaces" "abort" (err res);
    let rows = ok_exn (S.query db "SELECT v FROM tx") in
    Alcotest.(check int) "rolled back" 0 (List.length rows);
    ignore (ok_exn (S.close db))
  end

let test_transaction_exception_rollback () =
  if need_sqlite () then begin
    let db = memdb () in
    exec db "CREATE TABLE tx (v INTEGER)";
    let raised =
      try
        ignore
          (S.transaction db (fun () ->
               execp db [ S.Pos (S.Int 1L) ] "INSERT INTO tx VALUES (?)";
               failwith "boom"));
        false
      with Failure _ -> true
    in
    Alcotest.(check bool) "exception propagates" true raised;
    let rows = ok_exn (S.query db "SELECT v FROM tx") in
    Alcotest.(check int) "rolled back" 0 (List.length rows);
    ignore (ok_exn (S.close db))
  end

(* ---------- exec metadata ---------- *)

let test_changes_and_rowid () =
  if need_sqlite () then begin
    let db = memdb () in
    exec db "CREATE TABLE c (v INTEGER)";
    let r1 =
      ok_exn
        (S.exec db ~params:[ S.Pos (S.Int 10L) ]
           "INSERT INTO c VALUES (?)")
    in
    Alcotest.(check int) "changes 1" 1 r1.S.changes;
    Alcotest.(check bool) "rowid 1" true (Int64.equal r1.S.last_insert_id 1L);
    exec db "UPDATE c SET v = 11";
    Alcotest.(check int) "changes after update" 1 (S.changes db);
    ignore (ok_exn (S.close db))
  end

(* ---------- statement-shape guards ---------- *)

let test_guards () =
  if need_sqlite () then begin
    let db = memdb () in
    let multi = err (S.exec db "SELECT 1; SELECT 2") in
    Alcotest.(check bool) "multi statement rejected" true
      (String.length multi > 0);
    let txctl = err (S.exec db "BEGIN") in
    Alcotest.(check bool) "tx control rejected" true
      (String.length txctl > 0);
    ignore (ok_exn (S.close db))
  end

(* ---------- error surfacing ---------- *)

let test_error_surfacing () =
  if need_sqlite () then begin
    let db = memdb () in
    let syn = err (S.exec db "SELEC 1") in
    Alcotest.(check bool) "syntax error" true
      (String.length syn > 0);
    exec db "CREATE TABLE u (v TEXT UNIQUE)";
    execp db [ S.Pos (S.Text "x") ] "INSERT INTO u VALUES (?)";
    let con =
      err (S.exec db ~params:[ S.Pos (S.Text "x") ]
             "INSERT INTO u VALUES (?)")
    in
    Alcotest.(check bool) "constraint error" true
      (String.length con > 0);
    let missing = err (S.query db "SELECT * FROM nope") in
    Alcotest.(check bool) "missing table error" true
      (String.length missing > 0);
    ignore (ok_exn (S.close db))
  end

(* ---------- concurrent handles ---------- *)

let test_handle_independence () =
  if need_sqlite () then begin
    let a = memdb () and b = memdb () in
    exec a "CREATE TABLE only_a (v INTEGER)";
    execp a [ S.Pos (S.Int 1L) ] "INSERT INTO only_a VALUES (?)";
    let in_b = err (S.query b "SELECT v FROM only_a") in
    Alcotest.(check bool) "b cannot see a's table" true
      (String.length in_b > 0);
    let rows = ok_exn (S.query a "SELECT v FROM only_a") in
    Alcotest.(check int) "a keeps its data" 1 (List.length rows);
    ignore (ok_exn (S.close a));
    ignore (ok_exn (S.close b))
  end

(* ---------- file-backed db + WAL ---------- *)

let test_file_db_wal () =
  if need_sqlite () then begin
    let path = Filename.temp_file "lui-sqlite-test" ".db" in
    let db = ok_exn (S.open_db ~path ()) in
    let rows = ok_exn (S.query db "PRAGMA journal_mode") in
    let mode =
      match rows with
      | [ row ] ->
        (match row_lookup row "journal_mode" with
         | S.Text m -> m
         | _ -> "")
      | _ -> ""
    in
    Alcotest.(check string) "wal mode" "wal" (String.lowercase_ascii mode);
    exec db "CREATE TABLE f (v INTEGER)";
    ignore (ok_exn (S.close db));
    (* Reopen and verify persistence. *)
    let db2 = ok_exn (S.open_db ~path ()) in
    let rows2 = ok_exn (S.query db2 "SELECT v FROM f") in
    Alcotest.(check int) "file persisted" 0 (List.length rows2);
    ignore (ok_exn (S.close db2));
    List.iter
      (fun suffix -> try Sys.remove (path ^ suffix) with Sys_error _ -> ())
      [ ""; "-wal"; "-shm"; "-journal" ]
  end

(* ---------- JSON service round-trip ---------- *)

let call m arg = S.Plugin.call S.plugin m arg

let svc_ok = function
  | Ok s -> s
  | Error m -> failwith ("service: " ^ m)

let test_service_roundtrip () =
  if need_sqlite () then begin
    let p = S.plugin in
    Alcotest.(check string) "plugin name" "Sqlite" p.S.Plugin.name;
    ignore (ok_exn (p.S.Plugin.setup ()));
    (* open *)
    let opened =
      svc_ok (call "open" {|{"path": ":memory:", "id": "svc"}|})
    in
    let id =
      Yojson.Safe.from_string opened
      |> Yojson.Safe.Util.member "id" |> Yojson.Safe.Util.to_string
    in
    Alcotest.(check string) "open id" "svc" id;
    (* exec create *)
    ignore
      (svc_ok
         (call "exec"
            {|{"id": "svc", "sql": "CREATE TABLE s (i INTEGER, x TEXT)"}|}));
    (* exec insert with params *)
    let res =
      svc_ok
        (call "exec"
           {|{"id": "svc",
              "sql": "INSERT INTO s VALUES (?, ?)",
              "params": [ {"type": "integer", "integer": "42"},
                          {"type": "text", "text": "forty-two"} ]}|})
    in
    let changes =
      Yojson.Safe.from_string res
      |> Yojson.Safe.Util.member "changes"
      |> Yojson.Safe.Util.to_int
    in
    Alcotest.(check int) "insert changes" 1 changes;
    (* query *)
    let qres =
      svc_ok
        (call "query"
           {|{"id": "svc", "sql": "SELECT i, x FROM s WHERE i = ?",
              "params": [ {"type": "integer", "integer": "42"} ]}|})
    in
    let q = Yojson.Safe.from_string qres in
    let cols =
      Yojson.Safe.Util.member "columns" q
      |> Yojson.Safe.Util.to_list |> List.map Yojson.Safe.Util.to_string
    in
    Alcotest.(check (list string)) "columns" [ "i"; "x" ] cols;
    let rows =
      Yojson.Safe.Util.member "rows" q |> Yojson.Safe.Util.to_list
    in
    Alcotest.(check int) "row count" 1 (List.length rows);
    let row_i =
      Yojson.Safe.Util.member "i" (List.hd rows)
      |> Yojson.Safe.Util.member "integer" |> Yojson.Safe.Util.to_string
    in
    Alcotest.(check string) "row i" "42" row_i;
    (* batch: atomic inside a transaction *)
    let bres =
      svc_ok
        (call "batch"
           {|{"id": "svc",
              "statements": [ {"sql": "INSERT INTO s VALUES (?, ?)",
                               "params": [ {"type": "integer", "integer": "43"},
                                           {"type": "text", "text": "a"} ]},
                              {"sql": "INSERT INTO s VALUES (?, ?)",
                               "params": [ {"type": "integer", "integer": "44"},
                                           {"type": "text", "text": "b"} ]} ]}|})
    in
    let results =
      Yojson.Safe.from_string bres
      |> Yojson.Safe.Util.member "results" |> Yojson.Safe.Util.to_list
    in
    Alcotest.(check int) "batch results" 2 (List.length results);
    (* one bad statement rolls the whole batch back *)
    ignore
      (err
         (call "batch"
            {|{"id": "svc",
               "statements": [ {"sql": "INSERT INTO s VALUES (?, ?)",
                                "params": [ {"type": "integer", "integer": "45"},
                                            {"type": "text", "text": "c"} ]},
                               {"sql": "SELEC bogus"} ]}|}));
    let q45 =
      svc_ok
        (call "query"
           {|{"id": "svc",
              "sql": "SELECT i FROM s WHERE i = ?",
              "params": [ {"type": "integer", "integer": "45"} ]}|})
    in
    let n45 =
      Yojson.Safe.from_string q45
      |> Yojson.Safe.Util.member "rows" |> Yojson.Safe.Util.to_list
      |> List.length
    in
    Alcotest.(check int) "batch rolled back" 0 n45;
    (* pragma *)
    let pres =
      svc_ok (call "pragma" {|{"id": "svc", "name": "journal_mode"}|})
    in
    Alcotest.(check bool) "pragma ok" true (String.length pres > 0);
    (* errors surface through the service *)
    let e1 = err (call "exec" {|{"id": "svc", "sql": "SELEC 1"}|}) in
    Alcotest.(check bool) "service error" true (String.length e1 > 0);
    let e2 =
      err (call "query" {|{"id": "ghost", "sql": "SELECT 1"}|})
    in
    Alcotest.(check bool) "unknown handle error" true
      (String.length e2 > 0);
    (* close *)
    ignore (svc_ok (call "close" {|{"id": "svc"}|}));
    let e3 =
      err (call "exec" {|{"id": "svc", "sql": "SELECT 1"}|})
    in
    Alcotest.(check bool) "closed handle error" true
      (String.length e3 > 0);
    p.S.Plugin.teardown ()
  end

(* ---------- suite ---------- *)

let () =
  Alcotest.run "lui_plugin_sqlite"
    [ ( "basic",
        [ Alcotest.test_case "open/close memory" `Quick test_open_memory;
          Alcotest.test_case "typed values" `Quick test_typed_values;
          Alcotest.test_case "named params" `Quick test_named_params;
          Alcotest.test_case "changes + rowid" `Quick
            test_changes_and_rowid ] );
      ( "transactions",
        [ Alcotest.test_case "commit" `Quick test_transaction_commit;
          Alcotest.test_case "rollback" `Quick test_transaction_rollback;
          Alcotest.test_case "exception rollback" `Quick
            test_transaction_exception_rollback ] );
      ( "errors",
        [ Alcotest.test_case "statement guards" `Quick test_guards;
          Alcotest.test_case "error surfacing" `Quick
            test_error_surfacing ] );
      ( "isolation",
        [ Alcotest.test_case "handle independence" `Quick
            test_handle_independence;
          Alcotest.test_case "file db + wal" `Quick test_file_db_wal ] );
      ( "service",
        [ Alcotest.test_case "json round-trip" `Quick
            test_service_roundtrip ] ) ]
