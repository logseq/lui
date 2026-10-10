/* lui_ax — macOS accessibility bridge.
 *
 * Mirrors the Lui_a11y semantic tree as NSAccessibilityElement objects
 * so assistive technology sees a self-drawn app's structure: roles,
 * names, values, focus and actions. The ObjC side keeps a flat
 * node-id -> element table (the OCaml side rebuilds entries per update)
 * instead of mirroring the tree in C — subtree churn then only touches
 * dictionary entries.
 *
 * Compiled as Objective-C (see the dune file); on other platforms every
 * external fails immediately, like lui_text_coretext.c. */

#if defined(__APPLE__)

#import <AppKit/AppKit.h>
#import "lui_ax.h"

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <string.h>

/* Action codes shared with lui_ax.ml (drain_actions decodes these). */
enum {
  LUI_AX_PRESS = 0,      /* press the control */
  LUI_AX_INCREMENT,      /* step a ranged control up */
  LUI_AX_DECREMENT,      /* step a ranged control down */
  LUI_AX_FOCUS,          /* assistive tech moved focus onto the node */
  LUI_AX_SET_VALUE,      /* text was set (payload string follows) */
  LUI_AX_SCROLL_TO_VISIBLE, /* reveal the node in its scroll container */
  LUI_AX_EXPAND,         /* open a collapsible row */
  LUI_AX_COLLAPSE        /* close a collapsible row */
};

/* Bits of LuiAxElement.luiActions — keep in sync with lui_ax.ml. */
enum {
  LUI_AX_BIT_PRESS     = 1,
  LUI_AX_BIT_INCREMENT = 2,
  LUI_AX_BIT_DECREMENT = 4,
  LUI_AX_BIT_FOCUS     = 8,
  LUI_AX_BIT_SET_VALUE = 16,
  LUI_AX_BIT_SCROLL    = 32,
  LUI_AX_BIT_DISCLOSE  = 64
};

/* ------------------------------------------------------------- bridge */

/* One attach(): the element table, the top-level array and the focused
   node for a single host view. */
@interface LuiAxBridge : NSObject
@property(nonatomic, weak) NSView *view;
@property(nonatomic) NSMutableDictionary<NSNumber *, LuiAxElement *> *elements;
@property(nonatomic) NSArray<LuiAxElement *> *topLevel;
@property(nonatomic) NSInteger focusedId; /* -1 when nothing focused */
@end
@implementation LuiAxBridge
@end

@interface LuiAxElement ()
@property(nonatomic, weak) LuiAxBridge *luiBridge;
@end

static NSMutableArray *gBridges; /* LuiAxBridge | NSNull; index = bridge id */
static NSMutableArray *gActions; /* pending VoiceOver actions for OCaml */

static LuiAxBridge *lui_bridge_at(int bid)
{
  if (gBridges == nil || bid < 0 || (NSUInteger)bid >= gBridges.count)
    return nil;
  id b = gBridges[(NSUInteger)bid];
  return [b isKindOfClass:[LuiAxBridge class]] ? b : nil;
}

static LuiAxBridge *lui_bridge_for_view(id view)
{
  for (id b in gBridges) {
    if ([b isKindOfClass:[LuiAxBridge class]] &&
        ((LuiAxBridge *)b).view == view)
      return b;
  }
  return nil;
}

/* VoiceOver action delivery is polled, not called back: OCaml drains the
   queue each event-loop turn, so no ObjC code ever runs inside the OCaml
   runtime lock. */
static void lui_enqueue(LuiAxElement *el, int code, NSString *text)
{
  if (gActions == nil) gActions = [NSMutableArray new];
  [gActions addObject:@{
    @"bridge": @(el.luiBridgeId),
    @"node": @(el.luiNodeId),
    @"code": @(code),
    @"text": text != nil ? text : @""
  }];
}

/* ------------------------------------------------------------ element */

@implementation LuiAxElement

- (BOOL)luiHas:(NSUInteger)bit { return (self.luiActions & bit) != 0; }

