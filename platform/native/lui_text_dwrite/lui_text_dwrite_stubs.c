/* Platform text engine for lui_text_dwrite: the system's own text stack
   finds fonts, falls back for glyphs a font lacks, shapes paragraphs into
   positioned glyph runs, and rasterizes glyphs into coverage masks or
   color bitmaps.

   The stack on Windows: DirectWrite finds fonts in the system
   collection, IDWriteTextLayout itemizes, shapes and breaks paragraphs
   (handing its glyph runs to a renderer), and IDWriteGlyphRunAnalysis
   rasterizes glyphs, layer by layer for color fonts. */

#if defined(_WIN32)

#define COBJMACROS
#define INITGUID
#include <windows.h>
#include <dwrite_3.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <string.h>
#include <math.h>
#include <stdio.h>

/* ---------------------------------------------------------------- fonts */

/* A font handle keeps the resolved face (for metrics and rasterizing)
   plus a text format to shape with (which carries the font fallback
   when the family list continues past the font's own family). [id]
   identifies the resolved font face and size so equal fonts
   wrap-compare equal; [fam]/[fam8] is its family name in UTF-16 for
   API calls and UTF-8 for the OCaml side; [weight]/[style]/[stretch]
   are the resolved font's own values. */
struct lui_font {
  IDWriteFontFace *face;
  IDWriteTextFormat *format;
  IDWriteFontFallback *fallback;
  WCHAR *family;
  char *id;
  char *fam8;
  double size;
  int weight, style, stretch;
  int color;
};

#define Lui_font_val(v) (*(struct lui_font **)Data_custom_val(v))

static void lui_font_finalize(value v)
{
  struct lui_font *h = Lui_font_val(v);
  if (h == NULL) return;
  if (h->face != NULL) IDWriteFontFace_Release(h->face);
  if (h->format != NULL) IDWriteTextFormat_Release(h->format);
  if (h->fallback != NULL) IDWriteFontFallback_Release(h->fallback);
  free(h->family);
  free(h->id);
  free(h->fam8);
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
  "lui_text_dwrite.font",
  lui_font_finalize,
  lui_font_compare,
  lui_font_hash,
  custom_serialize_default,
  custom_deserialize_default,
  lui_font_compare_ext,
  custom_fixed_length_default
};

/* ------------------------------------------------------------- globals */

static IDWriteFactory *lui_factory = NULL;
static IDWriteFactory2 *lui_factory2 = NULL;
static IDWriteFactory3 *lui_factory3 = NULL;
static IDWriteFontCollection *lui_coll = NULL;
static IDWriteFontFallback *lui_sysfallback = NULL;
static IDWriteRenderingParams *lui_params = NULL;
static WCHAR lui_locale[LOCALE_NAME_MAX_LENGTH];
static int lui_ready = 0;

static void lui_ensure(void)
{
  if (lui_ready) return;
  HRESULT hr =
    DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
                        &IID_IDWriteFactory,
                        (IUnknown **)&lui_factory);
  if (FAILED(hr) || lui_factory == NULL)
    caml_failwith("lui_text_dwrite: cannot create a factory");
  IDWriteFactory_QueryInterface(lui_factory, &IID_IDWriteFactory2,
                                (void **)&lui_factory2);
  IDWriteFactory_QueryInterface(lui_factory, &IID_IDWriteFactory3,
                                (void **)&lui_factory3);
  hr = IDWriteFactory_GetSystemFontCollection(lui_factory, &lui_coll,
                                              FALSE);
  if (FAILED(hr) || lui_coll == NULL)
    caml_failwith("lui_text_dwrite: no system font collection");
  if (lui_factory2 != NULL) {
    IDWriteFactory2_GetSystemFontFallback(lui_factory2,
                                          &lui_sysfallback);
  }
  /* Rendering params drive the recommended rendering mode; optional. */
  IDWriteFactory_CreateRenderingParams(lui_factory, &lui_params);
  int n = GetUserDefaultLocaleName(lui_locale, LOCALE_NAME_MAX_LENGTH);
  if (n <= 0) wcscpy(lui_locale, L"en-US");
  lui_ready = 1;
}

/* ------------------------------------------------------------- strings */

/* UTF-16 for the stack; a best-effort string converts without a map. */
static WCHAR *lui_to_utf16(const char *s)
{
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  if (n <= 0) return NULL;
  WCHAR *w = malloc((size_t)n * sizeof(WCHAR));
  if (w == NULL) return NULL;
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}

static char *lui_to_utf8(const WCHAR *w)
{
  int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
  if (n <= 0) return NULL;
  char *s = malloc((size_t)n);
  if (s == NULL) return NULL;
  WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL);
  return s;
}

/* The English name of localized strings, or their first. */
static WCHAR *lui_name(IDWriteLocalizedStrings *strs)
{
  UINT32 index = 0;
  BOOL exists = FALSE;
  UINT32 len = 0;
  IDWriteLocalizedStrings_FindLocaleName(strs, L"en-us", &index,
                                       &exists);
  if (!exists) index = 0;
  if (FAILED(IDWriteLocalizedStrings_GetStringLength(strs, index,
                                                     &len)))
    return NULL;
  WCHAR *w = malloc(((size_t)len + 1) * sizeof(WCHAR));
  if (w == NULL) return NULL;
  w[len] = 0;
  if (FAILED(IDWriteLocalizedStrings_GetString(strs, index, w,
                                              len + 1))) {
    free(w);
    return NULL;
  }
  return w;
}

/* UTF-8 text as UTF-16 code units, and the byte offset of each unit's
   character (index[n] = byte length). Invalid bytes decode as U+FFFD. */
static WCHAR *lui_text_utf16(const char *s, int len, int **index,
                             int *nunits)
{
  int cap = len + 2;
  WCHAR *out = malloc((size_t)cap * sizeof(WCHAR));
  int *idx = malloc((size_t)(cap + 1) * sizeof(int));
  int u = 0, i = 0;
  while (i < len) {
    unsigned int cp;
    unsigned char c = (unsigned char)s[i];
    int adv;
    if (c < 0x80) {
      cp = c; adv = 1;
    } else if ((c & 0xE0) == 0xC0 && i + 1 < len &&
               ((unsigned char)s[i + 1] & 0xC0) == 0x80) {
      cp = ((unsigned)(c & 0x1F) << 6)
        | ((unsigned char)s[i + 1] & 0x3F);
      adv = 2;
      if (cp < 0x80) { cp = 0xFFFD; }
    } else if ((c & 0xF0) == 0xE0 && i + 2 < len &&
               ((unsigned char)s[i + 1] & 0xC0) == 0x80 &&
               ((unsigned char)s[i + 2] & 0xC0) == 0x80) {
      cp = ((unsigned)(c & 0x0F) << 12)
        | (((unsigned char)s[i + 1] & 0x3F) << 6)
        | ((unsigned char)s[i + 2] & 0x3F);
      adv = 3;
      if (cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF)) cp = 0xFFFD;
    } else if ((c & 0xF8) == 0xF0 && i + 3 < len &&
               ((unsigned char)s[i + 1] & 0xC0) == 0x80 &&
               ((unsigned char)s[i + 2] & 0xC0) == 0x80 &&
               ((unsigned char)s[i + 3] & 0xC0) == 0x80) {
      cp = ((unsigned)(c & 0x07) << 18)
        | (((unsigned char)s[i + 1] & 0x3F) << 12)
        | (((unsigned char)s[i + 2] & 0x3F) << 6)
        | ((unsigned char)s[i + 3] & 0x3F);
      adv = 4;
      if (cp < 0x10000 || cp > 0x10FFFF) cp = 0xFFFD;
    } else {
      cp = 0xFFFD;
      adv = 1;
    }
    if (cp < 0x10000) {
      idx[u] = i;
      out[u++] = (WCHAR)cp;
    } else {
      cp -= 0x10000;
      idx[u] = i;
      out[u++] = (WCHAR)(0xD800 + (cp >> 10));
      idx[u] = i;
      out[u++] = (WCHAR)(0xDC00 + (cp & 0x3FF));
    }
    i += adv;
  }
  idx[u] = len;
  *index = idx;
  *nunits = u;
  return out;
}

