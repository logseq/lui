/* SQLite C-API shim for lui_plugin_sqlite.

   The OCaml side owns all statement semantics; this file only carries
   values over the system SQLite library.  The library is resolved at
   run time with dlopen/dlsym (macOS, Linux) or LoadLibrary (Windows,
   winsqlite3.dll / sqlite3.dll) so the stub links and runs on machines
   without SQLite development headers; where no library can be found
   every entry point surfaces an error string to OCaml instead of
   failing to build.

   Handle safety: connections use close_v2, so an explicitly closed
   connection becomes a zombie that stays valid until its outstanding
   statements are finalized.  Statement finalizers may therefore run
   after the owning connection was closed.  `closed`/`finalized` flags
   make repeated close/finalize calls no-ops. */

#if defined(_WIN32)
#define LUI_SQ_WIN 1
#elif defined(__APPLE__) || defined(__linux__) || defined(__unix__)
#define LUI_SQ_POSIX 1
#else
#define LUI_SQ_NONE 1
#endif

#include <string.h>
#include <stdlib.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/custom.h>
#include <caml/intext.h>

#if defined(LUI_SQ_POSIX)

#include <dlfcn.h>
#include <pthread.h>

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

typedef struct {
  const char *(*libversion)(void);
  const char *(*errstr)(int);
  int (*open_v2)(const char *, sqlite3 **, int, const char *);
  int (*close_v2)(sqlite3 *);
  int (*exec)(sqlite3 *, const char *,
              int (*)(void *, int, char **, char **), void *, char **);
  void (*freep)(void *);
  const char *(*errmsg)(sqlite3 *);
  int (*errcode)(sqlite3 *);
  int (*prepare_v2)(sqlite3 *, const char *, int, sqlite3_stmt **,
                    const char **);
  int (*finalize)(sqlite3_stmt *);
  int (*step)(sqlite3_stmt *);
  int (*bind_param_index)(sqlite3_stmt *, const char *);
  int (*bind_null)(sqlite3_stmt *, int);
  int (*bind_i64)(sqlite3_stmt *, int, long long);
  int (*bind_dbl)(sqlite3_stmt *, int, double);
  int (*bind_text)(sqlite3_stmt *, int, const char *, int,
                   void (*)(void *));
  int (*bind_blob)(sqlite3_stmt *, int, const void *, int,
                   void (*)(void *));
  int (*column_count)(sqlite3_stmt *);
  const char *(*column_name)(sqlite3_stmt *, int);
  int (*column_type)(sqlite3_stmt *, int);
  long long (*column_i64)(sqlite3_stmt *, int);
  double (*column_dbl)(sqlite3_stmt *, int);
  const unsigned char *(*column_text)(sqlite3_stmt *, int);
  const void *(*column_blob)(sqlite3_stmt *, int);
  int (*column_bytes)(sqlite3_stmt *, int);
  long long (*last_rowid)(sqlite3 *);
  int (*changes)(sqlite3 *);
  int (*busy_timeout)(sqlite3 *, int);
} sq_api;

static sq_api sq;
static int sq_loaded = 0; /* 0 pending, 1 ok, -1 unavailable */
static char sq_load_error[192];

static int sym(void *h, const char *name, void **out)
{
  *out = dlsym(h, name);
  return *out != 0;
}