/* Focus lives on the bridge: a node is focused when the model says so,
   not when AppKit last asked to focus it. */
- (BOOL)isAccessibilityFocused
{
  LuiAxBridge *b = self.luiBridge;
  return b != nil && b.focusedId == self.luiNodeId;
}

- (BOOL)accessibilityPerformPress
{
  if (![self luiHas:LUI_AX_BIT_PRESS]) return NO;
  lui_enqueue(self, LUI_AX_PRESS, nil);
  return YES;
}

- (BOOL)accessibilityPerformIncrement
{
  if (![self luiHas:LUI_AX_BIT_INCREMENT]) return NO;
  lui_enqueue(self, LUI_AX_INCREMENT, nil);
  return YES;
}

- (BOOL)accessibilityPerformDecrement
{
  if (![self luiHas:LUI_AX_BIT_DECREMENT]) return NO;
  lui_enqueue(self, LUI_AX_DECREMENT, nil);
  return YES;
}

/* The legacy action API: names are answered and performed only when the
   matching mask bit is set. "AXScrollToVisible" stays a string literal —
   it predates the exported constant on older macOS versions. */
- (NSArray *)accessibilityActionNames
{
  NSMutableArray *names = [NSMutableArray array];
  if ([self luiHas:LUI_AX_BIT_PRESS])
    [names addObject:NSAccessibilityPressAction];
  if ([self luiHas:LUI_AX_BIT_INCREMENT])
    [names addObject:NSAccessibilityIncrementAction];
  if ([self luiHas:LUI_AX_BIT_DECREMENT])
    [names addObject:NSAccessibilityDecrementAction];
  if ([self luiHas:LUI_AX_BIT_SCROLL])
    [names addObject:@"AXScrollToVisible"];
  return names;
}

- (NSString *)accessibilityActionDescription:(NSString *)action
{
  return NSAccessibilityActionDescription(action);
}

- (void)accessibilityPerformAction:(NSString *)action
{
  NSString *name = action;
  if ([name isEqualToString:@"AXPress"] &&
      [self luiHas:LUI_AX_BIT_PRESS])
    lui_enqueue(self, LUI_AX_PRESS, nil);
  else if ([name isEqualToString:@"AXIncrement"] &&
           [self luiHas:LUI_AX_BIT_INCREMENT])
    lui_enqueue(self, LUI_AX_INCREMENT, nil);
  else if ([name isEqualToString:@"AXDecrement"] &&
           [self luiHas:LUI_AX_BIT_DECREMENT])
    lui_enqueue(self, LUI_AX_DECREMENT, nil);
  else if ([name isEqualToString:@"AXScrollToVisible"] &&
           [self luiHas:LUI_AX_BIT_SCROLL])
    lui_enqueue(self, LUI_AX_SCROLL_TO_VISIBLE, nil);
}

- (BOOL)isAccessibilitySelectorAllowed:(SEL)selector
{
  if (selector == @selector(accessibilityPerformPress))
    return [self luiHas:LUI_AX_BIT_PRESS];
  if (selector == @selector(accessibilityPerformIncrement))
    return [self luiHas:LUI_AX_BIT_INCREMENT];
  if (selector == @selector(accessibilityPerformDecrement))
    return [self luiHas:LUI_AX_BIT_DECREMENT];
  if (selector == @selector(setAccessibilityFocused:))
    return [self luiHas:LUI_AX_BIT_FOCUS];
  if (selector == @selector(setAccessibilityValue:))
    return [self luiHas:LUI_AX_BIT_SET_VALUE] && self.luiValueSettable;
  if (selector == @selector(setAccessibilityDisclosed:))
    return [self luiHas:LUI_AX_BIT_DISCLOSE];
  return [super isAccessibilitySelectorAllowed:selector];
}

- (void)setAccessibilityFocused:(BOOL)focused
{
  [super setAccessibilityFocused:focused];
  if (focused && [self luiHas:LUI_AX_BIT_FOCUS])
    lui_enqueue(self, LUI_AX_FOCUS, nil);
}

