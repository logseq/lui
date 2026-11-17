/* The Direct3D 11 device of the native renderer: device and swapchain
   setup, shader compilation via D3DCompile, the dynamic instance
   buffer, draw state, backdrop passes and readback. On other systems
   every entry fails, so the library still builds. */
#if defined(_WIN32)

#define COBJMACROS
#include <windows.h>
#include <d3d11.h>
#include <d3dcompiler.h>
#include <dxgi1_2.h>
#include <stdio.h>
#include <string.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/memory.h>
#include <caml/bigarray.h>

/* {1 The context} */

typedef struct {
  ID3D11Texture2D *t;
  ID3D11ShaderResourceView *s;
  ID3D11RenderTargetView *r;
  int w, h;
} ltex;

typedef struct {
  int iid, ver, frame, w, h;
  ID3D11Texture2D *t;
  ID3D11ShaderResourceView *s;
} limg;

typedef struct {
  ID3D11Device *dev;
  ID3D11DeviceContext *ic;
  IDXGIFactory2 *factory;
  IDXGISwapChain1 *swap;
  ltex rt;                 /* the render target: the offscreen texture,
                              or the swapchain's back buffer */
  ID3D11Texture2D *staging;
  int staging_w, staging_h;
  int warp, hwnd;
  ID3D11VertexShader *vs;
  ID3D11PixelShader *ps;
  ID3D11InputLayout *layout;
  ID3D11BlendState *blend, *holeblend;
  ID3D11RasterizerState *rast;
  ID3D11SamplerState *samp;
  ID3D11Buffer *cb;        /* Globals: viewport size */
  ID3D11Buffer *pcb;       /* PassConstants */
  ID3D11Buffer *inst;      /* dynamic instance buffer */
  int instcap;
  ID3D11VertexShader *pvs;
  ID3D11PixelShader *downps, *blurps;
  ltex mask, color, grab, bd[2];
  limg *imgs; int nimg, aimg;
  ID3D11PixelShader **fx; int nfx, afx;
  char err[2048];
} lctx;

#define CTX(v) ((lctx *)Data_custom_val(v))

static void ltex_free(ltex *t) {
  if (t->s) ID3D11ShaderResourceView_Release(t->s);
  if (t->r) ID3D11RenderTargetView_Release(t->r);
  if (t->t) ID3D11Texture2D_Release(t->t);
  memset(t, 0, sizeof *t);
}

static void img_free(limg *i) {
  if (i->s) ID3D11ShaderResourceView_Release(i->s);
  if (i->t) ID3D11Texture2D_Release(i->t);
  memset(i, 0, sizeof *i);
}

static void ctx_free(lctx *c) {
  int i;
  if (c->staging) ID3D11Texture2D_Release(c->staging);
  if (c->imgs) {
    for (i = 0; i < c->nimg; i++) img_free(&c->imgs[i]);
    free(c->imgs);
  }
  if (c->fx) {
    for (i = 0; i < c->nfx; i++) ID3D11PixelShader_Release(c->fx[i]);
    free(c->fx);
  }
  ltex_free(&c->mask);
  ltex_free(&c->color);
  ltex_free(&c->grab);
  ltex_free(&c->bd[0]);
  ltex_free(&c->bd[1]);
  if (c->pvs) ID3D11VertexShader_Release(c->pvs);
  if (c->downps) ID3D11PixelShader_Release(c->downps);
  if (c->blurps) ID3D11PixelShader_Release(c->blurps);
  if (c->inst) ID3D11Buffer_Release(c->inst);
  if (c->cb) ID3D11Buffer_Release(c->cb);
  if (c->pcb) ID3D11Buffer_Release(c->pcb);
  if (c->samp) ID3D11SamplerState_Release(c->samp);
  if (c->rast) ID3D11RasterizerState_Release(c->rast);
  if (c->blend) ID3D11BlendState_Release(c->blend);
  if (c->holeblend) ID3D11BlendState_Release(c->holeblend);
  if (c->layout) ID3D11InputLayout_Release(c->layout);
  if (c->vs) ID3D11VertexShader_Release(c->vs);
  if (c->ps) ID3D11PixelShader_Release(c->ps);
  ltex_free(&c->rt);
  if (c->swap) IDXGISwapChain1_Release(c->swap);
  if (c->factory) IDXGIFactory2_Release(c->factory);
  if (c->ic) ID3D11DeviceContext_Release(c->ic);
  if (c->dev) ID3D11Device_Release(c->dev);
  memset(c, 0, sizeof *c);
}

static void ctx_finalize(value v) { ctx_free(CTX(v)); }

static struct custom_operations ctx_ops = {
  "lui_d3d11.ctx",
  ctx_finalize,
  custom_compare_default,
  custom_hash_default,
  custom_serialize_default,
  custom_deserialize_default,
  custom_compare_ext_default,
  custom_fixed_length_default
};

static void set_err(lctx *c, const char *what, HRESULT hr) {
  snprintf(c->err, sizeof c->err, "%s failed (0x%08lx)", what,
           (unsigned long)hr);
}

/* {1 Objects} */

static int compile(lctx *c, const char *src, const char *entry,
                   const char *target, ID3DBlob **out) {
  ID3DBlob *blob = NULL, *errb = NULL;
  HRESULT hr = D3DCompile(src, strlen(src), "lui.hlsl", NULL, NULL,
                          entry, target, D3DCOMPILE_OPTIMIZATION_LEVEL3, 0,
                          &blob, &errb);
  if (FAILED(hr)) {
    if (errb) {
      snprintf(c->err, sizeof c->err, "%s",
               (const char *)ID3D10Blob_GetBufferPointer(errb));
      ID3D10Blob_Release(errb);
    } else {
      set_err(c, "D3DCompile", hr);
    }
    return -1;
  }
  if (errb) ID3D10Blob_Release(errb);
  *out = blob;
  return 0;
}

static int mkdevice(lctx *c) {
  HRESULT hr;
  UINT flags = D3D11_CREATE_DEVICE_BGRA_SUPPORT;
  c->warp = 0;
  hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags,
                         NULL, 0, D3D11_SDK_VERSION, &c->dev, NULL, &c->ic);
  if (FAILED(hr)) {
    c->warp = 1;
    hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_WARP, NULL, flags,
                           NULL, 0, D3D11_SDK_VERSION, &c->dev, NULL, &c->ic);
  }
  if (FAILED(hr)) {
    set_err(c, "D3D11CreateDevice", hr);
    return -1;
  }
  return 0;
}