static int sq_resolve(void *h)
{
  int ok = 1;
  ok &= sym(h, "sqlite3_libversion", (void **)&sq.libversion);
  ok &= sym(h, "sqlite3_errstr", (void **)&sq.errstr);
  ok &= sym(h, "sqlite3_open_v2", (void **)&sq.open_v2);
  ok &= sym(h, "sqlite3_close_v2", (void **)&sq.close_v2);
  ok &= sym(h, "sqlite3_exec", (void **)&sq.exec);
  ok &= sym(h, "sqlite3_free", (void **)&sq.freep);
  ok &= sym(h, "sqlite3_errmsg", (void **)&sq.errmsg);
  ok &= sym(h, "sqlite3_errcode", (void **)&sq.errcode);
  ok &= sym(h, "sqlite3_prepare_v2", (void **)&sq.prepare_v2);
  ok &= sym(h, "sqlite3_finalize", (void **)&sq.finalize);
  ok &= sym(h, "sqlite3_step", (void **)&sq.step);
  ok &= sym(h, "sqlite3_bind_parameter_index",
            (void **)&sq.bind_param_index);
  ok &= sym(h, "sqlite3_bind_null", (void **)&sq.bind_null);
  ok &= sym(h, "sqlite3_bind_int64", (void **)&sq.bind_i64);
  ok &= sym(h, "sqlite3_bind_double", (void **)&sq.bind_dbl);
  ok &= sym(h, "sqlite3_bind_text", (void **)&sq.bind_text);
  ok &= sym(h, "sqlite3_bind_blob", (void **)&sq.bind_blob);
  ok &= sym(h, "sqlite3_column_count", (void **)&sq.column_count);
  ok &= sym(h, "sqlite3_column_name", (void **)&sq.column_name);
  ok &= sym(h, "sqlite3_column_type", (void **)&sq.column_type);
  ok &= sym(h, "sqlite3_column_int64", (void **)&sq.column_i64);
  ok &= sym(h, "sqlite3_column_double", (void **)&sq.column_dbl);
  ok &= sym(h, "sqlite3_column_text", (void **)&sq.column_text);
  ok &= sym(h, "sqlite3_column_blob", (void **)&sq.column_blob);
  ok &= sym(h, "sqlite3_column_bytes", (void **)&sq.column_bytes);
  ok &= sym(h, "sqlite3_last_insert_rowid", (void **)&sq.last_rowid);
  ok &= sym(h, "sqlite3_changes", (void **)&sq.changes);
  ok &= sym(h, "sqlite3_busy_timeout", (void **)&sq.busy_timeout);
  return ok;
}

static void sq_load_once(void)
{
#if defined(__APPLE__)
  static const char *names[] = {
    "libsqlite3.dylib", "libsqlite3.0.dylib",
    "/usr/lib/libsqlite3.dylib", "/usr/lib/libsqlite3.0.dylib", 0
  };
#else
  static const char *names[] = {
    "libsqlite3.so.0", "libsqlite3.so", "libsqlite3.so.1", 0
  };
#endif
  void *h = 0;
  const char *tried = names[0];
  int i;
  sq_loaded = -1;
  for (i = 0; names[i]; i++) {
    h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
    if (h) {
      tried = names[i];
      break;
    }
  }
  if (!h) {
    snprintf(sq_load_error, sizeof(sq_load_error),
             "sqlite: no system SQLite library found (tried %s)",
             names[0]);
    return;
  }
  if (!sq_resolve(h)) {
    snprintf(sq_load_error, sizeof(sq_load_error),
             "sqlite: %s is missing required symbols", tried);
    dlclose(h);
    return;
  }
  sq_loaded = 1;
}

static pthread_once_t sq_once = PTHREAD_ONCE_INIT;

static int sq_ensure(void)
{
  pthread_once(&sq_once, sq_load_once);
  return sq_loaded;
}

#elif defined(LUI_SQ_WIN)

#include <windows.h>

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

typedef const char *(*sq_cc_str_i)(int);
typedef const char *(*sq_cc_str_v)(void);
typedef int (*sq_open_t)(const char *, sqlite3 **, int,
                                   const char *);
typedef int (*sq_close_t)(sqlite3 *);
typedef int (*sq_exec_t)(sqlite3 *, const char *,
                                   int (*)(void *, int, char **, char **),
                                   void *, char **);
typedef void (*sq_free_t)(void *);
typedef const char *(*sq_errmsg_t)(sqlite3 *);
typedef int (*sq_errcode_t)(sqlite3 *);
typedef int (*sq_prep_t)(sqlite3 *, const char *, int,
                                   sqlite3_stmt **, const char **);
