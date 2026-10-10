/* Windows accessibility bridge — UI Automation server-side providers.
 *
 * One COM object per a11y node implements IRawElementProviderSimple +
 * IRawElementProviderFragment plus the control patterns the node's
 * role offers (a pattern bitmask gates both QueryInterface and
 * GetPatternProvider). The synthetic frame node additionally
 * implements IRawElementProviderFragmentRoot and is what WM_GETOBJECT
 * hands to UI Automation through UiaReturnRawElementProvider.
 *
 * The OCaml side pushes per-node descriptors (lui_ax_windows.ml's
 * uia_desc tuple — field order fixed there) plus parent/children
 * links and client-space rects. Assistive-technology actions are
 * queued here and polled via lui_axw_drain; platform code never calls
 * back into the OCaml runtime.
 *
 * UIA may call provider methods from its own threads (we advertise
 * ProviderOptions_UseComThreading), so all node data access and the
 * action queue sit under the bridge lock.
 */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <string.h>
#include <stdio.h>

#if defined(_WIN32)

#include <windows.h>
#include <oleauto.h>
#include <uiautomation.h>
#include <uiautomationcore.h>

/* ------------------------------------------------------------------ */
/* UIA constants — the OCaml side defines these for tests as well;    */
/* the numeric values are fixed by the UI Automation specification.   */

#define UIA_PROP_BOUNDING_RECT   30001
#define UIA_PROP_AUTOMATION_ID   30011
#define UIA_PROP_CONTROL_TYPE    30003
#define UIA_PROP_LOCALIZED_TYPE  30004
#define UIA_PROP_NAME            30005
#define UIA_PROP_HAS_KB_FOCUS    30008
#define UIA_PROP_IS_KB_FOCUSABLE 30009
#define UIA_PROP_IS_ENABLED      30010
#define UIA_PROP_HELP_TEXT       30013
#define UIA_PROP_IS_CONTROL_ELEM 30016
#define UIA_PROP_IS_CONTENT_ELEM 30017
#define UIA_PROP_IS_PASSWORD     30019
#define UIA_PROP_IS_OFFSCREEN    30022
#define UIA_PROP_FRAMEWORK_ID    30024
#define UIA_PROP_IS_REQUIRED     30025
#define UIA_PROP_VALUE           30045
#define UIA_PROP_VALUE_READONLY  30046
#define UIA_PROP_RV_VALUE        30047
#define UIA_PROP_RV_READONLY     30048
#define UIA_PROP_RV_MIN          30049
#define UIA_PROP_RV_MAX          30050
#define UIA_PROP_RV_LARGE        30051
#define UIA_PROP_RV_SMALL        30052
#define UIA_PROP_EXPAND_STATE    30070
#define UIA_PROP_IS_SELECTED     30079
#define UIA_PROP_TOGGLE_STATE    30086
#define UIA_PROP_LIVE_SETTING    30135
#define UIA_PROP_POS_IN_SET      30152
#define UIA_PROP_SIZE_OF_SET     30153
#define UIA_PROP_LEVEL           30154
#define UIA_PROP_FULL_DESC       30159
#define UIA_PROP_IS_DIALOG       30174

#define UIA_PAT_INVOKE      10000
#define UIA_PAT_SELECTION   10001
#define UIA_PAT_VALUE       10002
#define UIA_PAT_RANGE       10003
#define UIA_PAT_EXPAND      10005
#define UIA_PAT_SEL_ITEM    10010
#define UIA_PAT_TOGGLE      10015
#define UIA_PAT_SCROLL_ITEM 10017

/* Pattern bitmask — must match patterns_of in lui_ax_windows.ml. */
#define PAT_INVOKE      1
#define PAT_TOGGLE      2
#define PAT_SEL_ITEM    4
#define PAT_SELECTION   8
#define PAT_RANGE       16
#define PAT_VALUE       32
#define PAT_EXPAND      64
#define PAT_SCROLL_ITEM 128

/* Action codes — must match action_of_code in lui_ax_windows.ml. */
#define ACT_PRESS     0
#define ACT_INCREMENT 1
#define ACT_DECREMENT 2
#define ACT_FOCUS     3
#define ACT_SET_VALUE 4
#define ACT_SCROLL    5
#define ACT_EXPAND    6
#define ACT_COLLAPSE  7

#define UIA_ROOT_OBJECT_ID (-25)
#define UIA_RT_PREFIX      3
#ifndef UIA_E_ELEMENTNOTAVAILABLE
#define UIA_E_ELEMENTNOTAVAILABLE ((HRESULT)0x80040201)
#endif
#ifndef UIA_E_ELEMENTNOTENABLED
#define UIA_E_ELEMENTNOTENABLED   ((HRESULT)0x80040200)
#endif

#define AXW_FRAME_ID (-1)
#define AXW_MAX_BRIDGES 16
#define AXW_QUEUE_CAP 512

/* ------------------------------------------------------------------ */
/* Types                                                              */

typedef struct axw_node axw_node;
typedef struct axw_bridge axw_bridge;

typedef struct {
  int code;
  int node_id;
  char *text; /* owned */
} axw_action;

typedef struct {
  int key;        /* node id; 0 = empty slot, INT_MIN = tombstone */
  axw_node *val;
} axw_slot;

struct axw_node {
  LONG ref;
  axw_bridge *bridge;
  int id;
  int alive;

  /* COM interface slots — each holds its own vtable pointer, the
     object address handed to clients is &node->i_<iface>. */
  IRawElementProviderSimple       i_simple;
  IRawElementProviderFragment     i_fragment;
  IRawElementProviderFragmentRoot i_frag_root;
  IInvokeProvider                 i_invoke;
  IToggleProvider                 i_toggle;
  ISelectionItemProvider          i_selitem;
  ISelectionProvider              i_select;
  IRangeValueProvider             i_range;
  IValueProvider                  i_value;
  IExpandCollapseProvider         i_expand;
  IScrollItemProvider             i_scroll;

  /* semantic data — mirrors the uia_desc tuple */
  int control_type;
  int patterns;
  BSTR name;
  BSTR localized_type;
  BSTR description;
  int value_tag;    /* 0 none, 1 numeric, 2 text */
  double value_num;
  BSTR value_str;
  int has_min;   double vmin;
  int has_max;   double vmax;
  int enabled;
  int expanded;    /* -1 n/a, 0 collapsed, 1 expanded, 3 leaf */
  int focusable;
  int focused;
  int selected;    /* -1 n/a, 0, 1 */
  int toggle_state;/* -1 n/a, 0 off, 1 on, 2 indeterminate */
  int is_password;
  int pos_in_set;  /* 1-based, -1 n/a */
  int size_of_set; /* -1 n/a */
  int level;       /* 1-based, -1 n/a */
  int required;
  int live_setting;
  int action_mask;
  int is_dialog;
  int read_only;

  int parent_id;   /* node id, AXW_FRAME_ID for a11y roots, INT_MIN none */
  int *children;
  int child_count;
  int child_cap;
  RECT rect;       /* client coordinates, pixels */
};

struct axw_bridge {
  int used;
  HWND hwnd;
  axw_node *frame;      /* synthetic fragment root, id AXW_FRAME_ID */
  axw_slot *map;
  int map_cap;
  int map_count;
  int map_dead;
  int focused_id;       /* node id, or AXW_FRAME_ID/INT_MIN for none */
  axw_action *queue;
  int q_head;
  int q_count;
  int q_cap;
  CRITICAL_SECTION lock;
};

static axw_bridge g_bridges[AXW_MAX_BRIDGES];
static int g_init = 0;
static CRITICAL_SECTION g_bridges_lock;

/* ------------------------------------------------------------------ */
/* Small utilities                                                    */

static BSTR bstr_of_utf8(const char *s)
{
  int wlen;
  BSTR b;
  if (!s || !s[0]) return NULL;
  wlen = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  if (wlen <= 0) return NULL;
  b = SysAllocStringLen(NULL, (UINT)(wlen - 1));
  if (!b) return NULL;
  MultiByteToWideChar(CP_UTF8, 0, s, -1, b, wlen);
  return b;
}

static char *utf8_of_bstr(BSTR b)
{
  int len;
  char *s;
  if (!b || !b[0]) return NULL;
  len = WideCharToMultiByte(CP_UTF8, 0, b, -1, NULL, 0, NULL, NULL);
  if (len <= 0) return NULL;
  s = (char *)malloc((size_t)len);
  if (!s) return NULL;
  WideCharToMultiByte(CP_UTF8, 0, b, -1, s, len, NULL, NULL);
  return s;
}

static void set_bstr(BSTR *slot, const char *utf8)
{
  BSTR nb = bstr_of_utf8(utf8);
  if (*slot) SysFreeString(*slot);
  *slot = nb;
}

#define NODE_OF(iface_ptr, field) \
  ((axw_node *)((char *)(iface_ptr) - offsetof(axw_node, field)))

static void free_node(axw_node *n)
{
  if (n->name) SysFreeString(n->name);
  if (n->localized_type) SysFreeString(n->localized_type);
  if (n->description) SysFreeString(n->description);
  if (n->value_str) SysFreeString(n->value_str);
  free(n->children);
  free(n);
}

static LONG axw_addref(axw_node *n)
{
  return InterlockedIncrement(&n->ref);
}

static LONG axw_release(axw_node *n)
{
  LONG r = InterlockedDecrement(&n->ref);
  if (r == 0) free_node(n);
  return r;
}

