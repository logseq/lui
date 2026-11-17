#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#include <string>

extern "C" {
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/callback.h>
#include <caml/fail.h>
#include <caml/threads.h>
}

struct LuiSchemeHost {
  value options;
  bool stopped = false;
};

static void lui_stop_application(void) {
  [NSApp stop:nil];
  // A stop requested by WebKit/GCD must also wake AppKit's next-event wait.
  // Otherwise an idle update window can stay alive until another input event.
  NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined
      location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0
      context:nil subtype:0 data1:0 data2:0];
  [NSApp postEvent:wake atStart:YES];
}

static std::string lui_call_locked(LuiSchemeHost *host, int field, const char *argument,
                            std::string *mime = nullptr) {
  CAMLparam0();
  CAMLlocal2(input, result);
  input = caml_copy_string(argument);
  result = caml_callback_exn(Field(host->options, field), input);
  const bool failed = Is_exception_result(result);
  std::string output;
  if (!failed) {
    if (mime) {
      value type = Field(result, 0), body = Field(result, 1);
      mime->assign(String_val(type), caml_string_length(type));
      output.assign(String_val(body), caml_string_length(body));
    } else output.assign(String_val(result), caml_string_length(result));
  }
  if (failed) CAMLreturnT(std::string, "");
  CAMLreturnT(std::string, output);
}

static std::string lui_call(LuiSchemeHost *host, int field, const char *argument,
                            std::string *mime = nullptr) {
  caml_leave_blocking_section();
  std::string result = lui_call_locked(host, field, argument, mime);
  caml_enter_blocking_section();
  return result;
}

@interface LUIDesktopScheme : NSObject <WKURLSchemeHandler, WKScriptMessageHandler,
                                       WKNavigationDelegate, NSWindowDelegate,
                                       NSApplicationDelegate>
@property(nonatomic, assign) LuiSchemeHost *host;
@end

@implementation LUIDesktopScheme
- (void)webView:(WKWebView *)view startURLSchemeTask:(id<WKURLSchemeTask>)task {
  (void)view;
  NSURL *url = task.request.URL;
  if (![url.scheme isEqualToString:@"lui"] || ![url.host isEqualToString:@"localhost"]
      || ![task.request.HTTPMethod isEqualToString:@"GET"]) {
    [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorUnsupportedURL userInfo:nil]];
    return;
  }
  std::string mime;
  std::string body = lui_call(self.host, 5, url.path.UTF8String, &mime);
  if (mime.empty()) {
    [task didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorFileDoesNotExist userInfo:nil]];
    return;
  }
  NSString *type = [NSString stringWithUTF8String:mime.c_str()];
  NSString *origin = [task.request valueForHTTPHeaderField:@"Origin"] ?: @"lui://localhost";
  NSMutableDictionary *headers = [@{
    @"Content-Type": type, @"Cache-Control": @"no-store",
    @"Referrer-Policy": @"no-referrer", @"X-Content-Type-Options": @"nosniff",
    @"Content-Security-Policy": @"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; object-src 'none'; frame-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'"
  } mutableCopy];
  if ([origin isEqualToString:@"lui://localhost"] || [origin isEqualToString:@"null"])
    headers[@"Access-Control-Allow-Origin"] = origin;
  NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:url statusCode:200
      HTTPVersion:@"HTTP/1.1" headerFields:headers];
  [task didReceiveResponse:response];
  [task didReceiveData:[NSData dataWithBytes:body.data() length:body.size()]];
  [task didFinish];
  [response release];
  [headers release];
}

- (void)webView:(WKWebView *)view stopURLSchemeTask:(id<WKURLSchemeTask>)task {
  (void)view;
  (void)task;
  // Asset responses finish synchronously on the UI thread, with no queued work.
}

- (void)userContentController:(WKUserContentController *)controller
     didReceiveScriptMessage:(WKScriptMessage *)message {
  (void)controller;
  if (!self.host || self.host->stopped || !message.frameInfo.mainFrame
      || ![message.frameInfo.securityOrigin.protocol isEqualToString:@"lui"]
      || ![message.frameInfo.securityOrigin.host isEqualToString:@"localhost"]
      || ![message.body isKindOfClass:[NSDictionary class]]) return;
  NSDictionary *body = message.body;
  NSNumber *identifier = body[@"id"];
  NSString *method = body[@"method"];
  if (![identifier isKindOfClass:[NSNumber class]] || ![method isKindOfClass:[NSString class]]
      || method.length > 64 || identifier.longLongValue <= 0) return;
  std::string result = lui_call(self.host, 6, method.UTF8String);
  NSString *payload = result.empty() ? @"{\"error\":\"Request failed\"}"
      : [[[NSString alloc] initWithBytes:result.data() length:result.size() encoding:NSUTF8StringEncoding] autorelease];
  NSString *script = [NSString stringWithFormat:@"window.__luiReply(%lld,%@)", identifier.longLongValue, payload];
  [message.webView evaluateJavaScript:script completionHandler:nil];
  if ([method isEqualToString:@"later"]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      if (!self.host || self.host->stopped) return;
      self.host->stopped = true;
      lui_stop_application();
    });
  }
}

