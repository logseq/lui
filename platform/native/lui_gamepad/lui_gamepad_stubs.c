/* Gamepad host bridges for lui_gamepad.

   Two backends live behind the same OCaml externals:

   - SDL path (macOS, Linux): SDL3 is resolved at run time with
     dlopen/dlsym so this stub links and runs on machines without SDL
     hardware; hosts that already link SDL3 get the
     live library, others get a clean "not loaded" probe.  The path is
     state-polling only: it pumps the SDL event loop for fresh
     hardware state and reads SDL_GetGamepadAxis/GetGamepadButton —
     it never consumes the SDL event queue, so window hosts keep
     owning event delivery.

   - XInput path (Windows only): xinput1_4.dll via LoadLibrary.
     XInput polling needs no message pump.  Battery and keystroke
     entry points are exposed for hosts that want them.

   On every other platform each entry point raises Failure. */

/* glibc only exposes RTLD_DEFAULT (and dladdr, etc.) when _GNU_SOURCE is
   defined before the first libc header; other libcs declare it always. */
#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#if defined(_WIN32)
#define LUI_GP_WIN 1
#elif defined(__APPLE__) || defined(__linux__) || defined(__unix__)
#define LUI_GP_POSIX 1
#else
#define LUI_GP_NONE 1
#endif

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <caml/threads.h>

#if defined(LUI_GP_POSIX)
#include <dlfcn.h>
#endif

#define LUI_GP_MAX_PADS 16

/* ==================== SDL path (POSIX) ==================== */

#if defined(LUI_GP_POSIX)

#include <SDL3/SDL.h>

typedef struct {
  __typeof__(&SDL_InitSubSystem) init_subsystem;
  __typeof__(&SDL_WasInit) was_init;
  __typeof__(&SDL_PumpEvents) pump_events;
  __typeof__(&SDL_GetJoysticks) joysticks;
  __typeof__(&SDL_IsGamepad) is_controller;
  __typeof__(&SDL_GetGamepadNameForID) gc_name_for_index;
  __typeof__(&SDL_GetJoystickNameForID) joy_name_for_index;
  __typeof__(&SDL_GetJoystickGUIDForID) joy_device_guid;
  __typeof__(&SDL_GUIDToString) joy_guid_string;
  __typeof__(&SDL_GetGamepadMappingForID) gc_mapping_for_index;
  __typeof__(&SDL_OpenGamepad) gc_open;
  __typeof__(&SDL_GetGamepadJoystick) gc_get_joystick;
  __typeof__(&SDL_GetJoystickID) joy_instance_id;
  __typeof__(&SDL_GamepadConnected) gc_attached;
  __typeof__(&SDL_CloseGamepad) gc_close;
  __typeof__(&SDL_GetGamepadAxis) gc_axis;
  __typeof__(&SDL_GetGamepadButton) gc_button;
  __typeof__(&SDL_AddGamepadMapping) gc_add_mapping;
  __typeof__(&SDL_AddGamepadMappingsFromFile) gc_add_mappings_file;
  __typeof__(&SDL_GetError) get_error;
  __typeof__(&SDL_free) sdl_free;
  __typeof__(&SDL_AttachVirtualJoystick) joy_attach_virtual;
  __typeof__(&SDL_DetachVirtualJoystick) joy_detach_virtual;
  __typeof__(&SDL_OpenJoystick) joy_open;
  __typeof__(&SDL_CloseJoystick) joy_close;
  __typeof__(&SDL_GetJoystickFromID) joy_from_instance;
  __typeof__(&SDL_SetJoystickVirtualAxis) joy_set_virtual_axis;
  __typeof__(&SDL_SetJoystickVirtualButton) joy_set_virtual_button;
} sdl_api;

static void *sdl_lib;
static sdl_api S;
static char sdl_load_err[256];
static int sdl_resolved;

static struct { int inst; SDL_Gamepad *gc; } pads[LUI_GP_MAX_PADS];
static int npads;

static void sdl_store_err(const char *fallback)
{
  const char *e = (S.get_error ? S.get_error() : NULL);
  snprintf(sdl_load_err, sizeof(sdl_load_err), "%s",
           (e && e[0]) ? e : fallback);
}

