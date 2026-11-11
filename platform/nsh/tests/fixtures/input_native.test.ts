import { open, test } from "nsh/test";

// Build with build_virtual.py --fixture input; point LUI_NSH_OCAML_LIBRARY at
// that receipt-backed library before the normal native macOS test command.
test("native Input saves once with committed C ABI text and retained fields", async () => {
  const app = await open("../../nsh.json", { width: 980, height: 900, network: "live" });
  function check(value: unknown, message: string): asserts value {
    if (!value) throw new Error(message);
  }
  const draft = (label: string) => {
    const value = app.value("label:" + label);
    check(value !== null, "Missing native input: " + label);
    return value;
  };
  const saved = async (name: string, count: number, text: string) => {
    await app.waitFor("text:" + name + " saves " + count + " text " + text);
  };
  const model = async (name: string, text: string) => {
    await app.waitFor("text:" + name + " draft " + text);
  };
  await app.waitFor("Native Input blur qualification");
  await app.waitFor("text:/^Mounted primary=[1-9][0-9]* optional=[1-9][0-9]* outside=[1-9][0-9]* paragraph=[1-9][0-9]* count=4$/");
  // These statuses report canonical mounted identities. The Rust engine tests
  // separately check actual native NodeId retention.
  const mounts = app.texts().find((text) => text.startsWith("Mounted primary="));
  check(mounts, "All canonical fields appeared once");

  await app.type("label:Primary value", " +blur");
  let primary = draft("Primary value");
  await model("Primary", primary);
  await app.keyboard.press("up");
  await app.keyboard.press("down");
  await app.waitFor("Primary navigation previous=1 next=1");
  await app.waitFor("Optional navigation previous=0 next=0");
  check(draft("Primary value") === primary, "Navigation does not mutate the native draft");
  await app.keyboard.press("tab");
  await saved("Primary", 1, primary);
  await app.keyboard.press("q");
  await app.waitFor("text:/^Optional draft .*q/");
  await app.keyboard.press("up");
  await app.keyboard.press("down");
  await app.waitFor("Optional navigation previous=1 next=1");
  await app.waitFor("Primary navigation previous=1 next=1");
  await app.type("label:Outside value", " +independent");
  const outside = draft("Outside value");
  await model("Outside", outside);
  await app.keyboard.press("up");
  await app.waitFor("Optional navigation previous=1 next=1");
  await app.waitFor("Primary navigation previous=1 next=1");
  await saved("Optional", 0, "none");

  await app.type("label:Primary value", " +enter");
  primary = draft("Primary value");
  await model("Primary", primary);
  await app.keyboard.press("enter");
  await saved("Primary", 2, primary);
  await app.keyboard.press("x");
  check(draft("Primary value") === primary, "Single-line native Enter still blurs");
  await app.type("label:Outside value", "");
  await saved("Primary", 2, primary);

  // macOS supports the public marked-text test step. Cancel preedit before
  // committing a Unicode character; this does not simulate an OS IME chooser.
  await app.compose("label:Primary value", "zhong");
  await model("Primary", primary);
  await saved("Primary", 2, primary);
  await app.keyboard.press("up");
  await app.waitFor("Primary navigation previous=1 next=1");
  await app.compose("label:Primary value", "");
  await app.type("label:Primary value", "中");
  primary = draft("Primary value");
  check(primary.includes("中"), "Committed Unicode reaches the native editor");
  await app.keyboard.press("down");
  await app.waitFor("Primary navigation previous=1 next=2");
  await model("Primary", primary);
  await app.keyboard.press("tab");
  await saved("Primary", 3, primary);
  await app.waitFor("Primary navigation previous=1 next=2");

  await app.type("label:Outside value", "");
  await app.press("role:button[Enable optional blur]");
  await app.waitFor("Optional policy on");
  await app.type("label:Optional value", " +save");
  let optional = draft("Optional value");
  await model("Optional", optional);
  await app.keyboard.press("tab");
  await saved("Optional", 1, optional);
  await app.waitFor(mounts);
  await app.press("role:button[Disable optional blur]");
  await app.waitFor("Optional policy off");
  await app.type("label:Optional value", " +no-save");
  optional = draft("Optional value");
  await model("Optional", optional);
  await app.keyboard.press("tab");
  const optionalSaved = app.texts().find((text) => text.startsWith("Optional saves "));
  check(optionalSaved?.startsWith("Optional saves 1 text "), "Live false disables blur saves on the same Input");

  await app.type("label:Paragraph value", " +paragraph");
  const firstParagraph = draft("Paragraph value");
  await model("Paragraph", firstParagraph);
  await app.keyboard.press("enter");
  await saved("Paragraph", 1, firstParagraph);
  await app.keyboard.press("z");
  await app.waitFor("text:/^Paragraph draft .*z/");
  const paragraph = draft("Paragraph value");
  check(paragraph.length === firstParagraph.length + 1, "Textarea native Submit keeps focus");
  await app.type("label:Outside value", "");
  await saved("Paragraph", 2, paragraph);

  // Disable from the committed edit itself, before native focus-loss handling.
  // Clicking a Disable button while editing would introduce a focus-order race.
  await app.press("role:button[Arm disable on edit]");
  await app.waitFor("Disable on edit armed");
  await app.type("label:Primary value", "!");
  primary = draft("Primary value");
  await app.waitFor("Primary disabled");
  check(!app.enabled("label:Primary value"), "The same Input becomes disabled");
  await app.type("label:Outside value", "");
  const primarySaved = app.texts().find((text) => text.startsWith("Primary saves "));
  check(primarySaved?.startsWith("Primary saves 3 text "), "Disabled native blur cannot commit another save");
  await app.press("role:button[Enable primary]");
  await app.waitFor("Primary enabled");
  check(draft("Primary value") === primary, "Re-enabling keeps the committed native draft");
  check(draft("Optional value") === optional, "The optional draft remains independent");
  check(draft("Outside value") === outside, "The ordinary Input remains independent");
  check(draft("Paragraph value") === paragraph, "The textarea draft remains independent");
  await app.waitFor(mounts);
  await app.setColorScheme("light");
  await app.screenshot("_build/nsh/input-qualification/inputs-light.png");
  await app.setColorScheme("dark");
  await app.screenshot("_build/nsh/input-qualification/inputs-dark.png");
}, 60_000);