static int mktex(lctx *c, ltex *t, int w, int h, DXGI_FORMAT fmt,
                 UINT bind, const void *pix, int pitch) {
  D3D11_TEXTURE2D_DESC d;
  D3D11_SUBRESOURCE_DATA init, *ip = NULL;
  HRESULT hr;
  memset(&d, 0, sizeof d);
  d.Width = (UINT)w;
  d.Height = (UINT)h;
  d.MipLevels = 1;
  d.ArraySize = 1;
  d.Format = fmt;
  d.SampleDesc.Count = 1;
  d.Usage = D3D11_USAGE_DEFAULT;
  d.BindFlags = bind;
  if (pix) {
    init.pSysMem = pix;
    init.SysMemPitch = (UINT)pitch;
    init.SysMemSlicePitch = 0;
    ip = &init;
  }
  hr = ID3D11Device_CreateTexture2D(c->dev, &d, ip, &t->t);
  if (FAILED(hr)) {
    set_err(c, "CreateTexture2D", hr);
    return -1;
  }
  t->w = w;
  t->h = h;
  return 0;
}

static int mksrv(lctx *c, ltex *t) {
  HRESULT hr = ID3D11Device_CreateShaderResourceView(
      c->dev, (ID3D11Resource *)t->t, NULL, &t->s);
  if (FAILED(hr)) {
    set_err(c, "CreateShaderResourceView", hr);
    return -1;
  }
  return 0;
}

static int mkrtv(lctx *c, ltex *t) {
  HRESULT hr = ID3D11Device_CreateRenderTargetView(
      c->dev, (ID3D11Resource *)t->t, NULL, &t->r);
  if (FAILED(hr)) {
    set_err(c, "CreateRenderTargetView", hr);
    return -1;
  }
  return 0;
}

/* The fifteen float4 instance attributes, in the order the shader's
   Inst struct lists them (Lui_gpu's packed layout). */
static int makelayout(lctx *c, ID3DBlob *vsb) {
  static const char *names[] = {
    "RECT", "RADII", "INNER", "COLOR", "COLOR", "COLOR",
    "GRAD", "UV", "CLIP", "CLIPR", "PARAMS",
    "CLIPB", "CLIPBR", "CLIPC", "CLIPCR"
  };
  static const UINT idx[] = { 0, 0, 0, 0, 1, 2, 0, 0, 0, 0, 0,
                            0, 0, 0, 0 };
  D3D11_INPUT_ELEMENT_DESC el[15];
  HRESULT hr;
  int i;
  for (i = 0; i < 15; i++) {
    el[i].SemanticName = names[i];
    el[i].SemanticIndex = idx[i];
    el[i].Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    el[i].InputSlot = 0;
    el[i].AlignedByteOffset = 16 * (UINT)i;
    el[i].InputSlotClass = D3D11_INPUT_PER_INSTANCE_DATA;
    el[i].InstanceDataStepRate = 1;
  }
  hr = ID3D11Device_CreateInputLayout(
      c->dev, el, 15, ID3D10Blob_GetBufferPointer(vsb),
      ID3D10Blob_GetBufferSize(vsb), &c->layout);
  if (FAILED(hr)) {
    set_err(c, "CreateInputLayout", hr);
    return -1;
  }
  return 0;
}

/* The instance buffer feeds the fifteen attributes; draws point it at
   their batch's instances. It grows on demand, mapped for writing. */
static int grow_inst(lctx *c, int count) {
  D3D11_BUFFER_DESC d;
  HRESULT hr;
  int cap = c->instcap > 0 ? c->instcap : 1024;
  while (cap < count) cap += cap / 2;
  if (c->inst) ID3D11Buffer_Release(c->inst);
  memset(&d, 0, sizeof d);
  d.ByteWidth = (UINT)(cap * 240);
  d.Usage = D3D11_USAGE_DYNAMIC;
  d.BindFlags = D3D11_BIND_VERTEX_BUFFER;
  d.CPUAccessFlags = D3D11_CPU_ACCESS_WRITE;
  hr = ID3D11Device_CreateBuffer(c->dev, &d, NULL, &c->inst);
  if (FAILED(hr)) {
    set_err(c, "CreateBuffer(inst)", hr);
    return -1;
  }
  c->instcap = cap;
  return 0;
}

static int makecb(lctx *c, int bytes, ID3D11Buffer **out) {
  D3D11_BUFFER_DESC d;
  HRESULT hr;
  memset(&d, 0, sizeof d);
  d.ByteWidth = (UINT)bytes;
  d.Usage = D3D11_USAGE_DEFAULT;
  d.BindFlags = D3D11_BIND_CONSTANT_BUFFER;
  hr = ID3D11Device_CreateBuffer(c->dev, &d, NULL, out);
  if (FAILED(hr)) {
    set_err(c, "CreateBuffer(cb)", hr);
    return -1;
  }
  return 0;
}

/* Blend premultiplied colors over what is drawn (dual-source), or for
   a hole, take their coverage away (source factor ZERO). */
static int makeblend(lctx *c, int hole, ID3D11BlendState **out) {
  D3D11_BLEND_DESC d;
  HRESULT hr;
  memset(&d, 0, sizeof d);
  d.RenderTarget[0].BlendEnable = TRUE;
  d.RenderTarget[0].SrcBlend = hole ? D3D11_BLEND_ZERO : D3D11_BLEND_ONE;
  d.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC1_COLOR;
  d.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;
  d.RenderTarget[0].SrcBlendAlpha =
    hole ? D3D11_BLEND_ZERO : D3D11_BLEND_ONE;
  d.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_INV_SRC1_ALPHA;
  d.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;
  d.RenderTarget[0].RenderTargetWriteMask = 0xf;
  hr = ID3D11Device_CreateBlendState(c->dev, &d, out);
  if (FAILED(hr)) {
    set_err(c, "CreateBlendState", hr);
    return -1;
  }
  return 0;
}

