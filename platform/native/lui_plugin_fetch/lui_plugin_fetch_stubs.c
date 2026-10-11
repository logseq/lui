/* HTTP transport for lui_plugin_fetch over the platform libcurl.

   libcurl is resolved at runtime with dlopen/dlsym — the same pattern
   as the other native stubs — so this file links and runs on machines
   without curl development headers. The declarations needed are
   self-contained below; the easy interface is ABI-stable.

   The OCaml call carries a flat argument list and receives a flat
   5-tuple back (ok, status, error, raw_headers, body); all JSON
   semantics live on the OCaml side. On platforms without a known
   libcurl name the externals fail with
   "lui_plugin_fetch: not supported on this platform". */

#if defined(__APPLE__) || defined(__linux__)

#include <string.h>
#include <stdlib.h>
#include <dlfcn.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/threads.h>

/* ---- Minimal libcurl declarations (no headers required) ---- */

typedef void CURL;
typedef int CURLcode;
struct curl_slist {
  char *data;
  struct curl_slist *next;
};

/* CURLOPT encoding: (type << 0) style constants, stable ABI. */
#define LUI_CURLOPT_WRITEDATA      10001
#define LUI_CURLOPT_URL            10002
#define LUI_CURLOPT_ERRORBUFFER    10010
#define LUI_CURLOPT_WRITEFUNCTION  20011
#define LUI_CURLOPT_POSTFIELDS     10015
#define LUI_CURLOPT_USERAGENT      10018
#define LUI_CURLOPT_HTTPHEADER     10023
#define LUI_CURLOPT_HEADERDATA     10029
#define LUI_CURLOPT_HEADERFUNCTION 20079
#define LUI_CURLOPT_CUSTOMREQUEST  10036
#define LUI_CURLOPT_FOLLOWLOCATION 52
#define LUI_CURLOPT_POSTFIELDSIZE  60
#define LUI_CURLOPT_MAXREDIRS      68
#define LUI_CURLOPT_NOSIGNAL       99
#define LUI_CURLOPT_TIMEOUT_MS     155
#define LUI_CURLOPT_CONNECTTIMEOUT_MS 156

/* CURLINFO_LONG | 2 */
#define LUI_CURLINFO_RESPONSE_CODE 0x200002

static CURL *(*p_curl_easy_init)(void) = 0;
static CURLcode (*p_curl_easy_setopt)(CURL *, int, ...) = 0;
static CURLcode (*p_curl_easy_perform)(CURL *) = 0;
static CURLcode (*p_curl_easy_getinfo)(CURL *, int, ...) = 0;
static const char *(*p_curl_easy_strerror)(CURLcode) = 0;
static void (*p_curl_easy_cleanup)(CURL *) = 0;
static struct curl_slist *(*p_curl_slist_append)(struct curl_slist *,
                                                const char *) = 0;
static void (*p_curl_slist_free_all)(struct curl_slist *) = 0;

/* 0 = not tried, 1 = usable, -1 = absent */
static int curl_state = 0;

static int sym(void *h, const char *name, void **out)
{
  *out = dlsym(h, name);
  return *out != 0;
}

static int curl_resolve(void)
{
  if (curl_state != 0) return curl_state;
  curl_state = -1;
  static const char *names[] = {
#if defined(__APPLE__)
    "libcurl.4.dylib", "libcurl.dylib", "/usr/lib/libcurl.dylib",
#else
    "libcurl.so.4", "libcurl.so",
#endif
    0
  };
  void *h = 0;
  for (int i = 0; names[i] && !h; i++)
    h = dlopen(names[i], RTLD_NOW | RTLD_LOCAL);
  if (!h) return -1;
  int ok = 1;
  ok &= sym(h, "curl_easy_init", (void **)&p_curl_easy_init);
  ok &= sym(h, "curl_easy_setopt", (void **)&p_curl_easy_setopt);
  ok &= sym(h, "curl_easy_perform", (void **)&p_curl_easy_perform);
  ok &= sym(h, "curl_easy_getinfo", (void **)&p_curl_easy_getinfo);
  ok &= sym(h, "curl_easy_strerror", (void **)&p_curl_easy_strerror);
  ok &= sym(h, "curl_easy_cleanup", (void **)&p_curl_easy_cleanup);
  ok &= sym(h, "curl_slist_append", (void **)&p_curl_slist_append);
  ok &= sym(h, "curl_slist_free_all", (void **)&p_curl_slist_free_all);
  curl_state = ok ? 1 : -1;
  return curl_state;
}

CAMLprim value lui_fetch_available(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_bool(curl_resolve() == 1));
}

/* ---- Response accumulators ---- */

struct buf {
  char *p;
  size_t len;
  size_t cap;
  int oom;
};

static size_t buf_cb(char *ptr, size_t size, size_t nmemb, void *ud)
{
  struct buf *b = (struct buf *)ud;
  size_t n = size * nmemb;
  if (b->oom) return 0;
  if (b->len + n > b->cap) {
    size_t cap = b->cap ? b->cap : 8192;
    while (cap < b->len + n) cap *= 2;
    char *q = (char *)realloc(b->p, cap);
    if (!q) {
      b->oom = 1;
      return 0; /* aborts the transfer with CURLE_WRITE_ERROR */
    }
    b->p = q;
    b->cap = cap;
  }
  memcpy(b->p + b->len, ptr, n);
  b->len += n;
  return n;
}

static value take_buf(struct buf *b)
{
  value v = caml_alloc_initialized_string((mlsize_t)b->len, b->p ? b->p : "");
  free(b->p);
  b->p = 0;
  b->len = b->cap = 0;
  return v;
}

