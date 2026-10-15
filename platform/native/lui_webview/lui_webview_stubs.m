/* Native web view stubs for lui_webview.
 *
 * One C ABI on every platform, implemented by the platform's own web
 * engine:
 *   macOS   WKWebView inside a flipped NSView container added to the
 *           host NSWindow's contentView (compiled as Objective-C
 *           under ARC).
 *   Linux   WebKitGTK bound through dlopen — no GTK/WebKit dev
 *           packages are needed to compile; the GTK window is
 *           reparented into the host's X11 window id (X11 only;
 *           Wayland hosts can run SDL through XWayland).
 *   Windows WebView2 bound through LoadLibrary + minimal COM vtables —
 *           no SDK headers needed; the controller is parented to the
 *           host HWND.
 *
 * Engines report asynchronously: navigation events, script results and
 * script messages are pushed onto a per-view queue drained by
 * [lui_wv_next_event] into OCaml. Event tags: 0 navigate, 1 commit,
 * 2 finish, 3 load error (url, msg), 4 async-eval result (token, json),
 * 5 script message.
 */

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/mlvalues.h>

#if defined(__APPLE__)
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#endif

#if defined(__has_include)
# if __has_include(<SDL.h>) && __has_include(<SDL_syswm.h>)
#  define LUI_WV_SDL 1
# endif
#endif
#ifdef LUI_WV_SDL
# include <SDL.h>
# include <SDL_syswm.h>
#endif

/* ------------------------------------------------------- event queue */

typedef struct lui_wv_ev {
  int tag;
  char *a;
  char *b;
  struct lui_wv_ev *next;
} lui_wv_ev;

/* Lifetime + event-queue sentinel. Engine callbacks (navigation
   delegates, JS completion blocks, signal handlers) may fire after
   the owning LuiWv has been destroyed; they capture this cell instead
   of the LuiWv pointer so they can drop events once `dead` is set.
   The cell is intentionally never freed — one small allocation per
   view lifetime — because there is no reliable way to count the
   engine's outstanding callbacks. */
typedef struct LuiWvCore {
  int dead;
  int loading, ready, failed;
  int cap_done, cap_fail;
  lui_wv_ev *head, *tail;
} LuiWvCore;

typedef struct LuiWv {
  LuiWvCore *core;
#if defined(__APPLE__)
  void *web;   /* WKWebView* */
  void *clip;  /* NSView* container in the host's contentView */
  void *del;   /* LuiWvDelegate* */
  void *host;  /* NSWindow* */
#elif defined(__linux__)
  void *win;               /* GtkWindow* holding the web view */
  void *web;               /* WebKitWebView* */
  unsigned long xid;
  unsigned long host_xid;
  void *dpy;
  int visible;
#elif defined(_WIN32)
  void *env, *ctl, *wv;    /* COM interface pointers */
  void *hwnd;
  void *hs;                /* lui_win_handlers block */
#endif
} LuiWv;

static char *lui_wv_dup(const char *s)
{
  size_t n;
  char *r;
  if (s == NULL) s = "";
  n = strlen(s) + 1;
  r = (char *)malloc(n);
  if (r != NULL) memcpy(r, s, n);
  return r;
}

static void lui_wv_push(LuiWvCore *c, int tag, const char *a,
                        const char *b)
{
  lui_wv_ev *e;
  if (c == NULL || c->dead) return;
  e = (lui_wv_ev *)calloc(1, sizeof(*e));
  if (e == NULL) return;
  e->tag = tag;
  e->a = lui_wv_dup(a);
  e->b = lui_wv_dup(b);
  if (c->tail != NULL) c->tail->next = e;
  else c->head = e;
  c->tail = e;
}

static void lui_wv_free_queue(LuiWvCore *c)
{
  lui_wv_ev *e = c->head;
  while (e != NULL) {
    lui_wv_ev *n = e->next;
    free(e->a); free(e->b); free(e);
    e = n;
  }
  c->head = c->tail = NULL;
}

static void lui_wv_die(const char *what)
{
  char buf[200];
  snprintf(buf, sizeof buf, "lui_webview: %s", what);
  caml_failwith(buf);
}

static LuiWv *lui_wv_wv(value v)
{
  LuiWv *w = (LuiWv *)(intnat)Nativeint_val(v);
  if (w == NULL) caml_invalid_argument("lui_webview: null view");
  return w;
}

/* ===================================================================== */
#if defined(__APPLE__)
/* ========================= macOS: WKWebView =========================== */

/* The container view is flipped so an (x, y, w, h) rect in top-left
   logical points becomes (x, contentH - y - h, w, h) in the unflipped
   contentView; the WKWebView fills the container. masksToBounds clips
   the page during frame moves. */
@interface LuiWvClip : NSView
@end
@implementation LuiWvClip
- (BOOL)isFlipped { return YES; }
@end

@interface LuiWvDelegate : NSObject <WKNavigationDelegate,
                                     WKScriptMessageHandler>
/* The delegate outlives its LuiWv (the user content controller keeps
   it alive), so it holds the core sentinel, not the view. */
@property(assign) LuiWvCore *core;
@end

static NSString *lui_wv_json_of(id r)
{
  if (r == nil || [r isKindOfClass:[NSNull class]]) return @"null";
  if ([r isKindOfClass:[NSString class]]) return (NSString *)r;
  if ([r isKindOfClass:[NSNumber class]])
    return [NSString stringWithFormat:@"%@", r];
  NSData *d = [NSJSONSerialization dataWithJSONObject:r options:0
                                                error:nil];
  if (d != nil)
    return [[NSString alloc] initWithData:d
                                 encoding:NSUTF8StringEncoding];
  return [NSString stringWithFormat:@"%@", r];
}

@implementation LuiWvDelegate
- (void)push:(int)tag url:(NSURL *)u err:(NSError *)e
{
  const char *a = u != nil ? u.absoluteString.UTF8String : "";
  const char *b = e != nil ? e.localizedDescription.UTF8String : "";
  lui_wv_push(self.core, tag, a, b);
}

- (void)webView:(WKWebView *)web
    didStartProvisionalNavigation:(WKNavigation *)n
{
  [self push:0 url:web.URL err:nil];
}

- (void)webView:(WKWebView *)web didCommitNavigation:(WKNavigation *)n
{
  [self push:1 url:web.URL err:nil];
}

- (void)webView:(WKWebView *)web didFinishNavigation:(WKNavigation *)n
{
  [self push:2 url:web.URL err:nil];
}

- (void)webView:(WKWebView *)web
    didFailProvisionalNavigation:(WKNavigation *)n
                      withError:(NSError *)error
{
  [self push:3 url:web.URL err:error];
}

- (void)webView:(WKWebView *)web didFailNavigation:(WKNavigation *)n
                             withError:(NSError *)error
{
  [self push:3 url:web.URL err:error];
}

- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)msg
{
  lui_wv_push(self.core, 5, lui_wv_json_of(msg.body).UTF8String, "");
}
@end

#define WV_WEB(w)  ((__bridge WKWebView *)(w)->web)
#define WV_CLIP(w) ((__bridge NSView *)(w)->clip)
#define WV_HOST(w) ((__bridge NSWindow *)(w)->host)

static NSRect lui_wv_mac_rect(LuiWv *w, double x, double y,
                              double ww, double hh)
{
  CGFloat ch = WV_HOST(w).contentView.bounds.size.height;
  return NSMakeRect(x, ch - y - hh, ww, hh);
}

static void lui_wv_mac_create(LuiWv *w, value vhost, double x, double y,
                              double ww, double hh)
{
  void *raw = (void *)(intnat)Nativeint_val(vhost);
  NSWindow *host = (__bridge NSWindow *)raw;
  NSView *content;
  LuiWvClip *clip;
  LuiWvDelegate *del;
  WKWebViewConfiguration *cfg;
  WKWebView *web;
  if (raw == NULL || ![host isKindOfClass:[NSWindow class]])
    lui_wv_die("host is not an NSWindow");
  content = host.contentView;
  if (content == nil) lui_wv_die("host window has no contentView");
  w->host = (void *)CFBridgingRetain(host);
  clip = [[LuiWvClip alloc] initWithFrame:NSMakeRect(0, 0, ww, hh)];
  clip.wantsLayer = YES;
  clip.layer.masksToBounds = YES;
  del = [[LuiWvDelegate alloc] init];
  del.core = w->core;
  cfg = [[WKWebViewConfiguration alloc] init];
  /* Local pages must fetch their own sibling assets: a file:// entry
     (or an Html source on a file:// base) cannot load ./app.js or
     ./icons otherwise — WKWebView refuses file subresource and module
     loads without this preference, which mygo sets for the same
     reason. */
  [cfg.preferences setValue:@YES forKey:@"allowFileAccessFromFileURLs"];
  [cfg.userContentController addScriptMessageHandler:del name:@"lui_wv"];
  web = [[WKWebView alloc] initWithFrame:clip.bounds configuration:cfg];
  web.navigationDelegate = del;
  web.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  [clip addSubview:web];
  [content addSubview:clip];
  w->web = (void *)CFBridgingRetain(web);
  w->clip = (void *)CFBridgingRetain(clip);
  w->del = (void *)CFBridgingRetain(del);
  WV_CLIP(w).frame = lui_wv_mac_rect(w, x, y, ww, hh);
}