static int makestates(lctx *c) {
  D3D11_RASTERIZER_DESC rd;
  D3D11_SAMPLER_DESC sd;
  HRESULT hr;
  if (makeblend(c, 0, &c->blend) || makeblend(c, 1, &c->holeblend))
    return -1;
  memset(&rd, 0, sizeof rd);
  rd.FillMode = D3D11_FILL_SOLID;
  rd.CullMode = D3D11_CULL_NONE;
  rd.DepthClipEnable = TRUE;
  rd.ScissorEnable = TRUE;
  hr = ID3D11Device_CreateRasterizerState(c->dev, &rd, &c->rast);
  if (FAILED(hr)) {
    set_err(c, "CreateRasterizerState", hr);
    return -1;
  }
  memset(&sd, 0, sizeof sd);
  sd.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  sd.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
  sd.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
  sd.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  sd.MaxLOD = D3D11_FLOAT32_MAX;
  hr = ID3D11Device_CreateSamplerState(c->dev, &sd, &c->samp);
  if (FAILED(hr)) {
    set_err(c, "CreateSamplerState", hr);
    return -1;
  }
  return 0;
}

/* {1 Targets} */

static const IID iid_dxgi_device =
  {0x54ec77fa, 0x1377, 0x44e6,
   {0x8c, 0x32, 0x88, 0xfd, 0x5f, 0x44, 0xc8, 0x4c}};
static const IID iid_factory2 =
  {0x50c83a1c, 0xe072, 0x4c48,
   {0x87, 0xb0, 0x36, 0x30, 0xfa, 0x36, 0xa6, 0xd0}};
static const IID iid_tex2d =
  {0x6f15aaf2, 0xd208, 0x4e89,
   {0x9a, 0xb4, 0x48, 0x95, 0x35, 0xd3, 0x4f, 0x9c}};

static int swap_setup(lctx *c, HWND hwnd, int w, int h) {
  IDXGIDevice *dxdev = NULL;
  IDXGIAdapter *ad = NULL;
  DXGI_SWAP_CHAIN_DESC1 d;
  HRESULT hr;
  hr = ID3D11Device_QueryInterface(c->dev, &iid_dxgi_device,
                                   (void **)&dxdev);
  if (FAILED(hr)) {
    set_err(c, "QueryInterface(IDXGIDevice)", hr);
    return -1;
  }
  hr = IDXGIDevice_GetAdapter(dxdev, &ad);
  IDXGIDevice_Release(dxdev);
  if (FAILED(hr)) {
    set_err(c, "GetAdapter", hr);
    return -1;
  }
  hr = IDXGIObject_GetParent((IDXGIObject *)ad, &iid_factory2,
                             (void **)&c->factory);
  IDXGIAdapter_Release(ad);
  if (FAILED(hr)) {
    set_err(c, "GetParent(IDXGIFactory2)", hr);
    return -1;
  }
  memset(&d, 0, sizeof d);
  d.Width = (UINT)w;
  d.Height = (UINT)h;
  d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  d.SampleDesc.Count = 1;
  d.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  d.BufferCount = 2;
  d.Scaling = DXGI_SCALING_STRETCH;
  d.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  d.AlphaMode = DXGI_ALPHA_MODE_UNSPECIFIED;
  hr = IDXGIFactory2_CreateSwapChainForHwnd(c->factory,
      (IUnknown *)c->dev, hwnd, &d, NULL, NULL, &c->swap);
  if (FAILED(hr)) {
    set_err(c, "CreateSwapChainForHwnd", hr);
    return -1;
  }
  IDXGIFactory_MakeWindowAssociation((IDXGIFactory *)c->factory, hwnd,
                                     DXGI_MWA_NO_ALT_ENTER);
  hr = IDXGISwapChain1_GetBuffer(c->swap, 0, &iid_tex2d,
                                 (void **)&c->rt.t);
  if (FAILED(hr)) {
    set_err(c, "GetBuffer", hr);
    return -1;
  }
  hr = ID3D11Device_CreateRenderTargetView(c->dev,
      (ID3D11Resource *)c->rt.t, NULL, &c->rt.r);
  if (FAILED(hr)) {
    set_err(c, "CreateRenderTargetView(back)", hr);
    return -1;
  }
  c->rt.w = w;
  c->rt.h = h;
  return 0;
}

/* Resize the swapchain buffers after the frame's size changed, and
   re-fetch the back buffer. */
static int swap_resize(lctx *c, int w, int h) {
  HRESULT hr;
  if (c->rt.r) ID3D11RenderTargetView_Release(c->rt.r);
  if (c->rt.t) ID3D11Texture2D_Release(c->rt.t);
  c->rt.r = NULL;
  c->rt.t = NULL;
  hr = IDXGISwapChain1_ResizeBuffers(c->swap, 0, (UINT)w, (UINT)h,
                                    DXGI_FORMAT_UNKNOWN, 0);
  if (FAILED(hr)) {
    set_err(c, "ResizeBuffers", hr);
    return -1;
  }
  hr = IDXGISwapChain1_GetBuffer(c->swap, 0, &iid_tex2d,
                                 (void **)&c->rt.t);
  if (FAILED(hr)) {
    set_err(c, "GetBuffer", hr);
    return -1;
  }
  hr = ID3D11Device_CreateRenderTargetView(c->dev,
      (ID3D11Resource *)c->rt.t, NULL, &c->rt.r);
  if (FAILED(hr)) {
    set_err(c, "CreateRenderTargetView(back)", hr);
    return -1;
  }
  c->rt.w = w;
  c->rt.h = h;
  return 0;
}

static int rt_setup(lctx *c, int w, int h) {
  if (mktex(c, &c->rt, w, h, DXGI_FORMAT_B8G8R8A8_UNORM,
            D3D11_BIND_RENDER_TARGET, NULL, 0))
    return -1;
  return mkrtv(c, &c->rt);
}

/* The pipeline the instances draw with; texture slots are 0 = mask
   atlas, 1 = color atlas, 2 = image, 3 = the backdrop. */
