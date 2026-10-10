/* Platform text engine for lui_text_pango: the system's own text stack
   finds fonts, falls back for glyphs a font lacks, shapes paragraphs into
   positioned glyph runs, and rasterizes glyphs into coverage masks or
   color bitmaps.

   The stack on Linux: Fontconfig finds fonts and the generic-family
   fallbacks, Pango itemizes and shapes paragraphs (through HarfBuzz) and
   breaks lines, and cairo rasterizes glyphs into image surfaces. */

#if defined(__linux__)

#include <pango/pangocairo.h>
#include <pango/pangofc-font.h>
#include <fontconfig/fontconfig.h>
#include <cairo.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

/* ---------------------------------------------------------------- fonts */

/* A font handle keeps the resolved PangoFont plus the font description
   to shape with: the description's family may be a list (requested
   fallbacks before the system's own), which the resolved font alone
   does not carry. [id] identifies the resolved font so equal fonts
   wrap-compare equal; [fam] is its best-effort family name; [size] is
   its size in points. */
struct lui_font {
  PangoFont *font;
  PangoFontDescription *desc;
  char *id;
  char *fam;
  double size;
};

#define Lui_font_val(v) (*(struct lui_font **)Data_custom_val(v))

static void lui_font_finalize(value v)
{
  struct lui_font *h = Lui_font_val(v);
  if (h == NULL) return;
  if (h->font != NULL) g_object_unref(h->font);
  if (h->desc != NULL) pango_font_description_free(h->desc);
  g_free(h->id);
  g_free(h->fam);
  free(h);
}

static int lui_font_compare(value a, value b)
{
  struct lui_font *ha = Lui_font_val(a);
  struct lui_font *hb = Lui_font_val(b);
  if (ha == hb) return 0;
  if (ha == NULL || ha->id == NULL) return -1;
  if (hb == NULL || hb->id == NULL) return 1;
  return strcmp(ha->id, hb->id);
}

static int lui_font_compare_ext(value a, value b)
{
  return lui_font_compare(a, b);
}

static intnat lui_font_hash(value v)
{
  struct lui_font *hf = Lui_font_val(v);
  const char *s = hf != NULL && hf->id != NULL ? hf->id : "";
  uint64_t h = 1469598103934665603ULL;
  for (; *s != '\0'; s++) {
    h = (h ^ (unsigned char)*s) * 1099511628211ULL;
  }
  return (intnat)h;
}

static struct custom_operations lui_font_ops = {
  "lui_text_pango.font",
  lui_font_finalize,
  lui_font_compare,
  lui_font_hash,
  custom_serialize_default,
  custom_deserialize_default,
  lui_font_compare_ext,
  custom_fixed_length_default
};

/* Wrap a resolved font. Takes ownership of [font] (a full reference)
   and of [shape_desc] when given; without one the font's own absolute
   description becomes the shaping description. */
static value lui_font_wrap(PangoFont *font, PangoFontDescription *shape_desc)
{
  value v = caml_alloc_custom(&lui_font_ops, sizeof(struct lui_font *),
                              0, 1);
  Lui_font_val(v) = NULL;
  struct lui_font *h = calloc(1, sizeof(*h));
  if (h == NULL) caml_failwith("lui_text_pango: out of memory");
  h->font = font;
  if (shape_desc != NULL) {
    h->desc = shape_desc;
  } else {
    h->desc = pango_font_describe_with_absolute_size(font);
  }
  {
    /* Font identity and family name come from the resolved font, not
       the request description. */
    PangoFontDescription *rd =
      pango_font_describe_with_absolute_size(font);
    h->id = pango_font_description_to_string(rd);
    const char *fam = pango_font_description_get_family(rd);
    h->fam = g_strdup(fam != NULL ? fam : "");
    h->size =
      (double)pango_font_description_get_size(rd) / PANGO_SCALE;
    pango_font_description_free(rd);
  }
  Lui_font_val(v) = h;
  return v;
}

/* The stack's shared font map and context. The font map is our own:
   font lookups and itemization must agree on one cache for run fonts to
   compare equal to the fonts they were shaped from. */
static PangoFontMap *lui_map = NULL;
static PangoContext *lui_ctx = NULL;

