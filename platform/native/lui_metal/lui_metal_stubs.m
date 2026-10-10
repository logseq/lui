/* The Metal renderer's Objective-C side. Each Metal object the OCaml
   side uses (context, library, pipeline state, texture) is boxed in a
   custom block holding a CFRetained pointer, so OCaml values stay small
   and release explicitly.

   Compiled as Objective-C (see the dune file) for ARC and the Metal
   frameworks. On non-Apple platforms every external fails fast, the
   same convention the other platform modules use, so the library still
   builds everywhere. */

#if defined(__APPLE__)

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import <SDL_metal.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/bigarray.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#define MTD(...) do { if (getenv("LUI_METAL_DEBUG")) { fprintf(stderr, __VA_ARGS__); fflush(stderr); } } while (0)

/* ------------------------------------------------------------------ */
/* context                                                             */

/* One renderer: the device, its queue, the nearest sampler every draw
   shares, the target texture being drawn (owned for offscreen, or the
   size of the window's layer), and the two small textures backdrop
   passes ping-pong between. For a window, sdl_view/layer are the
   SDL-created Metal view and its CAMetalLayer. */
@interface LuiMtlCtx : NSObject {
@public
    id<MTLDevice> dev;
    id<MTLCommandQueue> queue;
    id<MTLSamplerState> smp;
    CAMetalLayer *layer;
    SDL_MetalView sdl_view;
    id<MTLTexture> target;
    id<MTLTexture> bd0;
    id<MTLTexture> bd1;
    int tw, th;   /* target pixel size */
    int bw, bh;   /* backdrop textures' current size */
}
@end

@implementation LuiMtlCtx
- (void)dealloc {
    if (sdl_view) SDL_Metal_DestroyView(sdl_view);
}
@end

/* ------------------------------------------------------------------ */
/* boxing                                                              */

struct lui_ref { void *o; };
#define Lui_ref_val(v) (((struct lui_ref *)Data_custom_val(v))->o)

static void lui_ref_finalize(value v)
{
    void *p = Lui_ref_val(v);
    Lui_ref_val(v) = NULL;
    if (p) CFRelease(p);
}

static struct custom_operations lui_ref_ops = {
    "lui_metal.ref",
    lui_ref_finalize,
    custom_compare_default,
    custom_hash_default,
    custom_serialize_default,
    custom_deserialize_default,
    custom_compare_ext_default,
    custom_fixed_length_default
};

static value lui_box(void *o)
{
    MTD("box: %p ops=%p\n", o, &lui_ref_ops);
    value v = caml_alloc_custom(&lui_ref_ops, sizeof(struct lui_ref), 0, 1);
    MTD("box: v=%lx\n", (unsigned long)v);
    Lui_ref_val(v) = o;
    MTD("box: done\n");
    return v;
}

/* Result constructors: Ok x = tag 0, Error e = tag 1 (OCaml result). */
static value ok_box(void *o)
{
    CAMLparam0();
    CAMLlocal1(r);
    r = caml_alloc(1, 0);
    Store_field(r, 0, lui_box(o));
    CAMLreturn(r);
}

static value err_str(const char *s)
{
    CAMLparam0();
    CAMLlocal1(r);
    r = caml_alloc(1, 1);
    Store_field(r, 0, caml_copy_string(s ? s : "unknown error"));
    CAMLreturn(r);
}

static value err_ns(NSError *e)
{
    return err_str(e ? [[e localizedDescription] UTF8String] : "Metal error");
}

#define UNBOX(v) ((__bridge id)Lui_ref_val(v))

static id<MTLSamplerState> make_sampler(id<MTLDevice> dev)
{
    MTLSamplerDescriptor *sd = [MTLSamplerDescriptor new];
    /* Bilinear like every texture in the GL frontend. */
    sd.minFilter = MTLSamplerMinMagFilterLinear;
    sd.magFilter = MTLSamplerMinMagFilterLinear;
    sd.sAddressMode = MTLSamplerAddressModeClampToEdge;
    sd.tAddressMode = MTLSamplerAddressModeClampToEdge;
    return [dev newSamplerStateWithDescriptor:sd];
}

static id<MTLTexture> make_target(id<MTLDevice> dev, NSUInteger w, NSUInteger h)
{
    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                         width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModePrivate;
    return [dev newTextureWithDescriptor:td];
}