- (void)webView:(WKWebView *)view decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
  (void)view;
  NSURL *url = action.request.URL;
  if ([url.scheme isEqualToString:@"lui"] && [url.host isEqualToString:@"localhost"])
    decisionHandler(WKNavigationActionPolicyAllow);
  else {
    decisionHandler(WKNavigationActionPolicyCancel);
    if (action.navigationType == WKNavigationTypeLinkActivated
        && ([url.scheme isEqualToString:@"https"] || [url.scheme isEqualToString:@"http"]))
      [[NSWorkspace sharedWorkspace] openURL:url];
  }
}

- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  self.host->stopped = true;
  lui_stop_application();
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)application {
  self.host->stopped = true;
  (void)application;
  lui_stop_application();
  return NSTerminateCancel;
}
@end

extern "C" CAMLprim value lui_desktop_scheme_window_run(value options) {
  CAMLparam1(options);
  LuiSchemeHost host{options};
  caml_register_generational_global_root(&host.options);
  const std::string title = String_val(Field(options, 0));
  const std::string url = String_val(Field(options, 1));
  const int width = Int_val(Field(options, 2)), height = Int_val(Field(options, 3));
  caml_enter_blocking_section();
  @autoreleasepool {
    NSApplication *application = [NSApplication sharedApplication];
    LUIDesktopScheme *delegate = [[LUIDesktopScheme alloc] init];
    delegate.host = &host;
    application.delegate = delegate;
    [application setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSMenu *menu = [[[NSMenu alloc] init] autorelease];
    NSMenuItem *appItem = [[[NSMenuItem alloc] init] autorelease];
    NSMenu *appMenu = [[[NSMenu alloc] init] autorelease];
    [appMenu addItemWithTitle:@"Quit" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [menu addItem:appItem];
    NSMenuItem *editItem = [[[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""] autorelease];
    NSMenu *editMenu = [[[NSMenu alloc] initWithTitle:@"Edit"] autorelease];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [menu addItem:editItem];
    application.mainMenu = menu;

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    [configuration setURLSchemeHandler:delegate forURLScheme:@"lui"];
    [configuration.userContentController addScriptMessageHandler:delegate name:@"luiDesktop"];
    NSString *source = @"(() => { let next = 0; const pending = new Map();"
      "window.__lui_request = method => new Promise((resolve,reject) => {"
      "const id = ++next; pending.set(id,{resolve,reject});"
      "window.webkit.messageHandlers.luiDesktop.postMessage({id,method}); });"
      "window.__luiReply = (id,result) => { const p=pending.get(id); if(!p)return; pending.delete(id);"
      "if(result && result.error) p.reject(new Error(result.error)); else p.resolve(result); };"
      "window.__lui_check_for_updates = () => window.__lui_request('check_for_updates');"
      "window.__lui_later = () => window.__lui_request('later'); })();";
    WKUserScript *script = [[WKUserScript alloc] initWithSource:source
        injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:YES];
    [configuration.userContentController addUserScript:script];
    [script release];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, width, height)
        styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                   | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
        backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    window.title = [NSString stringWithUTF8String:title.c_str()];
    window.delegate = delegate;
    WKWebView *view = [[WKWebView alloc] initWithFrame:NSMakeRect(0, 0, width, height) configuration:configuration];
    view.navigationDelegate = delegate;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    window.contentView = view;
    [window center];
    [window makeKeyAndOrderFront:nil];
    [application activateIgnoringOtherApps:YES];
    [view loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[NSString stringWithUTF8String:url.c_str()]]]];
    [application run];
    view.navigationDelegate = nil;
    [configuration.userContentController removeScriptMessageHandlerForName:@"luiDesktop"];
    window.delegate = nil;
    [window close];
    window.contentView = nil;
    [view release];
    [configuration release];
    [window release];
    application.delegate = nil;
    delegate.host = nullptr;
    [delegate release];
  }
  caml_leave_blocking_section();
  caml_remove_generational_global_root(&host.options);
  CAMLreturn(Val_unit);
}