static void lui_ensure(void)
{
  if (lui_ctx != NULL) return;
  FcInit();
  lui_map = pango_cairo_font_map_new();
  if (lui_map == NULL)
    caml_failwith("lui_text_pango: cannot create a font map");
  lui_ctx = pango_font_map_create_context(lui_map);
  if (lui_ctx == NULL)
    caml_failwith("lui_text_pango: cannot create a context");
  /* Grayscale antialiasing (what a coverage mask wants), metrics hinted
     to whole pixels, and glyph positions kept fractional so shaping and
     rasterizing can place pens inside a pixel. */
  cairo_font_options_t *o = cairo_font_options_create();
  cairo_font_options_set_antialias(o, CAIRO_ANTIALIAS_GRAY);
  cairo_font_options_set_hint_metrics(o, CAIRO_HINT_METRICS_ON);
  cairo_font_options_set_hint_style(o, CAIRO_HINT_STYLE_MEDIUM);
  pango_cairo_context_set_font_options(lui_ctx, o);
  cairo_font_options_destroy(o);
  pango_context_set_round_glyph_positions(lui_ctx, FALSE);
}

static PangoFontDescription *lui_desc(const char *family, double size,
                                      int weight, int italic)
{
  PangoFontDescription *d = pango_font_description_new();
  pango_font_description_set_family(d, family);
  pango_font_description_set_weight(d, (PangoWeight)weight);
  pango_font_description_set_style(
    d, italic ? PANGO_STYLE_ITALIC : PANGO_STYLE_NORMAL);
  pango_font_description_set_absolute_size(d, size * PANGO_SCALE);
  return d;
}

/* Normalized family-name equality: case and separators do not count. */
static int lui_family_eq(const char *a, const char *b)
{
  for (;;) {
    while (*a == ' ' || *a == '-' || *a == '_') a++;
    while (*b == ' ' || *b == '-' || *b == '_') b++;
    if (*a == '\0' && *b == '\0') return 1;
    if (tolower((unsigned char)*a) != tolower((unsigned char)*b))
      return 0;
    a++;
    b++;
  }
}

static int lui_is_generic(const char *name)
{
  static const char *const generics[] = {
    "sans", "sans-serif", "serif", "monospace", "system-ui",
    "cursive", "fantasy", "emoji", "math", "fangsong",
    "ui-sans-serif", "ui-serif", "ui-monospace", "ui-rounded", NULL
  };
  for (int i = 0; generics[i] != NULL; i++) {
    if (lui_family_eq(name, generics[i])) return 1;
  }
  return 0;
}

/* Whether Fontconfig has a family of this name. Generic names resolve
   through the configuration's aliases; a real family must come back as
   one of the matched pattern's own families, or the request silently
   fell back to the default font. */
static int lui_family_installed(const char *name)
{
  int found = 0;
  FcPattern *pat = FcPatternCreate();
  FcPattern *match = NULL;
  if (pat == NULL) return 0;
  FcPatternAddString(pat, FC_FAMILY, (const FcChar8 *)name);
  FcConfigSubstitute(NULL, pat, FcMatchPattern);
  FcDefaultSubstitute(pat);
  {
    FcResult res = FcResultNoMatch;
    match = FcFontMatch(FcConfigGetCurrent(), pat, &res);
  }
  if (match != NULL) {
    if (lui_is_generic(name)) {
      found = 1;
    } else {
      FcChar8 *fam = NULL;
      for (int i = 0;
           FcPatternGetString(match, FC_FAMILY, i, &fam) == FcResultMatch;
           i++) {
        if (lui_family_eq((const char *)fam, name)) {
          found = 1;
          break;
        }
      }
    }
    FcPatternDestroy(match);
  }
  FcPatternDestroy(pat);
  return found;
}

/* named : family -> size -> weight -> italic -> font option
   The face of [family] best matching weight and italics, or None when
   the family is not installed. */
CAMLprim value lui_pango_named(value vname, value vsize, value vweight,
                               value vitalic)
{
  CAMLparam4(vname, vsize, vweight, vitalic);
  CAMLlocal2(vopt, vfont);
  lui_ensure();
  const char *name = String_val(vname);
  if (!lui_family_installed(name)) CAMLreturn(Val_int(0));
  PangoFontDescription *d =
    lui_desc(name, Double_val(vsize), (int)lround(Double_val(vweight)),
             Bool_val(vitalic));
  PangoFont *font =
    pango_font_map_load_font(lui_map, lui_ctx, d);
  if (font == NULL) {
    pango_font_description_free(d);
    CAMLreturn(Val_int(0));
  }
  vfont = lui_font_wrap(font, d);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vfont);
  CAMLreturn(vopt);
}

