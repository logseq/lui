import assert from "node:assert/strict";
import test from "node:test";

const modules = new URL("../../../_build/default/examples/components/web/lui-components-web/node_modules/", import.meta.url);
const Command = await import(new URL("lui/lui_command.js", modules));
const Desktop = await import(new URL("lui.web.dom/shell/lui_web_desktop.js", modules));
const descriptor = Command.v(Command.Name.of_string("app.echo")._0, Command.Codec.string, Command.Codec.string);

test("desktop invocation preserves typed responses and structured errors", async () => {
  const previous = globalThis.window;
  try {
    globalThis.window = {};
    assert.equal((await Desktop.invoke(descriptor, "hello"))._0.code, Command.code_of_name("unavailable"));
    globalThis.window.luiDesktop = {invoke: async (name, payload) => {
      assert.equal(name, "app.echo"); return payload + " 中文 …";
    }};
    assert.deepEqual(await Desktop.invoke(descriptor, "hello"), {TAG: 0, _0: "hello 中文 …"});
    globalThis.window.luiDesktop.invoke = async () => { throw Object.assign(new Error("Refused"), {code: "command_failed"}); };
    assert.deepEqual(await Desktop.invoke(descriptor, "hello"), {
      TAG: 1, _0: {code: Command.code_of_name("command_failed"), message: "Refused"},
    });
    globalThis.window.luiDesktop.invoke = async () => 42;
    assert.equal((await Desktop.invoke(descriptor, "hello"))._0.code, Command.code_of_name("invalid_response"));
    globalThis.window.luiDesktop.invoke = async () => { throw null; };
    assert.equal((await Desktop.invoke(descriptor, "hello"))._0.code, Command.code_of_name("internal_error"));
    globalThis.window.luiDesktop.invoke = async () => { throw {code: 42, message: {private: true}}; };
    assert.deepEqual((await Desktop.invoke(descriptor, "hello"))._0, {
      code: Command.code_of_name("internal_error"), message: "Native command failed",
    });
    globalThis.window.luiDesktop.invoke = async () => { throw {get code() {throw new Error("Broken property");}}; };
    assert.equal((await Desktop.invoke(descriptor, "hello"))._0.code, Command.code_of_name("internal_error"));
  } finally { globalThis.window = previous; }
});