typedef int (*sq_fin_t)(sqlite3_stmt *);
typedef int (*sq_step_t)(sqlite3_stmt *);
typedef int (*sq_bidx_t)(sqlite3_stmt *, const char *);
typedef int (*sq_bnull_t)(sqlite3_stmt *, int);
typedef int (*sq_bi64_t)(sqlite3_stmt *, int, long long);
typedef int (*sq_bdbl_t)(sqlite3_stmt *, int, double);
typedef int (*sq_btext_t)(sqlite3_stmt *, int, const char *,
                                    int, void (*)(void *));
typedef int (*sq_cc_t)(sqlite3_stmt *);
typedef const char *(*sq_cname_t)(sqlite3_stmt *, int);
typedef int (*sq_ctype_t)(sqlite3_stmt *, int);
typedef long long (*sq_ci64_t)(sqlite3_stmt *, int);
typedef double (*sq_cdbl_t)(sqlite3_stmt *, int);
typedef const unsigned char *(*sq_ctext_t)(sqlite3_stmt *, int);
typedef const void *(*sq_cblob_t)(sqlite3_stmt *, int);
typedef int (*sq_cbytes_t)(sqlite3_stmt *, int);
typedef long long (*sq_rowid_t)(sqlite3 *);
typedef int (*sq_changes_t)(sqlite3 *);
typedef int (*sq_busy_t)(sqlite3 *, int);

typedef struct {
  sq_cc_str_v libversion;
  sq_cc_str_i errstr;
  sq_open_t open_v2;
  sq_close_t close_v2;
  sq_exec_t exec;
  sq_free_t freep;
  sq_errmsg_t errmsg;
  sq_errcode_t errcode;
  sq_prep_t prepare_v2;
  sq_fin_t finalize;
  sq_step_t step;
  sq_bidx_t bind_param_index;
  sq_bnull_t bind_null;
  sq_bi64_t bind_i64;
  sq_bdbl_t bind_dbl;
  sq_btext_t bind_text;
  sq_btext_t bind_blob;
  sq_cc_t column_count;
  sq_cname_t column_name;
  sq_ctype_t column_type;
  sq_ci64_t column_i64;
  sq_cdbl_t column_dbl;
  sq_ctext_t column_text;
  sq_cblob_t column_blob;
  sq_cbytes_t column_bytes;
  sq_rowid_t last_rowid;
  sq_changes_t changes;
  sq_busy_t busy_timeout;
} sq_api;

static sq_api sq;
static int sq_loaded = 0;
static char sq_load_error[192];

static int wsym(HMODULE h, const char *name, void **out)
{
  *out = (void *)GetProcAddress(h, name);
  return *out != 0;
}

