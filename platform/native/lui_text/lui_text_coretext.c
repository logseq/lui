/* Platform text engine for lui_text: the system's own text stack finds
   fonts, falls back for glyphs a font lacks, shapes paragraphs into
   positioned glyph runs, and rasterizes glyphs into coverage masks or
   color bitmaps.

   This file is compiled as Objective-C (see the dune file) so it can use
   NSFont for the system font and @autoreleasepool for temporary objects.
   Everything else goes through the C interfaces of Core Text, Core
   Graphics and Core Foundation. */

#if defined(__APPLE__)

#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <CoreGraphics/CoreGraphics.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <string.h>
#include <math.h>

/* ---------------------------------------------------------------- fonts */

/* A font handle is a retained CTFontRef in a custom block. Hash and
   compare follow the font's own identity so equal fonts wrap-equal for
   the OCaml side (cache keys, maps, hash tables). */

#define Lui_font_val(v) (*(CTFontRef *)Data_custom_val(v))

static void lui_font_finalize(value v)
{
  CFRelease(Lui_font_val(v));
}

static int lui_font_compare(value a, value b)
{
  uintptr_t fa = (uintptr_t)Lui_font_val(a);
  uintptr_t fb = (uintptr_t)Lui_font_val(b);
  if (fa == fb) return 0;
  if (CFEqual((CFTypeRef)fa, (CFTypeRef)fb)) return 0;
  return fa < fb ? -1 : 1;
}

static int lui_font_compare_ext(value a, value b)
{
  return lui_font_compare(a, b);
}

static intnat lui_font_hash(value v)
{
  return (intnat)CFHash(Lui_font_val(v));
}

static struct custom_operations lui_font_ops = {
  "lui_text.font",
  lui_font_finalize,
  lui_font_compare,
  lui_font_hash,
  custom_serialize_default,
  custom_deserialize_default,
  lui_font_compare_ext,
  custom_fixed_length_default
};

static value lui_font_wrap(CTFontRef font)
{
  value v = caml_alloc_custom(&lui_font_ops, sizeof(CTFontRef), 0, 1);
  Lui_font_val(v) = font;
  return v;
}

static CFStringRef lui_cfstr(const char *s)
{
  return CFStringCreateWithBytes(NULL, (const UInt8 *)s,
                                 (CFIndex)strlen(s), kCFStringEncodingUTF8,
                                 false);
}

/* Descriptor of the face of a family best matching weight and italics,
   or NULL when the family is not installed. */
static CTFontDescriptorRef lui_match_family(const char *name,
                                            double weight, int italic)
{
  CTFontDescriptorRef match = NULL;
  CFStringRef family = NULL;
  CFNumberRef wnum = NULL, snum = NULL;
  int32_t symbolic = italic ? kCTFontItalicTrait : 0;
  CFDictionaryRef traits_dict = NULL, attrs_dict = NULL;
  CTFontDescriptorRef raw = NULL;
  CFSetRef set = NULL;

  family = lui_cfstr(name);
  if (family == NULL) goto done;

  double w = weight;
  wnum = CFNumberCreate(NULL, kCFNumberFloat64Type, &w);
  snum = CFNumberCreate(NULL, kCFNumberSInt32Type, &symbolic);
  if (wnum == NULL || snum == NULL) goto done;

  {
    const void *keys[] = { kCTFontWeightTrait, kCTFontSymbolicTrait };
    const void *vals[] = { wnum, snum };
    traits_dict = CFDictionaryCreate(NULL, keys, vals, 2,
                                     &kCFTypeDictionaryKeyCallBacks,
                                     &kCFTypeDictionaryValueCallBacks);
    const void *akeys[] = { kCTFontFamilyNameAttribute,
                            kCTFontTraitsAttribute };
    const void *avals[] = { family, traits_dict };
    attrs_dict = CFDictionaryCreate(NULL, akeys, avals, 2,
                                    &kCFTypeDictionaryKeyCallBacks,
                                    &kCFTypeDictionaryValueCallBacks);
  }
  if (traits_dict == NULL || attrs_dict == NULL) goto done;

  raw = CTFontDescriptorCreateWithAttributes(attrs_dict);
  if (raw == NULL) goto done;
  {
    const void *need[] = { kCTFontFamilyNameAttribute };
    set = CFSetCreate(NULL, need, 1, &kCFTypeSetCallBacks);
    if (set == NULL) goto done;
    match = CTFontDescriptorCreateMatchingFontDescriptor(raw, set);
  }

done:
  if (family != NULL) CFRelease(family);
  if (wnum != NULL) CFRelease(wnum);
  if (snum != NULL) CFRelease(snum);
  if (traits_dict != NULL) CFRelease(traits_dict);
  if (attrs_dict != NULL) CFRelease(attrs_dict);
  if (raw != NULL) CFRelease(raw);
  if (set != NULL) CFRelease(set);
  return match;
}

static CTFontRef lui_make_italic(CTFontRef font, int italic)
{
  if (!italic || font == NULL) return font;
  CTFontRef f = CTFontCreateCopyWithSymbolicTraits(font, 0.0, NULL,
                                                   kCTFontItalicTrait,
                                                   kCTFontItalicTrait);
  if (f != NULL) {
    CFRelease(font);
    return f;
  }
  return font;
}