static void bind_pipe(lctx *c, int w, int h, int with_bd) {
  ID3D11DeviceContext *ic = c->ic;
  D3D11_VIEWPORT vp;
  ID3D11ShaderResourceView *srvs[4];
  FLOAT globals[4];
  UINT stride = 240, off = 0;
  ID3D11Buffer *bufs[1];
  memset(&vp, 0, sizeof vp);
  vp.Width = (FLOAT)w;
  vp.Height = (FLOAT)h;
  vp.MaxDepth = 1.0f;
  ID3D11DeviceContext_OMSetRenderTargets(ic, 1, &c->rt.r, NULL);
  ID3D11DeviceContext_RSSetViewports(ic, 1, &vp);
  ID3D11DeviceContext_IASetInputLayout(ic, c->layout);
  ID3D11DeviceContext_IASetPrimitiveTopology(
      ic, D3D11_PRIMITIVE_TOPOLOGY_TRIANGLESTRIP);
  if (c->inst) {
    bufs[0] = c->inst;
    ID3D11DeviceContext_IASetVertexBuffers(ic, 0, 1, bufs, &stride, &off);
  }
  ID3D11DeviceContext_VSSetShader(ic, c->vs, NULL, 0);
  globals[0] = (FLOAT)w;
  globals[1] = (FLOAT)h;
  globals[2] = 0.0f;
  globals[3] = 0.0f;
  ID3D11DeviceContext_UpdateSubresource(ic, (ID3D11Resource *)c->cb, 0,
                                        NULL, globals, 0, 0);
  ID3D11DeviceContext_VSSetConstantBuffers(ic, 0, 1, &c->cb);
  ID3D11DeviceContext_PSSetShader(ic, c->ps, NULL, 0);
  ID3D11DeviceContext_PSSetSamplers(ic, 0, 1, &c->samp);
  srvs[0] = c->mask.s;
  srvs[1] = c->color.s;
  srvs[2] = NULL;
  srvs[3] = with_bd ? c->bd[0].s : NULL;
  ID3D11DeviceContext_PSSetShaderResources(ic, 0, 4, srvs);
  ID3D11DeviceContext_OMSetBlendState(ic, c->blend, NULL, 0xffffffffu);
  ID3D11DeviceContext_RSSetState(ic, c->rast);
}

/* {1 The stubs} */

CAMLprim value lui_d3d11_init(value vhwnd, value vw, value vh, value vsrc) {
  CAMLparam4(vhwnd, vw, vh, vsrc);
  CAMLlocal1(vctx);
  lctx *c;
  ID3DBlob *vsb = NULL, *psb = NULL, *pvb = NULL, *dpb = NULL, *bpb = NULL;
  const char *src = String_val(vsrc);
  int w = Int_val(vw), h = Int_val(vh);
  HWND hwnd = (HWND)(uintptr_t)Nativeint_val(vhwnd);
  vctx = caml_alloc_custom(&ctx_ops, sizeof(lctx), 0, 1);
  c = CTX(vctx);
  memset(c, 0, sizeof *c);
  c->hwnd = hwnd != NULL;
  if (mkdevice(c)) goto fail;
  if (compile(c, src, "vs", "vs_5_0", &vsb) ||
      compile(c, src, "ps", "ps_5_0", &psb) ||
      compile(c, src, "passvs", "vs_5_0", &pvb) ||
      compile(c, src, "downps", "ps_5_0", &dpb) ||
      compile(c, src, "blurps", "ps_5_0", &bpb))
    goto fail;
  if (FAILED(ID3D11Device_CreateVertexShader(
          c->dev, ID3D10Blob_GetBufferPointer(vsb),
          ID3D10Blob_GetBufferSize(vsb), NULL, &c->vs)) ||
      FAILED(ID3D11Device_CreatePixelShader(
          c->dev, ID3D10Blob_GetBufferPointer(psb),
          ID3D10Blob_GetBufferSize(psb), NULL, &c->ps)) ||
      FAILED(ID3D11Device_CreateVertexShader(
          c->dev, ID3D10Blob_GetBufferPointer(pvb),
          ID3D10Blob_GetBufferSize(pvb), NULL, &c->pvs)) ||
      FAILED(ID3D11Device_CreatePixelShader(
          c->dev, ID3D10Blob_GetBufferPointer(dpb),
          ID3D10Blob_GetBufferSize(dpb), NULL, &c->downps)) ||
      FAILED(ID3D11Device_CreatePixelShader(
          c->dev, ID3D10Blob_GetBufferPointer(bpb),
          ID3D10Blob_GetBufferSize(bpb), NULL, &c->blurps))) {
    snprintf(c->err, sizeof c->err, "creating shaders failed");
    goto fail;
  }
  if (makelayout(c, vsb)) goto fail;
  ID3D10Blob_Release(vsb);
  ID3D10Blob_Release(psb);
  ID3D10Blob_Release(pvb);
  ID3D10Blob_Release(dpb);
  ID3D10Blob_Release(bpb);
  vsb = psb = pvb = dpb = bpb = NULL;
  if (makestates(c) || makecb(c, 16, &c->cb) || makecb(c, 48, &c->pcb))
    goto fail;
  if (c->hwnd ? swap_setup(c, hwnd, w, h) : rt_setup(c, w, h)) goto fail;
  CAMLreturn(vctx);
fail:
  if (vsb) ID3D10Blob_Release(vsb);
  if (psb) ID3D10Blob_Release(psb);
  if (pvb) ID3D10Blob_Release(pvb);
  if (dpb) ID3D10Blob_Release(dpb);
  if (bpb) ID3D10Blob_Release(bpb);
  {
    char msg[2048];
    snprintf(msg, sizeof msg, "%s", c->err[0] ? c->err : "init failed");
    ctx_free(c);
    caml_failwith(msg);
  }
}

CAMLprim value lui_d3d11_warp(value vc) {
  CAMLparam1(vc);
  CAMLreturn(Val_bool(CTX(vc)->warp));
}