/* cascade : font -> string array -> weight -> italic -> font
   [font] with the named families (the installed ones) put before the
   system's own fallbacks for glyphs it lacks: the shaping description's
   family becomes a list, which itemization walks in order. */
CAMLprim value lui_pango_cascade(value vfont, value vnames,
                                 value vweight, value vitalic)
{
  CAMLparam4(vfont, vnames, vweight, vitalic);
  CAMLlocal1(vout);
  mlsize_t n = Wosize_val(vnames);
  struct lui_font *base = Lui_font_val(vfont);
  const char *base_fam =
    pango_font_description_get_family(base->desc);
  GString *joined = g_string_new(base_fam != NULL ? base_fam : "");
  int added = 0;
  for (mlsize_t i = 0; i < n; i++) {
    const char *name = String_val(Field(vnames, i));
    if (lui_family_installed(name)) {
      g_string_append(joined, ",");
      g_string_append(joined, name);
      added = 1;
    }
  }
  /* With no installed cascade families the font stays itself. */
  PangoFontDescription *d = pango_font_description_copy(base->desc);
  if (added) pango_font_description_set_family(d, joined->str);
  g_string_free(joined, TRUE);
  PangoFont *font = pango_font_map_load_font(lui_map, lui_ctx, d);
  if (font == NULL) {
    g_object_ref(base->font);
    font = base->font;
  }
  vout = lui_font_wrap(font, d);
  CAMLreturn(vout);
}

/* system : size -> weight -> italic -> monospace -> font */
CAMLprim value lui_pango_system(value vsize, value vweight,
                                value vitalic, value vmono)
{
  CAMLparam4(vsize, vweight, vitalic, vmono);
  CAMLlocal1(vfont);
  lui_ensure();
  PangoFontDescription *d =
    lui_desc(Bool_val(vmono) ? "monospace" : "sans-serif",
             Double_val(vsize), (int)lround(Double_val(vweight)),
             Bool_val(vitalic));
  PangoFont *font = pango_font_map_load_font(lui_map, lui_ctx, d);
  if (font == NULL) {
    pango_font_description_free(d);
    caml_failwith("lui_text_pango: no system font");
  }
  vfont = lui_font_wrap(font, d);
  CAMLreturn(vfont);
}

/* fallback : font -> string -> font option
   The font the system picks to cover the characters of the string the
   font lacks; the first itemized run whose font differs, else the
   string's own run font. None when nothing can render it. */
CAMLprim value lui_pango_fallback(value vfont, value vstr)
{
  CAMLparam2(vfont, vstr);
  CAMLlocal3(vopt, vres, vtmp);
  lui_ensure();
  struct lui_font *base = Lui_font_val(vfont);
  const char *text = (const char *)Bytes_val(vstr);
  int len = (int)caml_string_length(vstr);
  if (len == 0) CAMLreturn(Val_int(0));

  PangoAttrList *attrs = pango_attr_list_new();
  pango_attr_list_insert(attrs, pango_attr_font_desc_new(base->desc));
  GList *items =
    pango_itemize(lui_ctx, text, 0, len, attrs, NULL);
  pango_attr_list_unref(attrs);
  if (items == NULL) CAMLreturn(Val_int(0));

  PangoFont *pick = NULL;
  PangoFont *first = NULL;
  for (GList *l = items; l != NULL; l = l->next) {
    PangoItem *item = (PangoItem *)l->data;
    PangoFont *f = item->analysis.font;
    if (f == NULL) continue;
    if (first == NULL) first = f;
    if (pick == NULL && f != base->font) {
      PangoFontDescription *fd =
        pango_font_describe_with_absolute_size(f);
      char *fid = fd != NULL ? pango_font_description_to_string(fd) : NULL;
      if (fid == NULL || strcmp(fid, base->id) != 0) pick = f;
      g_free(fid);
      if (fd != NULL) pango_font_description_free(fd);
    }
  }
  if (pick == NULL) pick = first;
  if (pick == NULL) {
    g_list_free_full(items, (GDestroyNotify)pango_item_free);
    CAMLreturn(Val_int(0));
  }
  g_object_ref(pick);
  vres = lui_font_wrap(pick, NULL);
  g_list_free_full(items, (GDestroyNotify)pango_item_free);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vres);
  CAMLreturn(vopt);
}