static LuiMtlCtx *new_ctx(id<MTLDevice> dev, int w, int h)
{
    LuiMtlCtx *m = [LuiMtlCtx new];
    m->dev = dev;
    m->queue = [dev newCommandQueue];
    m->smp = make_sampler(dev);
    m->target = make_target(dev, w, h);
    m->tw = w;
    m->th = h;
    return m;
}

/* ------------------------------------------------------------------ */
/* externals                                                           */

CAMLprim value lui_metal_create_offscreen(value vw, value vh)
{
    CAMLparam2(vw, vh);
    int w = Int_val(vw), h = Int_val(vh);
    if (w <= 0 || h <= 0) CAMLreturn(err_str("invalid framebuffer size"));
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev) CAMLreturn(err_str("no Metal device"));
    MTD("offscreen: dev=%p\n", dev);
    LuiMtlCtx *m = new_ctx(dev, w, h);
    MTD("offscreen: ctx=%p target=%p queue=%p\n", m, m->target, m->queue);
    if (!m->target || !m->queue) CAMLreturn(err_str("Metal target creation failed"));
    CAMLreturn(ok_box((void *)CFBridgingRetain(m)));
}

CAMLprim value lui_metal_create_layer(value vwin)
{
    CAMLparam1(vwin);
    SDL_Window *win = (SDL_Window *)Nativeint_val(vwin);
    if (!win) CAMLreturn(err_str("null SDL window"));
    SDL_MetalView sv = SDL_Metal_CreateView(win);
    if (!sv) CAMLreturn(err_str("SDL_Metal_CreateView failed"));
    CAMetalLayer *layer = (__bridge CAMetalLayer *)SDL_Metal_GetLayer(sv);
    id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
    if (!dev || !layer) {
        if (sv) SDL_Metal_DestroyView(sv);
        CAMLreturn(err_str("no Metal device/layer"));
    }
    layer.device = dev;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = YES;
    CGSize sz = layer.drawableSize;
    int w = sz.width > 1 ? (int)sz.width : 1;
    int h = sz.height > 1 ? (int)sz.height : 1;
    LuiMtlCtx *m = new_ctx(dev, w, h);
    m->layer = layer;
    m->sdl_view = sv;
    CAMLreturn(ok_box((void *)CFBridgingRetain(m)));
}

CAMLprim value lui_metal_compile(value vctx, value vsrc)
{
    CAMLparam2(vctx, vsrc);
    LuiMtlCtx *m = (__bridge LuiMtlCtx *)Lui_ref_val(vctx);
    if (!m) caml_failwith("lui_metal: released context");
    @autoreleasepool {
        NSString *src = [[NSString alloc] initWithBytes:String_val(vsrc)
                                               length:caml_string_length(vsrc)
                                             encoding:NSUTF8StringEncoding];
        MTLCompileOptions *o = [MTLCompileOptions new];
        o.mathMode = MTLMathModeSafe;
        NSError *e = nil;
        MTD("compile: src %u bytes\n", (unsigned)[src length]);
        id<MTLLibrary> lib = [m->dev newLibraryWithSource:src options:o error:&e];
        MTD("compile: lib=%p err=%p\n", lib, e);
        if (!lib) CAMLreturn(err_ns(e));
        CAMLreturn(ok_box((void *)CFBridgingRetain(lib)));
    }
    CAMLreturn(err_str("unreachable"));
}

/* Blend modes, matching the GL evaluator's two pipeline variants:
   0: over with dual-source (src ONE, dst ONE_MINUS_SRC1_COLOR/ALPHA)
   1: over single-source (src ONE, dst ONE_MINUS_SRC_ALPHA)
   2: hole batch, dual-source (src ZERO)
   3: hole batch, single-source (src ZERO)
   4: pass shaders, no blending */