CAMLprim value lui_d3d11_release(value vc) {
  CAMLparam1(vc);
  ctx_free(CTX(vc));
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_begin(value vc, value vw, value vh, value vr,
                               value vg, value vb, value va) {
  CAMLparam5(vc, vw, vh, vr, vg);
  CAMLxparam2(vb, va);
  lctx *c = CTX(vc);
  int w = Int_val(vw), h = Int_val(vh);
  FLOAT clear[4];
  if (c->swap && (w != c->rt.w || h != c->rt.h)) {
    if (swap_resize(c, w, h)) caml_failwith(c->err);
  }
  clear[0] = (FLOAT)Double_val(vr);
  clear[1] = (FLOAT)Double_val(vg);
  clear[2] = (FLOAT)Double_val(vb);
  clear[3] = (FLOAT)Double_val(va);
  bind_pipe(c, w, h, 0);
  ID3D11DeviceContext_ClearRenderTargetView(c->ic, c->rt.r, clear);
  {
    RECT sc = { 0, 0, w, h };
    ID3D11DeviceContext_RSSetScissorRects(c->ic, 1, &sc);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_begin_byte(value *argv, int argn) {
  (void)argn;
  return lui_d3d11_begin(argv[0], argv[1], argv[2], argv[3], argv[4],
                         argv[5], argv[6]);
}

CAMLprim value lui_d3d11_state(value vc, value vw, value vh) {
  CAMLparam3(vc, vw, vh);
  lctx *c = CTX(vc);
  bind_pipe(c, Int_val(vw), Int_val(vh), 1);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_instances(value vc, value vba) {
  CAMLparam2(vc, vba);
  lctx *c = CTX(vc);
  struct caml_ba_array *ba = Caml_ba_array_val(vba);
  intnat floats = ba->dim[0];
  int count = (int)(floats / 44);
  D3D11_MAPPED_SUBRESOURCE m;
  HRESULT hr;
  if (count > c->instcap && grow_inst(c, count)) caml_failwith(c->err);
  hr = ID3D11DeviceContext_Map(c->ic, (ID3D11Resource *)c->inst, 0,
                               D3D11_MAP_WRITE_DISCARD, 0, &m);
  if (FAILED(hr)) {
    set_err(c, "Map(inst)", hr);
    caml_failwith(c->err);
  }
  memcpy(m.pData, ba->data, (size_t)floats * 4);
  ID3D11DeviceContext_Unmap(c->ic, (ID3D11Resource *)c->inst, 0);
  {
    /* Rebind: growth may have replaced the buffer. */
    UINT stride = 240, off = 0;
    ID3D11Buffer *bufs[1];
    bufs[0] = c->inst;
    ID3D11DeviceContext_IASetVertexBuffers(c->ic, 0, 1, bufs,
                                           &stride, &off);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_shader(value vc, value vid) {
  CAMLparam2(vc, vid);
  lctx *c = CTX(vc);
  int id = Int_val(vid);
  ID3D11PixelShader *ps = c->ps;
  if (id > 0 && id <= c->nfx) ps = c->fx[id - 1];
  ID3D11DeviceContext_PSSetShader(c->ic, ps, NULL, 0);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_hole(value vc, value vh) {
  CAMLparam2(vc, vh);
  lctx *c = CTX(vc);
  ID3D11DeviceContext_OMSetBlendState(
      c->ic, Bool_val(vh) ? c->holeblend : c->blend, NULL, 0xffffffffu);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_scissor(value vc, value vl, value vt, value vr,
                                 value vb) {
  CAMLparam5(vc, vl, vt, vr, vb);
  lctx *c = CTX(vc);
  RECT sc;
  sc.left = (LONG)Int_val(vl);
  sc.top = (LONG)Int_val(vt);
  sc.right = (LONG)Int_val(vr);
  sc.bottom = (LONG)Int_val(vb);
  ID3D11DeviceContext_RSSetScissorRects(c->ic, 1, &sc);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_draw(value vc, value vstart, value vcount) {
  CAMLparam3(vc, vstart, vcount);
  lctx *c = CTX(vc);
  ID3D11DeviceContext_DrawInstanced(c->ic, 4, (UINT)Int_val(vcount), 0,
                                    (UINT)Int_val(vstart));
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_grab(value vc, value vx0, value vy0, value vx1,
                              value vy1) {
  CAMLparam5(vc, vx0, vy0, vx1, vy1);
  lctx *c = CTX(vc);
  ID3D11ShaderResourceView *none[5] = { NULL, NULL, NULL, NULL, NULL };
  D3D11_BOX box;
  /* Nothing the copy or the passes read may stay bound as a shader
     resource while it is a copy target or render target. */
  ID3D11DeviceContext_PSSetShaderResources(c->ic, 0, 5, none);
  box.left = (UINT)Int_val(vx0);
  box.top = (UINT)Int_val(vy0);
  box.front = 0;
  box.right = (UINT)Int_val(vx1);
  box.bottom = (UINT)Int_val(vy1);
  box.back = 1;
  ID3D11DeviceContext_CopySubresourceRegion(
      c->ic, (ID3D11Resource *)c->grab.t, 0, 0, 0, 0,
      (ID3D11Resource *)c->rt.t, 0, &box);
  ID3D11DeviceContext_OMSetBlendState(c->ic, NULL, NULL, 0xffffffffu);
  ID3D11DeviceContext_IASetInputLayout(c->ic, NULL);
  ID3D11DeviceContext_VSSetShader(c->ic, c->pvs, NULL, 0);
  ID3D11DeviceContext_PSSetConstantBuffers(c->ic, 1, 1, &c->pcb);
  CAMLreturn(Val_unit);
}

/* Run the down or blur pass from src into the w×h texels at the start
   of dst, textures numbered 0 = grab, 1/2 = backdrop ping-pong. */
CAMLprim value lui_d3d11_pass(value vc, value vsh, value vsrc, value vdst,
                              value vints, value vsigma, value vw,
                              value vh) {
  CAMLparam5(vc, vsh, vsrc, vdst, vints);
  CAMLxparam3(vsigma, vw, vh);
  lctx *c = CTX(vc);
  int sh = Int_val(vsh), src = Int_val(vsrc), dst = Int_val(vdst);
  int w = Int_val(vw), h = Int_val(vh);
  int i;
  struct {
    INT ox, oy, lx, ly, sx, sy, dx, dy, down, radius;
    FLOAT sigma, pad;
  } pc;
  ltex *st[3], *dt;
  ID3D11PixelShader *ps;
  D3D11_VIEWPORT vp;
  RECT sc;
  ID3D11ShaderResourceView *zero = NULL;
  st[0] = &c->grab;
  st[1] = &c->bd[0];
  st[2] = &c->bd[1];
  if (src < 0 || src > 2 || dst < 1 || dst > 2 || c->bd[0].t == NULL)
    caml_failwith("lui_d3d11_pass: bad backdrop textures");
  dt = &c->bd[dst - 1];
  ps = sh == 0 ? c->downps : c->blurps;
  for (i = 0; i < 8; i++) {
    int *p = &pc.ox + i;
    *p = (INT)Int_val(Field(vints, i));
  }
  pc.down = (INT)Int_val(Field(vints, 8));
  pc.radius = (INT)Int_val(Field(vints, 9));
  pc.sigma = (FLOAT)Double_val(vsigma);
  pc.pad = 0.0f;
  ID3D11DeviceContext_UpdateSubresource(
      c->ic, (ID3D11Resource *)c->pcb, 0, NULL, &pc, 0, 0);
  ID3D11DeviceContext_OMSetRenderTargets(c->ic, 1, &dt->r, NULL);
  memset(&vp, 0, sizeof vp);
  vp.Width = (FLOAT)dt->w;
  vp.Height = (FLOAT)dt->h;
  vp.MaxDepth = 1.0f;
  ID3D11DeviceContext_RSSetViewports(c->ic, 1, &vp);
  sc.left = 0;
  sc.top = 0;
  sc.right = (LONG)w;
  sc.bottom = (LONG)h;
  ID3D11DeviceContext_RSSetScissorRects(c->ic, 1, &sc);
  ID3D11DeviceContext_PSSetShader(c->ic, ps, NULL, 0);
  ID3D11DeviceContext_PSSetShaderResources(c->ic, 4, 1, &st[src]->s);
  ID3D11DeviceContext_DrawInstanced(c->ic, 4, 1, 0, 0);
  ID3D11DeviceContext_PSSetShaderResources(c->ic, 4, 1, &zero);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_pass_byte(value *argv, int argn) {
  (void)argn;
  return lui_d3d11_pass(argv[0], argv[1], argv[2], argv[3], argv[4],
                        argv[5], argv[6], argv[7]);
}

CAMLprim value lui_d3d11_fit(value vc, value vgw, value vgh, value vbw,
                             value vbh) {
  CAMLparam5(vc, vgw, vgh, vbw, vbh);
  lctx *c = CTX(vc);
  int gw = Int_val(vgw), gh = Int_val(vgh);
  int bw = Int_val(vbw), bh = Int_val(vbh);
  if ((gw > c->grab.w || gh > c->grab.h) && c->grab.t != NULL) {
    /* The OCaml side only calls when growth is needed, but keep the
       guard harmless for the initial, zero-size call. */
    ltex_free(&c->grab);
  }
  if (c->grab.t == NULL && gw > 0 && gh > 0) {
    if (mktex(c, &c->grab, gw, gh, DXGI_FORMAT_B8G8R8A8_UNORM,
              D3D11_BIND_SHADER_RESOURCE, NULL, 0) ||
        mksrv(c, &c->grab))
      caml_failwith(c->err);
  }
  if (bw > c->bd[0].w || bh > c->bd[0].h) {
    int i;
    for (i = 0; i < 2; i++) {
      ltex_free(&c->bd[i]);
      if (mktex(c, &c->bd[i], bw, bh, DXGI_FORMAT_B8G8R8A8_UNORM,
                D3D11_BIND_SHADER_RESOURCE | D3D11_BIND_RENDER_TARGET,
                NULL, 0) ||
          mksrv(c, &c->bd[i]) ||
          mkrtv(c, &c->bd[i]))
        caml_failwith(c->err);
    }
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_atlas(value vc, value vslot, value vw, value vh,
                               value vpix) {
  CAMLparam5(vc, vslot, vw, vh, vpix);
  lctx *c = CTX(vc);
  int slot = Int_val(vslot), w = Int_val(vw), h = Int_val(vh);
  ltex *t = slot == 0 ? &c->mask : &c->color;
  ltex_free(t);
  if (mktex(c, t, w, h,
            slot == 0 ? DXGI_FORMAT_R8_UNORM
                      : DXGI_FORMAT_R8G8B8A8_UNORM,
            D3D11_BIND_SHADER_RESOURCE, Bytes_val(vpix),
            w * (slot == 0 ? 1 : 4)) ||
      mksrv(c, t))
    caml_failwith(c->err);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_atlas_region(value vc, value vslot, value vx0,
                                      value vy0, value vx1, value vy1,
                                      value vpix, value voff,
                                      value vpitch) {
  CAMLparam5(vc, vslot, vx0, vy0, vx1);
  CAMLxparam4(vy1, vpix, voff, vpitch);
  lctx *c = CTX(vc);
  ltex *t = Int_val(vslot) == 0 ? &c->mask : &c->color;
  D3D11_BOX box;
  box.left = (UINT)Int_val(vx0);
  box.top = (UINT)Int_val(vy0);
  box.front = 0;
  box.right = (UINT)Int_val(vx1);
  box.bottom = (UINT)Int_val(vy1);
  box.back = 1;
  if (t->t == NULL) caml_failwith("lui_d3d11_atlas_region: no texture");
  ID3D11DeviceContext_UpdateSubresource(
      c->ic, (ID3D11Resource *)t->t, 0, &box,
      (char *)Bytes_val(vpix) + Int_val(voff), (UINT)Int_val(vpitch), 0);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_atlas_region_byte(value *argv, int argn) {
  (void)argn;
  return lui_d3d11_atlas_region(argv[0], argv[1], argv[2], argv[3],
                                argv[4], argv[5], argv[6], argv[7],
                                argv[8]);
}

static limg *img_find(lctx *c, int iid) {
  int i;
  for (i = 0; i < c->nimg; i++)
    if (c->imgs[i].iid == iid) return &c->imgs[i];
  if (c->nimg == c->aimg) {
    int cap = c->aimg ? c->aimg * 2 : 16;
    limg *n = realloc(c->imgs, (size_t)cap * sizeof *n);
    if (!n) return NULL;
    c->imgs = n;
    c->aimg = cap;
  }
  memset(&c->imgs[c->nimg], 0, sizeof c->imgs[c->nimg]);
  return &c->imgs[c->nimg++];
}

CAMLprim value lui_d3d11_image(value vc, value viid, value vver, value vw,
                               value vh, value vframe, value vpix) {
  CAMLparam5(vc, viid, vver, vw, vh);
  CAMLxparam2(vframe, vpix);
  lctx *c = CTX(vc);
  int iid = Int_val(viid), ver = Int_val(vver);
  int w = Int_val(vw), h = Int_val(vh);
  limg *im = img_find(c, iid);
  if (im == NULL) caml_failwith("lui_d3d11_image: out of memory");
  if (im->t != NULL && (w != im->w || h != im->h)) img_free(im);
  if (im->t != NULL && im->ver != ver) {
    /* Refresh the whole texture. */
    D3D11_BOX box;
    box.left = 0;
    box.top = 0;
    box.front = 0;
    box.right = (UINT)w;
    box.bottom = (UINT)h;
    box.back = 1;
    ID3D11DeviceContext_UpdateSubresource(
        c->ic, (ID3D11Resource *)im->t, 0, &box, Bytes_val(vpix),
        (UINT)(w * 4), 0);
  }
  if (im->t == NULL) {
    HRESULT hr;
    D3D11_TEXTURE2D_DESC d;
    D3D11_SUBRESOURCE_DATA init;
    memset(&d, 0, sizeof d);
    d.Width = (UINT)w;
    d.Height = (UINT)h;
    d.MipLevels = 1;
    d.ArraySize = 1;
    d.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
    d.SampleDesc.Count = 1;
    d.Usage = D3D11_USAGE_DEFAULT;
    d.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    init.pSysMem = Bytes_val(vpix);
    init.SysMemPitch = (UINT)(w * 4);
    init.SysMemSlicePitch = 0;
    hr = ID3D11Device_CreateTexture2D(c->dev, &d, &init, &im->t);
    if (FAILED(hr)) {
      set_err(c, "CreateTexture2D(image)", hr);
      caml_failwith(c->err);
    }
    hr = ID3D11Device_CreateShaderResourceView(
        c->dev, (ID3D11Resource *)im->t, NULL, &im->s);
    if (FAILED(hr)) {
      set_err(c, "CreateShaderResourceView(image)", hr);
      caml_failwith(c->err);
    }
    im->iid = iid;
    im->w = w;
    im->h = h;
  }
  im->ver = ver;
  im->frame = Int_val(vframe);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_image_byte(value *argv, int argn) {
  (void)argn;
  return lui_d3d11_image(argv[0], argv[1], argv[2], argv[3], argv[4],
                         argv[5], argv[6]);
}

CAMLprim value lui_d3d11_bind_image(value vc, value viid) {
  CAMLparam2(vc, viid);
  lctx *c = CTX(vc);
  int iid = Int_val(viid), i;
  ID3D11ShaderResourceView *s = NULL;
  for (i = 0; i < c->nimg; i++)
    if (c->imgs[i].iid == iid) s = c->imgs[i].s;
  ID3D11DeviceContext_PSSetShaderResources(c->ic, 2, 1, &s);
  CAMLreturn(Val_unit);
}

/* Drop one image's texture; the OCaml side drops its bookkeeping. */
CAMLprim value lui_d3d11_image_free(value vc, value viid) {
  CAMLparam2(vc, viid);
  lctx *c = CTX(vc);
  int iid = Int_val(viid), i;
  for (i = 0; i < c->nimg; i++) {
    if (c->imgs[i].iid == iid) {
      img_free(&c->imgs[i]);
      c->imgs[i] = c->imgs[--c->nimg];
      break;
    }
  }
  CAMLreturn(Val_unit);
}

/* The staging texture read maps, created on demand at the render
   target's size. */
static int want_staging(lctx *c) {
  if (c->staging != NULL && c->staging_w == c->rt.w &&
      c->staging_h == c->rt.h)
    return 0;
  if (c->staging) ID3D11Texture2D_Release(c->staging);
  {
    D3D11_TEXTURE2D_DESC d;
    memset(&d, 0, sizeof d);
    d.Width = (UINT)c->rt.w;
    d.Height = (UINT)c->rt.h;
    d.MipLevels = 1;
    d.ArraySize = 1;
    d.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    d.SampleDesc.Count = 1;
    d.Usage = D3D11_USAGE_STAGING;
    d.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    {
      HRESULT hr = ID3D11Device_CreateTexture2D(c->dev, &d, NULL,
                                                &c->staging);
      if (FAILED(hr)) {
        set_err(c, "CreateTexture2D(staging)", hr);
        return -1;
      }
    }
  }
  c->staging_w = c->rt.w;
  c->staging_h = c->rt.h;
  return 0;
}

CAMLprim value lui_d3d11_present(value vc) {
  CAMLparam1(vc);
  lctx *c = CTX(vc);
  if (c->swap) {
    /* The back buffer is undefined once presented; keep the frame for
       reads. */
    if (want_staging(c) == 0) {
      ID3D11DeviceContext_CopyResource(c->ic,
          (ID3D11Resource *)c->staging, (ID3D11Resource *)c->rt.t);
    }
    IDXGISwapChain1_Present(c->swap, 1, 0);
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_d3d11_read(value vc) {
  CAMLparam1(vc);
  CAMLlocal1(out);
  lctx *c = CTX(vc);
  int w = c->rt.w, h = c->rt.h;
  D3D11_MAPPED_SUBRESOURCE m;
  HRESULT hr;
  int y;
  if (w <= 0 || h <= 0) CAMLreturn(caml_alloc_string(0));
  if (want_staging(c)) caml_failwith(c->err);
  /* Swapchain frames are copied out before presenting; offscreen
     frames are still in the render target. */
  if (c->swap == NULL) {
    ID3D11DeviceContext_CopyResource(c->ic,
        (ID3D11Resource *)c->staging, (ID3D11Resource *)c->rt.t);
  }
  hr = ID3D11DeviceContext_Map(c->ic, (ID3D11Resource *)c->staging, 0,
                               D3D11_MAP_READ, 0, &m);
  if (FAILED(hr)) {
    set_err(c, "Map(staging)", hr);
    caml_failwith(c->err);
  }
  out = caml_alloc_string((size_t)w * (size_t)h * 4);
  for (y = 0; y < h; y++)
    memcpy((char *)Bytes_val(out) + (size_t)y * (size_t)w * 4,
           (const char *)m.pData + (size_t)y * m.RowPitch,
           (size_t)w * 4);
  ID3D11DeviceContext_Unmap(c->ic, (ID3D11Resource *)c->staging, 0);
  CAMLreturn(out);
}

CAMLprim value lui_d3d11_compile(value vc, value vsrc) {
  CAMLparam2(vc, vsrc);
  lctx *c = CTX(vc);
  ID3DBlob *blob = NULL;
  ID3D11PixelShader *ps = NULL;
  ID3D11PixelShader **n;
  HRESULT hr;
  if (compile(c, String_val(vsrc), "ps", "ps_5_0", &blob))
    CAMLreturn(Val_int(-1));
  hr = ID3D11Device_CreatePixelShader(
      c->dev, ID3D10Blob_GetBufferPointer(blob),
      ID3D10Blob_GetBufferSize(blob), NULL, &ps);
  ID3D10Blob_Release(blob);
  if (FAILED(hr)) {
    set_err(c, "CreatePixelShader(effect)", hr);
    CAMLreturn(Val_int(-1));
  }
  if (c->nfx == c->afx) {
    int cap = c->afx ? c->afx * 2 : 8;
    n = realloc(c->fx, (size_t)cap * sizeof *n);
    if (!n) {
      ID3D11PixelShader_Release(ps);
      caml_failwith("lui_d3d11_compile: out of memory");
    }
    c->fx = n;
    c->afx = cap;
  }
  c->fx[c->nfx++] = ps;
  CAMLreturn(Val_int(c->nfx));
}

CAMLprim value lui_d3d11_last_error(value vc) {
  CAMLparam1(vc);
  CAMLlocal1(out);
  out = caml_copy_string(CTX(vc)->err);
  CAMLreturn(out);
}

/* A hidden window for tests on machines without a desktop session. */
CAMLprim value lui_d3d11_window(value vw, value vh) {
  CAMLparam2(vw, vh);
  HWND hwnd = CreateWindowExW(0, L"STATIC", L"lui_d3d11",
                              WS_POPUP | WS_DISABLED, 0, 0,
                              Int_val(vw), Int_val(vh), NULL, NULL,
                              GetModuleHandleW(NULL), NULL);
  if (hwnd == NULL) caml_failwith("CreateWindowExW failed");
  CAMLreturn(caml_copy_nativeint((intnat)hwnd));
}

CAMLprim value lui_d3d11_window_destroy(value vhwnd) {
  CAMLparam1(vhwnd);
  DestroyWindow((HWND)(uintptr_t)Nativeint_val(vhwnd));
  CAMLreturn(Val_unit);
}

#else /* !_WIN32 */

#include <caml/mlvalues.h>
#include <caml/fail.h>

/* The library stays buildable on every platform so cross-platform
   consumers and platform-gated tests resolve cleanly; any call on an
   unsupported platform fails immediately. */
static value unsupported(void) {
  caml_failwith("lui_d3d11: this backend requires Windows");
  return Val_unit;
}

CAMLprim value lui_d3d11_init(value a, value b, value c, value d) {
  (void)a; (void)b; (void)c; (void)d;
  return unsupported();
}
CAMLprim value lui_d3d11_warp(value a) { (void)a; return unsupported(); }
CAMLprim value lui_d3d11_release(value a) { (void)a; return unsupported(); }
CAMLprim value lui_d3d11_begin(value a, value b, value c, value d, value e,
                               value f, value g) {
  (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
  return unsupported();
}
CAMLprim value lui_d3d11_begin_byte(value *argv, int argn) {
  (void)argv; (void)argn;
  return unsupported();
}
CAMLprim value lui_d3d11_state(value a, value b, value c) {
  (void)a; (void)b; (void)c;
  return unsupported();
}
CAMLprim value lui_d3d11_instances(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_shader(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_hole(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_scissor(value a, value b, value c, value d,
                                 value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e;
  return unsupported();
}
CAMLprim value lui_d3d11_draw(value a, value b, value c) {
  (void)a; (void)b; (void)c;
  return unsupported();
}
CAMLprim value lui_d3d11_grab(value a, value b, value c, value d,
                              value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e;
  return unsupported();
}
CAMLprim value lui_d3d11_pass(value a, value b, value c, value d, value e,
                              value f, value g, value h) {
  (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h;
  return unsupported();
}
CAMLprim value lui_d3d11_pass_byte(value *argv, int argn) {
  (void)argv; (void)argn;
  return unsupported();
}
CAMLprim value lui_d3d11_fit(value a, value b, value c, value d,
                             value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e;
  return unsupported();
}
CAMLprim value lui_d3d11_atlas(value a, value b, value c, value d,
                               value e) {
  (void)a; (void)b; (void)c; (void)d; (void)e;
  return unsupported();
}
CAMLprim value lui_d3d11_atlas_region(value a, value b, value c, value d,
                                      value e, value f, value g,
                                      value h, value i) {
  (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
  (void)h; (void)i;
  return unsupported();
}
CAMLprim value lui_d3d11_atlas_region_byte(value *argv, int argn) {
  (void)argv; (void)argn;
  return unsupported();
}
CAMLprim value lui_d3d11_image(value a, value b, value c, value d,
                               value e, value f, value g) {
  (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g;
  return unsupported();
}
CAMLprim value lui_d3d11_image_byte(value *argv, int argn) {
  (void)argv; (void)argn;
  return unsupported();
}
CAMLprim value lui_d3d11_bind_image(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_image_free(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_present(value a) { (void)a; return unsupported(); }
CAMLprim value lui_d3d11_read(value a) { (void)a; return unsupported(); }
CAMLprim value lui_d3d11_compile(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_last_error(value a) {
  (void)a; return unsupported();
}
CAMLprim value lui_d3d11_window(value a, value b) {
  (void)a; (void)b;
  return unsupported();
}
CAMLprim value lui_d3d11_window_destroy(value a) {
  (void)a; return unsupported();
}

#endif