/* metrics : font -> (size, ascent, descent, leading)
   A float tuple is a tag-0 block of boxed doubles. */
CAMLprim value lui_pango_metrics(value vfont)
{
  CAMLparam1(vfont);
  CAMLlocal1(vm);
  struct lui_font *h = Lui_font_val(vfont);
  double ascent = 0., descent = 0., leading = 0.;
  PangoFontMetrics *m = pango_font_get_metrics(h->font, NULL);
  if (m != NULL) {
    ascent = (double)pango_font_metrics_get_ascent(m) / PANGO_SCALE;
    descent = (double)pango_font_metrics_get_descent(m) / PANGO_SCALE;
    double height =
      (double)pango_font_metrics_get_height(m) / PANGO_SCALE;
    leading = height - ascent - descent;
    if (leading < 0.) leading = 0.;
    pango_font_metrics_unref(m);
  }
  vm = caml_alloc(4, 0);
  Store_field(vm, 0, caml_copy_double(h->size));
  Store_field(vm, 1, caml_copy_double(ascent));
  Store_field(vm, 2, caml_copy_double(descent));
  Store_field(vm, 3, caml_copy_double(leading));
  CAMLreturn(vm);
}

CAMLprim value lui_pango_is_color(value vfont)
{
  CAMLparam1(vfont);
  struct lui_font *h = Lui_font_val(vfont);
  int color = 0;
  if (PANGO_IS_FC_FONT(h->font)) {
    FcPattern *pat =
      pango_fc_font_get_pattern(PANGO_FC_FONT(h->font));
    FcBool b = FcFalse;
    if (pat != NULL &&
        FcPatternGetBool(pat, FC_COLOR, 0, &b) == FcResultMatch) {
      color = (b == FcTrue);
    }
  }
  CAMLreturn(Val_bool(color));
}

/* family : font -> string (best-effort installed family name) */
CAMLprim value lui_pango_family(value vfont)
{
  CAMLparam1(vfont);
  CAMLlocal1(vs);
  struct lui_font *h = Lui_font_val(vfont);
  /* The resolved family may be a comma-separated list; the first entry
     is the name that answers "which family is this". */
  char buf[512];
  const char *comma = strchr(h->fam, ',');
  size_t n = comma != NULL ? (size_t)(comma - h->fam) : strlen(h->fam);
  if (n >= sizeof(buf)) n = sizeof(buf) - 1;
  memcpy(buf, h->fam, n);
  buf[n] = '\0';
  vs = caml_copy_string(buf);
  CAMLreturn(vs);
}

/* --------------------------------------------------------------- shape */

/* One shaped run: font, direction and positioned glyphs. The returned
   value is a record/block:
   (font, start_byte, stop_byte, rtl, glyph array)
   where a glyph is (id, x, y_from_baseline, advance, cluster_byte). */
static value lui_shape_run(PangoGlyphItem *gi, int base, gint *pen)
{
  CAMLparam0();
  CAMLlocal5(vrun, vglyphs, vg, vfont, tmp);
  PangoItem *item = gi->item;
  PangoGlyphString *gs = gi->glyphs;
  int ng = gs->num_glyphs;

  g_object_ref(item->analysis.font);
  vfont = lui_font_wrap(item->analysis.font, NULL);

  vglyphs = caml_alloc((mlsize_t)ng, 0);
  for (int j = 0; j < ng; j++) {
    PangoGlyphInfo *g = &gs->glyphs[j];
    vg = caml_alloc(5, 0);
    Store_field(vg, 0, Val_int(g->glyph));
    /* The pen runs over the line's runs in visual order; offsets are
       the shaping offsets inside it. */
    Store_field(vg, 1,
                caml_copy_double((*pen + g->geometry.x_offset)
                                 / (double)PANGO_SCALE));
    Store_field(vg, 2,
                caml_copy_double(g->geometry.y_offset
                                 / (double)PANGO_SCALE));
    Store_field(vg, 3,
                caml_copy_double(g->geometry.width
                                 / (double)PANGO_SCALE));
    Store_field(vg, 4,
                Val_int(item->offset + gs->log_clusters[j] + base));
    Store_field(vglyphs, j, vg);
    *pen += g->geometry.width;
  }

  vrun = caml_alloc(5, 0);
  Store_field(vrun, 0, vfont);
  Store_field(vrun, 1, Val_int(item->offset + base));
  Store_field(vrun, 2, Val_int(item->offset + item->length + base));
  Store_field(vrun, 3, Val_bool((item->analysis.level & 1) != 0));
  Store_field(vrun, 4, vglyphs);
  tmp = vrun;
  CAMLreturn(tmp);
}