static void set_blend(MTLRenderPipelineColorAttachmentDescriptor *ca, int blend)
{
    switch (blend) {
    case 0:
        ca.blendingEnabled = YES;
        ca.rgbBlendOperation = MTLBlendOperationAdd;
        ca.alphaBlendOperation = MTLBlendOperationAdd;
        ca.sourceRGBBlendFactor = MTLBlendFactorOne;
        ca.destinationRGBBlendFactor = MTLBlendFactorOneMinusSource1Color;
        ca.sourceAlphaBlendFactor = MTLBlendFactorOne;
        ca.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSource1Alpha;
        break;
    case 1:
        ca.blendingEnabled = YES;
        ca.rgbBlendOperation = MTLBlendOperationAdd;
        ca.alphaBlendOperation = MTLBlendOperationAdd;
        ca.sourceRGBBlendFactor = MTLBlendFactorOne;
        ca.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        ca.sourceAlphaBlendFactor = MTLBlendFactorOne;
        ca.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        break;
    case 2:
        ca.blendingEnabled = YES;
        ca.rgbBlendOperation = MTLBlendOperationAdd;
        ca.alphaBlendOperation = MTLBlendOperationAdd;
        ca.sourceRGBBlendFactor = MTLBlendFactorZero;
        ca.destinationRGBBlendFactor = MTLBlendFactorOneMinusSource1Color;
        ca.sourceAlphaBlendFactor = MTLBlendFactorZero;
        ca.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSource1Alpha;
        break;
    case 3:
        ca.blendingEnabled = YES;
        ca.rgbBlendOperation = MTLBlendOperationAdd;
        ca.alphaBlendOperation = MTLBlendOperationAdd;
        ca.sourceRGBBlendFactor = MTLBlendFactorZero;
        ca.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        ca.sourceAlphaBlendFactor = MTLBlendFactorZero;
        ca.destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
        break;
    default:
        ca.blendingEnabled = NO;
    }
}

CAMLprim value lui_metal_pipeline(value vctx, value vlib, value vvert,
                                  value vfrag, value vblend)
{
    CAMLparam5(vctx, vlib, vvert, vfrag, vblend);
    LuiMtlCtx *m = (__bridge LuiMtlCtx *)Lui_ref_val(vctx);
    id<MTLLibrary> lib = UNBOX(vlib);
    if (!m || !lib) caml_failwith("lui_metal: released object");
    @autoreleasepool {
        NSString *vn = [[NSString alloc] initWithBytes:String_val(vvert)
                                              length:caml_string_length(vvert)
                                            encoding:NSUTF8StringEncoding];
        NSString *fn = [[NSString alloc] initWithBytes:String_val(vfrag)
                                              length:caml_string_length(vfrag)
                                            encoding:NSUTF8StringEncoding];
        id<MTLFunction> vf = [lib newFunctionWithName:vn];
        id<MTLFunction> ff = [lib newFunctionWithName:fn];
        if (!vf || !ff)
            CAMLreturn(err_str("shader entry point not found"));
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = vf;
        pd.fragmentFunction = ff;
        MTLRenderPipelineColorAttachmentDescriptor *ca = pd.colorAttachments[0];
        ca.pixelFormat = MTLPixelFormatBGRA8Unorm;
        set_blend(ca, Int_val(vblend));
        NSError *e = nil;
        MTD("pipeline: vf=%p ff=%p blend=%d\n", vf, ff, Int_val(vblend));
        id<MTLRenderPipelineState> ps =
            [m->dev newRenderPipelineStateWithDescriptor:pd error:&e];
        MTD("pipeline: ps=%p err=%p\n", ps, e);
        if (!ps) CAMLreturn(err_ns(e));
        CAMLreturn(ok_box((void *)CFBridgingRetain(ps)));
    }
    CAMLreturn(err_str("unreachable"));
}

/* fmt: 0 = R8 (mask atlas), 1 = RGBA8 premultiplied (color atlas,
   images), 2 = BGRA8 (renderable). */