static BOOL CALLBACK sq_init_once(PINIT_ONCE once, PVOID param,
                                  PVOID *ctx)
{
  static const char *names[] = { "winsqlite3.dll", "sqlite3.dll", 0 };
  HMODULE h = 0;
  const char *tried = names[0];
  int i, ok = 1;
  (void)once; (void)param; (void)ctx;
  sq_loaded = -1;
  for (i = 0; names[i]; i++) {
    h = LoadLibraryA(names[i]);
    if (h) { tried = names[i]; break; }
  }
  if (!h) {
    snprintf(sq_load_error, sizeof(sq_load_error),
             "sqlite: no system SQLite library found (tried %s)",
             names[0]);
    return TRUE;
  }
#define LUI_WSYM(field, name) ok &= wsym(h, name, (void **)&sq.field)
  LUI_WSYM(libversion, "sqlite3_libversion");
  LUI_WSYM(errstr, "sqlite3_errstr");
  LUI_WSYM(open_v2, "sqlite3_open_v2");
  LUI_WSYM(close_v2, "sqlite3_close_v2");
  LUI_WSYM(exec, "sqlite3_exec");
  LUI_WSYM(freep, "sqlite3_free");
  LUI_WSYM(errmsg, "sqlite3_errmsg");
  LUI_WSYM(errcode, "sqlite3_errcode");
  LUI_WSYM(prepare_v2, "sqlite3_prepare_v2");
  LUI_WSYM(finalize, "sqlite3_finalize");
  LUI_WSYM(step, "sqlite3_step");
  LUI_WSYM(bind_param_index, "sqlite3_bind_parameter_index");
  LUI_WSYM(bind_null, "sqlite3_bind_null");
  LUI_WSYM(bind_i64, "sqlite3_bind_int64");
  LUI_WSYM(bind_dbl, "sqlite3_bind_double");
  LUI_WSYM(bind_text, "sqlite3_bind_text");
  LUI_WSYM(bind_blob, "sqlite3_bind_blob");
  LUI_WSYM(column_count, "sqlite3_column_count");
  LUI_WSYM(column_name, "sqlite3_column_name");
  LUI_WSYM(column_type, "sqlite3_column_type");
  LUI_WSYM(column_i64, "sqlite3_column_int64");
  LUI_WSYM(column_dbl, "sqlite3_column_double");
  LUI_WSYM(column_text, "sqlite3_column_text");
  LUI_WSYM(column_blob, "sqlite3_column_blob");
  LUI_WSYM(column_bytes, "sqlite3_column_bytes");
  LUI_WSYM(last_rowid, "sqlite3_last_insert_rowid");
  LUI_WSYM(changes, "sqlite3_changes");
  LUI_WSYM(busy_timeout, "sqlite3_busy_timeout");
#undef LUI_WSYM
  if (!ok) {
    snprintf(sq_load_error, sizeof(sq_load_error),
             "sqlite: %s is missing required symbols", tried);
    FreeLibrary(h);
    return TRUE;
  }
  sq_loaded = 1;
  return TRUE;
}

static INIT_ONCE sq_once = INIT_ONCE_STATIC_INIT;

static int sq_ensure(void)
{
  InitOnceExecuteOnce(&sq_once, sq_init_once, 0, 0);
  return sq_loaded;
}

#endif /* platform selection */

/* ---- Shared handle plumbing (compiled only where a loader exists) -- */

#if defined(LUI_SQ_POSIX) || defined(LUI_SQ_WIN)

#define SQLITE_ROW 100
#define SQLITE_DONE 101
#define SQLITE_TRANSIENT ((void (*)(void *)) - 1)

struct db_cell {
  sqlite3 *h;
  int closed;
};

struct stmt_cell {
  sqlite3_stmt *st;
  sqlite3 *db;
  int finalized;
};

#define Db_val(v) ((struct db_cell *)Data_custom_val(v))
#define Stmt_val(v) ((struct stmt_cell *)Data_custom_val(v))

static void db_finalize(value v)
{
  struct db_cell *c = Db_val(v);
  if (c->h && !c->closed) {
    sq.close_v2(c->h);
  }
  c->h = 0;
  c->closed = 1;
}

static void stmt_finalize(value v)
{
  struct stmt_cell *c = Stmt_val(v);
  if (c->st && !c->finalized) {
    sq.finalize(c->st);
  }
  c->st = 0;
  c->finalized = 1;
}