- (void)setAccessibilityValue:(id)value
{
  [super setAccessibilityValue:value];
  if (self.luiTextual && self.luiValueSettable &&
      [self luiHas:LUI_AX_BIT_SET_VALUE]) {
    NSString *s = nil;
    if ([value isKindOfClass:[NSString class]])
      s = value;
    else if ([value respondsToSelector:@selector(stringValue)])
      s = [value stringValue];
    lui_enqueue(self, LUI_AX_SET_VALUE, s);
  }
}

- (void)setAccessibilityDisclosed:(BOOL)disclosed
{
  [super setAccessibilityDisclosed:disclosed];
  if (self.luiOutlineItem && [self luiHas:LUI_AX_BIT_DISCLOSE])
    lui_enqueue(self, disclosed ? LUI_AX_EXPAND : LUI_AX_COLLAPSE, nil);
}

/* Text reading for fields: ranges are UTF-16 code-unit ranges over the
   stored value, which is what NSAccessibility expects. */
- (NSString *)accessibilityStringForRange:(NSRange)range
{
  id v = self.accessibilityValue;
  if (![v isKindOfClass:[NSString class]]) return nil;
  NSString *s = v;
  NSUInteger lo = MIN(range.location, s.length);
  NSUInteger hi = MIN(lo + range.length, s.length);
  return [s substringWithRange:NSMakeRange(lo, hi - lo)];
}

- (NSInteger)accessibilityLineForIndex:(NSInteger)index { return 0; }

- (NSRange)accessibilityRangeForLine:(NSInteger)line
{
  id v = self.accessibilityValue;
  NSUInteger n = [v isKindOfClass:[NSString class]] ? [v length] : 0;
  return NSMakeRange(0, n);
}

- (NSRect)accessibilityFrameForRange:(NSRange)range
{
  return self.accessibilityFrame;
}

/* Attributes the property storage does not cover are served through the
   legacy attribute API, like AXInvalid and the menu item mark. */
- (NSArray *)accessibilityAttributeNames
{
  NSArray *names = [super accessibilityAttributeNames];
  if (self.luiInvalid && ![names containsObject:@"AXInvalid"])
    names = [names arrayByAddingObject:@"AXInvalid"];
  if (self.luiMarkChar != nil &&
      ![names containsObject:@"AXMenuItemMarkChar"])
    names = [names arrayByAddingObject:@"AXMenuItemMarkChar"];
  return names;
}

- (id)accessibilityAttributeValue:(NSString *)attribute
{
  if ([attribute isEqualToString:@"AXInvalid"])
    return self.luiInvalid ? @"true" : nil;
  if ([attribute isEqualToString:@"AXMenuItemMarkChar"])
    return self.luiMarkChar;
  return [super accessibilityAttributeValue:attribute];
}

- (BOOL)accessibilityIsAttributeSettable:(NSString *)attribute
{
  if ([attribute isEqualToString:@"AXValue"])
    return self.luiValueSettable;
  if ([attribute isEqualToString:@"AXFocused"])
    return [self luiHas:LUI_AX_BIT_FOCUS];
  if ([attribute isEqualToString:@"AXDisclosing"])
    return self.luiOutlineItem;
  return NO;
}

@end

/* ------------------------------------------------------------ helpers */

static NSString *lui_nsstr(value v)
{
  NSString *s =
    [[NSString alloc] initWithBytes:String_val(v)
                             length:(NSUInteger)caml_string_length(v)
                           encoding:NSUTF8StringEncoding];
  if (s == nil)
    s = [[NSString alloc] initWithBytes:String_val(v)
                                 length:(NSUInteger)caml_string_length(v)
                               encoding:NSISOLatin1StringEncoding];
  return s != nil ? s : @"";
}

static LuiAxElement *lui_elem(LuiAxBridge *b, int bid, int nodeId,
                              int create)
{
  NSNumber *k = @(nodeId);
  LuiAxElement *el = b.elements[k];
  if (el == nil && create) {
    el = [LuiAxElement new];
    el.luiNodeId = nodeId;
    el.luiBridgeId = bid;
    el.luiBridge = b;
    b.elements[k] = el;
  }
  return el;
}