CAMLprim value lui_metal_texture(value vctx, value vw, value vh, value vfmt)
{
    CAMLparam4(vctx, vw, vh, vfmt);
    LuiMtlCtx *m = (__bridge LuiMtlCtx *)Lui_ref_val(vctx);
    if (!m) caml_failwith("lui_metal: released context");
    NSUInteger w = Int_val(vw), h = Int_val(vh);
    if (!w || !h || w > 16384 || h > 16384)
        caml_failwith("lui_metal: invalid texture size");
    @autoreleasepool {
        MTLPixelFormat pf;
        MTLTextureUsage usage;
        switch (Int_val(vfmt)) {
        case 0: pf = MTLPixelFormatR8Unorm; usage = MTLTextureUsageShaderRead; break;
        case 1: pf = MTLPixelFormatRGBA8Unorm; usage = MTLTextureUsageShaderRead; break;
        default: pf = MTLPixelFormatBGRA8Unorm;
                 usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget; break;
        }
        MTLTextureDescriptor *td =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:pf
                                                             width:w height:h mipmapped:NO];
        td.usage = usage;
        td.storageMode = MTLStorageModeShared;
        MTD("texture: fmt %d %lux%lu\n", (int)Int_val(vfmt), (unsigned long)w, (unsigned long)h);
        id<MTLTexture> t = [m->dev newTextureWithDescriptor:td];
        MTD("texture: %p\n", t);
        if (!t) caml_failwith("lui_metal: texture creation failed");
        CAMLreturn(lui_box((void *)CFBridgingRetain(t)));
    }
    CAMLreturn(Val_unit);
}

/* upload(t, (x, y, w, h), src, off, bpr): the rect as one tuple keeps
   the external at five arguments. */
CAMLprim value lui_metal_upload(value vtex, value vrect, value vsrc,
                                value voff, value vbpr)
{
    CAMLparam5(vtex, vrect, vsrc, voff, vbpr);
    id<MTLTexture> t = UNBOX(vtex);
    if (!t) caml_failwith("lui_metal: released texture");
    NSUInteger x = Int_val(Field(vrect, 0)), y = Int_val(Field(vrect, 1));
    NSUInteger w = Int_val(Field(vrect, 2)), h = Int_val(Field(vrect, 3));
    const char *src = (const char *)Bytes_val(vsrc) + Int_val(voff);
    NSUInteger bpr = Int_val(vbpr);
    /* Metal reads bpr*(h-1) + w*bpp bytes: the last row stops at its
       own pixels, so a region reaching the atlas's bottom edge still
       fits. */
    NSUInteger bpp = t.pixelFormat == MTLPixelFormatR8Unorm ? 1 : 4;
    if ((intnat)(Int_val(voff) + bpr * (h ? h - 1 : 0) + w * bpp)
        > caml_string_length(vsrc))
        caml_failwith("lui_metal: upload exceeds source");
    MTD("upload: tex=%p %lux%lu at %lu,%lu bpr %lu\n", t, (unsigned long)w, (unsigned long)h, (unsigned long)x, (unsigned long)y, (unsigned long)bpr);
    [t replaceRegion:MTLRegionMake2D(x, y, w, h) mipmapLevel:0
           withBytes:src bytesPerRow:bpr];
    MTD("upload: done\n");
    CAMLreturn(Val_unit);
}

/* The req record's field order is fixed with the OCaml side:
   0 width, 1 height, 2 clear (4 floats), 3 insts (float32 bigarray),
   4 draws, 5 mask, 6 color, 7 empty, 8 pipe_down, 9 pipe_blur.
   Each draw: 0 scissor (l,t,r,b ints), 1 first, 2 count, 3 pipe,
   4 image option, 5 backdrop option. A backdrop option carries:
   0 bx0, 1 by0, 2 bx1, 3 by1, 4 down, 5 radius, 6 sigma, 7 bw, 8 bh. */

static void ensure_bd(LuiMtlCtx *m, int w, int h)
{
    if (w <= 0 || h <= 0) return;
    if (m->bd0 && m->bw >= w && m->bh >= h) return;
    int nw = w > m->bw ? w : m->bw;
    int nh = h > m->bh ? h : m->bh;
    MTLTextureDescriptor *td =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                         width:nw height:nh mipmapped:NO];
    td.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    td.storageMode = MTLStorageModePrivate;
    m->bd0 = [m->dev newTextureWithDescriptor:td];
    m->bd1 = [m->dev newTextureWithDescriptor:td];
    m->bw = nw;
    m->bh = nh;
}

struct down_args { int ox, oy, lx, ly, down, pad; };
struct blur_args { int lx, ly, dx, dy, radius; float sigma; int pad0, pad1; };

