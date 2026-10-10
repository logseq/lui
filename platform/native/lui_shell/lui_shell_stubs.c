/* Desktop shell services for the native backend: app identity, the
   status-bar item, native menus, notifications, the clipboard, file
   dialogs and open-url handling.

   Compiled as Objective-C (see the dune file) for AppKit and
   UserNotifications; manual retain/release throughout, matching the
   other native stubs. Every external fails cleanly off macOS so the
   library still builds everywhere.

   Callbacks into OCaml: each event kind has a single handler,
   registered by lui_shell.ml under a fixed named value. Dispatch must
   run on the main thread — the app's event pump (and therefore the
   OCaml domain) lives there. Handlers fired off the main thread are
   bounced to the main queue; handlers fired on it call back
   reentrantly, which is legal while the domain is inside a C call —
   exactly the context the run loop fires them from. */

#if defined(__APPLE__)

#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <dispatch/dispatch.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/printexc.h>
#include <string.h>
#include <stdio.h>

/* ------------------------------------------------------------ helpers */

static NSString *lui_nsstring(value v)
{
  mlsize_t len = caml_string_length(v);
  NSString *s = [[NSString alloc] initWithBytes:Bytes_val(v)
                                 length:(NSUInteger)len
                                 encoding:NSUTF8StringEncoding];
  if (s == nil) {
    /* A byte string that is not UTF-8 survives as Latin-1. */
    s = [[NSString alloc] initWithBytes:Bytes_val(v)
           length:(NSUInteger)len
           encoding:NSISOLatin1StringEncoding];
  }
  return [s autorelease];
}

static value lui_ocamlstring(NSString *s)
{
  CAMLparam0();
  CAMLlocal1(v);
  NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
  if (d == nil) CAMLreturn(caml_alloc_initialized_string(0, ""));
  v = caml_alloc_initialized_string((mlsize_t)[d length],
                                    (const char *)[d bytes]);
  CAMLreturn(v);
}

static void lui_log_exn(value res, const char *name)
{
  if (Is_exception_result(res)) {
    char *msg = caml_format_exception(Extract_exception(res));
    fprintf(stderr, "lui_shell: %s callback raised: %s\n", name, msg);
    caml_stat_free(msg);
  }
}

static void lui_cb_int(const char *name, intnat v)
{
  const value *cb = caml_named_value(name);
  if (cb == NULL) return;
  CAMLparam0();
  lui_log_exn(caml_callback_exn(*cb, Val_long(v)), name);
  CAMLreturn0;
}

static void lui_cb_str(const char *name, NSString *s)
{
  const value *cb = caml_named_value(name);
  if (cb == NULL || s == nil) return;
  CAMLparam0();
  CAMLlocal1(vs);
  vs = lui_ocamlstring(s);
  lui_log_exn(caml_callback_exn(*cb, vs), name);
  CAMLreturn0;
}

/* Main-thread dispatch: call directly when already there, queue the
   call otherwise. A copied block retains the objects it captures, so
   the NSString* stays alive until the queued call runs. */
static void lui_dispatch_int(const char *name, intnat v)
{
  if ([NSThread isMainThread]) {
    lui_cb_int(name, v);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      lui_cb_int(name, v);
    });
  }
}

static void lui_dispatch_str(const char *name, NSString *s)
{
  if (s == nil) return;
  if ([NSThread isMainThread]) {
    lui_cb_str(name, s);
  } else {
    dispatch_async(dispatch_get_main_queue(), ^{
      lui_cb_str(name, s);
    });
  }
}

/* ------------------------------------------------------ event target */

/* One object serves as the target of menu items, status-item buttons,
   Apple-event get-url delivery, and both notification delegates.
   Lazily allocated, never released. */
@interface LuiShellHandler : NSObject
  <UNUserNotificationCenterDelegate, NSUserNotificationCenterDelegate>
@end

@implementation LuiShellHandler