/* Build an NSArray of elements for an OCaml int array of node ids;
   ids without an element are skipped. */
static NSArray *lui_elems_of(LuiAxBridge *b, int bid, value vids)
{
  mlsize_t n = Wosize_val(vids);
  NSMutableArray *out = [NSMutableArray arrayWithCapacity:(NSUInteger)n];
  for (mlsize_t i = 0; i < n; i++) {
    LuiAxElement *el = lui_elem(b, bid, (int)Int_val(Field(vids, i)), 0);
    if (el != nil) [out addObject:el];
  }
  return out;
}

static int lui_post(LuiAxBridge *b, int nodeId, NSString *name)
{
  id target = nil;
  if (nodeId >= 0) target = b.elements[@(nodeId)];
  if (target == nil) target = b.view;
  if (target == nil) return 0;
  NSAccessibilityPostNotification(target, name);
  return 1;
}

/* ----------------------------------------------------------- externals */

/* attach : native view pointer -> bridge id */
CAMLprim value lui_ax_attach(value vview)
{
  CAMLparam1(vview);
  int bid = -1;
  @autoreleasepool {
    if (gBridges == nil) gBridges = [NSMutableArray new];
    LuiAxBridge *b = [LuiAxBridge new];
    b.view = (__bridge NSView *)(void *)(intptr_t)Nativeint_val(vview);
    b.elements = [NSMutableDictionary new];
    b.topLevel = @[];
    b.focusedId = -1;
    for (NSUInteger i = 0; i < gBridges.count; i++) {
      if (gBridges[i] == (id)[NSNull null]) { bid = (int)i; break; }
    }
    if (bid < 0) {
      bid = (int)gBridges.count;
      [gBridges addObject:b];
    } else {
      gBridges[(NSUInteger)bid] = b;
    }
  }
  CAMLreturn(Val_int(bid));
}

/* detach : bridge id -> unit. Every live element is destroyed and the
   bridge slot is freed for reuse. */
CAMLprim value lui_ax_detach(value vb)
{
  CAMLparam1(vb);
  int bid = (int)Int_val(vb);
  @autoreleasepool {
    LuiAxBridge *b = lui_bridge_at(bid);
    if (b != nil) {
      for (LuiAxElement *el in b.elements.allValues)
        NSAccessibilityPostNotification(
          el, NSAccessibilityUIElementDestroyedNotification);
      [b.elements removeAllObjects];
      b.topLevel = @[];
      b.view = nil;
      gBridges[(NSUInteger)bid] = (id)[NSNull null];
      if (gActions != nil) {
        NSMutableIndexSet *drop = [NSMutableIndexSet indexSet];
        [gActions enumerateObjectsUsingBlock:^(NSDictionary *a,
                                               NSUInteger i, BOOL *s) {
          if ([a[@"bridge"] intValue] == bid) [drop addIndex:i];
        }];
        [gActions removeObjectsAtIndexes:drop];
      }
    }
  }
  CAMLreturn(Val_unit);
}

/* apply : bridge id -> node id -> ax_desc -> unit.
   Sets every attribute of the element, creating it when missing.
   Field order of ax_desc is fixed with lui_ax.ml:
   0 role, 1 subrole, 2 title, 3 label, 4 value_tag (0 none/1 num/2 str),
   5 value_num, 6 value_str, 7 has_min, 8 min, 9 has_max, 10 max,
   11 enabled, 12 expanded (-1/0/1), 13 orientation (0/1 vert/2 horiz),
   14 index (-1), 15 selected (-1/0/1), 16 placeholder, 17 help,
   18 nchars (-1), 19 sel_loc, 20 sel_len, 21 disclosed (-1/0/1),
   22 disclosure level (-1), 23 mark char, 24 invalid,
   25 action mask, 26 textual, 27 value settable, 28 outline item. */