static void encode_pass(id<MTLRenderCommandEncoder> enc,
                        id<MTLRenderPipelineState> pipe,
                        id<MTLTexture> src,
                        const void *args, NSUInteger argslen,
                        NSUInteger sw, NSUInteger sh)
{
    [enc setRenderPipelineState:pipe];
    [enc setFragmentTexture:src atIndex:0];
    [enc setFragmentBytes:args length:argslen atIndex:0];
    MTLViewport vp = { 0, 0, (double)sw, (double)sh, 0, 1 };
    [enc setViewport:vp];
    MTLScissorRect sc = { 0, 0, sw, sh };
    [enc setScissorRect:sc];
    [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
            vertexStart:0 vertexCount:4 instanceCount:1 baseInstance:0];
}

CAMLprim value lui_metal_render(value vctx, value vreq)
{
    CAMLparam2(vctx, vreq);
    LuiMtlCtx *m = (__bridge LuiMtlCtx *)Lui_ref_val(vctx);
    if (!m) caml_failwith("lui_metal: released context");
    @autoreleasepool {
        int w = Int_val(Field(vreq, 0)), h = Int_val(Field(vreq, 1));
        value vc = Field(vreq, 2);
        float cr = Double_val(Field(vc, 0)), cg = Double_val(Field(vc, 1));
        float cb_ = Double_val(Field(vc, 2)), ca = Double_val(Field(vc, 3));
        value vinsts = Field(vreq, 3);
        float *insts = Caml_ba_data_val(vinsts);
        NSUInteger ilen = (NSUInteger)Caml_ba_array_val(vinsts)->dim[0] * sizeof(float);
        value vdraws = Field(vreq, 4);
        id<MTLTexture> mask = UNBOX(Field(vreq, 5));
        id<MTLTexture> color = UNBOX(Field(vreq, 6));
        id<MTLTexture> empty = UNBOX(Field(vreq, 7));
        id<MTLRenderPipelineState> pdown = UNBOX(Field(vreq, 8));
        id<MTLRenderPipelineState> pblur = UNBOX(Field(vreq, 9));
        mlsize_t n = Wosize_val(vdraws);

        int nbw = 0, nbh = 0;
        for (mlsize_t i = 0; i < n; i++) {
            value vbd = Field(Field(vdraws, i), 5);
            if (Is_block(vbd)) {
                value vb = Field(vbd, 0);
                nbw = MAX(nbw, Int_val(Field(vb, 7)));
                nbh = MAX(nbh, Int_val(Field(vb, 8)));
            }
        }
        ensure_bd(m, nbw, nbh);

        id<MTLBuffer> ibuf = nil;
        if (ilen)
            ibuf = [m->dev newBufferWithBytes:insts length:ilen
                                      options:MTLResourceStorageModeShared];

        float us[2] = { (float)w, (float)h };
        MTD("render: draws %ld insts %lu\n", (long)n, (unsigned long)ilen);
        id<MTLCommandBuffer> cmd = [m->queue commandBuffer];
        id<MTLRenderCommandEncoder> enc = nil;
        BOOL cleared = NO;

        for (mlsize_t i = 0; i < n; i++) {
            value d = Field(vdraws, i);
            value sc = Field(d, 0);
            long sl = Int_val(Field(sc, 0)), st = Int_val(Field(sc, 1));
            long sr = Int_val(Field(sc, 2)), sb = Int_val(Field(sc, 3));
            int first = Int_val(Field(d, 1)), count = Int_val(Field(d, 2));
            id<MTLRenderPipelineState> pipe = UNBOX(Field(d, 3));
            value vimg = Field(d, 4);
            id<MTLTexture> img = Is_block(vimg) ? UNBOX(Field(vimg, 0)) : empty;
            value vbd = Field(d, 5);
            if (count <= 0 || !pipe || sr <= sl || sb <= st) continue;

            if (Is_block(vbd) && m->bd0 && pdown && pblur) {
                /* An effect's backdrop: finish the frame pass so the
                   target can be sampled, then down + blur into bd0. */
                if (enc) { [enc endEncoding]; enc = nil; }
                value b = Field(vbd, 0);
                int bx0 = Int_val(Field(b, 0)), by0 = Int_val(Field(b, 1));
                int bx1 = Int_val(Field(b, 2)), by1 = Int_val(Field(b, 3));
                int bdown = Int_val(Field(b, 4)), brad = Int_val(Field(b, 5));
                float bsigma = Double_val(Field(b, 6));
                int btw = Int_val(Field(b, 7)), bth = Int_val(Field(b, 8));
                if (btw > 0 && bth > 0) {
                    MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                    rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
                    rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                    rp.colorAttachments[0].texture = m->bd0;
                    id<MTLRenderCommandEncoder> pe =
                        [cmd renderCommandEncoderWithDescriptor:rp];
                    struct down_args da = { bx0, by0, bx1 - 1, by1 - 1, bdown, 0 };
                    encode_pass(pe, pdown, m->target,
                                &da, sizeof(da), btw, bth);
                    [pe endEncoding];
                    if (brad > 0) {
                        struct blur_args ra = { btw - 1, bth - 1, 1, 0, brad, bsigma, 0, 0 };
                        rp.colorAttachments[0].texture = m->bd1;
                        pe = [cmd renderCommandEncoderWithDescriptor:rp];
                        encode_pass(pe, pblur, m->bd0,
                                    &ra, sizeof(ra), btw, bth);
                        [pe endEncoding];
                        ra.dx = 0; ra.dy = 1;
                        rp.colorAttachments[0].texture = m->bd0;
                        pe = [cmd renderCommandEncoderWithDescriptor:rp];
                        encode_pass(pe, pblur, m->bd1,
                                    &ra, sizeof(ra), btw, bth);
                        [pe endEncoding];
                    }
                }
            }
            if (!enc) {
                MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
                rp.colorAttachments[0].texture = m->target;
                rp.colorAttachments[0].loadAction =
                    cleared ? MTLLoadActionLoad : MTLLoadActionClear;
                rp.colorAttachments[0].clearColor =
                    MTLClearColorMake(cr, cg, cb_, ca);
                rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                enc = [cmd renderCommandEncoderWithDescriptor:rp];
                cleared = YES;
                MTLViewport vp = { 0, 0, (double)w, (double)h, 0, 1 };
                [enc setViewport:vp];
                if (ibuf) [enc setVertexBuffer:ibuf offset:0 atIndex:0];
                [enc setVertexBytes:us length:sizeof(us) atIndex:1];
                [enc setFragmentTexture:(mask ? mask : empty) atIndex:0];
                [enc setFragmentTexture:(color ? color : empty) atIndex:1];
                [enc setFragmentSamplerState:m->smp atIndex:0];
            }
            [enc setFragmentTexture:(img ? img : empty) atIndex:2];
            [enc setFragmentTexture:(Is_block(vbd) ? m->bd0 : empty) atIndex:3];
            [enc setRenderPipelineState:pipe];
            MTLScissorRect sct = { (NSUInteger)sl, (NSUInteger)st,
                                   (NSUInteger)(sr - sl), (NSUInteger)(sb - st) };
            [enc setScissorRect:sct];
            [enc drawPrimitives:MTLPrimitiveTypeTriangleStrip
                    vertexStart:0 vertexCount:4
                 instanceCount:count baseInstance:first];
        }
        if (!cleared) {
            /* An empty frame still gets the clear color. */
            MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
            rp.colorAttachments[0].texture = m->target;
            rp.colorAttachments[0].loadAction = MTLLoadActionClear;
            rp.colorAttachments[0].clearColor = MTLClearColorMake(cr, cg, cb_, ca);
            rp.colorAttachments[0].storeAction = MTLStoreActionStore;
            enc = [cmd renderCommandEncoderWithDescriptor:rp];
            [enc endEncoding];
        } else if (enc) {
            [enc endEncoding];
        }
        MTD("render: committing\n");
        [cmd commit];
        [cmd waitUntilCompleted];
        MTD("render: done %ld\n", (long)cmd.status);
        if (cmd.status == MTLCommandBufferStatusError)
            caml_failwith([[cmd.error localizedDescription] UTF8String]);
    }
    CAMLreturn(Val_unit);
}