static struct custom_operations db_ops = {
  "lui.sqlite.db",
  db_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static struct custom_operations stmt_ops = {
  "lui.sqlite.stmt",
  stmt_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static value sq_ok(value x)
{
  CAMLparam1(x);
  CAMLlocal1(r);
  r = caml_alloc(1, 0);
  Store_field(r, 0, x);
  CAMLreturn(r);
}

static value sq_err_msg(const char *msg, int code)
{
  CAMLparam0();
  CAMLlocal2(s, r);
  char buf[512];
  snprintf(buf, sizeof(buf), "sqlite: %s (code %d)", msg, code);
  s = caml_copy_string(buf);
  r = caml_alloc(1, 1);
  Store_field(r, 0, s);
  CAMLreturn(r);
}

static value sq_err_str(const char *msg)
{
  CAMLparam0();
  CAMLlocal2(s, r);
  s = caml_copy_string(msg);
  r = caml_alloc(1, 1);
  Store_field(r, 0, s);
  CAMLreturn(r);
}

static value sq_unavailable(void)
{
  if (sq_load_error[0])
    return sq_err_str(sq_load_error);
  return sq_err_str("sqlite: system SQLite library unavailable");
}

CAMLprim value lui_sq_probe(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_int(sq_ensure() == 1));
}

CAMLprim value lui_sq_load_error(value unit)
{
  CAMLparam1(unit);
  if (sq_ensure() == 1 || !sq_load_error[0])
    CAMLreturn(caml_copy_string(""));
  CAMLreturn(caml_copy_string(sq_load_error));
}

CAMLprim value lui_sq_version(value unit)
{
  CAMLparam1(unit);
  if (sq_ensure() != 1)
    CAMLreturn(caml_copy_string(""));
  CAMLreturn(caml_copy_string(sq.libversion()));
}

CAMLprim value lui_sq_open(value path, value flags)
{
  CAMLparam2(path, flags);
  CAMLlocal2(v, r);
  sqlite3 *h = 0;
  int rc;
  struct db_cell *c;
  if (sq_ensure() != 1)
    CAMLreturn(sq_unavailable());
  rc = sq.open_v2(String_val(path), &h, Int_val(flags), 0);
  if (rc != 0) {
    const char *m = h ? sq.errmsg(h) : sq.errstr(rc);
    if (h)
      sq.close_v2(h);
    CAMLreturn(sq_err_msg(m ? m : "open failed", rc));
  }
  v = caml_alloc_custom(&db_ops, sizeof(struct db_cell), 0, 1);
  c = Db_val(v);
  c->h = h;
  c->closed = 0;
  r = sq_ok(v);
  CAMLreturn(r);
}

CAMLprim value lui_sq_close(value db)
{
  CAMLparam1(db);
  struct db_cell *c = Db_val(db);
  int rc;
  if (!c->h || c->closed)
    CAMLreturn(sq_ok(Val_unit));
  rc = sq.close_v2(c->h);
  c->closed = 1;
  if (rc != 0)
    CAMLreturn(sq_err_msg(sq.errstr(rc), rc));
  CAMLreturn(sq_ok(Val_unit));
}

CAMLprim value lui_sq_prepare(value db, value sql)
{
  CAMLparam2(db, sql);
  CAMLlocal2(v, r);
  struct db_cell *c = Db_val(db);
  sqlite3_stmt *st = 0;
  const char *tail = 0;
  const char *p;
  int rc;
  if (sq_ensure() != 1)
    CAMLreturn(sq_unavailable());
  if (!c->h || c->closed)
    CAMLreturn(sq_err_str("sqlite: database is closed"));
  rc = sq.prepare_v2(c->h, String_val(sql), -1, &st, &tail);
  if (rc != 0)
    CAMLreturn(sq_err_msg(sq.errmsg(c->h), rc));
  if (!st)
    CAMLreturn(sq_err_str("sqlite: empty statement"));
  if (tail) {
    p = tail;
    while (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' ||
           *p == ';')
      p++;
    if (*p) {
      sq.finalize(st);
      CAMLreturn(sq_err_str(
          "sqlite: a single statement per call is required"));
    }
  }
  v = caml_alloc_custom(&stmt_ops, sizeof(struct stmt_cell), 0, 1);
  {
    struct stmt_cell *s = Stmt_val(v);
    s->st = st;
    s->db = c->h;
    s->finalized = 0;
  }
  r = sq_ok(v);
  CAMLreturn(r);
}

CAMLprim value lui_sq_finalize(value stmt)
{
  CAMLparam1(stmt);
  struct stmt_cell *s = Stmt_val(stmt);
  int rc = 0;
  if (!s->st || s->finalized)
    CAMLreturn(sq_ok(Val_unit));
  rc = sq.finalize(s->st);
  s->finalized = 1;
  s->st = 0;
  if (rc != 0 && rc != SQLITE_DONE)
    CAMLreturn(sq_err_msg(sq.errstr(rc), rc));
  CAMLreturn(sq_ok(Val_unit));
}

static int stmt_check(value stmt)
{
  struct stmt_cell *s = Stmt_val(stmt);
  return s->st && !s->finalized;
}

static value bind_result(struct stmt_cell *s, int rc)
{
  CAMLparam0();
  if (rc != 0)
    CAMLreturn(sq_err_msg(sq.errmsg(s->db), rc));
  CAMLreturn(sq_ok(Val_unit));
}

CAMLprim value lui_sq_bind_index(value stmt, value name)
{
  CAMLparam2(stmt, name);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(Val_int(0));
  CAMLreturn(Val_int(sq.bind_param_index(s->st, String_val(name))));
}

CAMLprim value lui_sq_bind_null(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(sq_err_str("sqlite: statement is finalized"));
  CAMLreturn(bind_result(s, sq.bind_null(s->st, Int_val(idx))));
}

CAMLprim value lui_sq_bind_i64(value stmt, value idx, value x)
{
  CAMLparam3(stmt, idx, x);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(sq_err_str("sqlite: statement is finalized"));
  CAMLreturn(
      bind_result(s, sq.bind_i64(s->st, Int_val(idx), Int64_val(x))));
}

CAMLprim value lui_sq_bind_double(value stmt, value idx, value x)
{
  CAMLparam3(stmt, idx, x);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(sq_err_str("sqlite: statement is finalized"));
  CAMLreturn(
      bind_result(s, sq.bind_dbl(s->st, Int_val(idx), Double_val(x))));
}

CAMLprim value lui_sq_bind_text(value stmt, value idx, value x)
{
  CAMLparam3(stmt, idx, x);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(sq_err_str("sqlite: statement is finalized"));
  CAMLreturn(bind_result(
      s, sq.bind_text(s->st, Int_val(idx), String_val(x),
                      caml_string_length(x), SQLITE_TRANSIENT)));
}

CAMLprim value lui_sq_bind_blob(value stmt, value idx, value x)
{
  CAMLparam3(stmt, idx, x);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(sq_err_str("sqlite: statement is finalized"));
  CAMLreturn(bind_result(
      s, sq.bind_blob(s->st, Int_val(idx), Bytes_val(x),
                      caml_string_length(x), SQLITE_TRANSIENT)));
}

CAMLprim value lui_sq_step(value stmt)
{
  CAMLparam1(stmt);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(Val_int(-1));
  CAMLreturn(Val_int(sq.step(s->st)));
}

CAMLprim value lui_sq_stmt_errcode(value stmt)
{
  CAMLparam1(stmt);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!s->db)
    CAMLreturn(Val_int(0));
  CAMLreturn(Val_int(sq.errcode(s->db)));
}