static void lui_wv_mac_destroy(LuiWv *w)
{
  [WV_CLIP(w) removeFromSuperview];
  if (w->web != NULL) CFBridgingRelease(w->web);
  if (w->clip != NULL) CFBridgingRelease(w->clip);
  if (w->del != NULL) CFBridgingRelease(w->del);
  if (w->host != NULL) CFBridgingRelease(w->host);
  w->web = w->clip = w->del = w->host = NULL;
}

static void lui_wv_mac_load_url(LuiWv *w, const char *u)
{
  NSURL *url = [NSURL URLWithString:[NSString stringWithUTF8String:u]];
  if (url == nil || url.scheme == nil)
    lui_wv_die("load_url: not an absolute URL");
  [WV_WEB(w) loadRequest:[NSURLRequest requestWithURL:url]];
}

static void lui_wv_mac_load_html(LuiWv *w, const char *h, const char *b)
{
  NSURL *base = nil;
  if (b != NULL && b[0] != '\0')
    base = [NSURL URLWithString:[NSString stringWithUTF8String:b]];
  [WV_WEB(w) loadHTMLString:[NSString stringWithUTF8String:h]
                    baseURL:base];
}

static void lui_wv_mac_load_file(LuiWv *w, const char *p)
{
  NSURL *f = [NSURL fileURLWithPath:[NSString stringWithUTF8String:p]];
  [WV_WEB(w) loadFileURL:f
      allowingReadAccessToURL:[f URLByDeletingLastPathComponent]];
}

static void lui_wv_mac_nav(LuiWv *w, int d)
{
  WKWebView *v = WV_WEB(w);
  switch (d) {
  case 0: [v goBack]; break;
  case 1: [v goForward]; break;
  case 2: [v reload]; break;
  case 3: [v stopLoading]; break;
  default: break;
  }
}

static int lui_wv_mac_can_nav(LuiWv *w)
{
  WKWebView *v = WV_WEB(w);
  return (v.canGoBack ? 1 : 0) | (v.canGoForward ? 2 : 0);
}

static value lui_wv_mac_url(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  NSURL *u = WV_WEB(w).URL;
  s = caml_alloc_initialized_string(
      0, u != nil ? u.absoluteString.UTF8String : "");
  CAMLreturn(s);
}

static int lui_wv_mac_is_loading(LuiWv *w) { return WV_WEB(w).isLoading; }

static void lui_wv_mac_eval(LuiWv *w, const char *js)
{
  [WV_WEB(w) evaluateJavaScript:[NSString stringWithUTF8String:js]
              completionHandler:nil];
}

static void lui_wv_mac_call_async(LuiWv *w, int tok, const char *js)
{
  NSString *body = [NSString stringWithUTF8String:js];
  NSString *toks = [NSString stringWithFormat:@"%d", tok];
  /* The completion may fire after the view was destroyed; capture the
     sentinel, not w. */
  LuiWvCore *core = w->core;
  if (@available(macOS 10.15, *)) {
    [WV_WEB(w) callAsyncJavaScript:body
                         arguments:@{}
                           inFrame:nil
                    inContentWorld:WKContentWorld.pageWorld
                 completionHandler:^(id r, NSError *e) {
      NSString *s = e != nil
        ? [NSString stringWithFormat:@"Error: %@",
                                     e.localizedDescription]
        : lui_wv_json_of(r);
      lui_wv_push(core, 4, toks.UTF8String, s.UTF8String);
    }];
  } else {
    /* No async-function API: evaluate a synchronous wrapper that
       JSON-encodes the result. */
    NSString *wrapped = [NSString stringWithFormat:
        @"(function(){try{return JSON.stringify((function(){%@})())}"
         "catch(e){return \"Error: \"+e}})()", body];
    [WV_WEB(w) evaluateJavaScript:wrapped
                completionHandler:^(id r, NSError *e) {
      NSString *s = e != nil
        ? [NSString stringWithFormat:@"Error: %@",
                                     e.localizedDescription]
        : lui_wv_json_of(r);
      lui_wv_push(core, 4, toks.UTF8String, s.UTF8String);
    }];
  }
}

static void lui_wv_mac_set_zoom(LuiWv *w, double z)
{
  WV_WEB(w).pageZoom = z;
}

static double lui_wv_mac_zoom(LuiWv *w) { return WV_WEB(w).pageZoom; }

static void lui_wv_mac_set_ua(LuiWv *w, const char *ua)
{
  WV_WEB(w).customUserAgent =
    ua != NULL && ua[0] != '\0'
      ? [NSString stringWithUTF8String:ua] : nil;
}

static value lui_wv_mac_ua(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  NSString *u = WV_WEB(w).customUserAgent;
  s = caml_copy_string(u != nil ? u.UTF8String : "");
  CAMLreturn(s);
}

static void lui_wv_mac_set_transparent(LuiWv *w, int on)
{
  WKWebView *v = WV_WEB(w);
  NSView *c = WV_CLIP(w);
  v.wantsLayer = YES;
  v.layer.opaque = !on;
  c.layer.opaque = !on;
  if ([v respondsToSelector:@selector(_setDrawsBackground:)])
    [v setValue:@(!on) forKey:@"_drawsBackground"];
}

static void lui_wv_mac_set_frame(LuiWv *w, double x, double y,
                                 double ww, double hh)
{
  WV_CLIP(w).frame = lui_wv_mac_rect(w, x, y, ww, hh);
}

static value lui_wv_mac_frame(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(t);
  NSRect f = WV_CLIP(w).frame;
  CGFloat ch = WV_HOST(w).contentView.bounds.size.height;
  t = caml_alloc_tuple(4);
  Store_field(t, 0, caml_copy_double(f.origin.x));
  Store_field(t, 1, caml_copy_double(ch - f.origin.y - f.size.height));
  Store_field(t, 2, caml_copy_double(f.size.width));
  Store_field(t, 3, caml_copy_double(f.size.height));
  CAMLreturn(t);
}

static void lui_wv_mac_set_visible(LuiWv *w, int v)
{
  WV_CLIP(w).hidden = !v;
}