static CTFontRef lui_system_font(double size, double weight, int italic,
                                 int mono)
{
  @autoreleasepool {
    CTFontRef font = NULL;
    NSFont *ns = nil;
    if (mono) {
      SEL sel = @selector(monospacedSystemFontOfSize:weight:);
      if ([NSFont respondsToSelector:sel]) {
        ns = [NSFont monospacedSystemFontOfSize:size weight:weight];
      }
      if (ns == nil) {
        /* monospacedSystemFontOfSize:weight: needs macOS 10.15 */
        CTFontDescriptorRef d = lui_match_family("Menlo", weight, italic);
        if (d != NULL) {
          font = CTFontCreateWithFontDescriptor(d, size, NULL);
          CFRelease(d);
          return font;
        }
      }
    } else {
      ns = [NSFont systemFontOfSize:size weight:weight];
    }
    if (ns != nil) {
      font = (CTFontRef)CFRetain((__bridge CFTypeRef)ns);
    } else {
      font = CTFontCreateUIFontForLanguage(kCTFontUIFontSystem, size,
                                           NULL);
    }
    return lui_make_italic(font, italic);
  }
}

/* named : family -> size -> weight -> italic -> font option
   The face of [family] best matching weight and italics, or None when
   the family is not installed. */
CAMLprim value lui_ct_named(value vname, value vsize, value vweight,
                            value vitalic)
{
  CAMLparam4(vname, vsize, vweight, vitalic);
  CAMLlocal2(vopt, vfont);
  CTFontRef font = NULL;

  @autoreleasepool {
    CTFontDescriptorRef d =
      lui_match_family(String_val(vname), Double_val(vweight),
                       Bool_val(vitalic));
    if (d != NULL) {
      font = CTFontCreateWithFontDescriptor(d, Double_val(vsize), NULL);
      CFRelease(d);
    }
  }
  if (font == NULL) CAMLreturn(Val_int(0));
  vfont = lui_font_wrap(font);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vfont);
  CAMLreturn(vopt);
}

/* cascade : font -> string array -> weight -> italic -> font
   [font] with the named families (the installed ones) put before the
   system's own fallbacks for glyphs it lacks. */
CAMLprim value lui_ct_cascade(value vfont, value vnames, value vweight,
                              value vitalic)
{
  CAMLparam4(vfont, vnames, vweight, vitalic);
  CAMLlocal1(vout);
  mlsize_t n = Wosize_val(vnames);
  CTFontRef font = NULL;

  @autoreleasepool {
    CFMutableArrayRef cascade =
      CFArrayCreateMutable(NULL, (CFIndex)n, &kCFTypeArrayCallBacks);
    for (mlsize_t i = 0; i < n; i++) {
      CTFontDescriptorRef d =
        lui_match_family(String_val(Field(vnames, i)),
                         Double_val(vweight), Bool_val(vitalic));
      if (d != NULL) {
        CFArrayAppendValue(cascade, d);
        CFRelease(d);
      }
    }
    if (CFArrayGetCount(cascade) > 0) {
      const void *keys[] = { kCTFontCascadeListAttribute };
      const void *vals[] = { cascade };
      CFDictionaryRef attrs =
        CFDictionaryCreate(NULL, keys, vals, 1,
                           &kCFTypeDictionaryKeyCallBacks,
                           &kCFTypeDictionaryValueCallBacks);
      CTFontDescriptorRef extra =
        CTFontDescriptorCreateWithAttributes(attrs);
      CFRelease(attrs);
      /* size 0 keeps the font's size. */
      font = CTFontCreateCopyWithAttributes(Lui_font_val(vfont), 0.0,
                                            NULL, extra);
      CFRelease(extra);
    }
    CFRelease(cascade);
  }
  if (font == NULL) {
    /* No installed cascade families: the font itself. */
    CFRetain(Lui_font_val(vfont));
    font = Lui_font_val(vfont);
  }
  vout = lui_font_wrap(font);
  CAMLreturn(vout);
}

/* system : size -> weight -> italic -> monospace -> font */
CAMLprim value lui_ct_system(value vsize, value vweight, value vitalic,
                             value vmono)
{
  CAMLparam4(vsize, vweight, vitalic, vmono);
  CAMLlocal1(vfont);
  CTFontRef font = lui_system_font(Double_val(vsize), Double_val(vweight),
                                   Bool_val(vitalic), Bool_val(vmono));
  if (font == NULL) caml_failwith("lui_text: no system font");
  vfont = lui_font_wrap(font);
  CAMLreturn(vfont);
}

/* fallback : font -> string -> font option */
CAMLprim value lui_ct_fallback(value vfont, value vstr)
{
  CAMLparam2(vfont, vstr);
  CAMLlocal2(vopt, vres);
  CFStringRef str = NULL;
  CTFontRef fb = NULL;
  mlsize_t len = caml_string_length(vstr);

  str = CFStringCreateWithBytes(NULL, (const UInt8 *)Bytes_val(vstr),
                                (CFIndex)len, kCFStringEncodingUTF8, false);
  if (str == NULL) CAMLreturn(Val_int(0));
  fb = CTFontCreateForString(Lui_font_val(vfont), str,
                             CFRangeMake(0, CFStringGetLength(str)));
  CFRelease(str);
  if (fb == NULL) CAMLreturn(Val_int(0));
  vres = lui_font_wrap(fb);
  vopt = caml_alloc(1, 0);
  Store_field(vopt, 0, vres);
  CAMLreturn(vopt);
}