/* ------------------------------------------------------------------ */
/* id -> node map (open addressing, power-of-two capacity)            */

static unsigned axw_hash(int key)
{
  unsigned x = (unsigned)key;
  x ^= x >> 16;
  x *= 0x7feb352dU;
  x ^= x >> 15;
  x *= 0x846ca68bU;
  x ^= x >> 16;
  return x;
}

static void map_init(axw_bridge *b)
{
  b->map_cap = 64;
  b->map_count = 0;
  b->map_dead = 0;
  b->map = (axw_slot *)calloc((size_t)b->map_cap, sizeof(axw_slot));
}

static void map_insert_raw(axw_slot *map, int cap, int key, axw_node *v)
{
  unsigned i = axw_hash(key) & (unsigned)(cap - 1);
  while (map[i].key != 0)
    i = (i + 1) & (unsigned)(cap - 1);
  map[i].key = key;
  map[i].val = v;
}

static int map_grow(axw_bridge *b)
{
  int ncap = b->map_cap * 2;
  axw_slot *nm = (axw_slot *)calloc((size_t)ncap, sizeof(axw_slot));
  int i;
  if (!nm) return 0;
  for (i = 0; i < b->map_cap; i++)
    if (b->map[i].key > 0)
      map_insert_raw(nm, ncap, b->map[i].key, b->map[i].val);
  free(b->map);
  b->map = nm;
  b->map_cap = ncap;
  b->map_dead = 0;
  return 1;
}

static axw_node *map_find(axw_bridge *b, int key)
{
  unsigned i;
  if (!b->map) return NULL;
  i = axw_hash(key) & (unsigned)(b->map_cap - 1);
  while (b->map[i].key != 0) {
    if (b->map[i].key == key) return b->map[i].val;
    i = (i + 1) & (unsigned)(b->map_cap - 1);
  }
  return NULL;
}

static void map_insert(axw_bridge *b, int key, axw_node *v)
{
  unsigned i;
  if ((b->map_count + b->map_dead + 1) * 10 >= b->map_cap * 7)
    map_grow(b);
  i = axw_hash(key) & (unsigned)(b->map_cap - 1);
  while (b->map[i].key > 0 && b->map[i].key != key)
    i = (i + 1) & (unsigned)(b->map_cap - 1);
  if (b->map[i].key == 0 || b->map[i].key == INT_MIN)
    b->map_count++;
  b->map[i].key = key;
  b->map[i].val = v;
}

static void map_remove(axw_bridge *b, int key)
{
  unsigned i;
  if (!b->map) return;
  i = axw_hash(key) & (unsigned)(b->map_cap - 1);
  while (b->map[i].key != 0) {
    if (b->map[i].key == key) {
      b->map[i].key = INT_MIN;
      b->map[i].val = NULL;
      b->map_count--;
      b->map_dead++;
      return;
    }
    i = (i + 1) & (unsigned)(b->map_cap - 1);
  }
}

/* ------------------------------------------------------------------ */
/* Action queue                                                       */

static void queue_push(axw_bridge *b, int code, int node_id, const char *text)
{
  axw_action *a;
  EnterCriticalSection(&b->lock);
  if (b->q_count >= b->q_cap) {
    /* full: drop the oldest action to make room */
    axw_action *old = &b->queue[b->q_head];
    free(old->text);
    old->text = NULL;
    b->q_head = (b->q_head + 1) % b->q_cap;
    b->q_count--;
  }
  a = &b->queue[(b->q_head + b->q_count) % b->q_cap];
  a->code = code;
  a->node_id = node_id;
  a->text = text ? _strdup(text) : NULL;
  b->q_count++;
  LeaveCriticalSection(&b->lock);
}

/* ------------------------------------------------------------------ */
/* Node helpers                                                       */

static axw_node *resolve(axw_bridge *b, int id)
{
  axw_node *n;
  if (id == AXW_FRAME_ID) return b->frame;
  n = map_find(b, id);
  if (n && !n->alive) return NULL;
  return n;
}

static void client_rect_to_screen(axw_bridge *b, const RECT *r,
                                  double *left, double *top,
                                  double *w, double *h)
{
  POINT tl, br;
  tl.x = r->left;  tl.y = r->top;
  br.x = r->right; br.y = r->bottom;
  ClientToScreen(b->hwnd, &tl);
  ClientToScreen(b->hwnd, &br);
  *left = (double)tl.x;
  *top = (double)tl.y;
  *w = (double)(br.x - tl.x);
  *h = (double)(br.y - tl.y);
}

static SAFEARRAY *runtime_id_of(axw_node *n)
{
  SAFEARRAY *sa;
  LONG i;
  if (n->id == AXW_FRAME_ID) {
    sa = SafeArrayCreateVector(VT_I4, 0, 1);
    if (!sa) return NULL;
    i = UIA_RT_PREFIX;
    SafeArrayPutElement(sa, (LONG[]){0}, &i);
    return sa;
  }
  sa = SafeArrayCreateVector(VT_I4, 0, 3);
  if (!sa) return NULL;
  i = UIA_RT_PREFIX;
  SafeArrayPutElement(sa, (LONG[]){0}, &i);
  i = (LONG)(n->id & 0xFFFF);
  SafeArrayPutElement(sa, (LONG[]){1}, &i);
  i = (LONG)((n->id >> 16) & 0xFFFF);
  SafeArrayPutElement(sa, (LONG[]){2}, &i);
  return sa;
}

/* Clients see a host-composed runtime id: {42, hwnd, ...ours...} where
   our provider-side id arrives as the trailing ints. Direct (provider-
   side) reads give exactly {3, lo, hi} or {3} for the frame. */
static int node_id_of_runtime_id(SAFEARRAY *sa)
{
  LONG lo, hi, lower, upper;
  if (!sa) return INT_MIN;
  SafeArrayGetLBound(sa, 1, &lower);
  SafeArrayGetUBound(sa, 1, &upper);
  if (upper - lower + 1 < 3) return AXW_FRAME_ID;
  SafeArrayGetElement(sa, (LONG[]){lower}, &lo);
  if (lo == 42) { /* host-prefixed composition */
    if (upper - lower + 1 < 5) return AXW_FRAME_ID;
    SafeArrayGetElement(sa, (LONG[]){upper - 1}, &lo);
    SafeArrayGetElement(sa, (LONG[]){upper}, &hi);
    return (int)((lo & 0xFFFF) | ((hi & 0xFFFF) << 16));
  }
  SafeArrayGetElement(sa, (LONG[]){lower + 1}, &lo);
  SafeArrayGetElement(sa, (LONG[]){lower + 2}, &hi);
  return (int)((lo & 0xFFFF) | ((hi & 0xFFFF) << 16));
}

/* deepest element under a client-space point; reverse children order
   so later (topmost) children win */
static axw_node *hit_test(axw_bridge *b, axw_node *n, int x, int y)
{
  int i;
  if (!n->alive) return NULL;
  if (x < n->rect.left || x >= n->rect.right ||
      y < n->rect.top || y >= n->rect.bottom)
    return NULL;
  for (i = n->child_count - 1; i >= 0; i--) {
    axw_node *c = resolve(b, n->children[i]);
    axw_node *hit;
    if (!c) continue;
    hit = hit_test(b, c, x, y);
    if (hit) return hit;
  }
  return n;
}

/* ------------------------------------------------------------------ */
/* Forward declarations for the vtables                               */

static IRawElementProviderSimpleVtbl       g_simple_vtbl;
static IRawElementProviderFragmentVtbl     g_fragment_vtbl;
static IRawElementProviderFragmentRootVtbl g_frag_root_vtbl;
static IInvokeProviderVtbl                 g_invoke_vtbl;
static IToggleProviderVtbl                 g_toggle_vtbl;
static ISelectionItemProviderVtbl          g_selitem_vtbl;
static ISelectionProviderVtbl              g_select_vtbl;
static IRangeValueProviderVtbl             g_range_vtbl;
static IValueProviderVtbl                  g_value_vtbl;
static IExpandCollapseProviderVtbl         g_expand_vtbl;
static IScrollItemProviderVtbl             g_scroll_vtbl;

static axw_node *node_new(axw_bridge *b, int id)
{
  axw_node *n = (axw_node *)calloc(1, sizeof(axw_node));
  if (!n) return NULL;
  n->ref = 1;
  n->bridge = b;
  n->id = id;
  n->alive = 1;
  n->i_simple.lpVtbl = &g_simple_vtbl;
  n->i_fragment.lpVtbl = &g_fragment_vtbl;
  n->i_frag_root.lpVtbl = &g_frag_root_vtbl;
  n->i_invoke.lpVtbl = &g_invoke_vtbl;
  n->i_toggle.lpVtbl = &g_toggle_vtbl;
  n->i_selitem.lpVtbl = &g_selitem_vtbl;
  n->i_select.lpVtbl = &g_select_vtbl;
  n->i_range.lpVtbl = &g_range_vtbl;
  n->i_value.lpVtbl = &g_value_vtbl;
  n->i_expand.lpVtbl = &g_expand_vtbl;
  n->i_scroll.lpVtbl = &g_scroll_vtbl;
  n->expanded = -1;
  n->selected = -1;
  n->toggle_state = -1;
  n->pos_in_set = -1;
  n->size_of_set = -1;
  n->level = -1;
  n->parent_id = INT_MIN;
  n->enabled = 1;
  return n;
}

/* ------------------------------------------------------------------ */
/* IUnknown + shared QueryInterface                                   */