static void *sdl_sym(const char *name)
{
  void *p = sdl_lib ? dlsym(sdl_lib, name) : NULL;
  if (!p) p = dlsym(RTLD_DEFAULT, name);
  return p;
}

static int sdl_resolve(void)
{
  if (sdl_resolved)
    return S.init_subsystem && S.joysticks && S.gc_open && S.gc_axis && S.gc_button && S.sdl_free;
  sdl_resolved = 1;

  const char *override = getenv("SDL3_LIBRARY");
  if (override) sdl_lib = dlopen(override, RTLD_NOW | RTLD_GLOBAL);
  else {
    static const char *names[] = {
      "libSDL3.so.0", "libSDL3.so", "libSDL3.dylib", "SDL3.framework/SDL3", NULL
    };
    for (int i = 0; names[i] && !sdl_lib; i++)
      sdl_lib = dlopen(names[i], RTLD_NOW | RTLD_GLOBAL);
  }
#define R(name, field) S.field = sdl_sym(name)
  R("SDL_InitSubSystem", init_subsystem);
  R("SDL_WasInit", was_init);
  R("SDL_PumpEvents", pump_events);
  R("SDL_GetJoysticks", joysticks);
  R("SDL_IsGamepad", is_controller);
  R("SDL_GetGamepadNameForID", gc_name_for_index);
  R("SDL_GetJoystickNameForID", joy_name_for_index);
  R("SDL_GetJoystickGUIDForID", joy_device_guid);
  R("SDL_GUIDToString", joy_guid_string);
  R("SDL_GetGamepadMappingForID", gc_mapping_for_index);
  R("SDL_OpenGamepad", gc_open);
  R("SDL_GetGamepadJoystick", gc_get_joystick);
  R("SDL_GetJoystickID", joy_instance_id);
  R("SDL_GamepadConnected", gc_attached);
  R("SDL_CloseGamepad", gc_close);
  R("SDL_GetGamepadAxis", gc_axis);
  R("SDL_GetGamepadButton", gc_button);
  R("SDL_AddGamepadMapping", gc_add_mapping);
  R("SDL_AddGamepadMappingsFromFile", gc_add_mappings_file);
  R("SDL_GetError", get_error);
  R("SDL_free", sdl_free);
  R("SDL_AttachVirtualJoystick", joy_attach_virtual);
  R("SDL_DetachVirtualJoystick", joy_detach_virtual);
  R("SDL_OpenJoystick", joy_open);
  R("SDL_CloseJoystick", joy_close);
  R("SDL_GetJoystickFromID", joy_from_instance);
  R("SDL_SetJoystickVirtualAxis", joy_set_virtual_axis);
  R("SDL_SetJoystickVirtualButton", joy_set_virtual_button);
#undef R

  if (!S.init_subsystem || !S.joysticks || !S.gc_open || !S.gc_axis || !S.gc_button || !S.sdl_free)
    snprintf(sdl_load_err, sizeof(sdl_load_err),
             "SDL3 library not found or incomplete");
  return S.init_subsystem && S.joysticks && S.gc_open && S.gc_axis && S.gc_button && S.sdl_free;
}

static int sdl_ready(void)
{
  return sdl_resolve() && S.init_subsystem != NULL;
}

static SDL_Gamepad *pad_lookup(int inst)
{
  for (int i = 0; i < npads; i++)
    if (pads[i].inst == inst) return pads[i].gc;
  return NULL;
}

static int pad_store(int inst, SDL_Gamepad *gc)
{
  if (pad_lookup(inst)) return 1;
  if (npads >= LUI_GP_MAX_PADS) return 0;
  pads[npads].inst = inst;
  pads[npads].gc = gc;
  npads++;
  return 1;
}

static void pad_drop(int inst)
{
  for (int i = 0; i < npads; i++)
    if (pads[i].inst == inst) {
      pads[i] = pads[npads - 1];
      npads--;
      return;
    }
}

CAMLprim value lui_gp_sdl_probe(value unit)
{
  CAMLparam1(unit);
  CAMLreturn(Val_int(sdl_ready() ? 1 : 0));
}