/* metrics : font -> (size, ascent, descent, leading)
   A float tuple is a tag-0 block of boxed doubles. */
CAMLprim value lui_ct_metrics(value vfont)
{
  CAMLparam1(vfont);
  CAMLlocal1(vm);
  CTFontRef f = Lui_font_val(vfont);
  vm = caml_alloc(4, 0);
  Store_field(vm, 0, caml_copy_double(CTFontGetSize(f)));
  Store_field(vm, 1, caml_copy_double(CTFontGetAscent(f)));
  Store_field(vm, 2, caml_copy_double(CTFontGetDescent(f)));
  Store_field(vm, 3, caml_copy_double(CTFontGetLeading(f)));
  CAMLreturn(vm);
}

CAMLprim value lui_ct_is_color(value vfont)
{
  CAMLparam1(vfont);
  CTFontSymbolicTraits t = CTFontGetSymbolicTraits(Lui_font_val(vfont));
  CAMLreturn(Val_bool((t & kCTFontTraitColorGlyphs) != 0));
}

/* family : font -> string (best-effort installed family name) */
CAMLprim value lui_ct_family(value vfont)
{
  CAMLparam1(vfont);
  CAMLlocal1(vs);
  char buf[512];
  CFStringRef name =
    CTFontCopyAttribute(Lui_font_val(vfont), kCTFontFamilyNameAttribute);
  if (name == NULL ||
      !CFStringGetCString(name, buf, sizeof(buf), kCFStringEncodingUTF8)) {
    buf[0] = '\0';
  }
  if (name != NULL) CFRelease(name);
  vs = caml_copy_string(buf);
  CAMLreturn(vs);
}

/* --------------------------------------------------------------- shape */

/* Decode UTF-8 into UTF-16, recording the UTF-8 byte offset of each code
   unit (index[o] = byte offset of the character owning unit o). Invalid
   sequences emit U+FFFD per byte. Returns the code unit count; the
   caller frees the outputs. */
static CFIndex lui_utf8_to_utf16(const UInt8 *s, CFIndex len,
                                 UniChar **u16_out, CFIndex **idx_out)
{
  UniChar *u16 = malloc(sizeof(UniChar) * (size_t)(len + 1));
  CFIndex *idx = malloc(sizeof(CFIndex) * (size_t)(len + 2));
  if (u16 == NULL || idx == NULL) {
    free(u16);
    free(idx);
    caml_failwith("lui_text: out of memory");
  }
  CFIndex i = 0, o = 0;
  while (i < len) {
    unsigned c = s[i];
    uint32_t r;
    int n;
    if (c < 0x80)      { r = c;         n = 1; }
    else if (c < 0xC0) { r = 0xFFFD;    n = 1; }
    else if (c < 0xE0) { r = c & 0x1F;  n = 2; }
    else if (c < 0xF0) { r = c & 0x0F;  n = 3; }
    else if (c < 0xF8) { r = c & 0x07;  n = 4; }
    else               { r = 0xFFFD;    n = 1; }
    if (i + n > len) {
      r = 0xFFFD;
      n = 1;
    } else {
      for (int k = 1; k < n; k++) {
        unsigned cc = s[i + k];
        if ((cc & 0xC0) != 0x80) { r = 0xFFFD; n = 1; break; }
        r = (r << 6) | (cc & 0x3F);
      }
      if (n > 1 &&
          (r < (n == 2 ? 0x80 : n == 3 ? 0x800 : 0x10000u) ||
           r > 0x10FFFFu || (r >= 0xD800 && r < 0xE000))) {
        r = 0xFFFD;
      }
    }
    if (r >= 0x10000) {
      uint32_t v = r - 0x10000;
      idx[o] = i;
      u16[o++] = (UniChar)(0xD800 + (v >> 10));
      idx[o] = i;
      u16[o++] = (UniChar)(0xDC00 + (v & 0x3FF));
    } else {
      idx[o] = i;
      u16[o++] = (UniChar)r;
    }
    i += n;
  }
  idx[o] = len;
  *u16_out = u16;
  *idx_out = idx;
  return o;
}

/* Paragraph styles shared by every shape call, made once. */
static CTParagraphStyleRef lui_para_styles[2] = { NULL, NULL };

static CGColorSpaceRef lui_srgb(void);

static void lui_init_para_styles(void)
{
  for (int i = 0; i < 2; i++) {
    if (lui_para_styles[i] != NULL) continue;
    CTWritingDirection dir =
      i == 0 ? kCTWritingDirectionLeftToRight
             : kCTWritingDirectionRightToLeft;
    CTParagraphStyleSetting setting = {
      kCTParagraphStyleSpecifierBaseWritingDirection,
      sizeof(CTWritingDirection), &dir
    };
    lui_para_styles[i] = CTParagraphStyleCreate(&setting, 1);
  }
}

/* Byte offset of UTF-16 code unit [i], clamped to the mapping. */
static inline CFIndex lui_byte_of(const CFIndex *idx, CFIndex i, CFIndex n16)
{
  if (i < 0) i = 0;
  if (i > n16) i = n16;
  return idx[i];
}