/* Line ascent/descent: the most each run's font reaches above and below
   the baseline, like the line's typographic bounds. */
static void lui_line_height(PangoLayoutLine *ll, struct lui_font *base,
                            double *asc, double *desc)
{
  double a = 0., d = 0.;
  int any = 0;
  for (GSList *r = ll->runs; r != NULL; r = r->next) {
    PangoGlyphItem *gi = (PangoGlyphItem *)r->data;
    PangoFont *f = gi->item->analysis.font;
    PangoFontMetrics *m = pango_font_get_metrics(f, NULL);
    if (m == NULL) continue;
    any = 1;
    double fa = (double)pango_font_metrics_get_ascent(m) / PANGO_SCALE;
    double fd = (double)pango_font_metrics_get_descent(m) / PANGO_SCALE;
    if (fa > a) a = fa;
    if (fd > d) d = fd;
    pango_font_metrics_unref(m);
  }
  if (!any) {
    PangoFontMetrics *m = pango_font_get_metrics(base->font, NULL);
    if (m != NULL) {
      a = (double)pango_font_metrics_get_ascent(m) / PANGO_SCALE;
      d = (double)pango_font_metrics_get_descent(m) / PANGO_SCALE;
      pango_font_metrics_unref(m);
    }
  }
  *asc = a;
  *desc = d;
}

/* shape : font -> utf8 -> width -> rtl -> base -> line array
   A line is (start_byte, stop_byte, width, ascent, descent, leading,
   run array). Offsets are bytes into the OCaml string: Pango indexes
   UTF-8 by bytes too, so no code-unit mapping is needed. */