/* -------------------------------------------------------------- lookup */

/* Whether the system collection has a family. */
static int lui_has_family(const char *name)
{
  WCHAR *w = lui_to_utf16(name);
  if (w == NULL) return 0;
  UINT32 index = 0;
  BOOL exists = FALSE;
  HRESULT hr = IDWriteFontCollection_FindFamilyName(
    lui_coll, w, &index, &exists);
  free(w);
  return !FAILED(hr) && exists;
}

/* The face of the family's font best matching weight and style, and
   the matched font's own weight/style/stretch/family for identity. */
static IDWriteFontFace *lui_match(const char *family, int weight,
                                  int italic, WCHAR **fam_out,
                                  int *w_out, int *st_out, int *sty_out)
{
  WCHAR *w = lui_to_utf16(family);
  if (w == NULL) return NULL;
  UINT32 index = 0;
  BOOL exists = FALSE;
  HRESULT hr = IDWriteFontCollection_FindFamilyName(
    lui_coll, w, &index, &exists);
  free(w);
  if (FAILED(hr) || !exists) return NULL;

  IDWriteFontFamily *fam = NULL;
  IDWriteFont *font = NULL;
  IDWriteFontFace *face = NULL;
  if (FAILED(IDWriteFontCollection_GetFontFamily(lui_coll, index,
                                                 &fam)))
    return NULL;
  if (FAILED(IDWriteFontFamily_GetFirstMatchingFont(
        fam, (DWRITE_FONT_WEIGHT)weight, DWRITE_FONT_STRETCH_NORMAL,
        italic ? DWRITE_FONT_STYLE_ITALIC : DWRITE_FONT_STYLE_NORMAL,
        &font)))
    goto done;
  if (FAILED(IDWriteFont_CreateFontFace(font, &face))) goto done;

  {
    IDWriteFontFamily *ff = NULL;
    IDWriteLocalizedStrings *names = NULL;
    WCHAR *fn = NULL;
    *w_out = (int)IDWriteFont_GetWeight(font);
    *st_out = (int)IDWriteFont_GetStretch(font);
    *sty_out = (int)IDWriteFont_GetStyle(font);
    if (SUCCEEDED(IDWriteFont_GetFontFamily(font, &ff)) &&
        SUCCEEDED(IDWriteFontFamily_GetFamilyNames(ff, &names))) {
      fn = lui_name(names);
      IDWriteLocalizedStrings_Release(names);
      IDWriteFontFamily_Release(ff);
    }
    *fam_out = fn;
  }
done:
  if (font != NULL) IDWriteFont_Release(font);
  if (fam != NULL) IDWriteFontFamily_Release(fam);
  if (face == NULL) {
    free(*fam_out);
    *fam_out = NULL;
  }
  return face;
}

/* --------------------------------------------------------------- wrap */

static int lui_face_color(IDWriteFontFace *face)
{
  int color = 0;
  IDWriteFontFace2 *f2 = NULL;
  if (SUCCEEDED(IDWriteFontFace_QueryInterface(
        face, &IID_IDWriteFontFace2, (void **)&f2)) && f2 != NULL) {
    color = IDWriteFontFace2_IsColorFont(f2) ? 1 : 0;
    IDWriteFontFace2_Release(f2);
  }
  return color;
}

/* A shaping format for a family at size: carries no fallback unless the
   caller sets one (the layout then uses the system's own). */
static IDWriteTextFormat *lui_format(const WCHAR *family, int weight,
                                     int stretch, int style, double size)
{
  IDWriteTextFormat *format = NULL;
  HRESULT hr = IDWriteFactory_CreateTextFormat(
    lui_factory, family, lui_coll, (DWRITE_FONT_WEIGHT)weight,
    (DWRITE_FONT_STYLE)style, (DWRITE_FONT_STRETCH)stretch,
    (FLOAT)size, lui_locale, &format);
  if (FAILED(hr)) return NULL;
  return format;
}

/* Wrap a resolved face. Takes ownership of [face] (a full reference),
   and of [format]/[fb] when given; without a format one is made from
   the face's own font properties. */
static value lui_wrap(IDWriteFontFace *face, FLOAT em_size,
                      IDWriteTextFormat *format,
                      IDWriteFontFallback *fb)
{
  CAMLparam0();
  CAMLlocal1(v);
  value out;

  if (face == NULL) {
    if (format != NULL) IDWriteTextFormat_Release(format);
    if (fb != NULL) IDWriteFontFallback_Release(fb);
    caml_failwith("lui_text_dwrite: no font face");
  }

  /* Identity and family name come from the resolved font behind the
     face, not the request. */
  WCHAR *fam = NULL;
  int weight = 400, stretch = DWRITE_FONT_STRETCH_NORMAL, style = 0;
  {
    IDWriteFont *font = NULL;
    if (SUCCEEDED(IDWriteFontCollection_GetFontFromFontFace(
          lui_coll, face, &font)) && font != NULL) {
      IDWriteFontFamily *ff = NULL;
      IDWriteLocalizedStrings *names = NULL;
      weight = (int)IDWriteFont_GetWeight(font);
      stretch = (int)IDWriteFont_GetStretch(font);
      style = (int)IDWriteFont_GetStyle(font);
      if (SUCCEEDED(IDWriteFont_GetFontFamily(font, &ff)) &&
          SUCCEEDED(IDWriteFontFamily_GetFamilyNames(ff, &names))) {
        fam = lui_name(names);
        IDWriteLocalizedStrings_Release(names);
        IDWriteFontFamily_Release(ff);
      }
      IDWriteFont_Release(font);
    }
  }
  char *fam8 = fam != NULL ? lui_to_utf8(fam) : NULL;
  if (fam8 == NULL) fam8 = strdup("Segoe UI");
  if (fam == NULL) fam = lui_to_utf16(fam8);

  char id[768];
  snprintf(id, sizeof(id), "%s|%d|%d|%d|%.6g",
           fam8 != NULL ? fam8 : "", weight, stretch, style,
           (double)em_size);

  if (format == NULL) {
    format = lui_format(fam, weight, stretch, style, (double)em_size);
  }

  v = caml_alloc_custom(&lui_font_ops, sizeof(struct lui_font *), 0, 1);
  Lui_font_val(v) = NULL;
  struct lui_font *h = calloc(1, sizeof(*h));
  if (h == NULL) caml_failwith("lui_text_dwrite: out of memory");
  h->face = face;
  h->format = format;
  h->fallback = fb;
  h->family = fam;
  h->id = strdup(id);
  h->fam8 = fam8;
  h->size = (double)em_size;
  h->weight = weight;
  h->style = style;
  h->stretch = stretch;
  h->color = lui_face_color(face);
  Lui_font_val(v) = h;
  out = v;
  CAMLreturn(out);
}

