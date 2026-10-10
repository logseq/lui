/* lui_ax — macOS accessibility bridge (host-facing glue).
 *
 * The host's NSView subclass must implement the accessibility container
 * methods and delegate to the functions below:
 *
 *   - (BOOL)isAccessibilityElement            { return NO; }
 *   - (NSArray *)accessibilityChildren        { return LuiAxTopElements(self); }
 *   - (id)accessibilityHitTest:(NSPoint)p     { return LuiAxHitTest(self, p); }
 *   - (id)accessibilityFocusedUIElement       { return LuiAxFocusedElement(self); }
 *
 * If the view is not flipped (isFlipped == NO), flip layout-space rects
 * into its coordinate system before handing them to Lui_ax's frame
 * resolver — see Lui_ax.y_flip for the math.
 */

#ifndef LUI_AX_H
#define LUI_AX_H

#if defined(__APPLE__)

#import <AppKit/AppKit.h>

/* One accessibility element per a11y node. Not backed by an NSView:
 * every attribute AppKit can query is stored or computed on the object.
 * The extra lui* properties are driven by the OCaml side; reads happen
 * from assistive-technology queries on the main thread. */
@interface LuiAxElement : NSAccessibilityElement
@property(nonatomic) NSInteger luiNodeId;
@property(nonatomic) NSInteger luiBridgeId;
/* Bitmask of the actions the node supports (press/increment/decrement/
   focus/set-value/scroll-to-visible/disclose). */
@property(nonatomic) NSUInteger luiActions;
@property(nonatomic) BOOL luiTextual;
@property(nonatomic) BOOL luiValueSettable;
@property(nonatomic) BOOL luiOutlineItem;
@property(nonatomic) BOOL luiInvalid;
@property(nonatomic, copy) NSString *luiMarkChar;
@end

/* The a11y forest's top-level elements for the window content view that
   owns them, or an empty array when nothing is attached. */
NSArray *LuiAxTopElements(id view);

/* Deepest element containing a screen-space point, or the view itself.
   Element frames are stored in screen coordinates. */
id LuiAxHitTest(id view, NSPoint screenPoint);

/* The element currently holding accessibility focus, or the view. */
id LuiAxFocusedElement(id view);

#endif /* __APPLE__ */
#endif /* LUI_AX_H */