CAMLprim value lui_metal_read(value vctx, value vw, value vh)
{
    CAMLparam3(vctx, vw, vh);
    CAMLlocal1(out);
    LuiMtlCtx *m = (__bridge LuiMtlCtx *)Lui_ref_val(vctx);
    if (!m) caml_failwith("lui_metal: released context");
    NSUInteger w = Int_val(vw), h = Int_val(vh);
    if (!w || !h || (int)w > m->tw || (int)h > m->th)
        caml_failwith("lui_metal: read size exceeds target");
    @autoreleasepool {
        NSUInteger bpr = w * 4;
        MTD("read: %lux%lu\n", (unsigned long)w, (unsigned long)h);
        id<MTLBuffer> buf = [m->dev newBufferWithLength:bpr * h
                                              options:MTLResourceStorageModeShared];
        id<MTLCommandBuffer> cmd = [m->queue commandBuffer];
        id<MTLBlitCommandEncoder> blit = [cmd blitCommandEncoder];
        [blit copyFromTexture:m->target sourceSlice:0 sourceLevel:0
                  sourceOrigin:MTLOriginMake(0, 0, 0)
                    sourceSize:MTLSizeMake(w, h, 1)
                      toBuffer:buf destinationOffset:0
             destinationBytesPerRow:bpr destinationBytesPerImage:bpr * h];
        [blit endEncoding];
        [cmd commit];
        [cmd waitUntilCompleted];
        out = caml_alloc_string(bpr * h);
        memcpy(Bytes_val(out), buf.contents, bpr * h);
    }
    CAMLreturn(out);
}