CAMLprim value lui_pango_shape(value vfont, value vstr, value vwidth,
                               value vrtl, value vbase)
{
  CAMLparam5(vfont, vstr, vwidth, vrtl, vbase);
  CAMLlocal5(vlines, vline, vruns, vcons, vempty);
  struct lui_font *h = Lui_font_val(vfont);
  int base = Int_val(vbase);
  double width = Double_val(vwidth);
  int rtl = Bool_val(vrtl);
  const char *text = (const char *)Bytes_val(vstr);
  int len = (int)caml_string_length(vstr);
  int nlines = 0;

  vlines = Val_int(0); /* boxed list of finished lines, last first */

  if (len == 0) {
    vempty = caml_alloc(0, 0);
    CAMLreturn(vempty);
  }
  lui_ensure();

  pango_context_set_base_dir(
    lui_ctx, rtl ? PANGO_DIRECTION_RTL : PANGO_DIRECTION_LTR);
  PangoLayout *layout = pango_layout_new(lui_ctx);
  if (layout == NULL) caml_failwith("lui_text_pango: no layout");
  pango_layout_set_auto_dir(layout, FALSE);
  pango_layout_set_font_description(layout, h->desc);
  pango_layout_set_text(layout, text, len);
  if (width > 0.) {
    /* Round up to whole Pango units: truncating can make the box a
       thousandth of a point narrower than the text measured within
       it. */
    double w = ceil(width * PANGO_SCALE);
    if (w > (double)G_MAXINT) w = (double)G_MAXINT;
    pango_layout_set_width(layout, (int)w);
    pango_layout_set_wrap(layout, PANGO_WRAP_WORD_CHAR);
  }

  int n = pango_layout_get_line_count(layout);
  for (int i = 0; i < n; i++) {
    PangoLayoutLine *ll = pango_layout_get_line_readonly(layout, i);
    if (ll == NULL) continue;

    PangoRectangle logical;
    pango_layout_line_get_extents(ll, NULL, &logical);
    gint height = 0;
    pango_layout_line_get_height(ll, &height);
    double asc, desc;
    lui_line_height(ll, h, &asc, &desc);
    double leading =
      (double)height / PANGO_SCALE - asc - desc;
    if (leading < 0.) leading = 0.;

    gint pen = 0;
    int nr = 0;
    for (GSList *r = ll->runs; r != NULL; r = r->next) nr++;
    vruns = caml_alloc((mlsize_t)nr, 0);
    int ri = 0;
    for (GSList *r = ll->runs; r != NULL; r = r->next) {
      Store_field(vruns, ri,
                  lui_shape_run((PangoGlyphItem *)r->data, base, &pen));
      ri++;
    }

    vline = caml_alloc(7, 0);
    Store_field(vline, 0, Val_int(ll->start_index + base));
    Store_field(vline, 1,
                Val_int(ll->start_index + ll->length + base));
    Store_field(vline, 2,
                caml_copy_double((double)logical.width / PANGO_SCALE));
    Store_field(vline, 3, caml_copy_double(asc));
    Store_field(vline, 4, caml_copy_double(desc));
    Store_field(vline, 5, caml_copy_double(leading));
    Store_field(vline, 6, vruns);
    vcons = caml_alloc(2, 0);
    Store_field(vcons, 0, vline);
    Store_field(vcons, 1, vlines);
    vlines = vcons;
    nlines++;
  }
  g_object_unref(layout);

  /* The list is reversed (last line first); unpack it in order. */
  vempty = caml_alloc((mlsize_t)nlines, 0);
  {
    value cur = vlines;
    for (int i = nlines - 1; i >= 0; i--) {
      Store_field(vempty, i, Field(cur, 0));
      cur = Field(cur, 1);
    }
  }
  CAMLreturn(vempty);
}

/* ---------------------------------------------------------- rasterize */

/* rasterize : font -> glyph id -> scale -> dx -> shade -> bitmap option
   A bitmap is (left, top, w, h, color, bytes): the pixel box relative to
   the glyph's origin, and coverage (1 byte per pixel) or premultiplied
   BGRA (4 bytes per pixel) rows, top first. */