static HRESULT axw_qi(axw_node *n, REFIID riid, void **ppv)
{
  void *p = NULL;
  if (!ppv) return E_POINTER;
  *ppv = NULL;
  if (IsEqualIID(riid, &IID_IUnknown) ||
      IsEqualIID(riid, &IID_IRawElementProviderSimple))
    p = &n->i_simple;
  else if (IsEqualIID(riid, &IID_IRawElementProviderFragment))
    p = &n->i_fragment;
  else if (IsEqualIID(riid, &IID_IRawElementProviderFragmentRoot)) {
    if (n->id != AXW_FRAME_ID) return E_NOINTERFACE;
    p = &n->i_frag_root;
  }
  else if (IsEqualIID(riid, &IID_IInvokeProvider)) {
    if (!(n->patterns & PAT_INVOKE)) return E_NOINTERFACE;
    p = &n->i_invoke;
  }
  else if (IsEqualIID(riid, &IID_IToggleProvider)) {
    if (!(n->patterns & PAT_TOGGLE)) return E_NOINTERFACE;
    p = &n->i_toggle;
  }
  else if (IsEqualIID(riid, &IID_ISelectionItemProvider)) {
    if (!(n->patterns & PAT_SEL_ITEM)) return E_NOINTERFACE;
    p = &n->i_selitem;
  }
  else if (IsEqualIID(riid, &IID_ISelectionProvider)) {
    if (!(n->patterns & PAT_SELECTION)) return E_NOINTERFACE;
    p = &n->i_select;
  }
  else if (IsEqualIID(riid, &IID_IRangeValueProvider)) {
    if (!(n->patterns & PAT_RANGE)) return E_NOINTERFACE;
    p = &n->i_range;
  }
  else if (IsEqualIID(riid, &IID_IValueProvider)) {
    if (!(n->patterns & PAT_VALUE)) return E_NOINTERFACE;
    p = &n->i_value;
  }
  else if (IsEqualIID(riid, &IID_IExpandCollapseProvider)) {
    if (!(n->patterns & PAT_EXPAND)) return E_NOINTERFACE;
    p = &n->i_expand;
  }
  else if (IsEqualIID(riid, &IID_IScrollItemProvider)) {
    if (!(n->patterns & PAT_SCROLL_ITEM)) return E_NOINTERFACE;
    p = &n->i_scroll;
  }
  else
    return E_NOINTERFACE;
  axw_addref(n);
  *ppv = p;
  return S_OK;
}

#define IUNKNOWN_IMPL(IFACE, FIELD)                                     \
  static HRESULT STDMETHODCALLTYPE FIELD##_QI(                          \
      IFACE *This, REFIID riid, void **ppv)                             \
  { return axw_qi(NODE_OF(This, FIELD), riid, ppv); }                   \
  static ULONG STDMETHODCALLTYPE FIELD##_AddRef(IFACE *This)            \
  { return (ULONG)axw_addref(NODE_OF(This, FIELD)); }                   \
  static ULONG STDMETHODCALLTYPE FIELD##_Release(IFACE *This)           \
  { return (ULONG)axw_release(NODE_OF(This, FIELD)); }

IUNKNOWN_IMPL(IRawElementProviderSimple,       i_simple)
IUNKNOWN_IMPL(IRawElementProviderFragment,     i_fragment)
IUNKNOWN_IMPL(IRawElementProviderFragmentRoot, i_frag_root)
IUNKNOWN_IMPL(IInvokeProvider,                 i_invoke)
IUNKNOWN_IMPL(IToggleProvider,                 i_toggle)
IUNKNOWN_IMPL(ISelectionItemProvider,          i_selitem)
IUNKNOWN_IMPL(ISelectionProvider,              i_select)
IUNKNOWN_IMPL(IRangeValueProvider,             i_range)
IUNKNOWN_IMPL(IValueProvider,                  i_value)
IUNKNOWN_IMPL(IExpandCollapseProvider,         i_expand)
IUNKNOWN_IMPL(IScrollItemProvider,             i_scroll)

#define DEAD(n) (!(n)->alive)

/* ------------------------------------------------------------------ */
/* IRawElementProviderSimple                                          */