CAMLprim value lui_ax_apply(value vb, value vid, value vd)
{
  CAMLparam3(vb, vid, vd);
  @autoreleasepool {
    LuiAxBridge *b = lui_bridge_at((int)Int_val(vb));
    if (b != nil) {
      LuiAxElement *el =
        lui_elem(b, (int)Int_val(vb), (int)Int_val(vid), 1);
      NSString *subrole = lui_nsstr(Field(vd, 1));
      NSString *title = lui_nsstr(Field(vd, 2));
      NSString *label = lui_nsstr(Field(vd, 3));
      el.accessibilityRole = lui_nsstr(Field(vd, 0));
      el.accessibilitySubrole = subrole.length > 0 ? subrole : nil;
      el.accessibilityTitle = title.length > 0 ? title : nil;
      el.accessibilityLabel = label.length > 0 ? label : nil;
      long vtag = Int_val(Field(vd, 4));
      if (vtag == 1)
        el.accessibilityValue = @(Double_val(Field(vd, 5)));
      else if (vtag == 2)
        el.accessibilityValue = lui_nsstr(Field(vd, 6));
      else
        el.accessibilityValue = nil;
      el.accessibilityMinValue =
        Bool_val(Field(vd, 7)) ? @(Double_val(Field(vd, 8))) : nil;
      el.accessibilityMaxValue =
        Bool_val(Field(vd, 9)) ? @(Double_val(Field(vd, 10))) : nil;
      el.accessibilityEnabled = Bool_val(Field(vd, 11));
      long expanded = Int_val(Field(vd, 12));
      if (expanded >= 0) el.accessibilityExpanded = expanded != 0;
      long orient = Int_val(Field(vd, 13));
      if (orient > 0)
        el.accessibilityOrientation = (NSAccessibilityOrientation)orient;
      long index = Int_val(Field(vd, 14));
      if (index >= 0) el.accessibilityIndex = index;
      long selected = Int_val(Field(vd, 15));
      if (selected >= 0) el.accessibilitySelected = selected != 0;
      NSString *placeholder = lui_nsstr(Field(vd, 16));
      el.accessibilityPlaceholderValue =
        placeholder.length > 0 ? placeholder : nil;
      NSString *help = lui_nsstr(Field(vd, 17));
      el.accessibilityHelp = help.length > 0 ? help : nil;
      long nchars = Int_val(Field(vd, 18));
      if (nchars >= 0) {
        el.accessibilityNumberOfCharacters = nchars;
        el.accessibilitySelectedTextRange =
          NSMakeRange((NSUInteger)Int_val(Field(vd, 19)),
                      (NSUInteger)Int_val(Field(vd, 20)));
      }
      long disclosed = Int_val(Field(vd, 21));
      if (disclosed >= 0) el.accessibilityDisclosed = disclosed != 0;
      long level = Int_val(Field(vd, 22));
      if (level >= 0) el.accessibilityDisclosureLevel = level;
      NSString *mark = lui_nsstr(Field(vd, 23));
      el.luiMarkChar = mark.length > 0 ? mark : nil;
      el.luiInvalid = Bool_val(Field(vd, 24));
      el.luiActions = (NSUInteger)Int_val(Field(vd, 25));
      el.luiTextual = Bool_val(Field(vd, 26));
      el.luiValueSettable = Bool_val(Field(vd, 27));
      el.luiOutlineItem = Bool_val(Field(vd, 28));
    }
  }
  CAMLreturn(Val_unit);
}

/* link : bridge id -> node id -> parent id -> child ids -> unit.
   A parent id of -1 means the host view is the parent. */
CAMLprim value lui_ax_link(value vb, value vid, value vparent,
                           value vchildren)
{
  CAMLparam4(vb, vid, vparent, vchildren);
  @autoreleasepool {
    int bid = (int)Int_val(vb);
    LuiAxBridge *b = lui_bridge_at(bid);
    if (b != nil) {
      LuiAxElement *el = lui_elem(b, bid, (int)Int_val(vid), 1);
      int pid = (int)Int_val(vparent);
      el.accessibilityParent =
        pid >= 0 ? (id)lui_elem(b, bid, pid, 0) : (id)b.view;
      el.accessibilityChildren =
        lui_elems_of(b, bid, vchildren);
    }
  }
  CAMLreturn(Val_unit);
}