CAMLprim value lui_gp_sdl_load_error(value unit)
{
  CAMLparam1(unit);
  sdl_resolve();
  CAMLreturn(caml_copy_string(sdl_load_err));
}

/* 0 ok, <0 error. */
CAMLprim value lui_gp_sdl_init(value unit)
{
  CAMLparam1(unit);
  int rc = 0;
  if (!sdl_ready()) rc = -1;
  else if (!S.init_subsystem(SDL_INIT_GAMEPAD | SDL_INIT_EVENTS)) {
    sdl_store_err("SDL_InitSubSystem failed");
    rc = -2;
  }
  CAMLreturn(Val_int(rc));
}

CAMLprim value lui_gp_sdl_pump(value unit)
{
  CAMLparam1(unit);
  if (sdl_ready() && S.pump_events) {
    caml_release_runtime_system();
    S.pump_events();
    caml_acquire_runtime_system();
  }
  CAMLreturn(Val_unit);
}

CAMLprim value lui_gp_sdl_devices(value unit)
{
  CAMLparam1(unit);
  CAMLlocal2(result, cell);
  result = Val_emptylist;
  if (sdl_ready() && S.joysticks) {
    int count = 0;
    SDL_JoystickID *ids = S.joysticks(&count);
    if (ids) {
      for (int i = count - 1; i >= 0; i--) {
        cell = caml_alloc(2, 0);
        Store_field(cell, 0, Val_long(ids[i]));
        Store_field(cell, 1, result);
        result = cell;
      }
      S.sdl_free(ids);
    }
  }
  CAMLreturn(result);
}

CAMLprim value lui_gp_sdl_is_controller(value vidx)
{
  CAMLparam1(vidx);
  int r = (sdl_ready() && S.is_controller)
              ? S.is_controller(Int_val(vidx)) : 0;
  CAMLreturn(Val_bool(r != 0));
}

CAMLprim value lui_gp_sdl_device_name(value vidx)
{
  CAMLparam1(vidx);
  const char *n = NULL;
  if (sdl_ready()) {
    if (S.gc_name_for_index) n = S.gc_name_for_index(Int_val(vidx));
    if (!n && S.joy_name_for_index) n = S.joy_name_for_index(Int_val(vidx));
  }
  CAMLreturn(caml_copy_string(n ? n : ""));
}

CAMLprim value lui_gp_sdl_device_guid(value vidx)
{
  CAMLparam1(vidx);
  char buf[64];
  buf[0] = 0;
  if (sdl_ready() && S.joy_device_guid && S.joy_guid_string) {
    SDL_GUID g = S.joy_device_guid(Int_val(vidx));
    S.joy_guid_string(g, buf, (int) sizeof(buf));
  }
  CAMLreturn(caml_copy_string(buf));
}

CAMLprim value lui_gp_sdl_device_instance(value vidx)
{
  CAMLparam1(vidx);
  CAMLreturn(vidx);
}

CAMLprim value lui_gp_sdl_device_mapping(value vidx)
{
  CAMLparam1(vidx);
  value out = caml_copy_string("");
  if (sdl_ready() && S.gc_mapping_for_index) {
    char *m = S.gc_mapping_for_index(Int_val(vidx));
    if (m) {
      out = caml_copy_string(m);
      if (S.sdl_free) S.sdl_free(m); else free(m);
    }
  }
  CAMLreturn(out);
}

/* index -> instance id, or -1 on failure. */
CAMLprim value lui_gp_sdl_open(value vidx)
{
  CAMLparam1(vidx);
  int inst = -1;
  if (sdl_ready() && S.gc_open) {
    SDL_Gamepad *gc = S.gc_open(Int_val(vidx));
    if (gc) {
      SDL_Joystick *j = S.gc_get_joystick ? S.gc_get_joystick(gc) : NULL;
      if (j && S.joy_instance_id) {
        inst = S.joy_instance_id(j);
        if (!pad_store(inst, gc)) {
          S.gc_close(gc);
          inst = -1;
        }
      }
    } else {
      sdl_store_err("SDL_GamepadOpen failed");
    }
  }
  CAMLreturn(Val_int(inst));
}