static HRESULT STDMETHODCALLTYPE simple_get_ProviderOptions(
    IRawElementProviderSimple *This, enum ProviderOptions *pRetVal)
{
  if (!pRetVal) return E_POINTER;
  *pRetVal = (enum ProviderOptions)(
      ProviderOptions_ServerSideProvider |
      ProviderOptions_UseComThreading |
      ProviderOptions_ProviderOwnsSetFocus);
  (void)This;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE simple_GetPatternProvider(
    IRawElementProviderSimple *This, PATTERNID patternId,
    IUnknown **pRetVal)
{
  axw_node *n = NODE_OF(This, i_simple);
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  switch (patternId) {
  case UIA_PAT_INVOKE:
    if (n->patterns & PAT_INVOKE) *pRetVal = (IUnknown *)&n->i_invoke;
    break;
  case UIA_PAT_TOGGLE:
    if (n->patterns & PAT_TOGGLE) *pRetVal = (IUnknown *)&n->i_toggle;
    break;
  case UIA_PAT_SEL_ITEM:
    if (n->patterns & PAT_SEL_ITEM) *pRetVal = (IUnknown *)&n->i_selitem;
    break;
  case UIA_PAT_SELECTION:
    if (n->patterns & PAT_SELECTION) *pRetVal = (IUnknown *)&n->i_select;
    break;
  case UIA_PAT_RANGE:
    if (n->patterns & PAT_RANGE) *pRetVal = (IUnknown *)&n->i_range;
    break;
  case UIA_PAT_VALUE:
    if (n->patterns & PAT_VALUE) *pRetVal = (IUnknown *)&n->i_value;
    break;
  case UIA_PAT_EXPAND:
    if (n->patterns & PAT_EXPAND) *pRetVal = (IUnknown *)&n->i_expand;
    break;
  case UIA_PAT_SCROLL_ITEM:
    if (n->patterns & PAT_SCROLL_ITEM)
      *pRetVal = (IUnknown *)&n->i_scroll;
    break;
  default:
    break;
  }
  if (*pRetVal) axw_addref(n);
  return S_OK;
}

static void v_bool(VARIANT *v, int b)
{
  V_VT(v) = VT_BOOL;
  V_BOOL(v) = b ? VARIANT_TRUE : VARIANT_FALSE;
}

static void v_i4(VARIANT *v, LONG x)
{
  V_VT(v) = VT_I4;
  V_I4(v) = x;
}

static void v_r8(VARIANT *v, double x)
{
  V_VT(v) = VT_R8;
  V_R8(v) = x;
}

static void v_bstr(VARIANT *v, BSTR b)
{
  if (!b) { V_VT(v) = VT_EMPTY; return; }
  V_VT(v) = VT_BSTR;
  V_BSTR(v) = SysAllocString(b);
}

static HRESULT STDMETHODCALLTYPE simple_GetPropertyValue(
    IRawElementProviderSimple *This, PROPERTYID propertyId, VARIANT *pRetVal)
{
  axw_node *n = NODE_OF(This, i_simple);
  axw_bridge *b = n->bridge;
  if (!pRetVal) return E_POINTER;
  VariantInit(pRetVal);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  EnterCriticalSection(&b->lock);
  switch (propertyId) {
  case UIA_PROP_AUTOMATION_ID: {
    char buf[24];
    _snprintf(buf, sizeof(buf), "%d", n->id);
    V_VT(pRetVal) = VT_BSTR;
    V_BSTR(pRetVal) = bstr_of_utf8(buf);
    break;
  }
  case UIA_PROP_BOUNDING_RECT: {
    double l, t, w, h;
    SAFEARRAY *sa;
    LONG i;
    client_rect_to_screen(b, &n->rect, &l, &t, &w, &h);
    sa = SafeArrayCreateVector(VT_R8, 0, 4);
    if (sa) {
      double vals[4] = { l, t, w, h };
      for (i = 0; i < 4; i++)
        SafeArrayPutElement(sa, &i, &vals[i]);
      V_VT(pRetVal) = VT_R8 | VT_ARRAY;
      V_ARRAY(pRetVal) = sa;
    }
    break;
  }
  case UIA_PROP_CONTROL_TYPE:
    v_i4(pRetVal, n->control_type);
    break;
  case UIA_PROP_LOCALIZED_TYPE:
    v_bstr(pRetVal, n->localized_type);
    break;
  case UIA_PROP_NAME:
    v_bstr(pRetVal, n->name);
    break;
  case UIA_PROP_HAS_KB_FOCUS:
    v_bool(pRetVal, n->focused);
    break;
  case UIA_PROP_IS_KB_FOCUSABLE:
    v_bool(pRetVal, n->focusable);
    break;
  case UIA_PROP_IS_ENABLED:
    v_bool(pRetVal, n->enabled);
    break;
  case UIA_PROP_HELP_TEXT:
    v_bstr(pRetVal, n->description);
    break;
  case UIA_PROP_IS_CONTROL_ELEM:
  case UIA_PROP_IS_CONTENT_ELEM:
    v_bool(pRetVal, 1);
    break;
  case UIA_PROP_IS_PASSWORD:
    v_bool(pRetVal, n->is_password);
    break;
  case UIA_PROP_IS_OFFSCREEN: {
    RECT cr;
    GetClientRect(b->hwnd, &cr);
    v_bool(pRetVal,
           n->rect.right <= 0 || n->rect.bottom <= 0 ||
           n->rect.left >= cr.right || n->rect.top >= cr.bottom);
    break;
  }
  case UIA_PROP_FRAMEWORK_ID:
    V_VT(pRetVal) = VT_BSTR;
    V_BSTR(pRetVal) = bstr_of_utf8("LUI");
    break;
  case UIA_PROP_IS_REQUIRED:
    v_bool(pRetVal, n->required);
    break;
  case UIA_PROP_VALUE:
    if (n->patterns & PAT_VALUE) {
      if (n->value_tag == 2) {
        V_VT(pRetVal) = VT_BSTR;
        V_BSTR(pRetVal) =
            n->value_str ? SysAllocString(n->value_str) : NULL;
      } else if (n->value_tag == 1) {
        char buf[32];
        _snprintf(buf, sizeof(buf), "%g", n->value_num);
        V_VT(pRetVal) = VT_BSTR;
        V_BSTR(pRetVal) = bstr_of_utf8(buf);
      }
    }
    break;
  case UIA_PROP_VALUE_READONLY:
  case UIA_PROP_RV_READONLY:
    v_bool(pRetVal, n->read_only || !n->enabled);
    break;
  case UIA_PROP_RV_VALUE:
    if (n->patterns & PAT_RANGE) v_r8(pRetVal, n->value_num);
    break;
  case UIA_PROP_RV_MIN:
    if (n->patterns & PAT_RANGE) v_r8(pRetVal, n->has_min ? n->vmin : 0.0);
    break;
  case UIA_PROP_RV_MAX:
    if (n->patterns & PAT_RANGE) v_r8(pRetVal, n->has_max ? n->vmax : 100.0);
    break;
  case UIA_PROP_RV_LARGE:
    if (n->patterns & PAT_RANGE) {
      double span = (n->has_max ? n->vmax : 100.0) - (n->has_min ? n->vmin : 0.0);
      if (span <= 0) span = 1;
      v_r8(pRetVal, span / 10.0);
    }
    break;
  case UIA_PROP_RV_SMALL:
    if (n->patterns & PAT_RANGE) v_r8(pRetVal, 1.0);
    break;
  case UIA_PROP_EXPAND_STATE:
    if (n->patterns & PAT_EXPAND)
      v_i4(pRetVal, n->expanded < 0 ? ExpandCollapseState_LeafNode
                                    : n->expanded);
    break;
  case UIA_PROP_IS_SELECTED:
    if (n->selected >= 0) v_bool(pRetVal, n->selected);
    break;
  case UIA_PROP_TOGGLE_STATE:
    if (n->patterns & PAT_TOGGLE)
      v_i4(pRetVal, n->toggle_state < 0 ? ToggleState_Indeterminate
                                        : n->toggle_state);
    break;
  case UIA_PROP_LIVE_SETTING:
    v_i4(pRetVal, n->live_setting);
    break;
  case UIA_PROP_POS_IN_SET:
    if (n->pos_in_set > 0) v_i4(pRetVal, n->pos_in_set);
    break;
  case UIA_PROP_SIZE_OF_SET:
    if (n->size_of_set > 0) v_i4(pRetVal, n->size_of_set);
    break;
  case UIA_PROP_LEVEL:
    if (n->level > 0) v_i4(pRetVal, n->level);
    break;
  case UIA_PROP_FULL_DESC:
    v_bstr(pRetVal, n->description);
    break;
  case UIA_PROP_IS_DIALOG:
    if (n->is_dialog) v_bool(pRetVal, 1);
    break;
  default:
    break; /* VT_EMPTY — unsupported */
  }
  LeaveCriticalSection(&b->lock);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE simple_get_HostRawElementProvider(
    IRawElementProviderSimple *This, IRawElementProviderSimple **pRetVal)
{
  axw_node *n = NODE_OF(This, i_simple);
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (n->id == AXW_FRAME_ID)
    UiaHostProviderFromHwnd(n->bridge->hwnd, pRetVal);
  return S_OK;
}

static IRawElementProviderSimpleVtbl g_simple_vtbl = {
  i_simple_QI,
  i_simple_AddRef,
  i_simple_Release,
  simple_get_ProviderOptions,
  simple_GetPatternProvider,
  simple_GetPropertyValue,
  simple_get_HostRawElementProvider,
};

/* ------------------------------------------------------------------ */
/* IRawElementProviderFragment                                        */

static HRESULT STDMETHODCALLTYPE fragment_Navigate(
    IRawElementProviderFragment *This, enum NavigateDirection direction,
    IRawElementProviderFragment **pRetVal)
{
  axw_node *n = NODE_OF(This, i_fragment);
  axw_bridge *b = n->bridge;
  axw_node *out = NULL;
  int i;
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  EnterCriticalSection(&b->lock);
  switch (direction) {
  case NavigateDirection_Parent:
    if (n->id != AXW_FRAME_ID && n->parent_id != INT_MIN)
      out = resolve(b, n->parent_id);
    break;
  case NavigateDirection_FirstChild:
    if (n->child_count > 0)
      out = resolve(b, n->children[0]);
    break;
  case NavigateDirection_LastChild:
    if (n->child_count > 0)
      out = resolve(b, n->children[n->child_count - 1]);
    break;
  case NavigateDirection_NextSibling:
  case NavigateDirection_PreviousSibling: {
    axw_node *p;
    if (n->id == AXW_FRAME_ID || n->parent_id == INT_MIN) break;
    p = resolve(b, n->parent_id);
    if (!p) break;
    for (i = 0; i < p->child_count; i++) {
      if (p->children[i] == n->id) {
        int j = direction == NavigateDirection_NextSibling ? i + 1 : i - 1;
        if (j >= 0 && j < p->child_count)
          out = resolve(b, p->children[j]);
        break;
      }
    }
    break;
  }
  default:
    break;
  }
  if (out) {
    axw_addref(out);
    *pRetVal = &out->i_fragment;
  }
  LeaveCriticalSection(&b->lock);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE fragment_GetRuntimeId(
    IRawElementProviderFragment *This, SAFEARRAY **pRetVal)
{
  axw_node *n = NODE_OF(This, i_fragment);
  if (!pRetVal) return E_POINTER;
  *pRetVal = runtime_id_of(n);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE fragment_get_BoundingRectangle(
    IRawElementProviderFragment *This, struct UiaRect *pRetVal)
{
  axw_node *n = NODE_OF(This, i_fragment);
  double l, t, w, h;
  if (!pRetVal) return E_POINTER;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  client_rect_to_screen(n->bridge, &n->rect, &l, &t, &w, &h);
  pRetVal->left = l;
  pRetVal->top = t;
  pRetVal->width = w;
  pRetVal->height = h;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE fragment_GetEmbeddedFragmentRoots(
    IRawElementProviderFragment *This, SAFEARRAY **pRetVal)
{
  if (!pRetVal) return E_POINTER;
  *pRetVal = SafeArrayCreateVector(VT_UNKNOWN, 0, 0);
  (void)This;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE fragment_SetFocus(
    IRawElementProviderFragment *This)
{
  axw_node *n = NODE_OF(This, i_fragment);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_FOCUS, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE fragment_get_FragmentRoot(
    IRawElementProviderFragment *This,
    IRawElementProviderFragmentRoot **pRetVal)
{
  axw_node *n = NODE_OF(This, i_fragment);
  axw_node *root;
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  root = n->bridge->frame;
  if (root && root->alive) {
    axw_addref(root);
    *pRetVal = &root->i_frag_root;
  }
  return S_OK;
}

static IRawElementProviderFragmentVtbl g_fragment_vtbl = {
  i_fragment_QI,
  i_fragment_AddRef,
  i_fragment_Release,
  fragment_Navigate,
  fragment_GetRuntimeId,
  fragment_get_BoundingRectangle,
  fragment_GetEmbeddedFragmentRoots,
  fragment_SetFocus,
  fragment_get_FragmentRoot,
};

/* ------------------------------------------------------------------ */
/* IRawElementProviderFragmentRoot (frame node only)                  */

static HRESULT STDMETHODCALLTYPE fragroot_ElementProviderFromPoint(
    IRawElementProviderFragmentRoot *This, double x, double y,
    IRawElementProviderFragment **pRetVal)
{
  axw_node *n = NODE_OF(This, i_frag_root);
  axw_bridge *b = n->bridge;
  POINT pt;
  axw_node *hit;
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (!n->alive) return UIA_E_ELEMENTNOTAVAILABLE;
  pt.x = (LONG)x;
  pt.y = (LONG)y;
  ScreenToClient(b->hwnd, &pt);
  EnterCriticalSection(&b->lock);
  hit = hit_test(b, b->frame, (int)pt.x, (int)pt.y);
  if (!hit) hit = b->frame;
  axw_addref(hit);
  *pRetVal = &hit->i_fragment;
  LeaveCriticalSection(&b->lock);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE fragroot_GetFocus(
    IRawElementProviderFragmentRoot *This,
    IRawElementProviderFragment **pRetVal)
{
  axw_node *n = NODE_OF(This, i_frag_root);
  axw_bridge *b = n->bridge;
  axw_node *f;
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (!n->alive) return UIA_E_ELEMENTNOTAVAILABLE;
  EnterCriticalSection(&b->lock);
  f = resolve(b, b->focused_id);
  if (f) {
    axw_addref(f);
    *pRetVal = &f->i_fragment;
  }
  LeaveCriticalSection(&b->lock);
  return S_OK;
}

static IRawElementProviderFragmentRootVtbl g_frag_root_vtbl = {
  i_frag_root_QI,
  i_frag_root_AddRef,
  i_frag_root_Release,
  fragroot_ElementProviderFromPoint,
  fragroot_GetFocus,
};

/* ------------------------------------------------------------------ */
/* Control patterns                                                   */

static HRESULT STDMETHODCALLTYPE invoke_Invoke(IInvokeProvider *This)
{
  axw_node *n = NODE_OF(This, i_invoke);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_PRESS, n->id, NULL);
  return S_OK;
}

static IInvokeProviderVtbl g_invoke_vtbl = {
  i_invoke_QI, i_invoke_AddRef, i_invoke_Release, invoke_Invoke,
};

static HRESULT STDMETHODCALLTYPE toggle_Toggle(IToggleProvider *This)
{
  axw_node *n = NODE_OF(This, i_toggle);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_PRESS, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE toggle_get_ToggleState(
    IToggleProvider *This, enum ToggleState *pRetVal)
{
  axw_node *n = NODE_OF(This, i_toggle);
  if (!pRetVal) return E_POINTER;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  *pRetVal = n->toggle_state < 0 ? ToggleState_Indeterminate
                               : (enum ToggleState)n->toggle_state;
  return S_OK;
}

static IToggleProviderVtbl g_toggle_vtbl = {
  i_toggle_QI, i_toggle_AddRef, i_toggle_Release,
  toggle_Toggle, toggle_get_ToggleState,
};

static HRESULT STDMETHODCALLTYPE selitem_Select(ISelectionItemProvider *This)
{
  axw_node *n = NODE_OF(This, i_selitem);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_PRESS, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE selitem_AddToSelection(
    ISelectionItemProvider *This)
{
  axw_node *n = NODE_OF(This, i_selitem);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_PRESS, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE selitem_RemoveFromSelection(
    ISelectionItemProvider *This)
{
  axw_node *n = NODE_OF(This, i_selitem);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_PRESS, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE selitem_get_IsSelected(
    ISelectionItemProvider *This, WINBOOL *pRetVal)
{
  axw_node *n = NODE_OF(This, i_selitem);
  if (!pRetVal) return E_POINTER;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  *pRetVal = n->selected > 0 ? TRUE : FALSE;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE selitem_get_SelectionContainer(
    ISelectionItemProvider *This, IRawElementProviderSimple **pRetVal)
{
  axw_node *n = NODE_OF(This, i_selitem);
  axw_node *p;
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  p = n->parent_id == INT_MIN ? NULL : resolve(n->bridge, n->parent_id);
  if (p) {
    axw_addref(p);
    *pRetVal = &p->i_simple;
  }
  return S_OK;
}

static ISelectionItemProviderVtbl g_selitem_vtbl = {
  i_selitem_QI, i_selitem_AddRef, i_selitem_Release,
  selitem_Select, selitem_AddToSelection, selitem_RemoveFromSelection,
  selitem_get_IsSelected, selitem_get_SelectionContainer,
};

static HRESULT STDMETHODCALLTYPE select_GetSelection(
    ISelectionProvider *This, SAFEARRAY **pRetVal)
{
  axw_node *n = NODE_OF(This, i_select);
  axw_bridge *b = n->bridge;
  axw_node **sel;
  int i, count = 0;
  SAFEARRAY *sa;
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  EnterCriticalSection(&b->lock);
  sel = (axw_node **)malloc(sizeof(axw_node *) *
                            (size_t)(n->child_count ? n->child_count : 1));
  if (!sel) {
    LeaveCriticalSection(&b->lock);
    return E_OUTOFMEMORY;
  }
  for (i = 0; i < n->child_count; i++) {
    axw_node *c = resolve(b, n->children[i]);
    if (c && c->selected > 0) sel[count++] = c;
  }
  sa = SafeArrayCreateVector(VT_UNKNOWN, 0, (ULONG)count);
  for (i = 0; i < count; i++) {
    IUnknown *unk = (IUnknown *)&sel[i]->i_simple;
    LONG idx = i;
    axw_addref(sel[i]);
    SafeArrayPutElement(sa, &idx, unk);
    /* SafeArrayPutElement keeps the interface pointer; our addref is
       the one transferred to the array. */
    axw_release(sel[i]);
  }
  free(sel);
  LeaveCriticalSection(&b->lock);
  *pRetVal = sa;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE select_get_CanSelectMultiple(
    ISelectionProvider *This, WINBOOL *pRetVal)
{
  if (!pRetVal) return E_POINTER;
  *pRetVal = FALSE;
  (void)This;
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE select_get_IsSelectionRequired(
    ISelectionProvider *This, WINBOOL *pRetVal)
{
  if (!pRetVal) return E_POINTER;
  *pRetVal = FALSE;
  (void)This;
  return S_OK;
}

static ISelectionProviderVtbl g_select_vtbl = {
  i_select_QI, i_select_AddRef, i_select_Release,
  select_GetSelection, select_get_CanSelectMultiple,
  select_get_IsSelectionRequired,
};

static HRESULT STDMETHODCALLTYPE range_SetValue(
    IRangeValueProvider *This, double val)
{
  axw_node *n = NODE_OF(This, i_range);
  char buf[32];
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  if (n->read_only || !n->enabled) return UIA_E_ELEMENTNOTENABLED;
  _snprintf(buf, sizeof(buf), "%.17g", val);
  queue_push(n->bridge, ACT_SET_VALUE, n->id, buf);
  return S_OK;
}

#define RANGE_GET(NAME, EXPR)                                           \
  static HRESULT STDMETHODCALLTYPE range_get_##NAME(                    \
      IRangeValueProvider *This, double *pRetVal)                       \
  {                                                                     \
    axw_node *n = NODE_OF(This, i_range);                               \
    if (!pRetVal) return E_POINTER;                                     \
    if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;                      \
    *pRetVal = (EXPR);                                                  \
    return S_OK;                                                        \
  }

RANGE_GET(Value, n->value_num)
RANGE_GET(Maximum, n->has_max ? n->vmax : 100.0)
RANGE_GET(Minimum, n->has_min ? n->vmin : 0.0)
RANGE_GET(LargeChange,
          ((n->has_max ? n->vmax : 100.0) - (n->has_min ? n->vmin : 0.0))
              / 10.0)
RANGE_GET(SmallChange, 1.0)

static HRESULT STDMETHODCALLTYPE range_get_IsReadOnly(
    IRangeValueProvider *This, WINBOOL *pRetVal)
{
  axw_node *n = NODE_OF(This, i_range);
  if (!pRetVal) return E_POINTER;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  *pRetVal = (n->read_only || !n->enabled) ? TRUE : FALSE;
  return S_OK;
}

static IRangeValueProviderVtbl g_range_vtbl = {
  i_range_QI, i_range_AddRef, i_range_Release,
  range_SetValue, range_get_Value, range_get_IsReadOnly,
  range_get_Maximum, range_get_Minimum,
  range_get_LargeChange, range_get_SmallChange,
};

static HRESULT STDMETHODCALLTYPE value_SetValue(
    IValueProvider *This, LPCWSTR val)
{
  axw_node *n = NODE_OF(This, i_value);
  char *utf8;
  int len;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  if (n->read_only || !n->enabled) return UIA_E_ELEMENTNOTENABLED;
  if (!val) return E_INVALIDARG;
  len = WideCharToMultiByte(CP_UTF8, 0, val, -1, NULL, 0, NULL, NULL);
  if (len <= 0) return E_FAIL;
  utf8 = (char *)malloc((size_t)len);
  if (!utf8) return E_OUTOFMEMORY;
  WideCharToMultiByte(CP_UTF8, 0, val, -1, utf8, len, NULL, NULL);
  queue_push(n->bridge, ACT_SET_VALUE, n->id, utf8);
  free(utf8);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE value_get_Value(
    IValueProvider *This, BSTR *pRetVal)
{
  axw_node *n = NODE_OF(This, i_value);
  if (!pRetVal) return E_POINTER;
  *pRetVal = NULL;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  if (n->value_tag == 2) {
    if (n->value_str) *pRetVal = SysAllocString(n->value_str);
  } else if (n->value_tag == 1) {
    char buf[32];
    _snprintf(buf, sizeof(buf), "%g", n->value_num);
    *pRetVal = bstr_of_utf8(buf);
  }
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE value_get_IsReadOnly(
    IValueProvider *This, WINBOOL *pRetVal)
{
  axw_node *n = NODE_OF(This, i_value);
  if (!pRetVal) return E_POINTER;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  *pRetVal = (n->read_only || !n->enabled) ? TRUE : FALSE;
  return S_OK;
}

static IValueProviderVtbl g_value_vtbl = {
  i_value_QI, i_value_AddRef, i_value_Release,
  value_SetValue, value_get_Value, value_get_IsReadOnly,
};

static HRESULT STDMETHODCALLTYPE expand_Expand(
    IExpandCollapseProvider *This)
{
  axw_node *n = NODE_OF(This, i_expand);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_EXPAND, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE expand_Collapse(
    IExpandCollapseProvider *This)
{
  axw_node *n = NODE_OF(This, i_expand);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_COLLAPSE, n->id, NULL);
  return S_OK;
}

static HRESULT STDMETHODCALLTYPE expand_get_ExpandCollapseState(
    IExpandCollapseProvider *This, enum ExpandCollapseState *pRetVal)
{
  axw_node *n = NODE_OF(This, i_expand);
  if (!pRetVal) return E_POINTER;
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  *pRetVal = n->expanded < 0 ? ExpandCollapseState_LeafNode
                           : (enum ExpandCollapseState)n->expanded;
  return S_OK;
}

static IExpandCollapseProviderVtbl g_expand_vtbl = {
  i_expand_QI, i_expand_AddRef, i_expand_Release,
  expand_Expand, expand_Collapse, expand_get_ExpandCollapseState,
};

static HRESULT STDMETHODCALLTYPE scroll_ScrollIntoView(
    IScrollItemProvider *This)
{
  axw_node *n = NODE_OF(This, i_scroll);
  if (DEAD(n)) return UIA_E_ELEMENTNOTAVAILABLE;
  queue_push(n->bridge, ACT_SCROLL, n->id, NULL);
  return S_OK;
}

static IScrollItemProviderVtbl g_scroll_vtbl = {
  i_scroll_QI, i_scroll_AddRef, i_scroll_Release,
  scroll_ScrollIntoView,
};

/* ------------------------------------------------------------------ */
/* Bridge management                                                  */

static void bridge_init_once(void)
{
  if (g_init) return;
  InitializeCriticalSection(&g_bridges_lock);
  memset(g_bridges, 0, sizeof(g_bridges));
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  g_init = 1;
}

static axw_bridge *bridge_of_id(int id)
{
  if (id < 0 || id >= AXW_MAX_BRIDGES || !g_bridges[id].used)
    return NULL;
  return &g_bridges[id];
}

static int desc_int(value desc, int i)
{
  return (int)Int_val(Field(desc, i));
}

static int desc_bool(value desc, int i)
{
  return Int_val(Field(desc, i)) ? 1 : 0;
}

static double desc_num(value desc, int i)
{
  return Double_val(Field(desc, i));
}

static const char *desc_str(value desc, int i)
{
  return String_val(Field(desc, i));
}

static void node_apply_desc(axw_node *n, value desc)
{
  n->control_type = desc_int(desc, 0);
  n->patterns = desc_int(desc, 1);
  set_bstr(&n->name, desc_str(desc, 2));
  set_bstr(&n->localized_type, desc_str(desc, 3));
  set_bstr(&n->description, desc_str(desc, 4));
  n->value_tag = desc_int(desc, 5);
  n->value_num = desc_num(desc, 6);
  set_bstr(&n->value_str, desc_str(desc, 7));
  n->has_min = desc_bool(desc, 8);
  n->vmin = desc_num(desc, 9);
  n->has_max = desc_bool(desc, 10);
  n->vmax = desc_num(desc, 11);
  n->enabled = desc_bool(desc, 12);
  n->expanded = desc_int(desc, 13);
  n->focusable = desc_bool(desc, 14);
  n->focused = desc_bool(desc, 15);
  n->selected = desc_int(desc, 16);
  n->toggle_state = desc_int(desc, 17);
  n->is_password = desc_bool(desc, 18);
  n->pos_in_set = desc_int(desc, 19);
  n->size_of_set = desc_int(desc, 20);
  n->level = desc_int(desc, 21);
  n->required = desc_bool(desc, 22);
  n->live_setting = desc_int(desc, 23);
  n->action_mask = desc_int(desc, 24);
  n->is_dialog = desc_bool(desc, 25);
  n->read_only = desc_bool(desc, 26);
}

/* ---- OCaml entry points ---- */

CAMLprim value lui_axw_attach(value vhwnd)
{
  CAMLparam1(vhwnd);
  int i;
  HWND hwnd;
  axw_bridge *b = NULL;
  bridge_init_once();
  hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  EnterCriticalSection(&g_bridges_lock);
  for (i = 0; i < AXW_MAX_BRIDGES; i++)
    if (!g_bridges[i].used) { b = &g_bridges[i]; break; }
  if (!b) {
    LeaveCriticalSection(&g_bridges_lock);
    caml_failwith("lui_axw_attach: bridge table full");
  }
  memset(b, 0, sizeof(*b));
  b->used = 1;
  b->hwnd = hwnd;
  b->focused_id = INT_MIN;
  InitializeCriticalSection(&b->lock);
  map_init(b);
  b->q_cap = AXW_QUEUE_CAP;
  b->queue = (axw_action *)calloc((size_t)b->q_cap, sizeof(axw_action));
  b->frame = node_new(b, AXW_FRAME_ID);
  if (!b->frame || !b->map || !b->queue) {
    if (b->frame) free_node(b->frame);
    free(b->map);
    free(b->queue);
    DeleteCriticalSection(&b->lock);
    b->used = 0;
    LeaveCriticalSection(&g_bridges_lock);
    caml_failwith("lui_axw_attach: out of memory");
  }
  b->frame->control_type = 50033; /* Pane */
  set_bstr(&b->frame->name, "LUI window");
  {
    RECT cr;
    GetClientRect(hwnd, &cr);
    b->frame->rect = cr;
  }
  LeaveCriticalSection(&g_bridges_lock);
  CAMLreturn(Val_int((int)(b - g_bridges)));
}

CAMLprim value lui_axw_detach(value vid)
{
  CAMLparam1(vid);
  axw_bridge *b;
  int i;
  bridge_init_once();
  b = bridge_of_id(Int_val(vid));
  if (!b) CAMLreturn(Val_unit);
  EnterCriticalSection(&b->lock);
  /* mark every element dead; clients holding providers see them go */
  if (b->map)
    for (i = 0; i < b->map_cap; i++)
      if (b->map[i].key > 0) b->map[i].val->alive = 0;
  if (b->frame) b->frame->alive = 0;
  for (i = 0; i < b->q_count; i++) {
    axw_action *a = &b->queue[(b->q_head + i) % b->q_cap];
    free(a->text);
  }
  LeaveCriticalSection(&b->lock);
  EnterCriticalSection(&g_bridges_lock);
  b->used = 0;
  LeaveCriticalSection(&g_bridges_lock);
  /* release the bridge-held refs; client refs keep objects alive */
  if (b->map)
    for (i = 0; i < b->map_cap; i++)
      if (b->map[i].key > 0) axw_release(b->map[i].val);
  if (b->frame) axw_release(b->frame);
  free(b->map);
  free(b->queue);
  DeleteCriticalSection(&b->lock);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_apply(value vid, value vid2, value vdesc)
{
  CAMLparam3(vid, vid2, vdesc);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  int id = Int_val(vid2);
  if (!b || !b->map) CAMLreturn(Val_unit);
  EnterCriticalSection(&b->lock);
  n = map_find(b, id);
  if (!n) {
    n = node_new(b, id);
    if (!n) {
      LeaveCriticalSection(&b->lock);
      caml_failwith("lui_axw_apply: out of memory");
    }
    map_insert(b, id, n); /* bridge owns the initial ref */
  }
  node_apply_desc(n, vdesc);
  LeaveCriticalSection(&b->lock);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_link(value vid, value vid2, value vparent,
                            value vchildren)
{
  CAMLparam4(vid, vid2, vparent, vchildren);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  int id = Int_val(vid2);
  mlsize_t count = Wosize_val(vchildren);
  mlsize_t i;
  int *kids;
  if (!b || !b->map) CAMLreturn(Val_unit);
  kids = (int *)malloc(sizeof(int) * (size_t)(count ? count : 1));
  if (!kids) caml_failwith("lui_axw_link: out of memory");
  for (i = 0; i < count; i++)
    kids[i] = Int_val(Field(vchildren, i));
  EnterCriticalSection(&b->lock);
  n = map_find(b, id);
  if (!n) {
    n = node_new(b, id);
    if (!n) {
      LeaveCriticalSection(&b->lock);
      free(kids);
      caml_failwith("lui_axw_link: out of memory");
    }
    map_insert(b, id, n);
  }
  n->parent_id = Int_val(vparent);
  free(n->children);
  n->children = kids;
  n->child_count = (int)count;
  n->child_cap = (int)count;
  LeaveCriticalSection(&b->lock);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_set_frame(value vid, value vid2, value vrect)
{
  CAMLparam3(vid, vid2, vrect);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  double x, y, w, h;
  if (!b) CAMLreturn(Val_unit);
  /* an all-float record is an unboxed float array in OCaml */
  x = Double_field(vrect, 0);
  y = Double_field(vrect, 1);
  w = Double_field(vrect, 2);
  h = Double_field(vrect, 3);
  EnterCriticalSection(&b->lock);
  n = Int_val(vid2) == AXW_FRAME_ID ? b->frame : map_find(b, Int_val(vid2));
  if (n) {
    n->rect.left = (LONG)x;
    n->rect.top = (LONG)y;
    n->rect.right = (LONG)(x + w);
    n->rect.bottom = (LONG)(y + h);
  }
  LeaveCriticalSection(&b->lock);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_remove(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n, *p;
  int id = Int_val(vid2);
  int i;
  if (!b || !b->map) CAMLreturn(Val_unit);
  EnterCriticalSection(&b->lock);
  n = map_find(b, id);
  if (!n) {
    LeaveCriticalSection(&b->lock);
    CAMLreturn(Val_unit);
  }
  /* unlink from the parent's children list */
  p = n->parent_id == INT_MIN ? NULL : map_find(b, n->parent_id);
  if (!p && n->parent_id == AXW_FRAME_ID) p = b->frame;
  if (p) {
    for (i = 0; i < p->child_count; i++)
      if (p->children[i] == id) {
        memmove(&p->children[i], &p->children[i + 1],
                sizeof(int) * (size_t)(p->child_count - i - 1));
        p->child_count--;
        break;
      }
  }
  n->alive = 0;
  map_remove(b, id);
  LeaveCriticalSection(&b->lock);
  axw_release(n); /* drop the bridge ref; clients may still hold refs */
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_finish(value vid, value vroots)
{
  CAMLparam2(vid, vroots);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  mlsize_t count = Wosize_val(vroots);
  mlsize_t i;
  int *kids;
  if (!b) CAMLreturn(Val_unit);
  kids = (int *)malloc(sizeof(int) * (size_t)(count ? count : 1));
  if (!kids) caml_failwith("lui_axw_finish: out of memory");
  for (i = 0; i < count; i++)
    kids[i] = Int_val(Field(vroots, i));
  EnterCriticalSection(&b->lock);
  free(b->frame->children);
  b->frame->children = kids;
  b->frame->child_count = (int)count;
  b->frame->child_cap = (int)count;
  {
    RECT cr;
    GetClientRect(b->hwnd, &cr);
    b->frame->rect = cr;
  }
  LeaveCriticalSection(&b->lock);
  CAMLreturn(Val_unit);
}

static void variant_of_uia_v(value v, VARIANT *out)
{
  int tag;
  VariantInit(out);
  tag = Int_val(Field(v, 0));
  switch (tag) {
  case 1: v_i4(out, (LONG)Double_val(Field(v, 1))); break;
  case 2: v_r8(out, Double_val(Field(v, 1))); break;
  case 3: v_bool(out, Double_val(Field(v, 1)) != 0.0); break;
  case 4:
    V_VT(out) = VT_BSTR;
    V_BSTR(out) = bstr_of_utf8(String_val(Field(v, 2)));
    break;
  default: break; /* VT_EMPTY */
  }
}

CAMLprim value lui_axw_raise_prop(value vid, value vtarget, value vprop,
                                  value vold, value vnew)
{
  CAMLparam5(vid, vtarget, vprop, vold, vnew);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  VARIANT ov, nv;
  if (!b) CAMLreturn(Val_unit);
  variant_of_uia_v(vold, &ov);
  variant_of_uia_v(vnew, &nv);
  n = resolve(b, Int_val(vtarget));
  if (n)
    UiaRaiseAutomationPropertyChangedEvent(&n->i_simple,
                                           (PROPERTYID)Int_val(vprop),
                                           ov, nv);
  VariantClear(&ov);
  VariantClear(&nv);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_raise_event(value vid, value vtarget, value vev)
{
  CAMLparam3(vid, vtarget, vev);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vtarget));
  if (n)
    UiaRaiseAutomationEvent(&n->i_simple, (EVENTID)Int_val(vev));
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_raise_struct(value vid, value vtarget)
{
  CAMLparam2(vid, vtarget);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vtarget));
  if (n) {
    /* mingw's signature takes the runtime id as a plain int array */
    int rt[3];
    int len;
    if (n->id == AXW_FRAME_ID) {
      rt[0] = UIA_RT_PREFIX;
      len = 1;
    } else {
      rt[0] = UIA_RT_PREFIX;
      rt[1] = n->id & 0xFFFF;
      rt[2] = (n->id >> 16) & 0xFFFF;
      len = 3;
    }
    UiaRaiseStructureChangedEvent(&n->i_simple,
                                  StructureChangeType_ChildrenInvalidated,
                                  rt, len);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_set_focus(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  if (!b) CAMLreturn(Val_unit);
  EnterCriticalSection(&b->lock);
  b->focused_id = Int_val(vid2);
  LeaveCriticalSection(&b->lock);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_drain(value vid)
{
  CAMLparam1(vid);
  CAMLlocal3(res, tup, str);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  int i, n;
  if (!b) CAMLreturn(caml_alloc(0, 0));
  EnterCriticalSection(&b->lock);
  n = b->q_count;
  res = caml_alloc((mlsize_t)n, 0);
  for (i = 0; i < n; i++) {
    axw_action *a = &b->queue[(b->q_head + i) % b->q_cap];
    tup = caml_alloc(3, 0);
    str = caml_copy_string(a->text ? a->text : "");
    Store_field(tup, 0, Val_int(a->node_id));
    Store_field(tup, 1, Val_int(a->code));
    Store_field(tup, 2, str);
    Store_field(res, i, tup);
    free(a->text);
    a->text = NULL;
  }
  b->q_head = 0;
  b->q_count = 0;
  LeaveCriticalSection(&b->lock);
  CAMLreturn(res);
}

CAMLprim value lui_axw_get_object(value vhwnd, value vwp, value vlp)
{
  CAMLparam3(vhwnd, vwp, vlp);
  HWND hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  LPARAM lp = (LPARAM)Nativeint_val(vlp);
  LRESULT res = 0;
  int i;
  if ((LONG)lp == UIA_ROOT_OBJECT_ID) {
    bridge_init_once();
    for (i = 0; i < AXW_MAX_BRIDGES; i++) {
      axw_bridge *b = &g_bridges[i];
      if (b->used && b->hwnd == hwnd && b->frame && b->frame->alive) {
        res = UiaReturnRawElementProvider(hwnd,
                                          (WPARAM)Nativeint_val(vwp),
                                          lp, &b->frame->i_simple);
        break;
      }
    }
  }
  CAMLreturn(caml_copy_nativeint((intnat)res));
}

/* ------------------------------------------------------------------ */
/* Probes — UIA client-side wrappers used by the test suite           */

static struct UiaCondition g_true_cond = { ConditionType_True };

static struct UiaCacheRequest g_full_cache = {
  &g_true_cond,
  TreeScope_Element,
  NULL, 0,
  NULL, 0,
  AutomationElementMode_Full,
};

CAMLprim value lui_axw_probe_has_provider(value vid)
{
  CAMLparam1(vid);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  if (!b) CAMLreturn(Val_false);
  CAMLreturn(Val_bool(UiaHasServerSideProvider(b->hwnd) ? 1 : 0));
}

CAMLprim value lui_axw_probe_root(value vid)
{
  CAMLparam1(vid);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  HUIANODE h = NULL;
  if (!b || !b->frame) CAMLreturn(caml_copy_nativeint(0));
  bridge_init_once();
  if (FAILED(UiaNodeFromProvider(&b->frame->i_simple, &h))) h = NULL;
  CAMLreturn(caml_copy_nativeint((intnat)(uintptr_t)h));
}

CAMLprim value lui_axw_probe_find(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  HUIANODE h = NULL;
  if (!b) CAMLreturn(caml_copy_nativeint(0));
  bridge_init_once();
  n = resolve(b, Int_val(vid2));
  if (n && FAILED(UiaNodeFromProvider(&n->i_simple, &h))) h = NULL;
  CAMLreturn(caml_copy_nativeint((intnat)(uintptr_t)h));
}

CAMLprim value lui_axw_probe_free(value vh)
{
  CAMLparam1(vh);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  if (h) UiaNodeRelease(h);
  CAMLreturn(Val_unit);
}

/* navigate a client node one step; on success returns the node and
   transfers ownership to *out_node */
static HRESULT uia_step(HUIANODE h, enum NavigateDirection dir,
                        HUIANODE *out_node)
{
  SAFEARRAY *sa = NULL;
  BSTR tree = NULL;
  VARIANT v;
  LONG idx[2] = {0, 0};
  HRESULT hr;
  *out_node = NULL;
  hr = UiaNavigate(h, dir, &g_true_cond, &g_full_cache, &sa, &tree);
  if (FAILED(hr)) return hr;
  if (tree) SysFreeString(tree);
  if (!sa) return S_FALSE;
  VariantInit(&v);
  hr = SafeArrayGetElement(sa, idx, &v);
  if (SUCCEEDED(hr))
    hr = UiaHUiaNodeFromVariant(&v, out_node);
  VariantClear(&v);
  SafeArrayDestroy(sa);
  return hr;
}

CAMLprim value lui_axw_probe_children(value vh)
{
  CAMLparam1(vh);
  CAMLlocal1(res);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  HUIANODE cur = NULL;
  int ids[4096];
  int count = 0;
  if (!h) CAMLreturn(caml_alloc(0, 0));
  if (FAILED(uia_step(h, NavigateDirection_FirstChild, &cur)))
    CAMLreturn(caml_alloc(0, 0));
  while (cur && count < 4096) {
    SAFEARRAY *rt = NULL;
    HUIANODE next = NULL;
    int id = INT_MIN;
    if (SUCCEEDED(UiaGetRuntimeId(cur, &rt)) && rt) {
      id = node_id_of_runtime_id(rt);
      SafeArrayDestroy(rt);
    }
    ids[count++] = id;
    if (FAILED(uia_step(cur, NavigateDirection_NextSibling, &next)))
      next = NULL;
    UiaNodeRelease(cur);
    cur = next;
  }
  if (cur) UiaNodeRelease(cur);
  res = caml_alloc((mlsize_t)count, 0);
  for (int i = 0; i < count; i++)
    Store_field(res, i, Val_int(ids[i]));
  CAMLreturn(res);
}

CAMLprim value lui_axw_probe_runtime_id(value vh)
{
  CAMLparam1(vh);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  SAFEARRAY *rt = NULL;
  int id = INT_MIN;
  if (h && SUCCEEDED(UiaGetRuntimeId(h, &rt)) && rt) {
    id = node_id_of_runtime_id(rt);
    SafeArrayDestroy(rt);
  }
  CAMLreturn(Val_int(id == INT_MIN ? -2 : id));
}

CAMLprim value lui_axw_probe_prop_int(value vh, value vprop)
{
  CAMLparam2(vh, vprop);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  VARIANT v;
  int out = -1;
  VariantInit(&v);
  if (h && SUCCEEDED(UiaGetPropertyValue(h, (PROPERTYID)Int_val(vprop), &v))) {
    if (V_VT(&v) == VT_I4) out = (int)V_I4(&v);
    else if (V_VT(&v) == VT_BOOL) out = V_BOOL(&v) ? 1 : 0;
    else if (V_VT(&v) == VT_R8) out = (int)V_R8(&v);
  }
  VariantClear(&v);
  CAMLreturn(Val_int(out));
}

CAMLprim value lui_axw_probe_prop_bool(value vh, value vprop)
{
  CAMLparam2(vh, vprop);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  VARIANT v;
  int out = 0;
  VariantInit(&v);
  if (h && SUCCEEDED(UiaGetPropertyValue(h, (PROPERTYID)Int_val(vprop), &v))) {
    if (V_VT(&v) == VT_BOOL) out = V_BOOL(&v) ? 1 : 0;
    else if (V_VT(&v) == VT_I4) out = V_I4(&v) ? 1 : 0;
  }
  VariantClear(&v);
  CAMLreturn(Val_bool(out));
}

CAMLprim value lui_axw_probe_prop_str(value vh, value vprop)
{
  CAMLparam2(vh, vprop);
  CAMLlocal1(res);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  VARIANT v;
  res = caml_copy_string("");
  VariantInit(&v);
  if (h && SUCCEEDED(UiaGetPropertyValue(h, (PROPERTYID)Int_val(vprop), &v))) {
    if (V_VT(&v) == VT_BSTR && V_BSTR(&v)) {
      char *u = utf8_of_bstr(V_BSTR(&v));
      if (u) {
        res = caml_copy_string(u);
        free(u);
      }
    }
  }
  VariantClear(&v);
  CAMLreturn(res);
}

CAMLprim value lui_axw_probe_prop_num(value vh, value vprop)
{
  CAMLparam2(vh, vprop);
  HUIANODE h = (HUIANODE)(uintptr_t)Nativeint_val(vh);
  VARIANT v;
  double out = 0.0 / 0.0;
  VariantInit(&v);
  if (h && SUCCEEDED(UiaGetPropertyValue(h, (PROPERTYID)Int_val(vprop), &v))) {
    if (V_VT(&v) == VT_R8) out = V_R8(&v);
    else if (V_VT(&v) == VT_I4) out = (double)V_I4(&v);
  }
  VariantClear(&v);
  CAMLreturn(caml_copy_double(out));
}

CAMLprim value lui_axw_probe_pattern(value vid, value vid2, value vpat)
{
  CAMLparam3(vid, vid2, vpat);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  IUnknown *unk = NULL;
  int found = 0;
  if (!b) CAMLreturn(Val_false);
  n = resolve(b, Int_val(vid2));
  if (n &&
      SUCCEEDED(n->i_simple.lpVtbl->GetPatternProvider(
          &n->i_simple, (PATTERNID)Int_val(vpat), &unk)) &&
      unk) {
    unk->lpVtbl->Release(unk);
    found = 1;
  }
  CAMLreturn(Val_bool(found));
}

CAMLprim value lui_axw_probe_invoke(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_INVOKE))
    n->i_invoke.lpVtbl->Invoke(&n->i_invoke);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_toggle(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_TOGGLE))
    n->i_toggle.lpVtbl->Toggle(&n->i_toggle);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_select(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_SEL_ITEM))
    n->i_selitem.lpVtbl->Select(&n->i_selitem);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_set_range(value vid, value vid2, value v)
{
  CAMLparam3(vid, vid2, v);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_RANGE))
    n->i_range.lpVtbl->SetValue(&n->i_range, Double_val(v));
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_set_value(value vid, value vid2, value vs)
{
  CAMLparam3(vid, vid2, vs);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  BSTR w;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_VALUE)) {
    w = bstr_of_utf8(String_val(vs));
    n->i_value.lpVtbl->SetValue(&n->i_value, w);
    if (w) SysFreeString(w);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_expand(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_EXPAND))
    n->i_expand.lpVtbl->Expand(&n->i_expand);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_collapse(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_EXPAND))
    n->i_expand.lpVtbl->Collapse(&n->i_expand);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_scroll(value vid, value vid2)
{
  CAMLparam2(vid, vid2);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  axw_node *n;
  if (!b) CAMLreturn(Val_unit);
  n = resolve(b, Int_val(vid2));
  if (n && (n->patterns & PAT_SCROLL_ITEM))
    n->i_scroll.lpVtbl->ScrollIntoView(&n->i_scroll);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_axw_probe_hit(value vid, value vx, value vy)
{
  CAMLparam3(vid, vx, vy);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  POINT pt;
  IRawElementProviderFragment *frag = NULL;
  int id = -1;
  if (!b) CAMLreturn(Val_int(-1));
  /* exercise the real entry point: client coords -> screen ->
     ElementProviderFromPoint */
  pt.x = (LONG)Double_val(vx);
  pt.y = (LONG)Double_val(vy);
  ClientToScreen(b->hwnd, &pt);
  if (SUCCEEDED(b->frame->i_frag_root.lpVtbl->ElementProviderFromPoint(
          &b->frame->i_frag_root, (double)pt.x, (double)pt.y, &frag))
      && frag) {
    axw_node *hit = NODE_OF(frag, i_fragment);
    id = hit->id;
    frag->lpVtbl->Release(frag);
  }
  CAMLreturn(Val_int(id));
}

CAMLprim value lui_axw_probe_focused(value vid)
{
  CAMLparam1(vid);
  axw_bridge *b = bridge_of_id(Int_val(vid));
  IRawElementProviderFragment *frag = NULL;
  int id = -1;
  if (!b) CAMLreturn(Val_int(-1));
  if (SUCCEEDED(b->frame->i_frag_root.lpVtbl->GetFocus(
          &b->frame->i_frag_root, &frag))
      && frag) {
    axw_node *f = NODE_OF(frag, i_fragment);
    id = f->id;
    frag->lpVtbl->Release(frag);
  }
  CAMLreturn(Val_int(id));
}

#else /* !_WIN32 — stubs that fail at runtime */

#define AXW_STUB1(name)                                                 \
  CAMLprim value name(value a)                                          \
  {                                                                     \
    caml_failwith(#name ": windows-only");                              \
    return Val_unit;                                                    \
  }
#define AXW_STUB2(name)                                                 \
  CAMLprim value name(value a, value b)                                 \
  {                                                                     \
    caml_failwith(#name ": windows-only");                              \
    return Val_unit;                                                    \
  }
#define AXW_STUB3(name)                                                 \
  CAMLprim value name(value a, value b, value c)                        \
  {                                                                     \
    caml_failwith(#name ": windows-only");                              \
    return Val_unit;                                                    \
  }
#define AXW_STUB4(name)                                                 \
  CAMLprim value name(value a, value b, value c, value d)               \
  {                                                                     \
    caml_failwith(#name ": windows-only");                              \
    return Val_unit;                                                    \
  }
#define AXW_STUB5(name)                                                 \
  CAMLprim value name(value a, value b, value c, value d, value e)      \
  {                                                                     \
    caml_failwith(#name ": windows-only");                              \
    return Val_unit;                                                    \
  }

AXW_STUB1(lui_axw_attach)
AXW_STUB1(lui_axw_detach)
AXW_STUB3(lui_axw_apply)
AXW_STUB4(lui_axw_link)
AXW_STUB3(lui_axw_set_frame)
AXW_STUB2(lui_axw_remove)
AXW_STUB2(lui_axw_finish)
AXW_STUB5(lui_axw_raise_prop)
AXW_STUB3(lui_axw_raise_event)
AXW_STUB2(lui_axw_raise_struct)
AXW_STUB2(lui_axw_set_focus)
AXW_STUB1(lui_axw_drain)
AXW_STUB3(lui_axw_get_object)
AXW_STUB1(lui_axw_probe_has_provider)
AXW_STUB1(lui_axw_probe_root)
AXW_STUB2(lui_axw_probe_find)
AXW_STUB1(lui_axw_probe_free)
AXW_STUB1(lui_axw_probe_children)
AXW_STUB1(lui_axw_probe_runtime_id)
AXW_STUB2(lui_axw_probe_prop_int)
AXW_STUB2(lui_axw_probe_prop_bool)
AXW_STUB2(lui_axw_probe_prop_str)
AXW_STUB2(lui_axw_probe_prop_num)
AXW_STUB3(lui_axw_probe_pattern)
AXW_STUB2(lui_axw_probe_invoke)
AXW_STUB2(lui_axw_probe_toggle)
AXW_STUB2(lui_axw_probe_select)
AXW_STUB3(lui_axw_probe_set_range)
AXW_STUB3(lui_axw_probe_set_value)
AXW_STUB2(lui_axw_probe_expand)
AXW_STUB2(lui_axw_probe_collapse)
AXW_STUB2(lui_axw_probe_scroll)
AXW_STUB3(lui_axw_probe_hit)
AXW_STUB1(lui_axw_probe_focused)

#endif