CAMLprim value lui_sq_stmt_errmsg(value stmt)
{
  CAMLparam1(stmt);
  struct stmt_cell *s = Stmt_val(stmt);
  const char *m;
  if (!s->db)
    CAMLreturn(caml_copy_string("sqlite: statement is finalized"));
  m = sq.errmsg(s->db);
  CAMLreturn(caml_copy_string(m ? m : "unknown error"));
}

CAMLprim value lui_sq_column_count(value stmt)
{
  CAMLparam1(stmt);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(Val_int(0));
  CAMLreturn(Val_int(sq.column_count(s->st)));
}

CAMLprim value lui_sq_column_name(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  struct stmt_cell *s = Stmt_val(stmt);
  const char *n;
  if (!stmt_check(stmt))
    CAMLreturn(caml_copy_string(""));
  n = sq.column_name(s->st, Int_val(idx));
  CAMLreturn(caml_copy_string(n ? n : ""));
}

CAMLprim value lui_sq_column_type(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(Val_int(5));
  CAMLreturn(Val_int(sq.column_type(s->st, Int_val(idx))));
}

CAMLprim value lui_sq_column_i64(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(caml_copy_int64(0));
  CAMLreturn(caml_copy_int64(sq.column_i64(s->st, Int_val(idx))));
}