CAMLprim value lui_gp_sdl_close(value vinst)
{
  CAMLparam1(vinst);
  int inst = Int_val(vinst);
  SDL_Gamepad *gc = pad_lookup(inst);
  if (gc && S.gc_close) S.gc_close(gc);
  pad_drop(inst);
  CAMLreturn(Val_unit);
}

CAMLprim value lui_gp_sdl_attached(value vinst)
{
  CAMLparam1(vinst);
  SDL_Gamepad *gc = pad_lookup(Int_val(vinst));
  int r = (gc && S.gc_attached) ? S.gc_attached(gc) : 0;
  CAMLreturn(Val_bool(r != 0));
}

CAMLprim value lui_gp_sdl_axis(value vinst, value vaxis)
{
  CAMLparam2(vinst, vaxis);
  SDL_Gamepad *gc = pad_lookup(Int_val(vinst));
  CAMLreturn(Val_int(gc ? S.gc_axis(gc, Int_val(vaxis)) : 0));
}

CAMLprim value lui_gp_sdl_button(value vinst, value vbtn)
{
  CAMLparam2(vinst, vbtn);
  SDL_Gamepad *gc = pad_lookup(Int_val(vinst));
  CAMLreturn(Val_bool(gc && S.gc_button(gc, Int_val(vbtn)) != 0));
}

CAMLprim value lui_gp_sdl_add_mapping(value vs)
{
  CAMLparam1(vs);
  int r = -1;
  if (sdl_ready() && S.gc_add_mapping)
    r = S.gc_add_mapping(String_val(vs));
  CAMLreturn(Val_int(r));
}

CAMLprim value lui_gp_sdl_add_mappings_file(value vpath)
{
  CAMLparam1(vpath);
  int r = -1;
  if (sdl_ready() && S.gc_add_mappings_file)
    r = S.gc_add_mappings_file(String_val(vpath));
  CAMLreturn(Val_int(r));
}

/* ---- fake-event injection harness (virtual joysticks) ---- */

CAMLprim value lui_gp_sdl_attach_virtual(value vtype, value vnaxes,
                                         value vnbuttons, value vnhats)
{
  CAMLparam4(vtype, vnaxes, vnbuttons, vnhats);
  int r = -1;
  if (sdl_ready() && S.joy_attach_virtual) {
    SDL_VirtualJoystickDesc desc = {0};
    desc.version = sizeof(desc);
    desc.type = Int_val(vtype);
    desc.naxes = Int_val(vnaxes);
    desc.nbuttons = Int_val(vnbuttons);
    desc.nhats = Int_val(vnhats);
    desc.name = "LUI virtual gamepad";
    r = (int)S.joy_attach_virtual(&desc);
    if (r == 0) r = -1;
  }
  CAMLreturn(Val_int(r));
}

CAMLprim value lui_gp_sdl_detach_virtual(value vidx)
{
  CAMLparam1(vidx);
  int r = -1;
  if (sdl_ready() && S.joy_detach_virtual)
    r = S.joy_detach_virtual(Int_val(vidx)) ? 0 : -1;
  CAMLreturn(Val_int(r));
}

CAMLprim value lui_gp_sdl_joystick_open(value vidx)
{
  CAMLparam1(vidx);
  int inst = -1;
  if (sdl_ready() && S.joy_open && S.joy_instance_id) {
    SDL_Joystick *j = S.joy_open(Int_val(vidx));
    if (j) inst = S.joy_instance_id(j);
  }
  CAMLreturn(Val_int(inst));
}

CAMLprim value lui_gp_sdl_set_vaxis(value vinst, value vaxis, value vval)
{
  CAMLparam3(vinst, vaxis, vval);
  int r = -1;
  if (sdl_ready() && S.joy_from_instance && S.joy_set_virtual_axis) {
    SDL_Joystick *j = S.joy_from_instance(Int_val(vinst));
    if (j) r = S.joy_set_virtual_axis(j, Int_val(vaxis), Int_val(vval)) ? 0 : -1;
  }
  CAMLreturn(Val_int(r));
}

