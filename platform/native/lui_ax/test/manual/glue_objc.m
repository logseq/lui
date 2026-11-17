// Manual-test glue: an offscreen NSWindow plus a host view that
// delegates its accessibility container methods to the lui_ax helpers
// declared in lui_ax.h, then dumps the AX attributes of the element
// tree to stdout. Compiled only on macOS.

#if defined(__APPLE__)

#import <Cocoa/Cocoa.h>
#import <caml/mlvalues.h>
#import <caml/alloc.h>
#import <caml/memory.h>
#import <caml/callback.h>

extern NSArray *LuiAxTopElements(id view);
extern id LuiAxFocusedElement(id view);
extern id LuiAxHitTest(id view, NSPoint p);

/* The host-side contract a real backend copies: the view is not itself
   an element; it exposes the bridge's top-level elements, hit test and
   focus. */
@interface LuiAxManualView : NSView
@end

@implementation LuiAxManualView
- (BOOL)isAccessibilityElement { return NO; }
- (NSArray *)accessibilityChildren { return LuiAxTopElements(self); }
- (id)accessibilityFocusedUIElement { return LuiAxFocusedElement(self); }
- (id)accessibilityHitTest:(NSPoint)point {
  return LuiAxHitTest(self, point);
}
@end

static NSWindow *gWindow = nil;

CAMLprim value lui_manual_window(value unit) {
  CAMLparam1(unit);
  @autoreleasepool {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSRect r = NSMakeRect(0, 0, 480, 360);
    gWindow = [[NSWindow alloc]
        initWithContentRect:r
                styleMask:NSWindowStyleMaskTitled
                  backing:NSBackingStoreBuffered
                    defer:YES];
    LuiAxManualView *v =
        [[LuiAxManualView alloc] initWithFrame:
                                   NSMakeRect(0, 0, r.size.width,
                                              r.size.height)];
    [gWindow setContentView:v];
    [gWindow orderBack:nil];
    CAMLreturn(caml_copy_nativeint((intnat)(__bridge void *)v));
  }
}

static const char *cstr(id o)
{
  return o == nil ? "" : [[o description] UTF8String];
}

static void dump_desc(id e, NSString *indent) {
  @autoreleasepool {
    NSString *role = [e accessibilityRole] ?: @"";
    NSString *sub = [e accessibilitySubrole] ?: @"";
    NSString *title = [e accessibilityTitle] ?: @"";
    NSString *label =
        ([e respondsToSelector:@selector(accessibilityLabel)]
             ? [e accessibilityLabel]
             : @"")
            ?: @"";
    id val = [e accessibilityValue];
    NSRect fr = [e accessibilityFrame];
    BOOL en = [e isAccessibilityEnabled];
    BOOL foc = [e isAccessibilityFocused];
    NSArray *kids = [e accessibilityChildren] ?: @[];
    NSString *valDesc =
        [val isKindOfClass:[NSString class]] ? (NSString *)val
        : val ? [val description] : @"";
    printf("%sid=%s role=%s subrole=%s title=\"%s\" label=\"%s\" "
           "value=\"%s\" frame=%s enabled=%d focused=%d children=%lu\n",
           [indent UTF8String], cstr([e valueForKey:@"luiNodeId"]),
           [role UTF8String], [sub UTF8String], [title UTF8String],
           [label UTF8String], [valDesc UTF8String],
           [NSStringFromRect(fr) UTF8String], en ? 1 : 0, foc ? 1 : 0,
           (unsigned long)[kids count]);
    // row extras VoiceOver reports
    NSInteger idx = NSNotFound;
    BOOL sel = NO;
    @try {
      idx = [e accessibilityIndex];
      sel = [e isAccessibilitySelected];
    } @catch (__unused NSException *x) {
    }
    if (([role isEqualToString:@"AXRow"] && idx != NSNotFound) || sel) {
      printf("%s  index=%ld selected=%d\n", [indent UTF8String],
             (long)idx, sel ? 1 : 0);
    }
    NSString *deeper = [indent stringByAppendingString:@"  "];
    for (id c in kids) dump_desc(c, deeper);
  }
}

CAMLprim value lui_manual_dump(value vview) {
  CAMLparam1(vview);
  @autoreleasepool {
    id view = (__bridge id)(void *)Nativeint_val(vview);
    NSArray *top = [view accessibilityChildren];
    printf("== top-level elements: %lu ==\n",
           (unsigned long)[top count]);
    for (id e in top) dump_desc(e, @"  ");
    // focused/hit may resolve to the view itself, which has no node id
    id foc = [view accessibilityFocusedUIElement];
    printf("== focused element: %s ==\n",
           [foc respondsToSelector:@selector(luiNodeId)]
               ? cstr([foc valueForKey:@"luiNodeId"])
               : "none");
    // hit test at the middle of the view's bounds, in screen coords
    NSRect wr = [[view window]
        convertRectToScreen:[view convertRect:[view bounds]
                                     toView:nil]];
    NSPoint p = NSMakePoint(NSMidX(wr), NSMidY(wr));
    id hit = [view accessibilityHitTest:p];
    printf("== hit test (%.0f,%.0f): %s ==\n", p.x, p.y,
           [hit respondsToSelector:@selector(luiNodeId)]
               ? cstr([hit valueForKey:@"luiNodeId"])
               : "none");
  }
  CAMLreturn(Val_unit);
}

/* Perform a legacy action on the element for a node id — the way
   VoiceOver drives the bridge. */
static id find_el(id e, int nodeId)
{
  if ([e respondsToSelector:@selector(luiNodeId)] &&
      [[e valueForKey:@"luiNodeId"] intValue] == nodeId)
    return e;
  for (id c in [e accessibilityChildren] ?: @[]) {
    id r = find_el(c, nodeId);
    if (r != nil) return r;
  }
  return nil;
}

CAMLprim value lui_manual_perform(value vview, value vnode,
                                  value vaction) {
  CAMLparam3(vview, vnode, vaction);
  @autoreleasepool {
    id view = (__bridge id)(void *)Nativeint_val(vview);
    int nid = (int)Int_val(vnode);
    NSString *action = [NSString stringWithUTF8String:String_val(vaction)];
    for (id e in [view accessibilityChildren]) {
      id el = find_el(e, nid);
      if (el == nil) continue;
      if ([action isEqualToString:@"AXPress"])
        [el accessibilityPerformPress];
      else if ([action isEqualToString:@"AXIncrement"])
        [el accessibilityPerformIncrement];
      else if ([action isEqualToString:@"AXDecrement"])
        [el accessibilityPerformDecrement];
      break;
    }
  }
  CAMLreturn(Val_unit);
}

#else /* not macOS: same failwith shape as the library stubs */

#include <caml/mlvalues.h>
#include <caml/fail.h>

CAMLprim value lui_manual_window(value unit) {
  (void)unit;
  caml_failwith("lui_ax manual test is macOS-only");
}

CAMLprim value lui_manual_dump(value v) {
  (void)v;
  caml_failwith("lui_ax manual test is macOS-only");
}

CAMLprim value lui_manual_perform(value a, value b, value c) {
  (void)a; (void)b; (void)c;
  caml_failwith("lui_ax manual test is macOS-only");
}

#endif