CAMLprim value lui_sq_column_double(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  struct stmt_cell *s = Stmt_val(stmt);
  if (!stmt_check(stmt))
    CAMLreturn(caml_copy_double(0.));
  CAMLreturn(caml_copy_double(sq.column_dbl(s->st, Int_val(idx))));
}

CAMLprim value lui_sq_column_text(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLlocal1(s);
  struct stmt_cell *c = Stmt_val(stmt);
  const unsigned char *t;
  int n;
  if (!stmt_check(stmt))
    CAMLreturn(caml_copy_string(""));
  t = sq.column_text(c->st, Int_val(idx));
  n = sq.column_bytes(c->st, Int_val(idx));
  if (!t || n <= 0)
    CAMLreturn(caml_copy_string(""));
  s = caml_alloc_string(n);
  memcpy(Bytes_val(s), t, n);
  CAMLreturn(s);
}

CAMLprim value lui_sq_column_blob(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLlocal1(s);
  struct stmt_cell *c = Stmt_val(stmt);
  const void *b;
  int n;
  if (!stmt_check(stmt))
    CAMLreturn(caml_copy_string(""));
  b = sq.column_blob(c->st, Int_val(idx));
  n = sq.column_bytes(c->st, Int_val(idx));
  if (!b || n <= 0)
    CAMLreturn(caml_copy_string(""));
  s = caml_alloc_string(n);
  memcpy(Bytes_val(s), b, n);
  CAMLreturn(s);
}

CAMLprim value lui_sq_exec(value db, value sql)
{
  CAMLparam2(db, sql);
  CAMLlocal2(s, r);
  struct db_cell *c = Db_val(db);
  char *emsg = 0;
  int rc;
  if (sq_ensure() != 1)
    CAMLreturn(sq_unavailable());
  if (!c->h || c->closed)
    CAMLreturn(sq_err_str("sqlite: database is closed"));
  rc = sq.exec(c->h, String_val(sql), 0, 0, &emsg);
  if (rc != 0) {
    const char *m = emsg ? emsg : sq.errmsg(c->h);
    s = caml_copy_string(m ? m : "exec failed");
    if (emsg)
      sq.freep(emsg);
    r = caml_alloc(1, 1);
    Store_field(r, 0, s);
    CAMLreturn(r);
  }
  CAMLreturn(sq_ok(Val_unit));
}

CAMLprim value lui_sq_errcode(value db)
{
  CAMLparam1(db);
  struct db_cell *c = Db_val(db);
  if (!c->h)
    CAMLreturn(Val_int(0));
  CAMLreturn(Val_int(sq.errcode(c->h)));
}

CAMLprim value lui_sq_last_rowid(value db)
{
  CAMLparam1(db);
  struct db_cell *c = Db_val(db);
  if (!c->h)
    CAMLreturn(caml_copy_int64(0));
  CAMLreturn(caml_copy_int64(sq.last_rowid(c->h)));
}

CAMLprim value lui_sq_changes(value db)
{
  CAMLparam1(db);
  struct db_cell *c = Db_val(db);
  if (!c->h)
    CAMLreturn(Val_int(0));
  CAMLreturn(Val_int(sq.changes(c->h)));
}