- (void)menuAction:(id)sender
{
  lui_dispatch_int("lui_shell_menu_select", (intnat)[sender tag]);
}

- (void)statusItemAction:(id)sender
{
  lui_dispatch_int("lui_shell_status_click", (intnat)[sender tag]);
}

- (void)getURL:(NSAppleEventDescriptor *)event
    withReplyEvent:(NSAppleEventDescriptor *)reply
{
  (void)reply;
  NSString *url =
    [[event paramDescriptorForKeyword:keyDirectObject] stringValue];
  lui_dispatch_str("lui_shell_open_url", url);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
{
  (void)center;
  NSString *ident = [[response notification] request] == nil
    ? nil : [[[response notification] request] identifier];
  lui_dispatch_str("lui_shell_notify_click", ident);
  if (completionHandler != NULL) completionHandler();
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    willPresentNotification:(UNNotification *)notification
    withCompletionHandler:(void (^)(UNNotificationPresentationOptions))
      completionHandler
{
  (void)center;
  (void)notification;
  if (completionHandler != NULL) {
    completionHandler(UNNotificationPresentationOptionBanner |
                      UNNotificationPresentationOptionSound);
  }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
    didActivateNotification:(NSUserNotification *)notification
{
  (void)center;
  lui_dispatch_str("lui_shell_notify_click", [notification identifier]);
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
    shouldPresentNotification:(NSUserNotification *)notification
{
  (void)center;
  (void)notification;
  return YES;
}

@end

static LuiShellHandler *lui_handler(void)
{
  static LuiShellHandler *h = nil;
  if (h == nil) h = [[LuiShellHandler alloc] init];
  return h;
}

/* ----------------------------------------------------- custom blocks */

#define Lui_image_val(v) (*(NSImage **)Data_custom_val(v))
#define Lui_si_val(v) (*(NSStatusItem **)Data_custom_val(v))

static void lui_image_finalize(value v)
{
  [Lui_image_val(v) release];
}

static void lui_si_finalize(value v)
{
  NSStatusItem *item = Lui_si_val(v);
  if (item != nil) {
    [[NSStatusBar systemStatusBar] removeStatusItem:item];
    [item release];
    Lui_si_val(v) = nil;
  }
}

static struct custom_operations lui_image_ops = {
  "lui_shell.image",
  lui_image_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static struct custom_operations lui_si_ops = {
  "lui_shell.status_item",
  lui_si_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static value lui_wrap_image(NSImage *img)
{
  value v = caml_alloc_custom(&lui_image_ops, sizeof(NSImage *), 0, 1);
  Lui_image_val(v) = img;
  return v;
}

static value lui_wrap_si(NSStatusItem *item)
{
  value v = caml_alloc_custom(&lui_si_ops, sizeof(NSStatusItem *), 0, 1);
  Lui_si_val(v) = item;
  return v;
}

/* -------------------------------------------------------- menu build */

/* Rows from the OCaml side: (depth, kind, label, id, enabled, checked)
   with kind 0 item, 1 separator, 2 submenu; a submenu's children follow
   it at depth+1. Returns a retained NSMenu. */
static NSMenu *lui_menu_build(NSString *title, value rows)
{
  NSMenu *root = [[NSMenu alloc] initWithTitle:title];
  NSMutableArray *stack = [[NSMutableArray alloc] initWithCapacity:4];
  [stack addObject:root];
  mlsize_t n = Wosize_val(rows);
  for (mlsize_t i = 0; i < n; i++) {
    value row = Field(rows, i);
    int depth = Int_val(Field(row, 0));
    int kind = Int_val(Field(row, 1));
    NSString *label = lui_nsstring(Field(row, 2));
    int ident = Int_val(Field(row, 3));
    BOOL enabled = Int_val(Field(row, 4)) != 0;
    BOOL checked = Int_val(Field(row, 5)) != 0;

    /* The parent of a row at [depth] is the menu on top of the stack
       once everything deeper is popped. */
    while ((NSInteger)[stack count] > depth + 1)
      [stack removeLastObject];
    if ((NSInteger)[stack count] != depth + 1) continue;

    NSMenu *parent = [stack objectAtIndex:(NSUInteger)depth];
    if (kind == 1) {
      [parent addItem:[NSMenuItem separatorItem]];
    } else if (kind == 2) {
      NSMenu *sub = [[NSMenu alloc] initWithTitle:label];
      NSMenuItem *mi = [[NSMenuItem alloc]
          initWithTitle:label action:NULL keyEquivalent:@""];
      [mi setEnabled:enabled];
      [mi setSubmenu:sub];
      [parent addItem:mi];
      [stack addObject:sub];
      [sub release];
      [mi release];
    } else {
      NSMenuItem *mi = [[NSMenuItem alloc]
          initWithTitle:label
                 action:@selector(menuAction:)
          keyEquivalent:@""];
      [mi setTarget:lui_handler()];
      [mi setTag:ident];
      [mi setEnabled:enabled];
      [mi setState:checked ? NSControlStateValueOn
                           : NSControlStateValueOff];
      [parent addItem:mi];
      [mi release];
    }
  }
  [stack release];
  return root;
}

/* ------------------------------------------------------- app identity */

/* NSApp stays nil until the shared application is materialized; every
   app-level call goes through here first so the object exists (and so
   object retention like [NSApp setMainMenu:] actually retains). */
static NSApplication *lui_app(void)
{
  return [NSApplication sharedApplication];
}

CAMLprim value lui_sh_policy_set(value vpolicy)
{
  CAMLparam1(vpolicy);
  NSInteger p = (NSInteger)Int_val(vpolicy);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      lui_app();
      ok = [NSApp setActivationPolicy:(NSApplicationActivationPolicy)p];
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_sh_policy_get(value unit)
{
  CAMLparam1(unit);
  NSInteger p = -1;
  @autoreleasepool {
    @try {
      p = [lui_app() activationPolicy];
    } @catch (NSException *e) {
      p = -1;
    }
  }
  CAMLreturn(Val_int(p));
}

CAMLprim value lui_sh_set_app_name(value vname)
{
  CAMLparam1(vname);
  @autoreleasepool {
    @try {
      NSString *name = lui_nsstring(vname);
      NSMenu *mb = [lui_app() mainMenu];
      if (mb == nil) {
        mb = [[NSMenu alloc] init];
        [lui_app() setMainMenu:mb];
        [mb release];
      }
      if ([mb numberOfItems] == 0) {
        /* No application menu yet: install one with a submenu carrying
           the name, like the system-built app menu. */
        NSMenuItem *app_item = [[NSMenuItem alloc] init];
        NSMenu *app_menu = [[NSMenu alloc] initWithTitle:name];
        [app_item setSubmenu:app_menu];
        [mb addItem:app_item];
        [app_menu release];
        [app_item release];
      } else {
        NSMenu *app_menu = [[mb itemAtIndex:0] submenu];
        if (app_menu != nil) [app_menu setTitle:name];
      }
    } @catch (NSException *e) {
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_sh_dock_badge(value vopt)
{
  CAMLparam1(vopt);
  @autoreleasepool {
    @try {
      NSString *s = Is_block(vopt) ? lui_nsstring(Field(vopt, 0)) : nil;
      [[lui_app() dockTile] setBadgeLabel:s];
    } @catch (NSException *e) {
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_sh_attention(value vcritical)
{
  CAMLparam1(vcritical);
  NSInteger req = -1;
  @autoreleasepool {
    @try {
      req = [lui_app() requestUserAttention:
              Bool_val(vcritical) ? NSCriticalRequest
                                  : NSInformationalRequest];
    } @catch (NSException *e) {
      req = -1;
    }
  }
  CAMLreturn(Val_int(req));
}

CAMLprim value lui_sh_window_title(value vtitle)
{
  CAMLparam1(vtitle);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      NSApplication *app = lui_app();
      NSWindow *w = [app mainWindow];
      if (w == nil) w = [app keyWindow];
      if (w == nil && [[app windows] count] > 0)
        w = [[app windows] objectAtIndex:0];
      if (w != nil) {
        [w setTitle:lui_nsstring(vtitle)];
        ok = YES;
      }
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

/* ------------------------------------------------------------- image */

CAMLprim value lui_sh_image_rgba(value vw, value vh, value vbytes)
{
  CAMLparam3(vw, vh, vbytes);
  CAMLlocal2(vopt, vimg);
  int w = Int_val(vw);
  int h = Int_val(vh);
  NSImage *img = nil;
  if (w > 0 && h > 0 &&
      (size_t)caml_string_length(vbytes) >= (size_t)(w * h * 4)) {
    @autoreleasepool {
      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL
                      pixelsWide:(NSInteger)w
                      pixelsHigh:(NSInteger)h
                   bitsPerSample:8
                 samplesPerPixel:4
                        hasAlpha:YES
                        isPlanar:NO
                  colorSpaceName:NSDeviceRGBColorSpace
                    bitmapFormat:NSBitmapFormatAlphaNonpremultiplied
                     bytesPerRow:(NSInteger)(w * 4)
                    bitsPerPixel:32];
      if (rep != nil) {
        memcpy([rep bitmapData], Bytes_val(vbytes), (size_t)(w * h * 4));
        img = [[NSImage alloc] initWithSize:NSMakeSize(w, h)];
        [img addRepresentation:rep];
        [rep release];
      }
    }
  }
  if (img == nil) CAMLreturn(Val_int(0));
  vimg = lui_wrap_image(img);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vimg);
  CAMLreturn(vopt);
}

CAMLprim value lui_sh_image_size(value vimg)
{
  CAMLparam1(vimg);
  CAMLlocal1(vsize);
  NSSize s = NSMakeSize(0, 0);
  @autoreleasepool {
    s = [Lui_image_val(vimg) size];
  }
  vsize = caml_alloc(2, 0);
  Store_field(vsize, 0, caml_copy_double(s.width));
  Store_field(vsize, 1, caml_copy_double(s.height));
  CAMLreturn(vsize);
}

/* ------------------------------------------------------------- menus */

CAMLprim value lui_sh_menubar_insert(value vtitle, value vrows,
                                     value vat)
{
  CAMLparam3(vtitle, vrows, vat);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      NSMenu *mb = [lui_app() mainMenu];
      if (mb == nil) {
        mb = [[NSMenu alloc] init];
        [lui_app() setMainMenu:mb];
        [mb release];
      }
      NSInteger at = (NSInteger)Int_val(vat);
      NSInteger count = [mb numberOfItems];
      if (at < 0) at = count + at;
      if (at < 0) at = 0;
      if (at > count) at = count;
      NSMenu *menu = lui_menu_build(lui_nsstring(vtitle), vrows);
      NSMenuItem *top = [[NSMenuItem alloc] init];
      [top setTitle:lui_nsstring(vtitle)];
      [top setSubmenu:menu];
      [mb insertItem:top atIndex:at];
      [top release];
      [menu release];
      ok = YES;
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_sh_menubar_count(value unit)
{
  CAMLparam1(unit);
  NSInteger n = 0;
  @autoreleasepool {
    NSMenu *mb = [lui_app() mainMenu];
    if (mb != nil) n = [mb numberOfItems];
  }
  CAMLreturn(Val_int(n));
}

CAMLprim value lui_sh_menubar_remove(value vat)
{
  CAMLparam1(vat);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      NSMenu *mb = [lui_app() mainMenu];
      NSInteger at = (NSInteger)Int_val(vat);
      if (mb != nil && at >= 0 && at < [mb numberOfItems]) {
        [mb removeItemAtIndex:at];
        ok = YES;
      }
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

/* ------------------------------------------------------- status item */

CAMLprim value lui_sh_status_create(value vtag)
{
  CAMLparam1(vtag);
  CAMLlocal1(vsi);
  NSStatusItem *item = nil;
  @autoreleasepool {
    item = [[NSStatusBar systemStatusBar]
      statusItemWithLength:NSVariableStatusItemLength];
    [item retain];
    if (item != nil && [item button] != nil) {
      [[item button] setTag:(NSInteger)Int_val(vtag)];
      [[item button] setTarget:lui_handler()];
      [[item button] setAction:@selector(statusItemAction:)];
    }
  }
  if (item == nil) caml_failwith("lui_shell: no status item");
  vsi = lui_wrap_si(item);
  CAMLreturn(vsi);
}

CAMLprim value lui_sh_status_remove(value vsi)
{
  CAMLparam1(vsi);
  @autoreleasepool {
    NSStatusItem *item = Lui_si_val(vsi);
    if (item != nil) {
      [[NSStatusBar systemStatusBar] removeStatusItem:item];
      [item release];
      Lui_si_val(vsi) = nil;
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_sh_status_set_title(value vsi, value vtitle)
{
  CAMLparam2(vsi, vtitle);
  @autoreleasepool {
    NSStatusItem *item = Lui_si_val(vsi);
    if (item != nil && [item button] != nil)
      [[item button] setTitle:lui_nsstring(vtitle)];
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_sh_status_set_image(value vsi, value vopt)
{
  CAMLparam2(vsi, vopt);
  @autoreleasepool {
    NSStatusItem *item = Lui_si_val(vsi);
    if (item != nil && [item button] != nil) {
      NSImage *img = Is_block(vopt) ? Lui_image_val(Field(vopt, 0)) : nil;
      [[item button] setImage:img];
      [[item button] setImageScaling:NSImageScaleProportionallyDown];
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_sh_status_set_menu(value vsi, value vtitle,
                                      value vrows_opt)
{
  CAMLparam3(vsi, vtitle, vrows_opt);
  @autoreleasepool {
    NSStatusItem *item = Lui_si_val(vsi);
    if (item != nil) {
      if (Is_block(vrows_opt)) {
        NSMenu *menu =
          lui_menu_build(lui_nsstring(vtitle), Field(vrows_opt, 0));
        [item setMenu:menu];
        [menu release];
      } else {
        [item setMenu:nil];
      }
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_sh_status_set_on_click(value vsi, value von)
{
  CAMLparam2(vsi, von);
  @autoreleasepool {
    NSStatusItem *item = Lui_si_val(vsi);
    if (item != nil && [item button] != nil) {
      if (Bool_val(von)) {
        [[item button] setTarget:lui_handler()];
        [[item button] setAction:@selector(statusItemAction:)];
      } else {
        [[item button] setAction:NULL];
      }
    }
  }
  CAMLreturn(Val_unit);
}

/* -------------------------------------------------------- notification */

static BOOL lui_bundled(void)
{
  NSBundle *b = [NSBundle mainBundle];
  return [b bundleIdentifier] != nil &&
         [[b bundlePath] hasSuffix:@".app"];
}

CAMLprim value lui_sh_notify(value vid, value vtitle, value vsub,
                             value vbody)
{
  CAMLparam4(vid, vtitle, vsub, vbody);
  CAMLlocal2(vres, vdetail);
  @autoreleasepool {
    BOOL ok = NO;
    NSString *detail = @"unavailable";
    @try {
      NSString *ident = lui_nsstring(vid);
      NSString *title = lui_nsstring(vtitle);
      NSString *subtitle = lui_nsstring(vsub);
      NSString *body = lui_nsstring(vbody);
      if (!lui_bundled()) {
        detail = @"needs an .app bundle (no bundle id)";
      } else if ([UNUserNotificationCenter class] != Nil) {
        /* Modern path: authorize once, then post. Authorization is
           async; the request is queued once it resolves. */
        UNUserNotificationCenter *center =
          [UNUserNotificationCenter currentNotificationCenter];
        [center setDelegate:lui_handler()];
        UNMutableNotificationContent *content =
          [[UNMutableNotificationContent alloc] init];
        [content setTitle:title];
        if ([subtitle length] > 0) [content setSubtitle:subtitle];
        [content setBody:body];
        UNNotificationRequest *req =
          [UNNotificationRequest requestWithIdentifier:ident
                                               content:content
                                               trigger:nil];
        [content release];
        [center requestAuthorizationWithOptions:
            (UNAuthorizationOptionAlert | UNAuthorizationOptionSound |
             UNAuthorizationOptionBadge)
          completionHandler:^(BOOL granted, NSError *error) {
            (void)error;
            if (granted) {
              [center addNotificationRequest:req
                       withCompletionHandler:^(NSError *add_error) {
                (void)add_error;
              }];
            }
          }];
        ok = YES;
        detail = @"user-notification";
      } else {
        NSUserNotification *n = [[NSUserNotification alloc] init];
        [n setTitle:title];
        if ([subtitle length] > 0) [n setSubtitle:subtitle];
        [n setInformativeText:body];
        [n setIdentifier:ident];
        NSUserNotificationCenter *center =
          [NSUserNotificationCenter defaultUserNotificationCenter];
        [center setDelegate:lui_handler()];
        [center deliverNotification:n];
        [n release];
        ok = YES;
        detail = @"legacy-notification";
      }
    } @catch (NSException *e) {
      ok = NO;
      detail = @"notification failed";
    }
    vdetail = lui_ocamlstring(detail);
    vres = caml_alloc(2, 0);
    Store_field(vres, 0, Val_bool(ok));
    Store_field(vres, 1, vdetail);
  }
  CAMLreturn(vres);
}

/* --------------------------------------------------------- clipboard */

static NSPasteboard *lui_pasteboard(void)
{
  return [NSPasteboard generalPasteboard];
}

CAMLprim value lui_sh_clip_write(value vstr)
{
  CAMLparam1(vstr);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      NSPasteboard *pb = lui_pasteboard();
      if (pb != nil) {
        [pb clearContents];
        ok = [pb setString:lui_nsstring(vstr)
                   forType:NSPasteboardTypeString];
      }
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_sh_clip_read(value unit)
{
  CAMLparam1(unit);
  CAMLlocal2(vopt, vs);
  vopt = Val_int(0);
  @autoreleasepool {
    @try {
      NSPasteboard *pb = lui_pasteboard();
      NSString *s =
        pb != nil ? [pb stringForType:NSPasteboardTypeString] : nil;
      if (s != nil) {
        vs = lui_ocamlstring(s);
        vopt = caml_alloc(1, 0);
        Store_field(vopt, 0, vs);
      }
    } @catch (NSException *e) {
      vopt = Val_int(0);
    }
  }
  CAMLreturn(vopt);
}

CAMLprim value lui_sh_clip_clear(value unit)
{
  CAMLparam1(unit);
  NSInteger n = -1;
  @autoreleasepool {
    @try {
      NSPasteboard *pb = lui_pasteboard();
      if (pb != nil) n = [pb clearContents];
    } @catch (NSException *e) {
      n = -1;
    }
  }
  CAMLreturn(Val_int(n));
}

CAMLprim value lui_sh_clip_count(value unit)
{
  CAMLparam1(unit);
  NSInteger n = -1;
  @autoreleasepool {
    @try {
      NSPasteboard *pb = lui_pasteboard();
      if (pb != nil) n = [pb changeCount];
    } @catch (NSException *e) {
      n = -1;
    }
  }
  CAMLreturn(Val_int(n));
}

/* ------------------------------------------------------------ dialogs */

static BOOL lui_can_present(void)
{
  return [NSThread isMainThread] && [lui_app() isRunning];
}

CAMLprim value lui_sh_can_present(value unit)
{
  CAMLparam1(unit);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      ok = lui_can_present();
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

CAMLprim value lui_sh_open_panel(value vfiles, value vdirs,
                                 value vmulti, value vfilters)
{
  CAMLparam4(vfiles, vdirs, vmulti, vfilters);
  CAMLlocal3(vopt, varr, vs);
  vopt = Val_int(0);
  if (lui_can_present()) {
    @autoreleasepool {
      @try {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setCanChooseFiles:Bool_val(vfiles)];
        [panel setCanChooseDirectories:Bool_val(vdirs)];
        [panel setAllowsMultipleSelection:Bool_val(vmulti)];
        mlsize_t nf = Wosize_val(vfilters);
        if (nf > 0) {
          NSMutableArray *types =
            [[NSMutableArray alloc] initWithCapacity:(NSUInteger)nf];
          for (mlsize_t i = 0; i < nf; i++) {
            NSString *t = lui_nsstring(Field(vfilters, i));
            if ([t length] > 0) [types addObject:t];
          }
          if ([types count] > 0) [panel setAllowedFileTypes:types];
          [types release];
        }
        if ([panel runModal] == NSModalResponseOK) {
          NSArray *urls = [panel URLs];
          NSUInteger n = [urls count];
          varr = caml_alloc((mlsize_t)n, 0);
          for (NSUInteger i = 0; i < n; i++) {
            vs = lui_ocamlstring([[urls objectAtIndex:i] path]);
            Store_field(varr, i, vs);
          }
          vopt = caml_alloc(1, 0);
          Store_field(vopt, 0, varr);
        }
      } @catch (NSException *e) {
        vopt = Val_int(0);
      }
    }
  }
  CAMLreturn(vopt);
}

CAMLprim value lui_sh_save_panel(value vname)
{
  CAMLparam1(vname);
  CAMLlocal2(vopt, vs);
  vopt = Val_int(0);
  if (lui_can_present()) {
    @autoreleasepool {
      @try {
        NSSavePanel *panel = [NSSavePanel savePanel];
        NSString *name = lui_nsstring(vname);
        if ([name length] > 0) [panel setNameFieldStringValue:name];
        if ([panel runModal] == NSModalResponseOK) {
          NSString *path = [[panel URL] path];
          if (path != nil) {
            vs = lui_ocamlstring(path);
            vopt = caml_alloc(1, 0);
            Store_field(vopt, 0, vs);
          }
        }
      } @catch (NSException *e) {
        vopt = Val_int(0);
      }
    }
  }
  CAMLreturn(vopt);
}

/* ------------------------------------------------------------ open-url */

CAMLprim value lui_sh_install_openurl(value unit)
{
  CAMLparam1(unit);
  BOOL ok = NO;
  @autoreleasepool {
    @try {
      [[NSAppleEventManager sharedAppleEventManager]
        setEventHandler:lui_handler()
            andSelector:@selector(getURL:withReplyEvent:)
          forEventClass:kInternetEventClass
             andEventID:kAEGetURL];
      ok = YES;
    } @catch (NSException *e) {
      ok = NO;
    }
  }
  CAMLreturn(Val_bool(ok));
}

#else /* !__APPLE__ */

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void)
{
  caml_failwith("lui_shell: this backend requires macOS");
  return Val_unit;
}

CAMLprim value lui_sh_policy_set(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_policy_get(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_set_app_name(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_dock_badge(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_attention(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_window_title(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_image_rgba(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_sh_image_size(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_menubar_insert(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_sh_menubar_count(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_menubar_remove(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_status_create(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_status_remove(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_status_set_title(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_sh_status_set_image(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_sh_status_set_menu(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_sh_status_set_on_click(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_sh_notify(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_sh_clip_write(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_clip_read(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_clip_clear(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_clip_count(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_can_present(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_open_panel(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_sh_save_panel(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_sh_install_openurl(value a) {
  (void)a; return unsupported(); }

#endif /* __APPLE__ */