CAMLprim value lui_pango_rasterize(value vfont, value vid, value vscale,
                                   value vdx, value vshade)
{
  CAMLparam5(vfont, vid, vscale, vdx, vshade);
  CAMLlocal3(vres, vbytes, vtup);
  struct lui_font *h = Lui_font_val(vfont);
  uint32_t id = (uint32_t)Int_val(vid);
  double s = Double_val(vscale);
  double dx = Double_val(vdx);
  /* [shade] would thicken masks by fill luminance on stacks that do
     that; this one draws glyphs as they are. */
  (void)vshade;

  /* The invisible glyph Pango emits (e.g. the space ending a wrapped
     line) and the missing-glyph box are not the font's own glyphs. */
  if (id == PANGO_GLYPH_EMPTY || (id & PANGO_GLYPH_UNKNOWN_FLAG) != 0) {
    CAMLreturn(Val_int(0));
  }
  if (!PANGO_IS_CAIRO_FONT(h->font)) CAMLreturn(Val_int(0));

  cairo_scaled_font_t *src =
    pango_cairo_font_get_scaled_font(PANGO_CAIRO_FONT(h->font));
  if (src == NULL) CAMLreturn(Val_int(0));

  /* Draw at [scale] device pixels per point: the font's own matrix
     times the scale, in a user space of device pixels. */
  cairo_matrix_t m;
  cairo_scaled_font_get_font_matrix(src, &m);
  m.xx *= s;
  m.yx *= s;
  m.xy *= s;
  m.yy *= s;
  cairo_matrix_t identity;
  cairo_matrix_init_identity(&identity);
  cairo_font_options_t *opts = cairo_font_options_create();
  cairo_scaled_font_get_font_options(src, opts);
  /* Masks and bitmaps want grayscale coverage, not LCD filtering. */
  cairo_font_options_set_antialias(opts, CAIRO_ANTIALIAS_GRAY);
  cairo_scaled_font_t *sf =
    cairo_scaled_font_create(cairo_scaled_font_get_font_face(src),
                             &m, &identity, opts);
  cairo_font_options_destroy(opts);
  if (sf == NULL || cairo_scaled_font_status(sf) != CAIRO_STATUS_SUCCESS) {
    if (sf != NULL) cairo_scaled_font_destroy(sf);
    CAMLreturn(Val_int(0));
  }

  cairo_glyph_t g = { .index = id, .x = 0, .y = 0 };
  cairo_text_extents_t ext;
  cairo_scaled_font_glyph_extents(sf, &g, 1, &ext);
  if (ext.width <= 0 || ext.height <= 0) {
    cairo_scaled_font_destroy(sf);
    CAMLreturn(Val_int(0));
  }

  int pad = 1;
  int left = (int)floor(ext.x_bearing + dx) - pad;
  int top = (int)floor(ext.y_bearing) - pad;
  int right = (int)ceil(ext.x_bearing + ext.width + dx) + pad;
  int bottom = (int)ceil(ext.y_bearing + ext.height) + pad;
  int w = right - left;
  int hgt = bottom - top;
  if (w <= 0 || hgt <= 0 || w > 2048 || hgt > 2048) {
    cairo_scaled_font_destroy(sf);
    CAMLreturn(Val_int(0));
  }

  cairo_surface_t *surface =
    cairo_image_surface_create(CAIRO_FORMAT_ARGB32, w, hgt);
  cairo_t *cr = cairo_create(surface);
  cairo_set_scaled_font(cr, sf);
  cairo_set_source_rgba(cr, 1., 1., 1., 1.);
  g.x = dx - (double)left;
  g.y = -(double)top;
  cairo_show_glyphs(cr, &g, 1);
  cairo_destroy(cr);
  cairo_surface_flush(surface);
  cairo_scaled_font_destroy(sf);

  unsigned char *data = cairo_image_surface_get_data(surface);
  int stride = cairo_image_surface_get_stride(surface);
  if (data == NULL) {
    cairo_surface_destroy(surface);
    CAMLreturn(Val_int(0));
  }

  /* White on transparent: a plain font's glyph blends to equal channel
     values (the alpha is the coverage); anything else is colored. */
  int color = 0;
  for (int y = 0; y < hgt && !color; y++) {
    unsigned char *row = data + y * stride;
    for (int x = 0; x < w; x++) {
      unsigned char a = row[4 * x + 3];
      if (row[4 * x] != a || row[4 * x + 1] != a ||
          row[4 * x + 2] != a) {
        color = 1;
        break;
      }
    }
  }

  vbytes = caml_alloc_string((mlsize_t)(w * hgt * (color ? 4 : 1)));
  if (color) {
    /* ARGB32 little-endian is already premultiplied BGRA in memory. */
    unsigned char *dst = Bytes_val(vbytes);
    for (int y = 0; y < hgt; y++) {
      memcpy(dst + (size_t)y * 4 * w, data + y * stride,
             (size_t)(4 * w));
    }
  } else {
    unsigned char *dst = Bytes_val(vbytes);
    for (int y = 0; y < hgt; y++) {
      unsigned char *row = data + y * stride;
      for (int x = 0; x < w; x++) {
        dst[y * w + x] = row[4 * x + 3];
      }
    }
  }
  cairo_surface_destroy(surface);

  vtup = caml_alloc(6, 0);
  Store_field(vtup, 0, Val_int(left));
  Store_field(vtup, 1, Val_int(top));
  Store_field(vtup, 2, Val_int(w));
  Store_field(vtup, 3, Val_int(hgt));
  Store_field(vtup, 4, Val_bool(color));
  Store_field(vtup, 5, vbytes);
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, vtup);
  CAMLreturn(vres);
}

#else /* !__linux__ */

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void) {
  caml_failwith("lui_text_pango: this backend requires Linux");
  return Val_unit;
}

CAMLprim value lui_pango_named(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_pango_system(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_pango_cascade(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_pango_fallback(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_pango_metrics(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_pango_is_color(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_pango_family(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_pango_shape(value a, value b, value c, value d, value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }
CAMLprim value lui_pango_rasterize(value a, value b, value c, value d,
                                   value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }

#endif /* __linux__ */