/* set_rows : bridge id -> node id -> rows_desc -> unit.
   rows_desc fields: 0 row ids, 1 visible row ids, 2 selected row ids,
   3 total row count. For list/table/outline containers. */
CAMLprim value lui_ax_set_rows(value vb, value vid, value vr)
{
  CAMLparam3(vb, vid, vr);
  @autoreleasepool {
    int bid = (int)Int_val(vb);
    LuiAxBridge *b = lui_bridge_at(bid);
    if (b != nil) {
      LuiAxElement *el = lui_elem(b, bid, (int)Int_val(vid), 0);
      if (el != nil) {
        el.accessibilityRows = lui_elems_of(b, bid, Field(vr, 0));
        el.accessibilityVisibleRows = lui_elems_of(b, bid, Field(vr, 1));
        el.accessibilitySelectedRows = lui_elems_of(b, bid, Field(vr, 2));
        el.accessibilityRowCount = (NSInteger)Int_val(Field(vr, 3));
      }
    }
  }
  CAMLreturn(Val_unit);
}

/* set_frame : bridge id -> node id -> rect -> unit.
   The rect is in the host view's coordinate space (points) and is
   converted through the window to screen coordinates. The rect record
   is all-floats, so fields read as unboxed doubles. */
CAMLprim value lui_ax_set_frame(value vb, value vid, value vr)
{
  CAMLparam3(vb, vid, vr);
  @autoreleasepool {
    LuiAxBridge *b = lui_bridge_at((int)Int_val(vb));
    if (b != nil) {
      LuiAxElement *el =
        lui_elem(b, (int)Int_val(vb), (int)Int_val(vid), 0);
      if (el != nil) {
        NSRect r = NSMakeRect(Double_field(vr, 0), Double_field(vr, 1),
                              Double_field(vr, 2), Double_field(vr, 3));
        if (b.view != nil) {
          r = [b.view convertRect:r toView:nil];
          r = [b.view.window convertRectToScreen:r];
        }
        el.accessibilityFrame = r;
      }
    }
  }
  CAMLreturn(Val_unit);
}

/* remove : bridge id -> node id -> unit.
   Drops the element silently; the OCaml side posts the destroyed
   notification beforehand so it still resolves. */
CAMLprim value lui_ax_remove(value vb, value vid)
{
  CAMLparam2(vb, vid);
  @autoreleasepool {
    LuiAxBridge *b = lui_bridge_at((int)Int_val(vb));
    if (b != nil)
      [b.elements removeObjectForKey:@((NSInteger)Int_val(vid))];
  }
  CAMLreturn(Val_unit);
}

/* finish : bridge id -> top ids -> layout changed -> unit.
   Replaces the top-level array; posts AXLayoutChanged on the view when
   the top set or any link changed. */
CAMLprim value lui_ax_finish(value vb, value vtop, value vchanged)
{
  CAMLparam3(vb, vtop, vchanged);
  @autoreleasepool {
    int bid = (int)Int_val(vb);
    LuiAxBridge *b = lui_bridge_at(bid);
    if (b != nil) {
      NSArray *top = lui_elems_of(b, bid, vtop);
      BOOL same = [top isEqualToArray:b.topLevel ?: @[]];
      b.topLevel = top;
      if (!same || Bool_val(vchanged))
        NSAccessibilityPostNotification(
          b.view, NSAccessibilityLayoutChangedNotification);
    }
  }
  CAMLreturn(Val_unit);
}

/* post : bridge id -> node id -> notification name -> unit.
   node id -1 (or an unknown id) targets the host view. */
CAMLprim value lui_ax_post(value vb, value vid, value vname)
{
  CAMLparam3(vb, vid, vname);
  @autoreleasepool {
    LuiAxBridge *b = lui_bridge_at((int)Int_val(vb));
    if (b != nil)
      lui_post(b, (int)Int_val(vid), lui_nsstr(vname));
  }
  CAMLreturn(Val_unit);
}