/* named : family -> size -> weight -> italic -> font option
   The face of [family] best matching weight and italics, or None when
   the family is not installed. */
CAMLprim value lui_dwrite_named(value vname, value vsize, value vweight,
                                value vitalic)
{
  CAMLparam4(vname, vsize, vweight, vitalic);
  CAMLlocal2(vopt, vfont);
  lui_ensure();
  WCHAR *fam = NULL;
  int w, st, sty;
  IDWriteFontFace *face =
    lui_match(String_val(vname), (int)lround(Double_val(vweight)),
              Bool_val(vitalic), &fam, &w, &st, &sty);
  if (face == NULL) CAMLreturn(Val_int(0));
  IDWriteTextFormat *format =
    lui_format(fam, w, st, sty, Double_val(vsize));
  free(fam);
  vfont = lui_wrap(face, (FLOAT)Double_val(vsize), format, NULL);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vfont);
  CAMLreturn(vopt);
}

/* The concrete families the generic families stand for, best first. */
static const char *const lui_system_ui[] = {
  "Segoe UI", "Tahoma", "Arial", NULL
};
static const char *const lui_mono[] = {
  "Cascadia Mono", "Consolas", "Courier New", NULL
};

/* system : size -> weight -> italic -> monospace -> font */
CAMLprim value lui_dwrite_system(value vsize, value vweight,
                                 value vitalic, value vmono)
{
  CAMLparam4(vsize, vweight, vitalic, vmono);
  CAMLlocal1(vfont);
  lui_ensure();
  const char *const *cand =
    Bool_val(vmono) ? lui_mono : lui_system_ui;
  int weight = (int)lround(Double_val(vweight));
  int italic = Bool_val(vitalic);
  IDWriteFontFace *face = NULL;
  WCHAR *fam = NULL;
  int w = 400, st = DWRITE_FONT_STRETCH_NORMAL, sty = 0;
  for (int i = 0; cand[i] != NULL && face == NULL; i++) {
    face = lui_match(cand[i], weight, italic, &fam, &w, &st, &sty);
  }
  /* A system always has some UI font; last resort is its name. */
  if (face == NULL) {
    face = lui_match("Segoe UI", weight, italic, &fam, &w, &st, &sty);
  }
  if (face == NULL)
    caml_failwith("lui_text_dwrite: no system font");
  IDWriteTextFormat *format =
    lui_format(fam, w, st, sty, Double_val(vsize));
  free(fam);
  vfont = lui_wrap(face, (FLOAT)Double_val(vsize), format, NULL);
  CAMLreturn(vfont);
}

/* cascade : font -> string array -> weight -> italic -> font
   [font] with the named families (the installed ones) tried before the
   system's own fallbacks for glyphs it lacks: the shaping format gets
   an explicit font fallback chain. */
CAMLprim value lui_dwrite_cascade(value vfont, value vnames,
                                  value vweight, value vitalic)
{
  CAMLparam4(vfont, vnames, vweight, vitalic);
  CAMLlocal1(vout);
  struct lui_font *base = Lui_font_val(vfont);
  mlsize_t n = Wosize_val(vnames);

  /* With no fallback support (pre-Windows-8.1) or no names, the font
     stays itself. */
  IDWriteFontFallback *fb = NULL;
  IDWriteTextFormat *format = NULL;
  if (lui_factory2 != NULL) {
    IDWriteFontFallbackBuilder *builder = NULL;
    if (SUCCEEDED(IDWriteFactory2_CreateFontFallbackBuilder(
          lui_factory2, &builder)) && builder != NULL) {
      DWRITE_UNICODE_RANGE all = { 0, 0x10FFFF };
      for (mlsize_t i = 0; i < n; i++) {
        const char *name = String_val(Field(vnames, i));
        if (!lui_has_family(name)) continue;
        WCHAR *w = lui_to_utf16(name);
        if (w == NULL) continue;
        const WCHAR *targets[1] = { w };
        IDWriteFontFallbackBuilder_AddMapping(
          builder, &all, 1, targets, 1, lui_coll, NULL, NULL, 1.0f);
        free(w);
      }
      if (lui_sysfallback != NULL) {
        IDWriteFontFallbackBuilder_AddMappings(builder,
                                               lui_sysfallback);
      }
      IDWriteFontFallbackBuilder_CreateFontFallback(builder, &fb);
      IDWriteFontFallbackBuilder_Release(builder);
    }
    format = lui_format(base->family, base->weight, base->stretch,
                        base->style, base->size);
    if (format != NULL && fb != NULL) {
      IDWriteTextFormat1 *f1 = NULL;
      if (SUCCEEDED(IDWriteTextFormat_QueryInterface(
            format, &IID_IDWriteTextFormat1, (void **)&f1)) &&
          f1 != NULL) {
        IDWriteTextFormat1_SetFontFallback(f1, fb);
        IDWriteTextFormat1_Release(f1);
      }
    }
  }
  IDWriteFontFace_AddRef(base->face);
  vout = lui_wrap(base->face, (FLOAT)base->size, format, fb);
  CAMLreturn(vout);
}

/* ---------------------------------------------------- analysis source */

/* The text of a MapCharacters call, as an IDWriteTextAnalysisSource. */
typedef struct lui_tas {
  const IDWriteTextAnalysisSourceVtbl *lpVtbl;
  const WCHAR *text;
  UINT32 len;
} lui_tas;