static value lui_wv_mac_capture(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  __block NSData *png = nil;
  __block BOOL done = NO;
  WKSnapshotConfiguration *sc = [[WKSnapshotConfiguration alloc] init];
  [WV_WEB(w) takeSnapshotWithConfiguration:sc
                         completionHandler:^(NSImage *img, NSError *e) {
    if (e == nil && img != nil) {
      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
          initWithData:[img TIFFRepresentation]];
      if (rep != nil)
        png = [rep representationUsingType:NSBitmapImageFileTypePNG
                                properties:@{}];
    }
    done = YES;
  }];
  /* Bounded run-loop pump until WebKit answers (must be called on the
     UI thread that owns this run loop). */
  {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
      [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                               beforeDate:
          [NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
  }
  if (png == nil) s = caml_copy_string("");
  else s = caml_alloc_initialized_string((mlsize_t)[png length],
                                         (const char *)[png bytes]);
  CAMLreturn(s);
}

static void lui_wv_mac_pump(void)
{
  NSRunLoop *rl = [NSRunLoop currentRunLoop];
  int i;
  /* Bounded: a few short run-loop turns drain pending events, delegate
     callbacks and dispatched main-queue work. */
  for (i = 0; i < 4; i++)
    [rl runMode:NSDefaultRunLoopMode
     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}

/* ===================================================================== */
#elif defined(__linux__)
/* ============ Linux: WebKitGTK via dlopen, X11 reparent ============== */

/* Everything is bound at runtime so the library compiles and loads
   without GTK/WebKit dev packages; creating a view without them raises
   a clear [Failure]. Wayland is not supported: embedding a GTK view
   into a foreign surface has no cross-toolkit mechanism — SDL hosts on
   Wayland desktops can run under XWayland (SDL_VIDEODRIVER=x11). */

#include <dlfcn.h>

typedef struct {
  int tried, ok;
  char err[160];
  void *glib, *gobject, *gtk, *gdk, *webkit, *jsc, *x11, *cairo;
  int (*gtk_init_check)(int *, char ***);
  void *(*gtk_window_new)(int);
  void (*gtk_window_set_decorated)(void *, int);
  void (*gtk_window_set_skip_taskbar_hint)(void *, int);
  void (*gtk_window_set_skip_pager_hint)(void *, int);
  void (*gtk_window_resize)(void *, int, int);
  void (*gtk_container_add)(void *, void *);
  void (*gtk_widget_show_all)(void *);
  void (*gtk_widget_show)(void *);
  void (*gtk_widget_hide)(void *);
  void (*gtk_widget_realize)(void *);
  void *(*gtk_widget_get_window)(void *);
  void (*gtk_widget_set_size_request)(void *, int, int);
  void (*gtk_widget_destroy)(void *);
  void *(*gdk_x11_get_default_xdisplay)(void);
  unsigned long (*gdk_x11_window_get_xid)(void *);
  void (*g_object_unref)(void *);
  unsigned long (*g_signal_connect_data)(void *, const char *, void *,
                                         void *, void *, int);
  int (*g_main_context_iteration)(void *, int);
  long (*g_get_monotonic_time)(void);
  void (*g_free)(void *);
  void *(*webkit_web_view_new)(void);
  void (*webkit_web_view_load_uri)(void *, const char *);
  void (*webkit_web_view_load_html)(void *, const char *, const char *);
  void (*webkit_web_view_reload)(void *);
  void (*webkit_web_view_stop_loading)(void *);
  void (*webkit_web_view_go_back)(void *);
  void (*webkit_web_view_go_forward)(void *);
  int (*webkit_web_view_can_go_back)(void *);
  int (*webkit_web_view_can_go_forward)(void *);
  const char *(*webkit_web_view_get_uri)(void *);
  int (*webkit_web_view_is_loading)(void *);
  void (*webkit_web_view_set_zoom_level)(void *, double);
  double (*webkit_web_view_get_zoom_level)(void *);
  void *(*webkit_web_view_get_settings)(void *);
  void (*webkit_settings_set_user_agent)(void *, const char *);
  char *(*webkit_settings_get_user_agent)(void *);
  void (*webkit_web_view_set_background_color)(void *, const double *);
  void (*webkit_web_view_run_javascript)(void *, const char *, void *,
                                       void *, void *);
  void *(*webkit_web_view_run_javascript_finish)(void *, void *, void *);
  void *(*webkit_web_view_get_user_content_manager)(void *);
  int (*webkit_user_content_manager_register_script_message_handler)(
      void *, const char *);
  void (*webkit_web_view_get_snapshot)(void *, int, int, void *, void *,
                                     void *);
  void *(*webkit_web_view_get_snapshot_finish)(void *, void *, void *);
  void *(*webkit_javascript_result_get_js_value)(void *);
  char *(*jsc_value_to_json)(void *, int);
  char *(*jsc_value_to_string)(void *);
  int (*cairo_surface_write_to_png_stream)(void *, void *, void *);
  void (*cairo_surface_destroy)(void *);
  int (*XReparentWindow)(void *, unsigned long, unsigned long, int, int);
  int (*XMoveResizeWindow)(void *, unsigned long, int, int,
                           unsigned, unsigned);
  int (*XMapWindow)(void *, unsigned long);
  int (*XUnmapWindow)(void *, unsigned long);
  int (*XFlush)(void *);
} lui_gtk_t;

static lui_gtk_t G;

static int lui_bind(void *lib, void **fp, const char *sym)
{
  *fp = dlsym(lib, sym);
  if (*fp != NULL) return 0;
  snprintf(G.err, sizeof G.err, "missing symbol %s", sym);
  return -1;
}

#define BIND(lib, field) \
  do { if (lui_bind(lib, (void **)&G.field, #field) != 0) return -1; } \
  while (0)

static int lui_gtk_init(void)
{
  if (G.tried) return G.ok;
  G.tried = 1;
#define TRY_LIB(field, ...) \
  do { \
    const char *cands[] = { __VA_ARGS__ }; \
    size_t i; \
    for (i = 0; i < sizeof cands / sizeof cands[0]; i++) { \
      G.field = dlopen(cands[i], RTLD_NOW | RTLD_GLOBAL); \
      if (G.field != NULL) break; \
    } \
    if (G.field == NULL) { \
      snprintf(G.err, sizeof G.err, "cannot load %s", cands[0]); \
      return -1; \
    } \
  } while (0)

  TRY_LIB(glib,   "libglib-2.0.so.0", "libglib-2.0.so");
  TRY_LIB(gobject,"libgobject-2.0.so.0", "libgobject-2.0.so");
  TRY_LIB(x11,    "libX11.so.6", "libX11.so");
  TRY_LIB(gdk,    "libgdk-3.so.0", "libgdk-3.so");
  TRY_LIB(gtk,    "libgtk-3.so.0", "libgtk-3.so");
  TRY_LIB(webkit, "libwebkit2gtk-4.1.so.0", "libwebkit2gtk-4.1.so",
                  "libwebkit2gtk-4.0.so.37", "libwebkit2gtk-4.0.so");
  TRY_LIB(jsc,    "libjavascriptcoregtk-4.1.so.0",
                  "libjavascriptcoregtk-4.1.so",
                  "libjavascriptcoregtk-4.0.so.18",
                  "libjavascriptcoregtk-4.0.so");
  TRY_LIB(cairo,  "libcairo.so.2", "libcairo.so");

  BIND(G.glib, g_main_context_iteration);
  BIND(G.glib, g_get_monotonic_time);
  BIND(G.glib, g_free);
  BIND(G.gobject, g_object_unref);
  BIND(G.gobject, g_signal_connect_data);
  BIND(G.gtk, gtk_init_check);
  BIND(G.gtk, gtk_window_new);
  BIND(G.gtk, gtk_window_set_decorated);
  BIND(G.gtk, gtk_window_set_skip_taskbar_hint);
  BIND(G.gtk, gtk_window_set_skip_pager_hint);
  BIND(G.gtk, gtk_window_resize);
  BIND(G.gtk, gtk_container_add);
  BIND(G.gtk, gtk_widget_show_all);
  BIND(G.gtk, gtk_widget_show);
  BIND(G.gtk, gtk_widget_hide);
  BIND(G.gtk, gtk_widget_realize);
  BIND(G.gtk, gtk_widget_get_window);
  BIND(G.gtk, gtk_widget_set_size_request);
  BIND(G.gtk, gtk_widget_destroy);
  BIND(G.gdk, gdk_x11_get_default_xdisplay);
  BIND(G.gdk, gdk_x11_window_get_xid);
  BIND(G.webkit, webkit_web_view_new);
  BIND(G.webkit, webkit_web_view_load_uri);
  BIND(G.webkit, webkit_web_view_load_html);
  BIND(G.webkit, webkit_web_view_reload);
  BIND(G.webkit, webkit_web_view_stop_loading);
  BIND(G.webkit, webkit_web_view_go_back);
  BIND(G.webkit, webkit_web_view_go_forward);
  BIND(G.webkit, webkit_web_view_can_go_back);
  BIND(G.webkit, webkit_web_view_can_go_forward);
  BIND(G.webkit, webkit_web_view_get_uri);
  BIND(G.webkit, webkit_web_view_is_loading);
  BIND(G.webkit, webkit_web_view_set_zoom_level);
  BIND(G.webkit, webkit_web_view_get_zoom_level);
  BIND(G.webkit, webkit_web_view_get_settings);
  BIND(G.webkit, webkit_settings_set_user_agent);
  BIND(G.webkit, webkit_settings_get_user_agent);
  BIND(G.webkit, webkit_web_view_set_background_color);
  BIND(G.webkit, webkit_web_view_run_javascript);
  BIND(G.webkit, webkit_web_view_run_javascript_finish);
  BIND(G.webkit, webkit_web_view_get_user_content_manager);
  BIND(G.webkit,
       webkit_user_content_manager_register_script_message_handler);
  BIND(G.webkit, webkit_web_view_get_snapshot);
  BIND(G.webkit, webkit_web_view_get_snapshot_finish);
  BIND(G.webkit, webkit_javascript_result_get_js_value);
  BIND(G.jsc, jsc_value_to_json);
  BIND(G.jsc, jsc_value_to_string);
  BIND(G.cairo, cairo_surface_write_to_png_stream);
  BIND(G.cairo, cairo_surface_destroy);
  BIND(G.x11, XReparentWindow);
  BIND(G.x11, XMoveResizeWindow);
  BIND(G.x11, XMapWindow);
  BIND(G.x11, XUnmapWindow);
  BIND(G.x11, XFlush);

  if (!G.gtk_init_check(NULL, NULL)) {
    snprintf(G.err, sizeof G.err, "gtk_init_check failed (no display?)");
    return -1;
  }
  G.ok = 1;
  return 0;
#undef TRY_LIB
}

/* WebKitLoadEvent: STARTED 0, REDIRECTED 1, COMMITTED 2, FINISHED 3.
   Signal callbacks receive the core sentinel as user data: they may
   fire after the owning view was destroyed. */
static void lui_gtk_on_load_changed(void *web, int ev, void *data)
{
  LuiWvCore *c = (LuiWvCore *)data;
  const char *u = G.webkit_web_view_get_uri(web);
  switch (ev) {
  case 0: lui_wv_push(c, 0, u, ""); break;
  case 2: lui_wv_push(c, 1, u, ""); break;
  case 3: lui_wv_push(c, 2, u, ""); break;
  default: break;
  }
}

/* GError layout: { GQuark domain; gint code; gchar *message; } */
typedef struct { unsigned int domain; int code; char *message; } lui_gerror;

static void lui_gtk_on_load_failed(void *web, int ev, char *uri,
                                   void *err, void *data)
{
  LuiWvCore *c = (LuiWvCore *)data;
  const char *msg = err != NULL ? ((lui_gerror *)err)->message : "";
  lui_wv_push(c, 3, uri != NULL ? uri : "", msg);
  (void)web; (void)ev;
}

static void lui_gtk_on_script_message(void *ucc, void *result, void *data)
{
  LuiWvCore *c = (LuiWvCore *)data;
  void *v = G.webkit_javascript_result_get_js_value(result);
  /* to_string (not to_json): the "tok\njson" call_async payload needs
     a literal newline to split on. */
  char *txt = G.jsc_value_to_string(v);
  if (txt != NULL) {
    char *nl = strchr(txt, '\n');
    size_t toklen = nl != NULL ? (size_t)(nl - txt) : 0;
    if (toklen > 0 && strspn(txt, "0123456789") == toklen) {
      *nl = '\0';
      lui_wv_push(c, 4, txt, nl + 1);
    } else {
      lui_wv_push(c, 5, txt, "");
    }
    G.g_free(txt);
  }
  (void)ucc;
}

typedef struct {
  int done;
  char *buf;
  size_t len, cap;
} lui_snap_t;

/* cairo_write_func_t: 0 (CAIRO_STATUS_SUCCESS) on success. */
static int lui_png_write(void *data, const unsigned char *buf,
                         unsigned int len)
{
  lui_snap_t *s = (lui_snap_t *)data;
  if (s->len + len > s->cap) {
    size_t nc = (s->len + len) * 2 + 64;
    char *nb = (char *)realloc(s->buf, nc);
    if (nb == NULL) return 7; /* CAIRO_STATUS_WRITE_ERROR */
    s->buf = nb;
    s->cap = nc;
  }
  memcpy(s->buf + s->len, buf, len);
  s->len += len;
  return 0;
}

static void lui_gtk_on_snapshot(void *src, void *res, void *data)
{
  lui_snap_t *s = (lui_snap_t *)data;
  void *err = NULL;
  void *surf = G.webkit_web_view_get_snapshot_finish(src, res, &err);
  if (surf != NULL) {
    G.cairo_surface_write_to_png_stream(surf, lui_png_write, s);
    G.cairo_surface_destroy(surf);
  }
  s->done = 1;
}

static void lui_gtk_pump(void)
{
  if (!G.ok) return;
  while (G.g_main_context_iteration(NULL, 0)) {}
}

static void lui_gtk_create(LuiWv *w, value vhost,
                           double x, double y, double ww, double hh)
{
  if (lui_gtk_init() != 0) lui_wv_die(G.err);
  w->host_xid = (unsigned long)(intnat)Nativeint_val(vhost);
  w->dpy = G.gdk_x11_get_default_xdisplay();
  w->win = G.gtk_window_new(0); /* GTK_WINDOW_TOPLEVEL */
  G.gtk_window_set_decorated(w->win, 0);
  G.gtk_window_set_skip_taskbar_hint(w->win, 1);
  G.gtk_window_set_skip_pager_hint(w->win, 1);
  G.gtk_window_resize(w->win, (int)ww, (int)hh);
  w->web = G.webkit_web_view_new();
  G.gtk_container_add(w->win, w->web);
  G.gtk_widget_set_size_request(w->web, (int)ww, (int)hh);
  G.g_signal_connect_data(w->web, "load-changed",
                          (void *)lui_gtk_on_load_changed, w->core,
                          NULL, 0);
  G.g_signal_connect_data(w->web, "load-failed",
                          (void *)lui_gtk_on_load_failed, w->core,
                          NULL, 0);
  {
    void *ucc = G.webkit_web_view_get_user_content_manager(w->web);
    G.webkit_user_content_manager_register_script_message_handler(
        ucc, "lui_wv");
    G.g_signal_connect_data(ucc, "script-message-received::lui_wv",
                            (void *)lui_gtk_on_script_message, w->core,
                            NULL, 0);
  }
  /* Realize, then reparent the GTK window's X11 window into the SDL
     host's XID — best-effort foreign embedding; falls back to a
     standalone GTK window if the X server refuses it. */
  G.gtk_widget_realize(w->win);
  {
    void *gw = G.gtk_widget_get_window(w->win);
    w->xid = G.gdk_x11_window_get_xid(gw);
    if (w->dpy != NULL && w->host_xid != 0 && w->xid != 0) {
      G.XReparentWindow(w->dpy, w->xid, w->host_xid, (int)x, (int)y);
      G.XMoveResizeWindow(w->dpy, w->xid, (int)x, (int)y,
                          (unsigned)ww, (unsigned)hh);
    }
  }
  w->visible = 1;
  G.gtk_widget_show_all(w->win);
  if (w->dpy != NULL && w->xid != 0) {
    G.XMapWindow(w->dpy, w->xid);
    G.XFlush(w->dpy);
  }
  lui_gtk_pump();
}

static void lui_gtk_destroy(LuiWv *w)
{
  if (w->win != NULL) G.gtk_widget_destroy(w->win);
  w->win = w->web = NULL;
}

static void lui_gtk_load_url(LuiWv *w, const char *u)
{
  G.webkit_web_view_load_uri(w->web, u);
}

static void lui_gtk_load_html(LuiWv *w, const char *h, const char *b)
{
  G.webkit_web_view_load_html(w->web, h,
                              b != NULL && b[0] ? b : NULL);
}

static void lui_gtk_load_file(LuiWv *w, const char *p)
{
  char url[4096];
  if (p[0] == '/') snprintf(url, sizeof url, "file://%s", p);
  else snprintf(url, sizeof url, "file:///%s", p);
  G.webkit_web_view_load_uri(w->web, url);
}

static void lui_gtk_nav(LuiWv *w, int d)
{
  switch (d) {
  case 0: G.webkit_web_view_go_back(w->web); break;
  case 1: G.webkit_web_view_go_forward(w->web); break;
  case 2: G.webkit_web_view_reload(w->web); break;
  case 3: G.webkit_web_view_stop_loading(w->web); break;
  default: break;
  }
}

static int lui_gtk_can_nav(LuiWv *w)
{
  return (G.webkit_web_view_can_go_back(w->web) ? 1 : 0) |
         (G.webkit_web_view_can_go_forward(w->web) ? 2 : 0);
}

static value lui_gtk_url(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  const char *u = G.webkit_web_view_get_uri(w->web);
  s = caml_copy_string(u != NULL ? u : "");
  CAMLreturn(s);
}

static int lui_gtk_is_loading(LuiWv *w)
{
  return G.webkit_web_view_is_loading(w->web);
}

static void lui_gtk_eval(LuiWv *w, const char *js)
{
  G.webkit_web_view_run_javascript(w->web, js, NULL, NULL, NULL);
}

static void lui_gtk_call_async(LuiWv *w, int tok, const char *js)
{
  /* WebKitGTK has no async-function entry: wrap the body in an async
     IIFE that posts the JSON result through the script-message channel
     as "tok\njson" — decoded like other tag-4 results. */
  const char *tmpl =
    "(async()=>{try{var v=await(async()=>{%s})();"
    "webkit.messageHandlers.lui_wv.postMessage('%d\\n'+JSON.stringify(v))}"
    "catch(e){webkit.messageHandlers.lui_wv.postMessage("
    "'%d\\n\"Error: \"+e)}})()";
  char *buf = (char *)malloc(strlen(tmpl) + strlen(js) + 64);
  if (buf == NULL) caml_raise_out_of_memory();
  sprintf(buf, tmpl, js, tok, tok);
  G.webkit_web_view_run_javascript(w->web, buf, NULL, NULL, NULL);
  free(buf);
}

static void lui_gtk_set_zoom(LuiWv *w, double z)
{
  G.webkit_web_view_set_zoom_level(w->web, z);
}

static double lui_gtk_zoom(LuiWv *w)
{
  return G.webkit_web_view_get_zoom_level(w->web);
}

static void lui_gtk_set_ua(LuiWv *w, const char *ua)
{
  G.webkit_settings_set_user_agent(
      G.webkit_web_view_get_settings(w->web),
      ua != NULL && ua[0] ? ua : NULL);
}

static value lui_gtk_ua(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  char *u = G.webkit_settings_get_user_agent(
      G.webkit_web_view_get_settings(w->web));
  s = caml_copy_string(u != NULL ? u : "");
  if (u != NULL) G.g_free(u);
  CAMLreturn(s);
}

static void lui_gtk_set_transparent(LuiWv *w, int on)
{
  /* GdkRGBA is four doubles. */
  double rgba[4] = { 0.0, 0.0, 0.0, on ? 0.0 : 1.0 };
  G.webkit_web_view_set_background_color(w->web, rgba);
}

static void lui_gtk_set_frame(LuiWv *w, double x, double y,
                              double ww, double hh)
{
  G.gtk_widget_set_size_request(w->web, (int)ww, (int)hh);
  G.gtk_window_resize(w->win, (int)ww, (int)hh);
  if (w->dpy != NULL && w->xid != 0) {
    G.XMoveResizeWindow(w->dpy, w->xid, (int)x, (int)y,
                        (unsigned)ww, (unsigned)hh);
    G.XFlush(w->dpy);
  }
}

static value lui_gtk_frame(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(t);
  /* No cheap query of the reparented X window's geometry; callers
     track the rects they set. Report zeros. */
  t = caml_alloc_tuple(4);
  Store_field(t, 0, caml_copy_double(0));
  Store_field(t, 1, caml_copy_double(0));
  Store_field(t, 2, caml_copy_double(0));
  Store_field(t, 3, caml_copy_double(0));
  CAMLreturn(t);
}

static void lui_gtk_set_visible(LuiWv *w, int v)
{
  w->visible = v;
  if (v) G.gtk_widget_show(w->win);
  else G.gtk_widget_hide(w->win);
}

static value lui_gtk_capture(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  /* Heap-allocated: the async snapshot reply may arrive after the
     bounded wait returns, so the state must outlive this call. */
  lui_snap_t *snap = (lui_snap_t *)calloc(1, sizeof *snap);
  char *buf;
  size_t len;
  long deadline;
  if (snap == NULL) CAMLreturn(caml_copy_string(""));
  /* WEBKIT_SNAPSHOT_REGION_VISIBLE_DOCUMENT = 0, OPTIONS_NONE = 0 */
  G.webkit_web_view_get_snapshot(w->web, 0, 0, NULL,
                                 lui_gtk_on_snapshot, snap);
  deadline = G.g_get_monotonic_time() + 5000000L;
  while (!snap->done && G.g_get_monotonic_time() < deadline) {
    G.g_main_context_iteration(NULL, 1);
  }
  if (!snap->done) {
    /* The reply may still arrive: leak the state so the callback
       writes into live memory. */
    s = caml_copy_string("");
  } else {
    buf = snap->buf;
    len = snap->len;
    free(snap);
    if (buf == NULL) s = caml_copy_string("");
    else {
      s = caml_alloc_initialized_string((mlsize_t)len, buf);
      free(buf);
    }
  }
  CAMLreturn(s);
}

/* ===================================================================== */
#elif defined(_WIN32)
/* ========= Windows: WebView2 via LoadLibrary + minimal COM =========== */

/* Minimal Win32 declarations — needed only when SDL_syswm.h did not
   already pull in <windows.h>; otherwise the real protos apply (and
   windows.h macros like LoadLibraryW->LoadLibraryExW keep working). */

typedef long lui_hresult;
typedef unsigned long lui_ulong;
typedef void *lui_com;

#define LUI_STDCALL __stdcall

#ifndef WINAPI
extern __declspec(dllimport) void *LUI_STDCALL LoadLibraryW(
    const wchar_t *);
extern __declspec(dllimport) void *LUI_STDCALL GetProcAddress(
    void *, const char *);
extern __declspec(dllimport) int LUI_STDCALL PeekMessageW(
    void *, void *, unsigned, unsigned, unsigned);
extern __declspec(dllimport) int LUI_STDCALL TranslateMessage(const void *);
extern __declspec(dllimport) long LUI_STDCALL DispatchMessageW(
    const void *);
extern __declspec(dllimport) void LUI_STDCALL Sleep(unsigned long);
extern __declspec(dllimport) int LUI_STDCALL MultiByteToWideChar(
    unsigned, unsigned long, const char *, int, wchar_t *, int);
extern __declspec(dllimport) int LUI_STDCALL WideCharToMultiByte(
    unsigned, unsigned long, const wchar_t *, int, char *, int,
    const char *, int *);
extern __declspec(dllimport) long LUI_STDCALL GetHGlobalFromStream(
    void *, void **);
extern __declspec(dllimport) void *LUI_STDCALL GlobalLock(void *);
extern __declspec(dllimport) unsigned long LUI_STDCALL GlobalSize(void *);
extern __declspec(dllimport) int LUI_STDCALL GlobalUnlock(void *);
extern __declspec(dllimport) long LUI_STDCALL CreateStreamOnHGlobal(
    void *, int, void **);
extern __declspec(dllimport) void LUI_STDCALL CoTaskMemFree(void *);
#else
/* <windows.h> came in via SDL_syswm.h, which defines
   WIN32_LEAN_AND_MEAN: that skips the COM headers, so the real
   CoTaskMemFree / CreateStreamOnHGlobal / GetHGlobalFromStream protos
   must be pulled in explicitly. */
#include <objbase.h>
#endif /* !WINAPI — no real Win32 headers in this TU */

typedef struct {
  void *hwnd;
  unsigned msg;
  uintptr_t w, l;
  unsigned long time;
  struct { long x, y; } pt;
} lui_msg_t;

typedef struct { long left, top, right, bottom; } lui_rect_t;

/* COM: an interface pointer points at a vtbl pointer. */
typedef struct { void **vt; } lui_obj_t;

#define LUI_CALL0(o, i, r) \
  (((r(LUI_STDCALL *)(void *))((lui_obj_t *)(o))->vt[i])(o))
#define LUI_CALL1(o, i, r, t1, a) \
  (((r(LUI_STDCALL *)(void *, t1))((lui_obj_t *)(o))->vt[i])(o, a))
#define LUI_CALL2(o, i, r, t1, a, t2, b) \
  (((r(LUI_STDCALL *)(void *, t1, t2))((lui_obj_t *)(o))->vt[i]) \
   (o, a, b))
#define LUI_CALL3(o, i, r, t1, a, t2, b, t3, c) \
  (((r(LUI_STDCALL *)(void *, t1, t2, t3))((lui_obj_t *)(o))->vt[i]) \
   (o, a, b, c))

/* vtbl indices (ICoreWebView2* family, SDK-stable). */
#define LUI_ENV_CREATE_CONTROLLER 3
#define LUI_CTL_PUT_VISIBLE 4
#define LUI_CTL_GET_BOUNDS 5
#define LUI_CTL_PUT_BOUNDS 6
#define LUI_CTL_GET_ZOOM 7
#define LUI_CTL_PUT_ZOOM 8
#define LUI_CTL_CLOSE 24
#define LUI_CTL_GET_WEBVIEW2 25
#define LUI_WV_GET_SETTINGS 3
#define LUI_WV_GET_SOURCE 4
#define LUI_WV_NAVIGATE 5
#define LUI_WV_NAVIGATE_TO_STRING 6
#define LUI_WV_ADD_NAV_STARTING 7
#define LUI_WV_ADD_NAV_COMPLETED 15
#define LUI_WV_EXECUTE_SCRIPT 29
#define LUI_WV_CAPTURE_PREVIEW 30
#define LUI_WV_RELOAD 31
#define LUI_WV_ADD_WEB_MESSAGE 34
#define LUI_WV_GET_CAN_GO_BACK 38
#define LUI_WV_GET_CAN_GO_FORWARD 39
#define LUI_WV_GO_BACK 40
#define LUI_WV_GO_FORWARD 41
#define LUI_WV_STOP 43
#define LUI_SET2_PUT_USER_AGENT 22 /* ICoreWebView2Settings2 */
#define LUI_ARGS_GET_URI 3         /* NavigationStartingEventArgs */
#define LUI_ARGS_GET_IS_SUCCESS 3  /* NavigationCompletedEventArgs */
#define LUI_ARGS_TRY_STRING 5      /* WebMessageReceivedEventArgs */
#define LUI_STREAM_RELEASE 2       /* IStream::Release */

/* ICoreWebView2Settings2 iid, for QueryInterface. */
static const unsigned char lui_iid_settings2[16] = {
  0x68, 0x0f, 0x9a, 0xee, 0x6c, 0xf4, 0x32, 0x4e,
  0xac, 0x23, 0xef, 0x8c, 0xac, 0x22, 0x4d, 0x2a };

/* ---- the handlers we implement (IUnknown + Invoke) ---------------- */

typedef struct {
  void **vt;
  LuiWv *w;         /* valid only during create-time callbacks */
  LuiWvCore *core;  /* always valid; event callbacks use this */
  int tok;
  void *vt_next;
} lui_h_t;

static lui_hresult LUI_STDCALL lui_h_qi(void *self, const void *riid,
                                       void **out)
{
  /* Each handler implements exactly one interface; answering any iid
     keeps this free of GUID bookkeeping. */
  (void)riid;
  *out = self;
  return 0;
}

static lui_ulong LUI_STDCALL lui_h_addref(void *self)
{
  (void)self;
  return 2;
}

static lui_ulong LUI_STDCALL lui_h_release(void *self)
{
  (void)self;
  return 1;
}

static void **lui_h_vt(void *invoke)
{
  void **vt = (void **)malloc(4 * sizeof(void *));
  if (vt == NULL) return NULL;
  vt[0] = (void *)lui_h_qi;
  vt[1] = (void *)lui_h_addref;
  vt[2] = (void *)lui_h_release;
  vt[3] = invoke;
  return vt;
}

static lui_h_t *lui_h_new(void **vt, LuiWv *w, int tok, void *vt_next)
{
  lui_h_t *h = (lui_h_t *)malloc(sizeof *h);
  if (h == NULL) return NULL;
  h->vt = vt;
  h->w = w;
  h->core = w->core;
  h->tok = tok;
  h->vt_next = vt_next;
  return h;
}

typedef struct {
  void **env, **ctl, **nav_start, **nav_done, **msg, **script, **cap;
  void *nav_start_obj, *nav_done_obj, *msg_obj;
} lui_wv_handlers;

static wchar_t *lui_u16(const char *utf8)
{
  int n;
  wchar_t *s;
  if (utf8 == NULL) utf8 = "";
  n = MultiByteToWideChar(65001 /*CP_UTF8*/, 0, utf8, -1, NULL, 0);
  if (n <= 0) return NULL;
  s = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
  if (s == NULL) return NULL;
  MultiByteToWideChar(65001, 0, utf8, -1, s, n);
  return s;
}

static char *lui_u8(const wchar_t *u16)
{
  int n;
  char *s;
  if (u16 == NULL) return lui_wv_dup("");
  n = WideCharToMultiByte(65001, 0, u16, -1, NULL, 0, NULL, NULL);
  if (n <= 0) return lui_wv_dup("");
  s = (char *)malloc((size_t)n);
  if (s == NULL) return lui_wv_dup("");
  WideCharToMultiByte(65001, 0, u16, -1, s, n, NULL, NULL);
  return s;
}

static void lui_win_pump_until(volatile int *flag)
{
  int ticks = 10000;
  while (!*flag && ticks-- > 0) {
    lui_msg_t m;
    if (PeekMessageW((void *)&m, NULL, 0, 0, 1 /*PM_REMOVE*/)) {
      TranslateMessage((const void *)&m);
      DispatchMessageW((const void *)&m);
    } else {
      Sleep(1);
    }
  }
}

static void lui_win_pump(void)
{
  lui_msg_t m;
  while (PeekMessageW((void *)&m, NULL, 0, 0, 1)) {
    TranslateMessage((const void *)&m);
    DispatchMessageW((const void *)&m);
  }
}

static lui_hresult LUI_STDCALL lui_on_ctl(void *self, lui_hresult hr,
                                        lui_com ctl)
{
  lui_h_t *h = (lui_h_t *)self;
  LuiWv *w = h->w;
  LuiWvCore *core = h->core;
  lui_wv_handlers *hs = (lui_wv_handlers *)w->hs;
  if (hr != 0 || ctl == NULL) { core->failed = 1; return 0; }
  w->ctl = ctl;
  /* get_CoreWebView2(&wv) */
  LUI_CALL1(ctl, LUI_CTL_GET_WEBVIEW2, lui_hresult, void **, &w->wv);
  if (w->wv != NULL) {
    void *token = NULL;
    LUI_CALL2(w->wv, LUI_WV_ADD_NAV_STARTING, lui_hresult,
              void *, hs->nav_start_obj, void *, &token);
    LUI_CALL2(w->wv, LUI_WV_ADD_NAV_COMPLETED, lui_hresult,
              void *, hs->nav_done_obj, void *, &token);
    LUI_CALL2(w->wv, LUI_WV_ADD_WEB_MESSAGE, lui_hresult,
              void *, hs->msg_obj, void *, &token);
  }
  core->ready = 1;
  return 0;
}

static void lui_win_pump_once(void);

static lui_hresult LUI_STDCALL lui_on_env(void *self, lui_hresult hr,
                                        lui_com env)
{
  lui_h_t *h = (lui_h_t *)self;
  LuiWv *w = h->w;
  LuiWvCore *core = h->core;
  lui_h_t *ctl_h;
  if (hr != 0 || env == NULL) { core->failed = 1; return 0; }
  w->env = env;
  ctl_h = lui_h_new((void **)h->vt_next, w, 0, NULL);
  if (ctl_h == NULL) { core->failed = 1; return 0; }
  /* CreateCoreWebView2Controller(HWND, handler*) */
  LUI_CALL2(env, LUI_ENV_CREATE_CONTROLLER, lui_hresult,
            void *, w->hwnd, void *, ctl_h);
  return 0;
}

static lui_hresult LUI_STDCALL lui_on_nav_start(void *self, lui_com wv_,
                                              lui_com args)
{
  lui_h_t *h = (lui_h_t *)self;
  wchar_t *uri = NULL;
  char *u;
  (void)wv_;
  h->core->loading = 1;
  LUI_CALL1(args, LUI_ARGS_GET_URI, lui_hresult, wchar_t **, &uri);
  u = lui_u8(uri);
  lui_wv_push(h->core, 0, u, "");
  free(u);
  if (uri != NULL) CoTaskMemFree(uri);
  return 0;
}

static lui_hresult LUI_STDCALL lui_on_nav_done(void *self, lui_com wv_,
                                             lui_com args)
{
  lui_h_t *h = (lui_h_t *)self;
  int ok = 0;
  (void)wv_;
  h->core->loading = 0;
  LUI_CALL1(args, LUI_ARGS_GET_IS_SUCCESS, lui_hresult, int *, &ok);
  lui_wv_push(h->core, ok ? 2 : 3, "", ok ? "" : "navigation failed");
  return 0;
}

static lui_hresult LUI_STDCALL lui_on_msg(void *self, lui_com wv_,
                                        lui_com args)
{
  lui_h_t *h = (lui_h_t *)self;
  wchar_t *txt = NULL;
  char *u;
  (void)wv_;
  LUI_CALL1(args, LUI_ARGS_TRY_STRING, lui_hresult, wchar_t **, &txt);
  u = lui_u8(txt);
  /* call_async replies arrive as "tok\njson" through this channel;
     anything else is a script message. */
  {
    char *nl = strchr(u, '\n');
    if (nl != NULL && nl > u &&
        strspn(u, "0123456789") == (size_t)(nl - u)) {
      *nl = '\0';
      lui_wv_push(h->core, 4, u, nl + 1);
    } else {
      lui_wv_push(h->core, 5, u, "");
    }
  }
  free(u);
  if (txt != NULL) CoTaskMemFree(txt);
  return 0;
}

static lui_hresult LUI_STDCALL lui_on_script_done(void *self,
                                                lui_hresult hr,
                                                const wchar_t *json)
{
  lui_h_t *h = (lui_h_t *)self;
  if (h->tok > 0) {
    char tok[24];
    char *u = lui_u8(json);
    snprintf(tok, sizeof tok, "%d", h->tok);
    if (hr != 0) lui_wv_push(h->core, 4, tok, "Error: script failed");
    else lui_wv_push(h->core, 4, tok, u);
    free(u);
  }
  free(h);
  return 0;
}

static lui_hresult LUI_STDCALL lui_on_capture_done(void *self,
                                                 lui_hresult hr)
{
  lui_h_t *h = (lui_h_t *)self;
  if (hr != 0) h->core->cap_fail = 1;
  h->core->cap_done = 1;
  return 0;
}

static lui_wv_handlers *lui_handlers_new(void)
{
  lui_wv_handlers *hs = (lui_wv_handlers *)calloc(1, sizeof *hs);
  if (hs == NULL) return NULL;
  hs->env = lui_h_vt((void *)lui_on_env);
  hs->ctl = lui_h_vt((void *)lui_on_ctl);
  hs->nav_start = lui_h_vt((void *)lui_on_nav_start);
  hs->nav_done = lui_h_vt((void *)lui_on_nav_done);
  hs->msg = lui_h_vt((void *)lui_on_msg);
  hs->script = lui_h_vt((void *)lui_on_script_done);
  hs->cap = lui_h_vt((void *)lui_on_capture_done);
  return hs;
}

static void lui_handlers_free(lui_wv_handlers *hs)
{
  if (hs == NULL) return;
  free(hs->nav_start_obj); free(hs->nav_done_obj); free(hs->msg_obj);
  free(hs->env); free(hs->ctl); free(hs->nav_start); free(hs->nav_done);
  free(hs->msg); free(hs->script); free(hs->cap);
  free(hs);
}

typedef long (LUI_STDCALL *lui_wv2_create_fn)(void *, void *, void *,
                                             void *);

static void *lui_wv2_loader(void)
{
  static void *proc;
  static int tried;
  void *lib;
  if (tried) return proc;
  tried = 1;
  lib = LoadLibraryW(L"WebView2Loader.dll");
  if (lib != NULL)
    proc = (void *)GetProcAddress(lib,
                          "CreateCoreWebView2EnvironmentWithOptions");
  return proc;
}

static void lui_win_create(LuiWv *w, value vhost,
                           double x, double y, double ww, double hh)
{
  lui_wv2_create_fn create_env;
  lui_wv_handlers *hs;
  lui_h_t *eh;
  create_env = (lui_wv2_create_fn)lui_wv2_loader();
  if (create_env == NULL)
    lui_wv_die("WebView2Loader.dll not found (WebView2 runtime)");
  w->hwnd = (void *)(intnat)Nativeint_val(vhost);
  hs = lui_handlers_new();
  if (hs == NULL) caml_raise_out_of_memory();
  w->hs = hs;
  eh = lui_h_new(hs->env, w, 0, hs->ctl);
  if (eh == NULL) caml_raise_out_of_memory();
  /* Persistent handler objects for the registered events (created
     before the env dance so on_ctl can register them). */
  hs->nav_start_obj = lui_h_new(hs->nav_start, w, 0, NULL);
  hs->nav_done_obj = lui_h_new(hs->nav_done, w, 0, NULL);
  hs->msg_obj = lui_h_new(hs->msg, w, 0, NULL);
  if (hs->nav_start_obj == NULL || hs->nav_done_obj == NULL ||
      hs->msg_obj == NULL)
    caml_raise_out_of_memory();
  /* CreateCoreWebView2EnvironmentWithOptions(exeFolder, userFolder,
                                              options, handler) */
  create_env(NULL, NULL, NULL, eh);
  while (!w->core->ready && !w->core->failed)
    lui_win_pump_once();
  if (w->core->failed || w->wv == NULL || w->ctl == NULL)
    lui_wv_die("WebView2 controller creation failed");
  {
    lui_rect_t r;
    r.left = (long)x; r.top = (long)y;
    r.right = (long)(x + ww); r.bottom = (long)(y + hh);
    LUI_CALL1(w->ctl, LUI_CTL_PUT_BOUNDS, lui_hresult, lui_rect_t, r);
    LUI_CALL1(w->ctl, LUI_CTL_PUT_VISIBLE, lui_hresult, int, 1);
  }
}

static void lui_win_destroy(LuiWv *w)
{
  if (w->ctl != NULL)
    LUI_CALL0(w->ctl, LUI_CTL_CLOSE, lui_hresult);
  lui_handlers_free((lui_wv_handlers *)w->hs);
  w->hs = NULL;
}

static void lui_win_load_url(LuiWv *w, const char *u)
{
  wchar_t *s = lui_u16(u);
  if (s == NULL) return;
  w->core->loading = 1;
  LUI_CALL1(w->wv, LUI_WV_NAVIGATE, lui_hresult, wchar_t *, s);
  free(s);
}

static void lui_win_load_html(LuiWv *w, const char *h, const char *b)
{
  wchar_t *s = lui_u16(h);
  (void)b;
  if (s == NULL) return;
  w->core->loading = 1;
  LUI_CALL1(w->wv, LUI_WV_NAVIGATE_TO_STRING, lui_hresult, wchar_t *, s);
  free(s);
}

static void lui_win_load_file(LuiWv *w, const char *p)
{
  char url[4096];
  snprintf(url, sizeof url, "file:///%s", p);
  lui_win_load_url(w, url);
}

static void lui_win_nav(LuiWv *w, int d)
{
  switch (d) {
  case 0: LUI_CALL0(w->wv, LUI_WV_GO_BACK, lui_hresult); break;
  case 1: LUI_CALL0(w->wv, LUI_WV_GO_FORWARD, lui_hresult); break;
  case 2: LUI_CALL0(w->wv, LUI_WV_RELOAD, lui_hresult); break;
  case 3: LUI_CALL0(w->wv, LUI_WV_STOP, lui_hresult); break;
  default: break;
  }
}

static int lui_win_can_nav(LuiWv *w)
{
  int back = 0, fwd = 0;
  LUI_CALL1(w->wv, LUI_WV_GET_CAN_GO_BACK, lui_hresult, int *, &back);
  LUI_CALL1(w->wv, LUI_WV_GET_CAN_GO_FORWARD, lui_hresult, int *, &fwd);
  return (back ? 1 : 0) | (fwd ? 2 : 0);
}

static value lui_win_url(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  wchar_t *src = NULL;
  char *u;
  LUI_CALL1(w->wv, LUI_WV_GET_SOURCE, lui_hresult, wchar_t **, &src);
  u = lui_u8(src);
  s = caml_copy_string(u);
  free(u);
  if (src != NULL) CoTaskMemFree(src);
  CAMLreturn(s);
}

static int lui_win_is_loading(LuiWv *w) { return w->core->loading; }

static void lui_win_eval(LuiWv *w, const char *js)
{
  lui_h_t *h;
  wchar_t *s = lui_u16(js);
  if (s == NULL) return;
  h = lui_h_new(((lui_wv_handlers *)w->hs)->script, w, 0, NULL);
  if (h == NULL) { free(s); return; }
  LUI_CALL2(w->wv, LUI_WV_EXECUTE_SCRIPT, lui_hresult,
            wchar_t *, s, void *, h);
  free(s);
}

static void lui_win_call_async(LuiWv *w, int tok, const char *js)
{
  /* ExecuteScript does not await promises; deliver through the
     web-message channel as "tok\njson" — decoded like other tag-4
     results. */
  const char *tmpl =
    "(async()=>{try{var v=await(async()=>{%s})();"
    "chrome.webview.postMessage('%d\\n'+JSON.stringify(v))}"
    "catch(e){chrome.webview.postMessage("
    "'%d\\n\"Error: \"+e)}})()";
  char *body = (char *)malloc(strlen(tmpl) + strlen(js) + 64);
  wchar_t *s;
  lui_h_t *h;
  if (body == NULL) caml_raise_out_of_memory();
  sprintf(body, tmpl, js, tok, tok);
  s = lui_u16(body);
  h = lui_h_new(((lui_wv_handlers *)w->hs)->script, w, 0, NULL);
  free(body);
  if (s == NULL || h == NULL) { free(s); free(h); return; }
  LUI_CALL2(w->wv, LUI_WV_EXECUTE_SCRIPT, lui_hresult,
            wchar_t *, s, void *, h);
  free(s);
}

static void lui_win_set_zoom(LuiWv *w, double z)
{
  LUI_CALL1(w->ctl, LUI_CTL_PUT_ZOOM, lui_hresult, double, z);
}

static double lui_win_zoom(LuiWv *w)
{
  double z = 1.0;
  LUI_CALL1(w->ctl, LUI_CTL_GET_ZOOM, lui_hresult, double *, &z);
  return z;
}

static void lui_win_set_ua(LuiWv *w, const char *ua)
{
  void *settings = NULL;
  void *s2 = NULL;
  wchar_t *s;
  LUI_CALL1(w->wv, LUI_WV_GET_SETTINGS, lui_hresult,
            void **, &settings);
  if (settings == NULL) return;
  LUI_CALL2(settings, 0 /*QueryInterface*/, lui_hresult,
            const void *, lui_iid_settings2, void **, &s2);
  if (s2 == NULL) return;
  s = lui_u16(ua);
  if (s == NULL) return;
  LUI_CALL1(s2, LUI_SET2_PUT_USER_AGENT, lui_hresult, wchar_t *, s);
  free(s);
}

static value lui_win_ua(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  (void)w;
  s = caml_copy_string("");
  CAMLreturn(s);
}

static void lui_win_set_transparent(LuiWv *w, int on)
{
  /* ICoreWebView2Controller2 put_DefaultBackgroundColor (index 27)
     needs another QI — left for a later change. */
  (void)w; (void)on;
}

static void lui_win_set_frame(LuiWv *w, double x, double y,
                              double ww, double hh)
{
  lui_rect_t r;
  r.left = (long)x; r.top = (long)y;
  r.right = (long)(x + ww); r.bottom = (long)(y + hh);
  LUI_CALL1(w->ctl, LUI_CTL_PUT_BOUNDS, lui_hresult, lui_rect_t, r);
}

static value lui_win_frame(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(t);
  lui_rect_t r;
  memset(&r, 0, sizeof r);
  LUI_CALL1(w->ctl, LUI_CTL_GET_BOUNDS, lui_hresult, lui_rect_t *, &r);
  t = caml_alloc_tuple(4);
  Store_field(t, 0, caml_copy_double((double)r.left));
  Store_field(t, 1, caml_copy_double((double)r.top));
  Store_field(t, 2, caml_copy_double((double)(r.right - r.left)));
  Store_field(t, 3, caml_copy_double((double)(r.bottom - r.top)));
  CAMLreturn(t);
}

static void lui_win_set_visible(LuiWv *w, int v)
{
  LUI_CALL1(w->ctl, LUI_CTL_PUT_VISIBLE, lui_hresult, int, v);
}

static value lui_win_capture(LuiWv *w)
{
  CAMLparam0();
  CAMLlocal1(s);
  void *stm = NULL;
  void *hg = NULL;
  void *buf;
  unsigned long n;
  lui_h_t *h;
  s = caml_copy_string("");
  if (CreateStreamOnHGlobal(NULL, 1, (void *)&stm) != 0 || stm == NULL)
    CAMLreturn(s);
  w->core->cap_done = 0;
  w->core->cap_fail = 0;
  h = lui_h_new(((lui_wv_handlers *)w->hs)->cap, w, 0, NULL);
  if (h != NULL) {
    /* CapturePreview(format 0 = PNG, IStream*, handler) */
    LUI_CALL3(w->wv, LUI_WV_CAPTURE_PREVIEW, lui_hresult,
              int, 0, void *, stm, void *, h);
    lui_win_pump_until(&w->core->cap_done);
  }
  if (!w->core->cap_fail &&
      GetHGlobalFromStream(stm, &hg) == 0 && hg != NULL &&
      (buf = GlobalLock(hg)) != NULL && (n = GlobalSize(hg)) > 0) {
    s = caml_alloc_initialized_string((mlsize_t)n, (const char *)buf);
    GlobalUnlock(hg);
  }
  LUI_CALL0(stm, LUI_STREAM_RELEASE, lui_ulong);
  free(h);
  CAMLreturn(s);
}

static void lui_win_pump_once(void)
{
  lui_msg_t m;
  if (PeekMessageW((void *)&m, NULL, 0, 0, 1)) {
    TranslateMessage((const void *)&m);
    DispatchMessageW((const void *)&m);
  } else {
    Sleep(1);
  }
}

#endif /* _WIN32 */

/* ===================================================================== */
/* =============== shared OCaml entry points =========================== */

CAMLprim value lui_wv_backend_name(value unit)
{
  CAMLparam1(unit);
  CAMLlocal1(s);
#if defined(__APPLE__)
  s = caml_copy_string("wkwebview");
#elif defined(__linux__)
  s = caml_copy_string("webkit2gtk");
#elif defined(_WIN32)
  s = caml_copy_string("webview2");
#else
  s = caml_copy_string("none");
#endif
  CAMLreturn(s);
}

CAMLprim value lui_wv_host_of_sdl(value vsdl)
{
  CAMLparam1(vsdl);
#ifdef LUI_WV_SDL
  {
    CAMLlocal1(v);
    SDL_Window *win = (SDL_Window *)(intnat)Nativeint_val(vsdl);
    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (win == NULL || !SDL_GetWindowWMInfo(win, &info))
      lui_wv_die("SDL_GetWindowWMInfo failed");
# if defined(__APPLE__)
    if (info.subsystem != SDL_SYSWM_COCOA)
      lui_wv_die("SDL window is not Cocoa");
    v = caml_copy_nativeint((intnat)info.info.cocoa.window);
# elif defined(__linux__)
    if (info.subsystem != SDL_SYSWM_X11)
      lui_wv_die("SDL window is not X11 (Wayland unsupported)");
    v = caml_copy_nativeint((intnat)info.info.x11.window);
# elif defined(_WIN32)
    v = caml_copy_nativeint((intnat)info.info.win.window);
# else
    v = caml_copy_nativeint(0);
# endif
    CAMLreturn(v);
  }
#else
  (void)vsdl;
  lui_wv_die("built without SDL2 headers");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value lui_wv_host_main(value unit)
{
  CAMLparam1(unit);
#if defined(__APPLE__)
  {
    CAMLlocal1(v);
    NSWindow *win = [NSApp mainWindow];
    if (win == nil && [[NSApp windows] count] > 0)
      win = [[NSApp windows] objectAtIndex:0];
    if (win == nil) lui_wv_die("no NSWindow");
    v = caml_copy_nativeint((intnat)win);
    CAMLreturn(v);
  }
#else
  (void)unit;
  lui_wv_die("host_main_window unsupported on this platform");
  CAMLreturn(Val_unit);
#endif
}

CAMLprim value lui_wv_create(value vhost, value vx, value vy, value vw,
                             value vh)
{
  CAMLparam5(vhost, vx, vy, vw, vh);
  CAMLlocal1(v);
  LuiWv *w = (LuiWv *)calloc(1, sizeof *w);
  w->core = (LuiWvCore *)calloc(1, sizeof *w->core);
  double x = Double_val(vx), y = Double_val(vy);
  double ww = Double_val(vw), hh = Double_val(vh);
  if (w == NULL) caml_raise_out_of_memory();
#if defined(__APPLE__)
  lui_wv_mac_create(w, vhost, x, y, ww, hh);
#elif defined(__linux__)
  lui_gtk_create(w, vhost, x, y, ww, hh);
#elif defined(_WIN32)
  lui_win_create(w, vhost, x, y, ww, hh);
#else
  (void)vhost;
  lui_wv_die("no webview backend on this platform");
#endif
  v = caml_copy_nativeint((intnat)w);
  CAMLreturn(v);
}

CAMLprim value lui_wv_create_bc(value *argv, int argc)
{
  (void)argc;
  return lui_wv_create(argv[0], argv[1], argv[2], argv[3], argv[4]);
}

CAMLprim value lui_wv_destroy(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
  /* Mark dead first: any engine callback fired during or after
     teardown drops its events. The core sentinel itself is
     intentionally left allocated (see LuiWvCore) because outstanding
     callbacks cannot be counted. */
  w->core->dead = 1;
#if defined(__APPLE__)
  lui_wv_mac_destroy(w);
#elif defined(__linux__)
  if (G.ok) lui_gtk_destroy(w);
#elif defined(_WIN32)
  lui_win_destroy(w);
#endif
  lui_wv_free_queue(w->core);
  free(w);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_load_url(value v, value u)
{
  CAMLparam2(v, u);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_load_url(w, String_val(u));
#elif defined(__linux__)
  if (G.ok) lui_gtk_load_url(w, String_val(u));
#elif defined(_WIN32)
  lui_win_load_url(w, String_val(u));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_load_html(value v, value h, value b)
{
  CAMLparam3(v, h, b);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_load_html(w, String_val(h), String_val(b));
#elif defined(__linux__)
  if (G.ok) lui_gtk_load_html(w, String_val(h), String_val(b));
#elif defined(_WIN32)
  lui_win_load_html(w, String_val(h), String_val(b));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_load_file(value v, value p)
{
  CAMLparam2(v, p);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_load_file(w, String_val(p));
#elif defined(__linux__)
  if (G.ok) lui_gtk_load_file(w, String_val(p));
#elif defined(_WIN32)
  lui_win_load_file(w, String_val(p));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_nav(value v, value d)
{
  CAMLparam2(v, d);
  LuiWv *w = lui_wv_wv(v);
  int dir = Int_val(d);
#if defined(__APPLE__)
  lui_wv_mac_nav(w, dir);
#elif defined(__linux__)
  if (G.ok) lui_gtk_nav(w, dir);
#elif defined(_WIN32)
  lui_win_nav(w, dir);
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_can_nav(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
  int r = 0;
#if defined(__APPLE__)
  r = lui_wv_mac_can_nav(w);
#elif defined(__linux__)
  if (G.ok) r = lui_gtk_can_nav(w);
#elif defined(_WIN32)
  r = lui_win_can_nav(w);
#endif
  CAMLreturn(Val_int(r));
}

CAMLprim value lui_wv_url(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  CAMLreturn(lui_wv_mac_url(w));
#elif defined(__linux__)
  if (G.ok) CAMLreturn(lui_gtk_url(w));
#elif defined(_WIN32)
  CAMLreturn(lui_win_url(w));
#endif
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_wv_is_loading(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
  int r = 0;
#if defined(__APPLE__)
  r = lui_wv_mac_is_loading(w);
#elif defined(__linux__)
  if (G.ok) r = lui_gtk_is_loading(w);
#elif defined(_WIN32)
  r = lui_win_is_loading(w);
#endif
  CAMLreturn(Val_bool(r));
}

CAMLprim value lui_wv_eval(value v, value js)
{
  CAMLparam2(v, js);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_eval(w, String_val(js));
#elif defined(__linux__)
  if (G.ok) lui_gtk_eval(w, String_val(js));
#elif defined(_WIN32)
  lui_win_eval(w, String_val(js));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_call_async(value v, value tok, value js)
{
  CAMLparam3(v, tok, js);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_call_async(w, Int_val(tok), String_val(js));
#elif defined(__linux__)
  if (G.ok) lui_gtk_call_async(w, Int_val(tok), String_val(js));
#elif defined(_WIN32)
  lui_win_call_async(w, Int_val(tok), String_val(js));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_set_zoom(value v, value z)
{
  CAMLparam2(v, z);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_set_zoom(w, Double_val(z));
#elif defined(__linux__)
  if (G.ok) lui_gtk_set_zoom(w, Double_val(z));
#elif defined(_WIN32)
  lui_win_set_zoom(w, Double_val(z));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_zoom(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
  double r = 1.0;
#if defined(__APPLE__)
  r = lui_wv_mac_zoom(w);
#elif defined(__linux__)
  if (G.ok) r = lui_gtk_zoom(w);
#elif defined(_WIN32)
  r = lui_win_zoom(w);
#endif
  CAMLreturn(caml_copy_double(r));
}

CAMLprim value lui_wv_set_user_agent(value v, value u)
{
  CAMLparam2(v, u);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_set_ua(w, String_val(u));
#elif defined(__linux__)
  if (G.ok) lui_gtk_set_ua(w, String_val(u));
#elif defined(_WIN32)
  lui_win_set_ua(w, String_val(u));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_user_agent(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  CAMLreturn(lui_wv_mac_ua(w));
#elif defined(__linux__)
  if (G.ok) CAMLreturn(lui_gtk_ua(w));
#elif defined(_WIN32)
  CAMLreturn(lui_win_ua(w));
#endif
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_wv_set_transparent(value v, value on)
{
  CAMLparam2(v, on);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_set_transparent(w, Bool_val(on));
#elif defined(__linux__)
  if (G.ok) lui_gtk_set_transparent(w, Bool_val(on));
#elif defined(_WIN32)
  lui_win_set_transparent(w, Bool_val(on));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_set_frame(value v, value x, value y, value w_,
                                value h_)
{
  CAMLparam5(v, x, y, w_, h_);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_set_frame(w, Double_val(x), Double_val(y), Double_val(w_),
                       Double_val(h_));
#elif defined(__linux__)
  if (G.ok) lui_gtk_set_frame(w, Double_val(x), Double_val(y),
                              Double_val(w_), Double_val(h_));
#elif defined(_WIN32)
  lui_win_set_frame(w, Double_val(x), Double_val(y), Double_val(w_),
                    Double_val(h_));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_set_frame_bc(value *argv, int argc)
{
  (void)argc;
  return lui_wv_set_frame(argv[0], argv[1], argv[2], argv[3], argv[4]);
}

CAMLprim value lui_wv_frame(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  CAMLreturn(lui_wv_mac_frame(w));
#elif defined(__linux__)
  if (G.ok) CAMLreturn(lui_gtk_frame(w));
#elif defined(_WIN32)
  CAMLreturn(lui_win_frame(w));
#endif
  {
    CAMLlocal1(t);
    t = caml_alloc_tuple(4);
    Store_field(t, 0, caml_copy_double(0));
    Store_field(t, 1, caml_copy_double(0));
    Store_field(t, 2, caml_copy_double(0));
    Store_field(t, 3, caml_copy_double(0));
    CAMLreturn(t);
  }
}

CAMLprim value lui_wv_set_visible(value v, value b)
{
  CAMLparam2(v, b);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  lui_wv_mac_set_visible(w, Bool_val(b));
#elif defined(__linux__)
  if (G.ok) lui_gtk_set_visible(w, Bool_val(b));
#elif defined(_WIN32)
  lui_win_set_visible(w, Bool_val(b));
#endif
  CAMLreturn(Val_unit);
}

CAMLprim value lui_wv_capture(value v)
{
  CAMLparam1(v);
  LuiWv *w = lui_wv_wv(v);
#if defined(__APPLE__)
  CAMLreturn(lui_wv_mac_capture(w));
#elif defined(__linux__)
  if (G.ok) CAMLreturn(lui_gtk_capture(w));
#elif defined(_WIN32)
  CAMLreturn(lui_win_capture(w));
#endif
  CAMLreturn(caml_copy_string(""));
}

CAMLprim value lui_wv_next_event(value v)
{
  CAMLparam1(v);
  CAMLlocal3(t, s, o);
  LuiWv *w = lui_wv_wv(v);
  lui_wv_ev *e = w->core->head;
  if (e == NULL) CAMLreturn(Val_int(0));
  w->core->head = e->next;
  if (w->core->head == NULL) w->core->tail = NULL;
  t = caml_alloc_tuple(3);
  s = caml_copy_string(e->a != NULL ? e->a : "");
  Store_field(t, 0, Val_int(e->tag));
  Store_field(t, 1, s);
  s = caml_copy_string(e->b != NULL ? e->b : "");
  Store_field(t, 2, s);
  o = caml_alloc(1, 0);
  Store_field(o, 0, t);
  free(e->a);
  free(e->b);
  free(e);
  CAMLreturn(o);
}

CAMLprim value lui_wv_pump(value unit)
{
  CAMLparam1(unit);
#if defined(__APPLE__)
  lui_wv_mac_pump();
#elif defined(__linux__)
  lui_gtk_pump();
#elif defined(_WIN32)
  lui_win_pump();
#endif
  CAMLreturn(Val_unit);
}