/* One shaped run: font, direction and positioned glyphs. The returned
   value is a record/block:
   (font, start_byte, stop_byte, rtl, glyph array)
   where a glyph is (id, x, y_from_baseline, advance, cluster_byte). */
static value lui_shape_run(CTRunRef run, const CFIndex *idx, CFIndex n16,
                           CFIndex base)
{
  CAMLparam0();
  CAMLlocal5(vrun, vglyphs, vg, vfont, tmp);
  CFRange rr = CTRunGetStringRange(run);
  CFIndex ng = CTRunGetGlyphCount(run);

  CFDictionaryRef attrs = CTRunGetAttributes(run);
  CTFontRef rf =
    (CTFontRef)CFDictionaryGetValue(attrs, kCTFontAttributeName);
  CFRetain(rf);
  vfont = lui_font_wrap(rf);

  vglyphs = caml_alloc((mlsize_t)ng, 0);
  if (ng > 0) {
    CGGlyph *gids = malloc(sizeof(CGGlyph) * (size_t)ng);
    CGPoint *pos = malloc(sizeof(CGPoint) * (size_t)ng);
    CGSize *adv = malloc(sizeof(CGSize) * (size_t)ng);
    CFIndex *ind = malloc(sizeof(CFIndex) * (size_t)ng);
    if (gids == NULL || pos == NULL || adv == NULL || ind == NULL) {
      free(gids); free(pos); free(adv); free(ind);
      caml_failwith("lui_text: out of memory");
    }
    CTRunGetGlyphs(run, CFRangeMake(0, 0), gids);
    CTRunGetPositions(run, CFRangeMake(0, 0), pos);
    CTRunGetAdvances(run, CFRangeMake(0, 0), adv);
    CTRunGetStringIndices(run, CFRangeMake(0, 0), ind);
    for (CFIndex j = 0; j < ng; j++) {
      vg = caml_alloc(5, 0);
      Store_field(vg, 0, Val_int(gids[j]));
      Store_field(vg, 1, caml_copy_double(pos[j].x));
      /* Positions sit on the baseline, y up; report y down so callers
         can add the glyph's y to the line's baseline directly. */
      Store_field(vg, 2, caml_copy_double(-pos[j].y));
      Store_field(vg, 3, caml_copy_double(adv[j].width));
      Store_field(vg, 4, Val_int(lui_byte_of(idx, ind[j], n16) + base));
      Store_field(vglyphs, j, vg);
    }
    free(gids); free(pos); free(adv); free(ind);
  }

  CTRunStatus st = CTRunGetStatus(run);

  /* Per-range ink color, when a span set one: packed 0xRRGGBBAA in an
     option. */
  value vcolor = Val_int(0);
  CGColorRef colr = (CGColorRef)CFDictionaryGetValue(
      attrs, kCTForegroundColorAttributeName);
  if (colr != NULL) {
    const CGFloat *cc = CGColorGetComponents(colr);
    size_t nc = CGColorGetNumberOfComponents(colr);
    int r = 0, g = 0, b = 0, a = 255;
    if (nc >= 4) {
      r = (int)(cc[0] * 255. + 0.5);
      g = (int)(cc[1] * 255. + 0.5);
      b = (int)(cc[2] * 255. + 0.5);
      a = (int)(cc[3] * 255. + 0.5);
    } else if (nc == 2) {
      r = g = b = (int)(cc[0] * 255. + 0.5);
      a = (int)(cc[1] * 255. + 0.5);
    }
    intnat packed = ((intnat)r << 24) | ((intnat)g << 16)
                    | ((intnat)b << 8) | (intnat)a;
    vcolor = caml_alloc(1, 0);
    Store_field(vcolor, 0, Val_int(packed));
  }

  CFNumberRef un = (CFNumberRef)CFDictionaryGetValue(
      attrs, kCTUnderlineStyleAttributeName);
  int under = 0;
  if (un != NULL) CFNumberGetValue(un, kCFNumberIntType, &under);

  vrun = caml_alloc(7, 0);
  Store_field(vrun, 0, vfont);
  Store_field(vrun, 1, Val_int(lui_byte_of(idx, rr.location, n16) + base));
  Store_field(vrun, 2,
              Val_int(lui_byte_of(idx, rr.location + rr.length, n16)
                      + base));
  Store_field(vrun, 3, Val_bool((st & kCTRunStatusRightToLeft) != 0));
  Store_field(vrun, 4, vglyphs);
  Store_field(vrun, 5, vcolor);
  Store_field(vrun, 6, Val_int(under));
  tmp = vrun;
  CAMLreturn(tmp);
}

/* Emit one line record (start, stop, width, ascent, descent, leading,
   run array) for a typeset line; byte offsets gain [base]. */