/* lui_fetch_perform url method headers body follow maxredirs timeout_ms
   -> (ok, status, error, raw_headers, body) */
static value perform_impl(value v_url, value v_method, value v_headers,
                          value v_body, value v_follow, value v_maxredirs,
                          value v_timeout)
{
  CAMLparam5(v_url, v_method, v_headers, v_body, v_follow);
  CAMLxparam2(v_maxredirs, v_timeout);
  CAMLlocal3(v_err, v_hraw, v_resp);

  if (curl_resolve() != 1)
    caml_failwith("lui_plugin_fetch: libcurl not available");

  CURL *c = p_curl_easy_init();
  if (!c) caml_failwith("lui_plugin_fetch: curl_easy_init failed");

  char errbuf[256];
  errbuf[0] = '\0';
  struct buf body = {0, 0, 0, 0};
  struct buf heads = {0, 0, 0, 0};

  p_curl_easy_setopt(c, LUI_CURLOPT_ERRORBUFFER, errbuf);
  p_curl_easy_setopt(c, LUI_CURLOPT_URL, String_val(v_url));
  p_curl_easy_setopt(c, LUI_CURLOPT_CUSTOMREQUEST, String_val(v_method));
  p_curl_easy_setopt(c, LUI_CURLOPT_WRITEFUNCTION, buf_cb);
  p_curl_easy_setopt(c, LUI_CURLOPT_WRITEDATA, &body);
  p_curl_easy_setopt(c, LUI_CURLOPT_HEADERFUNCTION, buf_cb);
  p_curl_easy_setopt(c, LUI_CURLOPT_HEADERDATA, &heads);
  p_curl_easy_setopt(c, LUI_CURLOPT_NOSIGNAL, 1L);
  p_curl_easy_setopt(c, LUI_CURLOPT_USERAGENT, "lui-plugin-fetch/1");
  p_curl_easy_setopt(c, LUI_CURLOPT_FOLLOWLOCATION,
                     Long_val(v_follow) ? 1L : 0L);
  p_curl_easy_setopt(c, LUI_CURLOPT_MAXREDIRS, Long_val(v_maxredirs));
  long timeout_ms = Long_val(v_timeout);
  if (timeout_ms > 0) {
    p_curl_easy_setopt(c, LUI_CURLOPT_TIMEOUT_MS, timeout_ms);
    p_curl_easy_setopt(c, LUI_CURLOPT_CONNECTTIMEOUT_MS, timeout_ms);
  }
  mlsize_t blen = caml_string_length(v_body);
  if (blen > 0) {
    /* POSTFIELDS is NUL-terminated for curl's purposes; the explicit
       size keeps binary bodies intact. */
    p_curl_easy_setopt(c, LUI_CURLOPT_POSTFIELDS, String_val(v_body));
    p_curl_easy_setopt(c, LUI_CURLOPT_POSTFIELDSIZE, (long)blen);
  }
  mlsize_t nh = Wosize_val(v_headers);
  struct curl_slist *hl = 0;
  for (mlsize_t i = 0; i < nh; i++)
    hl = p_curl_slist_append(hl, String_val(Field(v_headers, i)));
  if (hl) p_curl_easy_setopt(c, LUI_CURLOPT_HTTPHEADER, hl);

  caml_release_runtime_system();
  CURLcode rc = p_curl_easy_perform(c);
  caml_acquire_runtime_system();

  long status = 0;
  p_curl_easy_getinfo(c, LUI_CURLINFO_RESPONSE_CODE, &status);
  p_curl_easy_cleanup(c);
  if (hl) p_curl_slist_free_all(hl);

  int ok = (rc == 0 && !body.oom && !heads.oom);
  if (body.oom || heads.oom) {
    v_err = caml_copy_string("lui_plugin_fetch: out of memory");
  } else if (rc != 0) {
    const char *m = errbuf[0] ? errbuf : p_curl_easy_strerror(rc);
    v_err = caml_copy_string(m);
  } else {
    v_err = caml_copy_string("");
  }
  v_hraw = take_buf(&heads);

  /* Body ownership moves into the tuple on success only. */
  value v_body_out = take_buf(&body);

  v_resp = caml_alloc_tuple(5);
  Store_field(v_resp, 0, Val_bool(ok));
  Store_field(v_resp, 1, Val_long(status));
  Store_field(v_resp, 2, v_err);
  Store_field(v_resp, 3, v_hraw);
  Store_field(v_resp, 4, v_body_out);
  CAMLreturn(v_resp);
}

CAMLprim value lui_fetch_perform(value v_url, value v_method,
                                 value v_headers, value v_body,
                                 value v_follow, value v_maxredirs,
                                 value v_timeout)
{
  return perform_impl(v_url, v_method, v_headers, v_body, v_follow,
                      v_maxredirs, v_timeout);
}

CAMLprim value lui_fetch_perform_bc(value *argv, int argn)
{
  (void)argn;
  return perform_impl(argv[0], argv[1], argv[2], argv[3], argv[4],
                      argv[5], argv[6]);
}

#else /* !(defined(__APPLE__) || defined(__linux__)) */

#include <caml/mlvalues.h>
#include <caml/fail.h>
#include <caml/alloc.h>

static value fetch_fail(void)
{
  caml_failwith("lui_plugin_fetch: not supported on this platform");
  return Val_unit;
}

CAMLprim value lui_fetch_available(value a)
{
  (void)a;
  return Val_bool(0);
}

CAMLprim value lui_fetch_perform(value a, value b, value c, value d,
                                 value e, value f, value g)
{
  (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
  return fetch_fail();
}

CAMLprim value lui_fetch_perform_bc(value *argv, int argn)
{
  (void)argv; (void)argn;
  return fetch_fail();
}

#endif