/* set_focus : bridge id -> node id -> unit. id -1 clears focus. */
CAMLprim value lui_ax_set_focus(value vb, value vid)
{
  CAMLparam2(vb, vid);
  @autoreleasepool {
    LuiAxBridge *b = lui_bridge_at((int)Int_val(vb));
    if (b != nil) b.focusedId = (NSInteger)Int_val(vid);
  }
  CAMLreturn(Val_unit);
}

/* drain : bridge id -> (node id, action code, text) array.
   Empties the bridge's share of the pending action queue. */
CAMLprim value lui_ax_drain(value vb)
{
  CAMLparam1(vb);
  CAMLlocal3(vtup, varr, vtext);
  int bid = (int)Int_val(vb);
  varr = caml_alloc(0, 0);
  @autoreleasepool {
    if (gActions != nil) {
      NSMutableArray *mine = [NSMutableArray array];
      NSMutableIndexSet *drop = [NSMutableIndexSet indexSet];
      [gActions enumerateObjectsUsingBlock:^(NSDictionary *a,
                                             NSUInteger i, BOOL *s) {
        if ([a[@"bridge"] intValue] == bid) {
          [mine addObject:a];
          [drop addIndex:i];
        }
      }];
      [gActions removeObjectsAtIndexes:drop];
      varr = caml_alloc((mlsize_t)mine.count, 0);
      NSUInteger i = 0;
      for (NSDictionary *a in mine) {
        /* the string is copied while rooted, then the tuple filled —
           nothing allocates between its alloc and the stores */
        vtext = caml_copy_string([a[@"text"] UTF8String]);
        vtup = caml_alloc(3, 0);
        Store_field(vtup, 0, Val_int([a[@"node"] intValue]));
        Store_field(vtup, 1, Val_int([a[@"code"] intValue]));
        Store_field(vtup, 2, vtext);
        Store_field(varr, (mlsize_t)i, vtup);
        i++;
      }
    }
  }
  CAMLreturn(varr);
}

/* --------------------------------------------------------- host glue */

NSArray *LuiAxTopElements(id view)
{
  LuiAxBridge *b = lui_bridge_for_view(view);
  return b != nil && b.topLevel != nil ? b.topLevel : @[];
}

/* Deepest element containing the point wins; when several siblings
   cover it, the later one (painted on top) is kept. */
static id lui_hit_in(NSArray *kids, NSPoint p)
{
  id hit = nil;
  for (LuiAxElement *el in kids) {
    if ([el isKindOfClass:[LuiAxElement class]] &&
        NSPointInRect(p, el.accessibilityFrame)) {
      id sub = lui_hit_in(el.accessibilityChildren ?: @[], p);
      hit = sub != nil ? sub : el;
    }
  }
  return hit;
}

id LuiAxHitTest(id view, NSPoint p)
{
  LuiAxBridge *b = lui_bridge_for_view(view);
  if (b != nil) {
    id hit = lui_hit_in(b.topLevel ?: @[], p);
    if (hit != nil) return hit;
  }
  return view;
}

id LuiAxFocusedElement(id view)
{
  LuiAxBridge *b = lui_bridge_for_view(view);
  if (b != nil && b.focusedId >= 0) {
    LuiAxElement *el = b.elements[@(b.focusedId)];
    if (el != nil) return el;
  }
  return view;
}

#else /* !__APPLE__ */

/* Buildable everywhere; calls on an unsupported platform fail loudly. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void)
{
  caml_failwith("lui_ax: this backend requires macOS");
  return Val_unit;
}

CAMLprim value lui_ax_attach(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_ax_detach(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_ax_apply(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_ax_link(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_ax_set_rows(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_ax_set_frame(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_ax_remove(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_ax_finish(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_ax_post(value a, value b, value c) {
  (void)a; (void)b; (void)c; return unsupported(); }
CAMLprim value lui_ax_set_focus(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_ax_drain(value a) {
  (void)a; return unsupported(); }

#endif /* __APPLE__ */