static value lui_emit_line(CTLineRef line, const CFIndex *idx,
                           CFIndex n16, CFIndex base)
{
  CAMLparam0();
  CAMLlocal2(vline, vruns);
  CFRange lr = CTLineGetStringRange(line);
  CGFloat asc = 0, desc = 0, lead = 0;
  double lw = CTLineGetTypographicBounds(line, &asc, &desc, &lead);
  CFArrayRef runs = CTLineGetGlyphRuns(line);
  CFIndex nr = CFArrayGetCount(runs);
  vruns = caml_alloc((mlsize_t)nr, 0);
  for (CFIndex i = 0; i < nr; i++) {
    CTRunRef r = (CTRunRef)CFArrayGetValueAtIndex(runs, i);
    Store_field(vruns, i, lui_shape_run(r, idx, n16, base));
  }
  vline = caml_alloc(7, 0);
  Store_field(vline, 0,
              Val_int(lui_byte_of(idx, lr.location, n16) + base));
  Store_field(vline, 1,
              Val_int(lui_byte_of(idx, lr.location + lr.length, n16)
                      + base));
  Store_field(vline, 2, caml_copy_double(lw));
  Store_field(vline, 3, caml_copy_double(asc));
  Store_field(vline, 4, caml_copy_double(desc));
  Store_field(vline, 5, caml_copy_double(lead));
  Store_field(vline, 6, vruns);
  CAMLreturn(vline);
}

/* shape : font -> utf8 -> width -> rtl -> base -> line array
   A line is (start_byte, stop_byte, width, ascent, descent, leading,
   run array). */