CAMLprim value lui_metal_present(value vctx)
{
    CAMLparam1(vctx);
    LuiMtlCtx *m = (__bridge LuiMtlCtx *)Lui_ref_val(vctx);
    if (!m) caml_failwith("lui_metal: released context");
    @autoreleasepool {
        if (m->layer) {
            CGSize want = { m->tw, m->th };
            if (!CGSizeEqualToSize(m->layer.drawableSize, want))
                m->layer.drawableSize = want;
            id<CAMetalDrawable> dr = [m->layer nextDrawable];
            if (dr) {
                NSUInteger cw = MIN((NSUInteger)m->tw, dr.texture.width);
                NSUInteger ch = MIN((NSUInteger)m->th, dr.texture.height);
                id<MTLCommandBuffer> cmd = [m->queue commandBuffer];
                id<MTLBlitCommandEncoder> blit = [cmd blitCommandEncoder];
                [blit copyFromTexture:m->target sourceSlice:0 sourceLevel:0
                          sourceOrigin:MTLOriginMake(0, 0, 0)
                            sourceSize:MTLSizeMake(cw, ch, 1)
                           toTexture:dr.texture destinationSlice:0
                       destinationLevel:0
                      destinationOrigin:MTLOriginMake(0, 0, 0)];
                [blit endEncoding];
                [cmd presentDrawable:dr];
                [cmd commit];
            }
        }
    }
    CAMLreturn(Val_unit);
}

/* Release any boxed object from this module: drop the slot, let the
   finalizer release the pointer. A context's dealloc also removes its
   SDL view. */
CAMLprim value lui_metal_release(value v)
{
    CAMLparam1(v);
    void *p = Lui_ref_val(v);
    Lui_ref_val(v) = NULL;
    if (p) CFRelease(p);
    CAMLreturn(Val_unit);
}

#else /* !__APPLE__ */

#include <caml/mlvalues.h>
#include <caml/fail.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/bigarray.h>
#include <caml/memory.h>

#define NO_METAL() caml_failwith("lui_metal is only available on macOS")

CAMLprim value lui_metal_create_offscreen(value a, value b) { NO_METAL(); }
CAMLprim value lui_metal_create_layer(value a) { NO_METAL(); }
CAMLprim value lui_metal_compile(value a, value b) { NO_METAL(); }
CAMLprim value lui_metal_pipeline(value a, value b, value c, value d, value e) { NO_METAL(); }
CAMLprim value lui_metal_texture(value a, value b, value c, value d) { NO_METAL(); }
CAMLprim value lui_metal_upload(value a, value b, value c, value d, value e) { NO_METAL(); }
CAMLprim value lui_metal_render(value a, value b) { NO_METAL(); }
CAMLprim value lui_metal_read(value a, value b, value c) { NO_METAL(); }
CAMLprim value lui_metal_present(value a) { NO_METAL(); }
CAMLprim value lui_metal_release(value a) { NO_METAL(); }

#endif