CAMLprim value lui_sq_busy_timeout(value db, value ms)
{
  CAMLparam2(db, ms);
  struct db_cell *c = Db_val(db);
  int rc;
  if (sq_ensure() != 1)
    CAMLreturn(sq_unavailable());
  if (!c->h || c->closed)
    CAMLreturn(sq_err_str("sqlite: database is closed"));
  rc = sq.busy_timeout(c->h, Int_val(ms));
  if (rc != 0)
    CAMLreturn(sq_err_msg(sq.errmsg(c->h), rc));
  CAMLreturn(sq_ok(Val_unit));
}

#else /* LUI_SQ_NONE: stub-fail branch for unsupported platforms */

static value sq_fail(void)
{
  CAMLparam0();
  CAMLlocal2(s, r);
  s = caml_copy_string("sqlite: unsupported platform");
  r = caml_alloc(1, 1);
  Store_field(r, 0, s);
  CAMLreturn(r);
}

CAMLprim value lui_sq_probe(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_int(0));
}

CAMLprim value lui_sq_load_error(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(caml_copy_string("sqlite: unsupported platform"));
}

CAMLprim value lui_sq_version(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_sq_open(value path, value flags)
{
  (void)path; (void)flags;
  return sq_fail();
}

CAMLprim value lui_sq_close(value db)
{
  (void)db;
  return sq_fail();
}

CAMLprim value lui_sq_prepare(value db, value sql)
{
  (void)db; (void)sql;
  return sq_fail();
}

CAMLprim value lui_sq_finalize(value stmt)
{
  (void)stmt;
  return sq_fail();
}

CAMLprim value lui_sq_bind_index(value stmt, value name)
{
  (void)stmt; (void)name;
  return Val_int(0);
}

CAMLprim value lui_sq_bind_null(value stmt, value idx)
{
  (void)stmt; (void)idx;
  return sq_fail();
}

CAMLprim value lui_sq_bind_i64(value stmt, value idx, value x)
{
  (void)stmt; (void)idx; (void)x;
  return sq_fail();
}

CAMLprim value lui_sq_bind_double(value stmt, value idx, value x)
{
  (void)stmt; (void)idx; (void)x;
  return sq_fail();
}

CAMLprim value lui_sq_bind_text(value stmt, value idx, value x)
{
  (void)stmt; (void)idx; (void)x;
  return sq_fail();
}

CAMLprim value lui_sq_bind_blob(value stmt, value idx, value x)
{
  (void)stmt; (void)idx; (void)x;
  return sq_fail();
}

CAMLprim value lui_sq_step(value stmt)
{
  (void)stmt;
  return Val_int(-1);
}

CAMLprim value lui_sq_stmt_errcode(value stmt)
{
  (void)stmt;
  return Val_int(0);
}

CAMLprim value lui_sq_stmt_errmsg(value stmt)
{
  CAMLparam1(stmt);
  CAMLreturn(caml_copy_string("sqlite: unsupported platform"));
}

CAMLprim value lui_sq_column_count(value stmt)
{
  (void)stmt;
  return Val_int(0);
}

CAMLprim value lui_sq_column_name(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_sq_column_type(value stmt, value idx)
{
  (void)stmt; (void)idx;
  return Val_int(5);
}

CAMLprim value lui_sq_column_i64(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLreturn(caml_copy_int64(0));
}

CAMLprim value lui_sq_column_double(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLreturn(caml_copy_double(0.));
}

CAMLprim value lui_sq_column_text(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_sq_column_blob(value stmt, value idx)
{
  CAMLparam2(stmt, idx);
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_sq_exec(value db, value sql)
{
  (void)db; (void)sql;
  return sq_fail();
}

CAMLprim value lui_sq_errcode(value db)
{
  (void)db;
  return Val_int(0);
}

CAMLprim value lui_sq_last_rowid(value db)
{
  CAMLparam1(db);
  CAMLreturn(caml_copy_int64(0));
}

CAMLprim value lui_sq_changes(value db)
{
  (void)db;
  return Val_int(0);
}

CAMLprim value lui_sq_busy_timeout(value db, value ms)
{
  (void)db; (void)ms;
  return sq_fail();
}

#endif
