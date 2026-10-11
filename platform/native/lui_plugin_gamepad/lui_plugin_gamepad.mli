(** Gamepad plugin service for the native backend.

    A [Lui_plugin.t] descriptor named ["gamepad"] answering:

    - ["list"]   — connected controllers with live state
    - ["state"]  — [{"id": n}] one controller's snapshot, or all
    - ["events"] — one {!Lui_gamepad.pump} frame of events
    - ["map"]    — [{"mapping": "<sdl db line>"}] register a mapping
    - ["mapfile"]— [{"path": p}] SDL_GameControllerAddMappingsFromFile *)

val plugin : Lui_plugin.t