static HRESULT STDMETHODCALLTYPE tas_qi(IDWriteTextAnalysisSource *This,
                                        REFIID iid, void **out)
{
  if (IsEqualIID(iid, &IID_IUnknown) ||
      IsEqualIID(iid, &IID_IDWriteTextAnalysisSource)) {
    *out = This;
    return S_OK;
  }
  *out = NULL;
  return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE tas_addref(IDWriteTextAnalysisSource *This)
{
  (void)This;
  return 1;
}
static ULONG STDMETHODCALLTYPE tas_release(IDWriteTextAnalysisSource *This)
{
  (void)This;
  return 1;
}
static HRESULT STDMETHODCALLTYPE tas_at(IDWriteTextAnalysisSource *This,
                                        UINT32 pos, const WCHAR **text,
                                        UINT32 *len)
{
  lui_tas *t = (lui_tas *)This;
  if (pos > t->len) pos = t->len;
  *text = t->text + pos;
  *len = t->len - pos;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE tas_before(IDWriteTextAnalysisSource *This,
                                            UINT32 pos, const WCHAR **text,
                                            UINT32 *len)
{
  lui_tas *t = (lui_tas *)This;
  if (pos > t->len) pos = t->len;
  *text = t->text;
  *len = pos;
  return S_OK;
}
static DWRITE_READING_DIRECTION STDMETHODCALLTYPE tas_dir(
  IDWriteTextAnalysisSource *This)
{
  (void)This;
  return DWRITE_READING_DIRECTION_LEFT_TO_RIGHT;
}
static HRESULT STDMETHODCALLTYPE tas_locale(IDWriteTextAnalysisSource *This,
                                            UINT32 pos, UINT32 *len,
                                            const WCHAR **locale)
{
  (void)This; (void)pos;
  *len = (UINT32)wcslen(lui_locale);
  *locale = lui_locale;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE tas_numsub(IDWriteTextAnalysisSource *This,
                                            UINT32 pos, UINT32 *len,
                                            IDWriteNumberSubstitution **s)
{
  (void)This; (void)pos;
  *len = 0;
  *s = NULL;
  return S_OK;
}

static const IDWriteTextAnalysisSourceVtbl lui_tas_vtbl = {
  tas_qi, tas_addref, tas_release,
  tas_at, tas_before, tas_dir, tas_locale, tas_numsub
};

/* fallback : font -> string -> font option
   The font the system picks to cover the characters of the string the
   font lacks, down the font's own fallback chain or the system's. None
   when nothing can render it. */
CAMLprim value lui_dwrite_fallback(value vfont, value vstr)
{
  CAMLparam2(vfont, vstr);
  CAMLlocal3(vopt, vres, vtmp);
  lui_ensure();
  struct lui_font *h = Lui_font_val(vfont);
  if (lui_factory2 == NULL) CAMLreturn(Val_int(0));
  IDWriteFontFallback *fb =
    h->fallback != NULL ? h->fallback : lui_sysfallback;
  if (fb == NULL) CAMLreturn(Val_int(0));

  const char *s = (const char *)Bytes_val(vstr);
  int len = (int)caml_string_length(vstr);
  if (len == 0) CAMLreturn(Val_int(0));
  int *index = NULL;
  int nunits = 0;
  WCHAR *text = lui_text_utf16(s, len, &index, &nunits);
  free(index);
  if (text == NULL || nunits == 0) {
    free(text);
    CAMLreturn(Val_int(0));
  }

  lui_tas tas = { &lui_tas_vtbl, text, (UINT32)nunits };
  IDWriteFont *mapped = NULL;
  UINT32 mlen = 0;
  FLOAT scale = 1.0f;
  HRESULT hr = IDWriteFontFallback_MapCharacters(
    fb, (IDWriteTextAnalysisSource *)&tas, 0, (UINT32)nunits,
    lui_coll, h->family, (DWRITE_FONT_WEIGHT)h->weight,
    (DWRITE_FONT_STYLE)h->style, (DWRITE_FONT_STRETCH)h->stretch,
    &mlen, &mapped, &scale);
  free(text);
  if (FAILED(hr) || mapped == NULL || mlen == 0) {
    if (mapped != NULL) IDWriteFont_Release(mapped);
    CAMLreturn(Val_int(0));
  }

  IDWriteFontFace *face = NULL;
  hr = IDWriteFont_CreateFontFace(mapped, &face);
  IDWriteFont_Release(mapped);
  if (FAILED(hr) || face == NULL) CAMLreturn(Val_int(0));
  vres = lui_wrap(face, (FLOAT)h->size, NULL, NULL);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vres);
  CAMLreturn(vopt);
}

/* metrics : font -> (size, ascent, descent, leading)
   A float tuple is a tag-0 block of boxed doubles. */
CAMLprim value lui_dwrite_metrics(value vfont)
{
  CAMLparam1(vfont);
  CAMLlocal1(vm);
  struct lui_font *h = Lui_font_val(vfont);
  double ascent = 0., descent = 0., leading = 0.;
  DWRITE_FONT_METRICS m;
  IDWriteFontFace_GetMetrics(h->face, &m);
  if (m.designUnitsPerEm > 0) {
    double sc = h->size / (double)m.designUnitsPerEm;
    ascent = (double)m.ascent * sc;
    descent = (double)m.descent * sc;
    leading = (double)m.lineGap * sc;
    if (leading < 0.) leading = 0.;
  }
  vm = caml_alloc(4, 0);
  Store_field(vm, 0, caml_copy_double(h->size));
  Store_field(vm, 1, caml_copy_double(ascent));
  Store_field(vm, 2, caml_copy_double(descent));
  Store_field(vm, 3, caml_copy_double(leading));
  CAMLreturn(vm);
}

CAMLprim value lui_dwrite_is_color(value vfont)
{
  CAMLparam1(vfont);
  struct lui_font *h = Lui_font_val(vfont);
  CAMLreturn(Val_bool(h->color));
}

/* family : font -> string (best-effort installed family name) */
CAMLprim value lui_dwrite_family(value vfont)
{
  CAMLparam1(vfont);
  CAMLlocal1(vs);
  struct lui_font *h = Lui_font_val(vfont);
  vs = caml_copy_string(h->fam8 != NULL ? h->fam8 : "");
  CAMLreturn(vs);
}

/* -------------------------------------------------------- run collect */

/* One shaped run handed to the renderer: font face, direction and
   positioned glyphs, all copied. */
struct lui_run {
  IDWriteFontFace *face; /* a full reference */
  float em_size;
  int rtl;
  UINT32 pos, n;
  UINT32 nglyphs;
  UINT16 *glyphs;
  float *advances;
  DWRITE_GLYPH_OFFSET *offsets;
  UINT16 *clusters;
};

static struct lui_run *lui_runs = NULL;
static int lui_nruns = 0;
static int lui_capruns = 0;

static void lui_runs_clear(void)
{
  for (int i = 0; i < lui_nruns; i++) {
    struct lui_run *r = &lui_runs[i];
    if (r->face != NULL) IDWriteFontFace_Release(r->face);
    free(r->glyphs);
    free(r->advances);
    free(r->offsets);
    free(r->clusters);
  }
  lui_nruns = 0;
}

static void lui_collect(const DWRITE_GLYPH_RUN *run,
                        const DWRITE_GLYPH_RUN_DESCRIPTION *desc)
{
  if (lui_nruns == lui_capruns) {
    int cap = lui_capruns ? lui_capruns * 2 : 16;
    struct lui_run *nr =
      realloc(lui_runs, (size_t)cap * sizeof(*nr));
    if (nr == NULL) return;
    lui_runs = nr;
    lui_capruns = cap;
  }
  struct lui_run *r = &lui_runs[lui_nruns];
  memset(r, 0, sizeof(*r));
  r->face = run->fontFace;
  if (r->face != NULL) IDWriteFontFace_AddRef(r->face);
  r->em_size = run->fontEmSize;
  r->rtl = (run->bidiLevel & 1) != 0;
  r->pos = desc != NULL ? desc->textPosition : 0;
  r->n = desc != NULL ? desc->stringLength : 0;
  UINT32 ng = run->glyphCount;
  r->nglyphs = ng;
  if (ng > 0) {
    r->glyphs = malloc((size_t)ng * sizeof(UINT16));
    memcpy(r->glyphs, run->glyphIndices,
           (size_t)ng * sizeof(UINT16));
    if (run->glyphAdvances != NULL) {
      r->advances = malloc((size_t)ng * sizeof(float));
      memcpy(r->advances, run->glyphAdvances,
             (size_t)ng * sizeof(float));
    }
    if (run->glyphOffsets != NULL) {
      r->offsets = malloc((size_t)ng * sizeof(DWRITE_GLYPH_OFFSET));
      memcpy(r->offsets, run->glyphOffsets,
             (size_t)ng * sizeof(DWRITE_GLYPH_OFFSET));
    }
    if (desc != NULL && desc->clusterMap != NULL && r->n > 0) {
      r->clusters = malloc((size_t)r->n * sizeof(UINT16));
      memcpy(r->clusters, desc->clusterMap,
             (size_t)r->n * sizeof(UINT16));
    }
  }
  lui_nruns++;
}

/* ----------------------------------------------------------- renderer */

/* The renderer IDWriteTextLayout.Draw hands its glyph runs to, which
   collects them in drawing order. */
static HRESULT STDMETHODCALLTYPE ren_qi(IDWriteTextRenderer *This,
                                        REFIID iid, void **out)
{
  if (IsEqualIID(iid, &IID_IUnknown) ||
      IsEqualIID(iid, &IID_IDWritePixelSnapping) ||
      IsEqualIID(iid, &IID_IDWriteTextRenderer)) {
    *out = This;
    return S_OK;
  }
  *out = NULL;
  return E_NOINTERFACE;
}
static ULONG STDMETHODCALLTYPE ren_addref(IDWriteTextRenderer *This)
{
  (void)This;
  return 1;
}
static ULONG STDMETHODCALLTYPE ren_release(IDWriteTextRenderer *This)
{
  (void)This;
  return 1;
}
static HRESULT STDMETHODCALLTYPE ren_snapped(IDWriteTextRenderer *This,
                                             void *ctx, WINBOOL *disabled)
{
  (void)This; (void)ctx;
  *disabled = TRUE;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE ren_transform(IDWriteTextRenderer *This,
                                               void *ctx, DWRITE_MATRIX *m)
{
  (void)This; (void)ctx;
  m->m11 = 1; m->m12 = 0; m->m21 = 0; m->m22 = 1;
  m->dx = 0; m->dy = 0;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE ren_ppd(IDWriteTextRenderer *This,
                                         void *ctx, FLOAT *ppd)
{
  (void)This; (void)ctx;
  *ppd = 1.0f;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE ren_draw(
  IDWriteTextRenderer *This, void *ctx, FLOAT x, FLOAT y,
  DWRITE_MEASURING_MODE mode, const DWRITE_GLYPH_RUN *run,
  const DWRITE_GLYPH_RUN_DESCRIPTION *desc, IUnknown *effect)
{
  (void)This; (void)ctx; (void)x; (void)y; (void)mode; (void)effect;
  lui_collect(run, desc);
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE ren_underline(
  IDWriteTextRenderer *This, void *ctx, FLOAT x, FLOAT y,
  const DWRITE_UNDERLINE *what, IUnknown *effect)
{
  (void)This; (void)ctx; (void)x; (void)y; (void)what; (void)effect;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE ren_strikethrough(
  IDWriteTextRenderer *This, void *ctx, FLOAT x, FLOAT y,
  const DWRITE_STRIKETHROUGH *what, IUnknown *effect)
{
  (void)This; (void)ctx; (void)x; (void)y; (void)what; (void)effect;
  return S_OK;
}
static HRESULT STDMETHODCALLTYPE ren_inline(
  IDWriteTextRenderer *This, void *ctx, FLOAT x, FLOAT y,
  IDWriteInlineObject *obj, WINBOOL sideways, WINBOOL rtl,
  IUnknown *effect)
{
  (void)This; (void)ctx; (void)x; (void)y; (void)obj;
  (void)sideways; (void)rtl; (void)effect;
  return S_OK;
}

static const IDWriteTextRendererVtbl lui_renderer_vtbl = {
  ren_qi, ren_addref, ren_release,
  ren_snapped, ren_transform, ren_ppd,
  ren_draw, ren_underline, ren_strikethrough, ren_inline
};
static IDWriteTextRenderer lui_renderer = {
  (IDWriteTextRendererVtbl *)&lui_renderer_vtbl
};

/* --------------------------------------------------------------- shape */

/* The byte offset of the first character of each glyph's cluster: the
   smallest text position in the largest cluster starting at or before
   the glyph. */
static void lui_first_glyphs(const struct lui_run *r, UINT32 *first)
{
  UINT32 ng = r->nglyphs;
  UINT32 *mink = malloc((size_t)ng * sizeof(UINT32));
  for (UINT32 g = 0; g < ng; g++) mink[g] = 0xFFFFFFFFU;
  if (r->clusters != NULL) {
    for (UINT32 k = 0; k < r->n; k++) {
      UINT32 v = r->clusters[k];
      if (v < ng && k < mink[v]) mink[v] = k;
    }
  }
  UINT32 best = 0;
  for (UINT32 g = 0; g < ng; g++) {
    if (mink[g] != 0xFFFFFFFFU) best = g;
    first[g] = mink[best] != 0xFFFFFFFFU ? mink[best] : 0;
  }
  free(mink);
}

/* One shaped run: font, direction and positioned glyphs. The returned
   value is a record/block:
   (font, start_byte, stop_byte, rtl, glyph array)
   where a glyph is (id, x, y_from_baseline, advance, cluster_byte).
   [x] is the run's origin, on the right for a right-to-left run. */
static value lui_shape_run(struct lui_run *r, float x,
                           const int *index, int nunits, int base)
{
  CAMLparam0();
  CAMLlocal5(vrun, vglyphs, vg, vfont, tmp);
  UINT32 nglyphs = r->nglyphs;

  vfont = lui_wrap(r->face, r->em_size, NULL, NULL);

  UINT32 *first = malloc((size_t)(nglyphs ? nglyphs : 1)
                         * sizeof(UINT32));
  lui_first_glyphs(r, first);

  float pen = x;
  vglyphs = caml_alloc((mlsize_t)nglyphs, 0);
  for (UINT32 i = 0; i < nglyphs; i++) {
    float adv = r->advances != NULL ? r->advances[i] : 0.f;
    float xo = r->offsets != NULL ? r->offsets[i].advanceOffset : 0.f;
    float yo = r->offsets != NULL ? r->offsets[i].ascenderOffset : 0.f;
    vg = caml_alloc(5, 0);
    Store_field(vg, 0, Val_int(r->glyphs[i]));
    double gx;
    if (r->rtl) {
      pen -= adv;
      gx = pen - xo;
    } else {
      gx = pen + xo;
      pen += adv;
    }
    UINT32 cp = r->pos + first[i];
    if (cp > (UINT32)nunits) cp = (UINT32)nunits;
    Store_field(vg, 1, caml_copy_double(gx));
    Store_field(vg, 2, caml_copy_double(-(double)yo));
    Store_field(vg, 3, caml_copy_double((double)adv));
    Store_field(vg, 4, Val_int(index[cp] + base));
    Store_field(vglyphs, i, vg);
  }
  free(first);

  UINT32 p0 = r->pos, p1 = r->pos + r->n;
  if (p0 > (UINT32)nunits) p0 = (UINT32)nunits;
  if (p1 > (UINT32)nunits) p1 = (UINT32)nunits;

  vrun = caml_alloc(5, 0);
  Store_field(vrun, 0, vfont);
  Store_field(vrun, 1, Val_int(index[p0] + base));
  Store_field(vrun, 2, Val_int(index[p1] + base));
  Store_field(vrun, 3, Val_bool(r->rtl));
  Store_field(vrun, 4, vglyphs);
  tmp = vrun;
  CAMLreturn(tmp);
}

/* shape : font -> utf8 -> width -> rtl -> base -> line array
   A line is (start_byte, stop_byte, width, ascent, descent, leading,
   run array). Offsets are bytes into the OCaml string. */
CAMLprim value lui_dwrite_shape(value vfont, value vstr, value vwidth,
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

  if (len == 0) {
    vempty = caml_alloc(0, 0);
    CAMLreturn(vempty);
  }
  lui_ensure();

  int *index = NULL;
  int nunits = 0;
  WCHAR *utext = lui_text_utf16(text, len, &index, &nunits);
  if (utext == NULL)
    caml_failwith("lui_text_dwrite: out of memory");

  IDWriteTextLayout *layout = NULL;
  FLOAT maxw = width > 0. ? (FLOAT)width : 16777216.f;
  HRESULT hr = IDWriteFactory_CreateTextLayout(
    lui_factory, utext, (UINT32)nunits, h->format, maxw, 16777216.f,
    &layout);
  if (FAILED(hr) || layout == NULL) {
    free(utext); free(index);
    caml_failwith("lui_text_dwrite: no layout");
  }
  IDWriteTextLayout_SetWordWrapping(
    layout, width > 0. ? DWRITE_WORD_WRAPPING_WRAP
                       : DWRITE_WORD_WRAPPING_NO_WRAP);
  if (rtl) {
    /* Trailing alignment keeps the lines at the left, as left-to-right
       lines are. */
    IDWriteTextLayout_SetReadingDirection(
      layout, DWRITE_READING_DIRECTION_RIGHT_TO_LEFT);
    IDWriteTextLayout_SetTextAlignment(
      layout, DWRITE_TEXT_ALIGNMENT_TRAILING);
  }

  UINT32 nlines = 0;
  DWRITE_LINE_METRICS *metrics = NULL;
  hr = IDWriteTextLayout_GetLineMetrics(layout, NULL, 0, &nlines);
  if (nlines > 0) {
    metrics = malloc((size_t)nlines * sizeof(DWRITE_LINE_METRICS));
    hr = IDWriteTextLayout_GetLineMetrics(layout, metrics, nlines,
                                          &nlines);
    if (FAILED(hr)) nlines = 0;
  }

  lui_runs_clear();
  IDWriteTextLayout_Draw(layout, NULL, &lui_renderer, 0.f, 0.f);

  /* Line ends in code units, cumulative. */
  UINT32 *ends = malloc((size_t)(nlines ? nlines : 1) * sizeof(UINT32));
  UINT32 pos = 0;
  for (UINT32 i = 0; i < nlines; i++) {
    pos += metrics[i].length;
    ends[i] = pos;
  }

  /* Per-run line, origin and total advance. */
  int *rl = malloc((size_t)lui_nruns * sizeof(int));
  float *rx = malloc((size_t)lui_nruns * sizeof(float));
  float *rt = malloc((size_t)lui_nruns * sizeof(float));
  int *rnr = calloc((size_t)(nlines ? nlines : 1), sizeof(int));
  for (int i = 0; i < lui_nruns; i++) {
    struct lui_run *r = &lui_runs[i];
    rl[i] = -1;
    for (UINT32 li = 0; li < nlines; li++) {
      if (ends[li] >= r->pos + 1) { rl[i] = (int)li; break; }
    }
    if (rl[i] >= 0) rnr[rl[i]]++;
    FLOAT x = 0.f, y = 0.f;
    DWRITE_HIT_TEST_METRICS hit;
    if (SUCCEEDED(IDWriteTextLayout_HitTestTextPosition(
          layout, r->pos, FALSE, &x, &y, &hit))) {
      rx[i] = x;
    } else {
      rx[i] = 0.f;
    }
    float t = 0.f;
    if (r->advances != NULL) {
      for (UINT32 g = 0; g < r->nglyphs; g++) t += r->advances[g];
    }
    rt[i] = t;
  }

  vlines = Val_int(0); /* boxed list of finished lines, last first */
  int made = 0;
  for (UINT32 li = 0; li < nlines; li++) {
    /* Typographic width: the right edge of the rightmost run. */
    float lw = 0.f;
    for (int i = 0; i < lui_nruns; i++) {
      if (rl[i] != (int)li) continue;
      float right =
        lui_runs[i].rtl ? rx[i] : rx[i] + rt[i];
      if (right > lw) lw = right;
    }

    /* Line ascent/descent: the most each run's font reaches above and
       below the baseline, like the line's typographic bounds. */
    double asc = 0., desc = 0.;
    int any = 0;
    for (int i = 0; i < lui_nruns; i++) {
      if (rl[i] != (int)li) continue;
      struct lui_run *r = &lui_runs[i];
      if (r->face == NULL) continue;
      DWRITE_FONT_METRICS fm;
      IDWriteFontFace_GetMetrics(r->face, &fm);
      if (fm.designUnitsPerEm == 0) continue;
      any = 1;
      double sc = r->em_size / (double)fm.designUnitsPerEm;
      double fa = (double)fm.ascent * sc;
      double fd = (double)fm.descent * sc;
      if (fa > asc) asc = fa;
      if (fd > desc) desc = fd;
    }
    if (!any) {
      DWRITE_FONT_METRICS fm;
      IDWriteFontFace_GetMetrics(h->face, &fm);
      if (fm.designUnitsPerEm > 0) {
        double sc = h->size / (double)fm.designUnitsPerEm;
        asc = (double)fm.ascent * sc;
        desc = (double)fm.descent * sc;
      }
    }
    double leading = (double)metrics[li].height - asc - desc;
    if (leading < 0.) leading = 0.;

    vruns = caml_alloc((mlsize_t)rnr[li], 0);
    int ri = 0;
    for (int i = 0; i < lui_nruns; i++) {
      if (rl[i] != (int)li) continue;
      Store_field(vruns, ri,
                  lui_shape_run(&lui_runs[i], rx[i], index, nunits,
                                base));
      ri++;
    }

    int lstart = li == 0 ? 0 : (int)ends[li - 1];
    int lstop = (int)ends[li];
    if (lstart > nunits) lstart = nunits;
    if (lstop > nunits) lstop = nunits;

    vline = caml_alloc(7, 0);
    Store_field(vline, 0, Val_int(index[lstart] + base));
    Store_field(vline, 1, Val_int(index[lstop] + base));
    Store_field(vline, 2, caml_copy_double((double)lw));
    Store_field(vline, 3, caml_copy_double(asc));
    Store_field(vline, 4, caml_copy_double(desc));
    Store_field(vline, 5, caml_copy_double(leading));
    Store_field(vline, 6, vruns);
    vcons = caml_alloc(2, 0);
    Store_field(vcons, 0, vline);
    Store_field(vcons, 1, vlines);
    vlines = vcons;
    made++;
  }

  lui_runs_clear();
  IDWriteTextLayout_Release(layout);
  free(utext);
  free(index);
  free(metrics);
  free(ends);
  free(rl); free(rx); free(rt); free(rnr);

  /* The list is reversed (last line first); unpack it in order. */
  vempty = caml_alloc((mlsize_t)made, 0);
  {
    value cur = vlines;
    for (int i = made - 1; i >= 0; i--) {
      Store_field(vempty, i, Field(cur, 0));
      cur = Field(cur, 1);
    }
  }
  CAMLreturn(vempty);
}

/* ---------------------------------------------------------- rasterize */

/* The rendering mode DirectWrite recommends for a face at a size. */
static void lui_mode(IDWriteFontFace *face, float size, float scale,
                     DWRITE_RENDERING_MODE1 *mode,
                     DWRITE_GRID_FIT_MODE *grid)
{
  *mode = DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC;
  *grid = DWRITE_GRID_FIT_MODE_DEFAULT;
  IDWriteFontFace3 *f3 = NULL;
  if (lui_factory3 != NULL &&
      SUCCEEDED(IDWriteFontFace_QueryInterface(
        face, &IID_IDWriteFontFace3, (void **)&f3)) && f3 != NULL) {
    HRESULT hr = IDWriteFontFace3_GetRecommendedRenderingMode(
      f3, size, 96.f * scale, 96.f * scale, NULL, FALSE,
      DWRITE_OUTLINE_THRESHOLD_ANTIALIASED,
      DWRITE_MEASURING_MODE_NATURAL, lui_params, mode, grid);
    IDWriteFontFace3_Release(f3);
    if (SUCCEEDED(hr) && *mode != DWRITE_RENDERING_MODE1_DEFAULT) {
      if (*mode == DWRITE_RENDERING_MODE1_OUTLINE)
        *mode = DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC;
      return;
    }
  }
  IDWriteFontFace2 *f2 = NULL;
  if (SUCCEEDED(IDWriteFontFace_QueryInterface(
        face, &IID_IDWriteFontFace2, (void **)&f2)) && f2 != NULL) {
    DWRITE_RENDERING_MODE m;
    HRESULT hr = IDWriteFontFace2_GetRecommendedRenderingMode(
      f2, size, 96.f * scale, 96.f * scale, NULL, FALSE,
      DWRITE_OUTLINE_THRESHOLD_ANTIALIASED,
      DWRITE_MEASURING_MODE_NATURAL, lui_params, &m, grid);
    IDWriteFontFace2_Release(f2);
    if (SUCCEEDED(hr) && m != DWRITE_RENDERING_MODE_DEFAULT) {
      *mode = m == DWRITE_RENDERING_MODE_OUTLINE
        ? DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC
        : (DWRITE_RENDERING_MODE1)m;
    }
  }
}

/* The grayscale glyph run analysis of a run drawn at (x, y), and the
   bounds of its pixels. */
static IDWriteGlyphRunAnalysis *lui_analyze(
  const DWRITE_GLYPH_RUN *run, float x, float y,
  DWRITE_RENDERING_MODE1 mode, DWRITE_GRID_FIT_MODE grid, RECT *rect)
{
  IDWriteGlyphRunAnalysis *a = NULL;
  HRESULT hr = E_FAIL;
  if (lui_factory3 != NULL) {
    hr = IDWriteFactory3_CreateGlyphRunAnalysis(
      lui_factory3, run, NULL, mode, DWRITE_MEASURING_MODE_NATURAL,
      grid, DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE, x, y, &a);
  } else if (lui_factory2 != NULL) {
    DWRITE_RENDERING_MODE m =
      mode == DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC_DOWNSAMPLED
        ? DWRITE_RENDERING_MODE_NATURAL_SYMMETRIC
        : (DWRITE_RENDERING_MODE)mode;
    hr = IDWriteFactory2_CreateGlyphRunAnalysis(
      lui_factory2, run, NULL, m, DWRITE_MEASURING_MODE_NATURAL,
      grid, DWRITE_TEXT_ANTIALIAS_MODE_GRAYSCALE, x, y, &a);
  } else {
    hr = IDWriteFactory_CreateGlyphRunAnalysis(
      lui_factory, run, 1.0f, NULL, (DWRITE_RENDERING_MODE)mode,
      DWRITE_MEASURING_MODE_NATURAL, x, y, &a);
  }
  if (FAILED(hr) || a == NULL) return NULL;
  DWRITE_TEXTURE_TYPE tex = DWRITE_TEXTURE_ALIASED_1x1;
  if (lui_factory2 == NULL) tex = DWRITE_TEXTURE_CLEARTYPE_3x1;
  if (FAILED(IDWriteGlyphRunAnalysis_GetAlphaTextureBounds(
        a, tex, rect)) || rect->right <= rect->left ||
      rect->bottom <= rect->top) {
    IDWriteGlyphRunAnalysis_Release(a);
    return NULL;
  }
  return a;
}

/* The coverage of an analyzed run's pixels in r, or NULL. */
static unsigned char *lui_alpha(IDWriteGlyphRunAnalysis *a,
                                const RECT *r)
{
  int w = (int)(r->right - r->left);
  int ht = (int)(r->bottom - r->top);
  if (lui_factory2 != NULL) {
    unsigned char *out = malloc((size_t)w * ht);
    if (out == NULL) return NULL;
    if (FAILED(IDWriteGlyphRunAnalysis_CreateAlphaTexture(
          a, DWRITE_TEXTURE_ALIASED_1x1, r, out,
          (UINT32)(w * ht)))) {
      free(out);
      return NULL;
    }
    return out;
  }
  /* The old factory makes ClearType only; average it. */
  int n = 3 * w * ht;
  unsigned char *buf = malloc((size_t)n);
  unsigned char *out = malloc((size_t)w * ht);
  if (buf == NULL || out == NULL) {
    free(buf); free(out);
    return NULL;
  }
  if (FAILED(IDWriteGlyphRunAnalysis_CreateAlphaTexture(
        a, DWRITE_TEXTURE_CLEARTYPE_3x1, r, buf, (UINT32)n))) {
    free(buf); free(out);
    return NULL;
  }
  for (int i = 0; i < w * ht; i++) {
    out[i] = (unsigned char)((buf[3 * i] + buf[3 * i + 1] +
                              buf[3 * i + 2] + 1) / 3);
  }
  free(buf);
  return out;
}

/* A glyph of a color font, drawn layer by layer into premultiplied
   BGRA, or NULL when it has no color. */
static value lui_color_glyph(const DWRITE_GLYPH_RUN *run, float dx,
                             int *has_color)
{
  CAMLparam0();
  CAMLlocal3(vres, vbytes, vtup);
  *has_color = 0;
  if (lui_factory2 == NULL) CAMLreturn(Val_int(0));
  IDWriteColorGlyphRunEnumerator *layers = NULL;
  HRESULT hr = IDWriteFactory2_TranslateColorGlyphRun(
    lui_factory2, dx, 0.f, run, NULL, DWRITE_MEASURING_MODE_NATURAL,
    NULL, 0, &layers);
  if (FAILED(hr) || layers == NULL) CAMLreturn(Val_int(0));
  *has_color = 1;

  struct layer {
    RECT r;
    unsigned char *alpha;
    float c[4];
  };
  struct layer *ls = NULL;
  int nls = 0, cap = 0;
  RECT box = { 0, 0, 0, 0 };
  for (;;) {
    BOOL more = FALSE;
    if (FAILED(IDWriteColorGlyphRunEnumerator_MoveNext(layers,
                                                       &more)) ||
        !more)
      break;
    const DWRITE_COLOR_GLYPH_RUN *cr = NULL;
    if (FAILED(IDWriteColorGlyphRunEnumerator_GetCurrentRun(
          layers, &cr)) || cr == NULL)
      break;
    DWRITE_COLOR_GLYPH_RUN copy = *cr;
    RECT r;
    IDWriteGlyphRunAnalysis *a = lui_analyze(
      &copy.glyphRun, copy.baselineOriginX, copy.baselineOriginY,
      DWRITE_RENDERING_MODE1_NATURAL_SYMMETRIC,
      DWRITE_GRID_FIT_MODE_DEFAULT, &r);
    if (a == NULL) continue;
    unsigned char *alpha = lui_alpha(a, &r);
    IDWriteGlyphRunAnalysis_Release(a);
    if (alpha == NULL) continue;
    if (nls == cap) {
      int nc = cap ? cap * 2 : 4;
      struct layer *nl = realloc(ls, (size_t)nc * sizeof(*nl));
      if (nl == NULL) { free(alpha); break; }
      ls = nl;
      cap = nc;
    }
    ls[nls].r = r;
    ls[nls].alpha = alpha;
    if (copy.paletteIndex == 0xFFFF) {
      /* The foreground palette index paints in the text color. */
      ls[nls].c[0] = 0.f; ls[nls].c[1] = 0.f;
      ls[nls].c[2] = 0.f; ls[nls].c[3] = 1.f;
    } else {
      ls[nls].c[0] = copy.runColor.r;
      ls[nls].c[1] = copy.runColor.g;
      ls[nls].c[2] = copy.runColor.b;
      ls[nls].c[3] = copy.runColor.a;
    }
    if (nls == 0) {
      box = r;
    } else {
      if (r.left < box.left) box.left = r.left;
      if (r.top < box.top) box.top = r.top;
      if (r.right > box.right) box.right = r.right;
      if (r.bottom > box.bottom) box.bottom = r.bottom;
    }
    nls++;
  }
  IDWriteColorGlyphRunEnumerator_Release(layers);

  if (nls == 0) {
    free(ls);
    CAMLreturn(Val_int(0));
  }
  int w = (int)(box.right - box.left);
  int ht = (int)(box.bottom - box.top);
  if (w <= 0 || ht <= 0 || w > 2048 || ht > 2048) {
    for (int i = 0; i < nls; i++) free(ls[i].alpha);
    free(ls);
    CAMLreturn(Val_int(0));
  }

  vbytes = caml_alloc_string((mlsize_t)(w * ht * 4));
  unsigned char *pix = Bytes_val(vbytes);
  memset(pix, 0, (size_t)w * ht * 4);
  for (int i = 0; i < nls; i++) {
    int lw = (int)(ls[i].r.right - ls[i].r.left);
    int lh = (int)(ls[i].r.bottom - ls[i].r.top);
    for (int y = 0; y < lh; y++) {
      int row = (y + (int)(ls[i].r.top - box.top)) * w
        + (int)(ls[i].r.left - box.left);
      for (int x = 0; x < lw; x++) {
        float cov = ls[i].alpha[y * lw + x] / 255.f * ls[i].c[3];
        if (cov == 0.f) continue;
        unsigned char *p = pix + 4 * (row + x);
        for (int c = 0; c < 3; c++) {
          p[c] = (unsigned char)(ls[i].c[c] * cov * 255.f
                                 + (float)p[c] * (1.f - cov) + 0.5f);
        }
        p[3] = (unsigned char)(cov * 255.f
                               + (float)p[3] * (1.f - cov) + 0.5f);
      }
    }
    free(ls[i].alpha);
  }
  free(ls);

  vtup = caml_alloc(6, 0);
  Store_field(vtup, 0, Val_int((int)box.left));
  Store_field(vtup, 1, Val_int((int)box.top));
  Store_field(vtup, 2, Val_int(w));
  Store_field(vtup, 3, Val_int(ht));
  Store_field(vtup, 4, Val_bool(1));
  Store_field(vtup, 5, vbytes);
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, vtup);
  CAMLreturn(vres);
}

/* rasterize : font -> glyph id -> scale -> dx -> shade -> bitmap option
   A bitmap is (left, top, w, h, color, bytes): the pixel box relative to
   the glyph's origin, and coverage (1 byte per pixel) or premultiplied
   BGRA (4 bytes per pixel) rows, top first. */
CAMLprim value lui_dwrite_rasterize(value vfont, value vid, value vscale,
                                    value vdx, value vshade)
{
  CAMLparam5(vfont, vid, vscale, vdx, vshade);
  CAMLlocal3(vres, vbytes, vtup);
  struct lui_font *h = Lui_font_val(vfont);
  UINT16 id = (UINT16)Int_val(vid);
  double s = Double_val(vscale);
  double dx = Double_val(vdx);
  /* [shade] would thicken masks by fill luminance on stacks that do
     that; this one draws glyphs as they are. */
  (void)vshade;
  lui_ensure();

  FLOAT zero = 0.f;
  DWRITE_GLYPH_RUN run;
  memset(&run, 0, sizeof(run));
  run.fontFace = h->face;
  run.fontEmSize = (FLOAT)(h->size * s);
  run.glyphCount = 1;
  run.glyphIndices = &id;
  run.glyphAdvances = &zero;

  if (h->color) {
    int has = 0;
    value b = lui_color_glyph(&run, (float)dx, &has);
    if (has || b != Val_int(0)) CAMLreturn(b);
  }

  DWRITE_RENDERING_MODE1 mode;
  DWRITE_GRID_FIT_MODE grid;
  lui_mode(h->face, (float)(h->size * s), (float)s, &mode, &grid);

  RECT r;
  IDWriteGlyphRunAnalysis *a =
    lui_analyze(&run, (float)dx, 0.f, mode, grid, &r);
  if (a == NULL) CAMLreturn(Val_int(0));

  int w = (int)(r.right - r.left);
  int ht = (int)(r.bottom - r.top);
  if (w <= 0 || ht <= 0 || w > 2048 || ht > 2048) {
    IDWriteGlyphRunAnalysis_Release(a);
    CAMLreturn(Val_int(0));
  }
  unsigned char *alpha = lui_alpha(a, &r);
  IDWriteGlyphRunAnalysis_Release(a);
  if (alpha == NULL) CAMLreturn(Val_int(0));

  vbytes = caml_alloc_string((mlsize_t)(w * ht));
  memcpy(Bytes_val(vbytes), alpha, (size_t)(w * ht));
  free(alpha);

  vtup = caml_alloc(6, 0);
  Store_field(vtup, 0, Val_int((int)r.left));
  Store_field(vtup, 1, Val_int((int)r.top));
  Store_field(vtup, 2, Val_int(w));
  Store_field(vtup, 3, Val_int(ht));
  Store_field(vtup, 4, Val_bool(0));
  Store_field(vtup, 5, vbytes);
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, vtup);
  CAMLreturn(vres);
}

#else /* !_WIN32 */

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void) {
  caml_failwith("lui_text_dwrite: this backend requires Windows");
  return Val_unit;
}

CAMLprim value lui_dwrite_named(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_dwrite_system(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_dwrite_cascade(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_dwrite_fallback(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_dwrite_metrics(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_dwrite_is_color(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_dwrite_family(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_dwrite_shape(value a, value b, value c, value d,
                                value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }
CAMLprim value lui_dwrite_rasterize(value a, value b, value c, value d,
                                    value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }

#endif /* _WIN32 */