CAMLprim value lui_ct_shape(value vfont, value vstr, value vwidth,
                            value vrtl, value vbase)
{
  CAMLparam5(vfont, vstr, vwidth, vrtl, vbase);
  CAMLlocal4(vlines, vline, vcons, vempty);
  CFIndex base = Long_val(vbase);
  double width = Double_val(vwidth);
  int rtl = Bool_val(vrtl);
  CFIndex len = (CFIndex)caml_string_length(vstr);
  int nlines = 0;

  /* Lines pile up on a boxed list: it stays GC-rooted while shaping
     allocates more blocks. */
  vlines = Val_int(0);

  if (len == 0) {
    vempty = caml_alloc(0, 0);
    CAMLreturn(vempty);
  }

  UniChar *u16 = NULL;
  CFIndex *idx = NULL;
  CFIndex n16 = lui_utf8_to_utf16(Bytes_val(vstr), len, &u16, &idx);

  CFStringRef str = NULL;
  CFAttributedStringRef attrstr = NULL;
  CFDictionaryRef attrs = NULL;
  CTTypesetterRef ts = NULL;
  CTLineRef line = NULL;

  @autoreleasepool {
    lui_init_para_styles();

    str = CFStringCreateWithCharacters(NULL, u16, n16);
    const void *akeys[] = { kCTFontAttributeName,
                            kCTParagraphStyleAttributeName };
    const void *avals[] = { Lui_font_val(vfont),
                            lui_para_styles[rtl ? 1 : 0] };
    attrs = CFDictionaryCreate(NULL, akeys, avals, 2,
                               &kCFTypeDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks);
    if (str == NULL || attrs == NULL) goto done;
    attrstr = CFAttributedStringCreate(NULL, str, attrs);
    if (attrstr == NULL) goto done;
    ts = CTTypesetterCreateWithAttributedString(attrstr);
    if (ts == NULL) goto done;

    CFIndex start = 0;
    while (start < n16) {
      CFIndex count = n16 - start;
      if (width > 0) {
        count = CTTypesetterSuggestLineBreak(ts, start, width);
        if (count < 1) count = 1;
      }
      line = CTTypesetterCreateLine(ts, CFRangeMake(start, count));
      if (line == NULL) break;

      vline = lui_emit_line(line, idx, n16, base);
      vcons = caml_alloc(2, 0);
      Store_field(vcons, 0, vline);
      Store_field(vcons, 1, vlines);
      vlines = vcons;
      nlines++;

      CFRelease(line);
      line = NULL;
      start += count;
    }
  } /* autoreleasepool */

done:
  if (str != NULL) CFRelease(str);
  if (attrs != NULL) CFRelease(attrs);
  if (attrstr != NULL) CFRelease(attrstr);
  if (ts != NULL) CFRelease(ts);
  if (line != NULL) CFRelease(line);
  free(u16);
  free(idx);

  /* The list is reversed (last line first); unpack it in order. The
     cells stay rooted through vlines while the array fills. */
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

/* First UTF-16 unit index whose byte offset is >= b. */
static CFIndex lui_u16_of_byte(const CFIndex *idx, CFIndex n16, CFIndex b)
{
  CFIndex lo = 0, hi = n16;
  while (lo < hi) {
    CFIndex mid = (lo + hi) / 2;
    if (idx[mid] < b) lo = mid + 1;
    else hi = mid;
  }
  return lo;
}

/* shape_spans : font -> utf8 -> width -> rtl -> base -> span_attr array
   -> line array. A span_attr is
   (start_byte, stop_byte, font option, color option, kern, under);
   ranges are byte offsets into the segment string. The attributed
   string gets the base font and paragraph style first, then each
   span's attributes over its range. */
CAMLprim value lui_ct_shape_spans(value vfont, value vstr, value vwidth,
                                  value vrtl, value vbase, value vspans)
{
  CAMLparam5(vfont, vstr, vwidth, vrtl, vbase);
  CAMLxparam1(vspans);
  CAMLlocal4(vlines, vline, vcons, vempty);
  CFIndex base = Long_val(vbase);
  double width = Double_val(vwidth);
  int rtl = Bool_val(vrtl);
  CFIndex len = (CFIndex)caml_string_length(vstr);
  int nlines = 0;

  vlines = Val_int(0);
  if (len == 0) {
    vempty = caml_alloc(0, 0);
    CAMLreturn(vempty);
  }

  UniChar *u16 = NULL;
  CFIndex *idx = NULL;
  CFIndex n16 = lui_utf8_to_utf16(Bytes_val(vstr), len, &u16, &idx);

  CFStringRef str = NULL;
  CFMutableAttributedStringRef attrstr = NULL;
  CFDictionaryRef attrs = NULL;
  CTTypesetterRef ts = NULL;
  CTLineRef line = NULL;

  @autoreleasepool {
    lui_init_para_styles();

    str = CFStringCreateWithCharacters(NULL, u16, n16);
    const void *akeys[] = { kCTFontAttributeName,
                            kCTParagraphStyleAttributeName };
    const void *avals[] = { Lui_font_val(vfont),
                            lui_para_styles[rtl ? 1 : 0] };
    attrs = CFDictionaryCreate(NULL, akeys, avals, 2,
                               &kCFTypeDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks);
    if (str == NULL || attrs == NULL) goto done;
    attrstr = CFAttributedStringCreateMutable(NULL, (CFIndex)n16);
    if (attrstr == NULL) goto done;
    CFAttributedStringReplaceString(attrstr, CFRangeMake(0, 0), str);
    CFAttributedStringSetAttributes(attrstr, CFRangeMake(0, n16), attrs,
                                  false);

    /* Per-range attributes: byte ranges land on UTF-16 unit ranges
       through the decode map. */
    mlsize_t nspans = Wosize_val(vspans);
    for (mlsize_t i = 0; i < nspans; i++) {
      value vspan = Field(vspans, i);
      CFIndex a16 = lui_u16_of_byte(idx, n16,
                                    (CFIndex)Long_val(Field(vspan, 0)));
      CFIndex b16 = lui_u16_of_byte(idx, n16,
                                    (CFIndex)Long_val(Field(vspan, 1)));
      if (b16 <= a16) continue;
      CFRange r = CFRangeMake(a16, b16 - a16);

      value vf = Field(vspan, 2);
      if (vf != Val_int(0)) {
        CFAttributedStringSetAttribute(
            attrstr, r, kCTFontAttributeName,
            Lui_font_val(Field(vf, 0)));
      }
      value vc = Field(vspan, 3);
      if (vc != Val_int(0)) {
        intnat c = Long_val(Field(vc, 0));
        CGFloat comps[4] = { (CGFloat)((c >> 24) & 0xFF) / 255.,
                             (CGFloat)((c >> 16) & 0xFF) / 255.,
                             (CGFloat)((c >> 8) & 0xFF) / 255.,
                             (CGFloat)(c & 0xFF) / 255. };
        CGColorRef col = CGColorCreate(lui_srgb(), comps);
        if (col != NULL) {
          CFAttributedStringSetAttribute(
              attrstr, r, kCTForegroundColorAttributeName, col);
          CFRelease(col);
        }
      }
      double kern = Double_val(Field(vspan, 4));
      if (kern != 0.) {
        CFNumberRef kn =
          CFNumberCreate(NULL, kCFNumberDoubleType, &kern);
        if (kn != NULL) {
          CFAttributedStringSetAttribute(attrstr, r,
                                         kCTKernAttributeName, kn);
          CFRelease(kn);
        }
      }
      int under = (int)Long_val(Field(vspan, 5));
      if (under != 0) {
        CFNumberRef un =
          CFNumberCreate(NULL, kCFNumberIntType, &under);
        if (un != NULL) {
          CFAttributedStringSetAttribute(attrstr, r,
                                         kCTUnderlineStyleAttributeName,
                                         un);
          CFRelease(un);
        }
      }
    }

    ts = CTTypesetterCreateWithAttributedString(attrstr);
    if (ts == NULL) goto done;

    CFIndex start = 0;
    while (start < n16) {
      CFIndex count = n16 - start;
      if (width > 0) {
        count = CTTypesetterSuggestLineBreak(ts, start, width);
        if (count < 1) count = 1;
      }
      line = CTTypesetterCreateLine(ts, CFRangeMake(start, count));
      if (line == NULL) break;

      vline = lui_emit_line(line, idx, n16, base);
      vcons = caml_alloc(2, 0);
      Store_field(vcons, 0, vline);
      Store_field(vcons, 1, vlines);
      vlines = vcons;
      nlines++;

      CFRelease(line);
      line = NULL;
      start += count;
    }
  } /* autoreleasepool */

done:
  if (str != NULL) CFRelease(str);
  if (attrs != NULL) CFRelease(attrs);
  if (attrstr != NULL) CFRelease(attrstr);
  if (ts != NULL) CFRelease(ts);
  if (line != NULL) CFRelease(line);
  free(u16);
  free(idx);

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

CAMLprim value lui_ct_shape_spans_byte(value *argv, int argn)
{
  (void)argn;
  return lui_ct_shape_spans(argv[0], argv[1], argv[2], argv[3],
                            argv[4], argv[5]);
}

/* graphemes : string -> int array — the byte offsets where composed
   character sequences start or end, ending at the string's length. */
CAMLprim value lui_ct_graphemes(value vstr)
{
  CAMLparam1(vstr);
  CAMLlocal1(vbounds);
  CFIndex len = (CFIndex)caml_string_length(vstr);
  UniChar *u16 = NULL;
  CFIndex *idx = NULL;
  CFIndex n16 = lui_utf8_to_utf16(Bytes_val(vstr), len, &u16, &idx);
  CFStringRef str = NULL;
  CFIndex *bounds =
    malloc(sizeof(CFIndex) * (size_t)(n16 + 2));
  if (bounds == NULL) {
    free(u16);
    free(idx);
    caml_failwith("lui_text: out of memory");
  }
  int k = 0;
  bounds[k++] = 0;
  str = CFStringCreateWithCharacters(NULL, u16, n16);
  if (str != NULL) {
    CFIndex p = 0;
    while (p < n16) {
      CFRange r = CFStringGetRangeOfComposedCharactersAtIndex(str, p);
      if (r.length <= 0) break;
      p = r.location + r.length;
      bounds[k++] = (CFIndex)lui_byte_of(idx, p, n16);
    }
  }
  vbounds = caml_alloc((mlsize_t)k, 0);
  for (int i = 0; i < k; i++)
    Store_field(vbounds, i, Val_int(bounds[i]));
  if (str != NULL) CFRelease(str);
  free(u16);
  free(idx);
  free(bounds);
  CAMLreturn(vbounds);
}

/* truncate : font -> utf8 -> width -> mode -> rtl -> line array
   mode 0 end, 1 start, 2 middle; the ellipsis token glyphs report a
   cluster clamped to the string's end. */
CAMLprim value lui_ct_truncate(value vfont, value vstr, value vwidth,
                               value vmode, value vrtl)
{
  CAMLparam5(vfont, vstr, vwidth, vmode, vrtl);
  CAMLlocal2(vout, vline);
  CFIndex len = (CFIndex)caml_string_length(vstr);
  double width = Double_val(vwidth);
  int mode = (int)Long_val(vmode);
  int rtl = Bool_val(vrtl);

  UniChar *u16 = NULL;
  CFIndex *idx = NULL;
  CFIndex n16 = lui_utf8_to_utf16(Bytes_val(vstr), len, &u16, &idx);

  CFStringRef str = NULL;
  CFAttributedStringRef attrstr = NULL;
  CFDictionaryRef attrs = NULL;
  CTTypesetterRef ts = NULL;
  CTLineRef full = NULL, truncd = NULL;
  vout = caml_alloc(0, 0);

  @autoreleasepool {
    lui_init_para_styles();

    str = CFStringCreateWithCharacters(NULL, u16, n16);
    const void *akeys[] = { kCTFontAttributeName,
                            kCTParagraphStyleAttributeName };
    const void *avals[] = { Lui_font_val(vfont),
                            lui_para_styles[rtl ? 1 : 0] };
    attrs = CFDictionaryCreate(NULL, akeys, avals, 2,
                               &kCFTypeDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks);
    if (str == NULL || attrs == NULL) goto done;
    attrstr = CFAttributedStringCreate(NULL, str, attrs);
    if (attrstr == NULL) goto done;
    ts = CTTypesetterCreateWithAttributedString(attrstr);
    if (ts == NULL) goto done;
    full = CTTypesetterCreateLine(ts, CFRangeMake(0, n16));
    if (full == NULL) goto done;

    CTLineTruncationType tt = kCTLineTruncationEnd;
    if (mode == 1) tt = kCTLineTruncationStart;
    else if (mode == 2) tt = kCTLineTruncationMiddle;
    truncd = CTLineCreateTruncatedLine(full, width, tt, NULL);
    if (truncd == NULL) goto done;

    vline = lui_emit_line(truncd, idx, n16, 0);
    vout = caml_alloc(1, 0);
    Store_field(vout, 0, vline);
  } /* autoreleasepool */

done:
  if (str != NULL) CFRelease(str);
  if (attrs != NULL) CFRelease(attrs);
  if (attrstr != NULL) CFRelease(attrstr);
  if (ts != NULL) CFRelease(ts);
  if (full != NULL) CFRelease(full);
  if (truncd != NULL) CFRelease(truncd);
  free(u16);
  free(idx);
  CAMLreturn(vout);
}

/* ---------------------------------------------------------- rasterize */

static CGColorSpaceRef lui_srgb(void)
{
  static CGColorSpaceRef cs = NULL;
  if (cs == NULL) {
#ifdef kCGColorSpaceSRGB
    cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
#endif
    if (cs == NULL) cs = CGColorSpaceCreateDeviceRGB();
  }
  return cs;
}

/* sRGB gray for a relative luminance: the fill the context rasterizes
   mask glyphs with, which decides how much font smoothing thickens. */
static double lui_shade_gray(double shade)
{
  if (shade <= 0.0031308) return shade * 12.92;
  return 1.055 * pow(shade, 1.0 / 2.4) - 0.055;
}

/* rasterize : font -> glyph id -> scale -> dx -> shade -> bitmap option
   A bitmap is (left, top, w, h, color, bytes): the pixel box relative to
   the glyph's origin, and coverage (1 byte per pixel) or premultiplied
   BGRA (4 bytes per pixel) rows, top first. */
CAMLprim value lui_ct_rasterize(value vfont, value vid, value vscale,
                                value vdx, value vshade)
{
  CAMLparam5(vfont, vid, vscale, vdx, vshade);
  CAMLlocal3(vres, vbytes, vtup);
  CTFontRef font = Lui_font_val(vfont);
  CGGlyph g = (CGGlyph)Int_val(vid);
  double s = Double_val(vscale);
  double dx = Double_val(vdx);
  double shade = Double_val(vshade);

  CGRect r = CGRectZero;
  CTFontGetBoundingRectsForGlyphs(font, kCTFontOrientationDefault, &g,
                                  &r, 1);
  if (r.size.width <= 0 || r.size.height <= 0) CAMLreturn(Val_int(0));

  CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(font);
  int color = (traits & kCTFontTraitColorGlyphs) != 0;
  /* Font smoothing spreads a mask glyph up to a pixel further. */
  int smooth = !color && shade > 0.0;
  int pad = smooth ? 2 : 1;

  /* Core Graphics y goes up: the box from r.y to r.y+r.h above the
     baseline is from -(r.y+r.h) to -r.y below it. */
  int left = (int)floor(r.origin.x * s + dx) - pad;
  int right = (int)ceil((r.origin.x + r.size.width) * s + dx) + pad;
  int top = (int)floor(-(r.origin.y + r.size.height) * s) - pad;
  int bottom = (int)ceil(-r.origin.y * s) + pad;
  int w = right - left;
  int h = bottom - top;
  if (w <= 0 || h <= 0 || w > 2048 || h > 2048) CAMLreturn(Val_int(0));

  size_t bpp = color ? 4 : 1;
  vbytes = caml_alloc_string((mlsize_t)(w * h * bpp));
  memset(Bytes_val(vbytes), 0, (size_t)(w * h * bpp));

  CGContextRef ctx;
  if (color) {
    ctx = CGBitmapContextCreate(Bytes_val(vbytes), (size_t)w, (size_t)h, 8,
                                (size_t)(4 * w), lui_srgb(),
                                kCGImageAlphaPremultipliedFirst |
                                kCGBitmapByteOrder32Little);
  } else {
    ctx = CGBitmapContextCreate(Bytes_val(vbytes), (size_t)w, (size_t)h, 8,
                                (size_t)w, NULL,
                                (CGBitmapInfo)kCGImageAlphaOnly);
  }
  if (ctx == NULL) CAMLreturn(Val_int(0));

  CGContextSetShouldAntialias(ctx, true);
  CGContextSetShouldSmoothFonts(ctx, color ? false : smooth);
  CGContextSetAllowsFontSubpixelPositioning(ctx, true);
  CGContextSetShouldSubpixelPositionFonts(ctx, true);
  CGContextSetAllowsFontSubpixelQuantization(ctx, false);
  CGContextSetShouldSubpixelQuantizeFonts(ctx, false);
  double gray = smooth ? lui_shade_gray(shade) : 0.0;
  CGContextSetRGBFillColor(ctx, gray, gray, gray, 1.0);
  CGContextScaleCTM(ctx, s, s);
  /* The bitmap's rows go from its top; the context's origin is at its
     bottom left and the baseline sits [bottom] pixels above it. */
  CGPoint pos = CGPointMake((dx - left) / s, bottom / s);
  CTFontDrawGlyphs(font, &g, &pos, 1, ctx);
  CGContextRelease(ctx);

  vtup = caml_alloc(6, 0);
  Store_field(vtup, 0, Val_int(left));
  Store_field(vtup, 1, Val_int(top));
  Store_field(vtup, 2, Val_int(w));
  Store_field(vtup, 3, Val_int(h));
  Store_field(vtup, 4, Val_bool(color));
  Store_field(vtup, 5, vbytes);
  vres = caml_alloc(1, 0);
  Store_field(vres, 0, vtup);
  CAMLreturn(vres);
}

#else /* !__APPLE__ */

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
#include <caml/mlvalues.h>
#include <caml/fail.h>

static value unsupported(void) {
  caml_failwith("lui_text: this backend requires macOS");
  return Val_unit;
}

CAMLprim value lui_ct_named(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_ct_system(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_ct_cascade(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d; return unsupported(); }
CAMLprim value lui_ct_fallback(value a, value b) {
  (void)a; (void)b; return unsupported(); }
CAMLprim value lui_ct_metrics(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_ct_is_color(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_ct_family(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_ct_shape(value a, value b, value c, value d, value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }
CAMLprim value lui_ct_rasterize(value a, value b, value c, value d,
                                value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }
CAMLprim value lui_ct_shape_spans(value a, value b, value c, value d,
                                  value e, value f) {
  (void)a; (void)b; (void)c; (void)d; (void)e; (void)f;
  return unsupported(); }
CAMLprim value lui_ct_shape_spans_byte(value *argv, int argn) {
  (void)argv; (void)argn; return unsupported(); }
CAMLprim value lui_ct_graphemes(value a) {
  (void)a; return unsupported(); }
CAMLprim value lui_ct_truncate(value a, value b, value c, value d,
                               value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e; return unsupported(); }

#endif /* __APPLE__ */
