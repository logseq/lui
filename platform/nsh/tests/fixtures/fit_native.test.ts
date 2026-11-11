import { open, test } from "nsh/test";

// The fixture must be built with build_virtual.py --fixture fit and supplied as
// LUI_NSH_OCAML_LIBRARY to the normal native macOS test command.
test("retained native fitting, keyboard visibility and Journal feedback", async () => {
  const app = await open("../../nsh.json", { width: 900, height: 820, network: "live" });
  function check(value: unknown, message: string): asserts value {
    if (!value) throw new Error(message);
  }
  const model = async (name: string, value: string) => {
    await app.waitFor("text:" + name + " model " + value);
  };
  const snapshot = async (name: string) => {
    await app.setColorScheme("light");
    await app.screenshot("_build/nsh/fit-qualification/" + name + "-light.png");
    await app.setColorScheme("dark");
    await app.screenshot("_build/nsh/fit-qualification/" + name + "-dark.png");
  };

  await app.waitFor("ViewThatFits native qualification");
  await app.waitFor("Fit appears wide=1 compact=0");
  await app.waitFor("Vertical appears preferred=0 fallback=1");
  check(app.count("label:Compact feedback draft") === 0,
    "The hidden compact candidate is excluded from the native scene");
  check(app.count("Vertical fallback") === 1, "Vertical fitting uses its last fallback");

  await app.type("label:Wide feedback draft", " +wide");
  let wideDraft = app.value("label:Wide feedback draft");
  check(wideDraft && wideDraft.includes("+wide"), "Wide editor receives native text input");
  await model("Wide", wideDraft);
  // A real resize that keeps the same alternative must preserve native focus.
  await app.setViewport(940, 820);
  await app.keyboard.press("x");
  await app.waitFor("text:/^Wide model .*x/");
  const wideAfterResize = app.value("label:Wide feedback draft");
  check(wideAfterResize && wideAfterResize.length === wideDraft.length + 1 &&
    wideAfterResize.replace("x", "") === wideDraft, "Wide editor retains focus across native layout");
  wideDraft = wideAfterResize;
  await app.waitFor("Fit appears wide=1 compact=0");
  await snapshot("wide");

  // Main is outside the pinned visibility scope. Changing the selected feedback
  // while Main has focus must not replace its editor or move keyboard input.
  await app.type("label:Main draft", " +main");
  const mainBeforeResize = app.value("label:Main draft");
  check(mainBeforeResize, "Main editor is present");
  await model("Main", mainBeforeResize);
  await app.setViewport(500, 820);
  await app.waitFor("Fit appears wide=1 compact=1");
  await app.keyboard.press("z");
  await app.waitFor("text:/^Main model .*z/");
  const mainDraft = app.value("label:Main draft");
  check(mainDraft && mainDraft.length === mainBeforeResize.length + 1 &&
    mainDraft.replace("z", "") === mainBeforeResize, "Unchanged Main keeps native focus through selection");
  check(app.count("label:Wide feedback draft") === 0, "The wider candidate is hidden after shrinking");

  // AppKit's spatial key-view loop places the pinned feedback above Main.
  // Traverse backward into it; the hidden wide editor must not consume input.
  await app.keyboard.press("shift+tab");
  await app.keyboard.press("q");
  await app.waitFor("text:/^Compact model .*q/");
  await app.type("label:Compact feedback draft", " +compact");
  const compactDraft = app.value("label:Compact feedback draft");
  check(compactDraft && compactDraft.includes("+compact"), "Compact editor owns an independent native draft");
  await model("Compact", compactDraft);
  await snapshot("compact");

  await app.setViewport(900, 820);
  await app.waitFor("Fit appears wide=2 compact=1");
  check(app.value("label:Wide feedback draft") === wideDraft, "Wide draft survives hiding and reselection");
  await app.setViewport(500, 820);
  await app.waitFor("Fit appears wide=2 compact=2");
  check(app.value("label:Compact feedback draft") === compactDraft, "Compact draft survives hiding and reselection");
  check(app.value("label:Main draft") === mainDraft, "The main editor keeps its independent draft");

  await app.press("role:button[Short vertical]");
  await app.waitFor("Vertical appears preferred=1 fallback=1");
  await app.waitFor("Short vertical candidate");
  check(app.count("Vertical fallback") === 0, "A live content-size change selects the earlier vertical candidate");

  await app.press("role:button[Hide feedback]");
  await app.waitFor("Feedback hidden");
  check(app.count("label:Compact feedback draft") === 0 && app.count("label:Wide feedback draft") === 0,
    "EdgeInset visibility suppresses both retained feedback candidates");
  check(app.count("Main body stays visible") === 1 && app.value("label:Main draft") === mainDraft,
    "Journal-style feedback visibility leaves the main body mounted");
  await app.type("label:Main draft", "");
  await app.keyboard.press("tab");
  await app.keyboard.press("enter");
  await app.waitFor("After actions 1");
  await app.waitFor("Fit appears wide=2 compact=2");
  await app.waitFor("Vertical appears preferred=1 fallback=1");
  await app.press("role:button[Show feedback]");
  await app.waitFor("Fit appears wide=2 compact=3");
  check(app.value("label:Compact feedback draft") === compactDraft,
    "Inherited visibility does not remount or reset the selected feedback body");
  await snapshot("restored");
}, 60_000);