CAMLprim value lui_gp_sdl_set_vbutton(value vinst, value vbtn, value vdown)
{
  CAMLparam3(vinst, vbtn, vdown);
  int r = -1;
  if (sdl_ready() && S.joy_from_instance && S.joy_set_virtual_button) {
    SDL_Joystick *j = S.joy_from_instance(Int_val(vinst));
    if (j)
      r = S.joy_set_virtual_button(j, Int_val(vbtn),
                                   Bool_val(vdown)) ? 0 : -1;
  }
  CAMLreturn(Val_int(r));
}

#else /* !LUI_GP_POSIX — SDL is not the gamepad path here. */

static value sdl_unsupported(void)
{
  caml_failwith("lui_gamepad: SDL backend unsupported on this platform");
  return Val_unit;
}

CAMLprim value lui_gp_sdl_probe(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_load_error(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_init(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_pump(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_devices(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_is_controller(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_device_name(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_device_guid(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_device_instance(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_device_mapping(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_open(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_close(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_attached(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_axis(value a, value b) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_button(value a, value b) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_add_mapping(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_add_mappings_file(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_attach_virtual(value a, value b, value c, value d)
{ return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_detach_virtual(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_joystick_open(value u) { return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_set_vaxis(value a, value b, value c)
{ return sdl_unsupported(); }
CAMLprim value lui_gp_sdl_set_vbutton(value a, value b, value c)
{ return sdl_unsupported(); }

#endif /* LUI_GP_POSIX */

/* ==================== XInput path (Windows) ==================== */

#if defined(LUI_GP_WIN)

#include <windows.h>

typedef struct {
  unsigned short wButtons;
  unsigned char bLeftTrigger, bRightTrigger;
  short sThumbLX, sThumbLY, sThumbRX, sThumbRY;
} XI_GAMEPAD;

typedef struct {
  unsigned long dwPacketNumber;
  XI_GAMEPAD Gamepad;
} XI_STATE;

typedef struct {
  unsigned char Type, SubType;
  unsigned short Flags;
  XI_GAMEPAD Gamepad;
  unsigned short wLeftMotor, wRightMotor;
} XI_CAPABILITIES;

typedef struct {
  unsigned char BatteryType, BatteryLevel;
} XI_BATTERY;

typedef struct {
  unsigned short VirtualKey, Unicode, Flags;
  unsigned char UserIndex, HidCode;
} XI_KEYSTROKE;

static HMODULE xinput_lib;
static int xinput_resolved;

static unsigned long (WINAPI *xi_get_state)(unsigned long, XI_STATE *);
static unsigned long (WINAPI *xi_get_caps)(unsigned long, unsigned long,
                                           XI_CAPABILITIES *);
static unsigned long (WINAPI *xi_get_battery)(unsigned long, unsigned char,
                                              XI_BATTERY *);
static unsigned long (WINAPI *xi_get_keystroke)(unsigned long, unsigned long,
                                                XI_KEYSTROKE *);

#define XI_ERR_NOT_CONNECTED 1167u

static void xinput_resolve(void)
{
  if (xinput_resolved) return;
  xinput_resolved = 1;
  static const char *names[] = {
    "xinput1_4.dll", "xinput1_3.dll", "xinput9_1_0.dll", NULL
  };
  for (int i = 0; names[i] && !xinput_lib; i++)
    xinput_lib = LoadLibraryA(names[i]);
  if (!xinput_lib) return;
  xi_get_state = (void *)GetProcAddress(xinput_lib, "XInputGetState");
  xi_get_caps = (void *)GetProcAddress(xinput_lib, "XInputGetCapabilities");
  xi_get_battery =
    (void *)GetProcAddress(xinput_lib, "XInputGetBatteryInformation");
  xi_get_keystroke =
    (void *)GetProcAddress(xinput_lib, "XInputGetKeystroke");
}

CAMLprim value lui_gp_xi_probe(value unit)
{
  CAMLparam1(unit);
  xinput_resolve();
  CAMLreturn(Val_int(xi_get_state ? 1 : 0));
}

/* [|err; packet; buttons; lt; rt; lx; ly; rx; ry|] */
CAMLprim value lui_gp_xi_get_state(value vuser)
{
  CAMLparam1(vuser);
  CAMLlocal1(arr);
  XI_STATE st;
  unsigned long err;
  memset(&st, 0, sizeof(st));
  xinput_resolve();
  err = xi_get_state ? xi_get_state(Int_val(vuser), &st) : 0x80004005u;
  arr = caml_alloc(9, 0);
  Field(arr, 0) = Val_int(err);
  Field(arr, 1) = Val_int(st.dwPacketNumber);
  Field(arr, 2) = Val_int(st.Gamepad.wButtons);
  Field(arr, 3) = Val_int(st.Gamepad.bLeftTrigger);
  Field(arr, 4) = Val_int(st.Gamepad.bRightTrigger);
  Field(arr, 5) = Val_int(st.Gamepad.sThumbLX);
  Field(arr, 6) = Val_int(st.Gamepad.sThumbLY);
  Field(arr, 7) = Val_int(st.Gamepad.sThumbRX);
  Field(arr, 8) = Val_int(st.Gamepad.sThumbRY);
  CAMLreturn(arr);
}

/* [|err; type; subtype; flags|] */
CAMLprim value lui_gp_xi_get_caps(value vuser)
{
  CAMLparam1(vuser);
  CAMLlocal1(arr);
  XI_CAPABILITIES caps;
  unsigned long err;
  memset(&caps, 0, sizeof(caps));
  xinput_resolve();
  err = xi_get_caps ? xi_get_caps(Int_val(vuser), 0, &caps) : 0x80004005u;
  arr = caml_alloc(4, 0);
  Field(arr, 0) = Val_int(err);
  Field(arr, 1) = Val_int(caps.Type);
  Field(arr, 2) = Val_int(caps.SubType);
  Field(arr, 3) = Val_int(caps.Flags);
  CAMLreturn(arr);
}

/* [|err; battery_type; battery_level|] */
CAMLprim value lui_gp_xi_get_battery(value vuser, value vtype)
{
  CAMLparam2(vuser, vtype);
  CAMLlocal1(arr);
  XI_BATTERY b;
  unsigned long err;
  memset(&b, 0, sizeof(b));
  xinput_resolve();
  err = xi_get_battery
    ? xi_get_battery(Int_val(vuser), Int_val(vtype), &b)
    : 0x80004005u;
  arr = caml_alloc(3, 0);
  Field(arr, 0) = Val_int(err);
  Field(arr, 1) = Val_int(b.BatteryType);
  Field(arr, 2) = Val_int(b.BatteryLevel);
  CAMLreturn(arr);
}

/* [|err; vk; unicode; flags; user; hid|] */
CAMLprim value lui_gp_xi_get_keystroke(value vuser)
{
  CAMLparam1(vuser);
  CAMLlocal1(arr);
  XI_KEYSTROKE k;
  unsigned long err;
  memset(&k, 0, sizeof(k));
  xinput_resolve();
  err = xi_get_keystroke
    ? xi_get_keystroke(Int_val(vuser), 0, &k)
    : 0x80004005u;
  arr = caml_alloc(6, 0);
  Field(arr, 0) = Val_int(err);
  Field(arr, 1) = Val_int(k.VirtualKey);
  Field(arr, 2) = Val_int(k.Unicode);
  Field(arr, 3) = Val_int(k.Flags);
  Field(arr, 4) = Val_int(k.UserIndex);
  Field(arr, 5) = Val_int(k.HidCode);
  CAMLreturn(arr);
}

#else /* !LUI_GP_WIN */

static value xi_unsupported(void)
{
  caml_failwith("lui_gamepad: XInput backend unsupported on this platform");
  return Val_unit;
}

CAMLprim value lui_gp_xi_probe(value u) { return xi_unsupported(); }
CAMLprim value lui_gp_xi_get_state(value u) { return xi_unsupported(); }
CAMLprim value lui_gp_xi_get_caps(value u) { return xi_unsupported(); }
CAMLprim value lui_gp_xi_get_battery(value a, value b)
{ return xi_unsupported(); }
CAMLprim value lui_gp_xi_get_keystroke(value u) { return xi_unsupported(); }

#endif /* LUI_GP_WIN */
