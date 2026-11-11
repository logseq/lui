import type { App } from "nsh/test";

/** Exercise the real OCaml application through native input and screenshots. */
export async function qualifyNavigation(app: App) {
  // Screenshots qualify appearance separately from the model/native-input checks.
  function check(value: unknown, message: string): asserts value {
    if (!value) throw new Error(message);
  }
  const state = (prefix: string) => {
    const value = app.texts().find((text) => text.startsWith(prefix));
    check(value !== undefined, "Missing native status: " + prefix);
    return value;
  };
  const splitState = (name: string) => {
    const value = state(name + " source ");
    const match = /source ([0-9.]+) requests ([0-9]+) last ([0-9.]+)$/.exec(value);
    check(match, "Malformed Split status: " + value);
    return { source: Number(match[1]), requests: Number(match[2]), last: Number(match[3]) };
  };
  const near = (actual: number, expected: number, tolerance: number, message: string) => {
    check(Math.abs(actual - expected) <= tolerance, message + ": " + actual);
  };
  const paneState = () => {
    const value = state("Pane order ");
    const match = /^Pane order (First,Second|Second,First) appears First=([0-9]+) Second=([0-9]+)$/.exec(value);
    check(match, "Malformed pane status: " + value);
    return { order: match[1], first: Number(match[2]), second: Number(match[3]) };
  };
  // Native panel groups expose their actual adjustable handle directly.
  const equalHandle = "role:adjustable[Equal layout divider]";
  const pixelHandle = "role:adjustable[Pixel layout divider]";

  await app.waitFor("Navigation and Split qualification");
  await app.setViewport(900, 760);
  await app.waitFor("Split echo disabled");
  check(!app.enabled("role:button[Archived]"), "The disabled breadcrumb is not interactive");
  check(!app.enabled("role:button[Unavailable page]"), "The disabled page is not interactive");

  // Arrow movement must skip disabled authored Buttons without activating one.
  await app.type("label:Before breadcrumb", "");
  await app.keyboard.press("tab");
  await app.keyboard.press("enter");
  await app.waitFor("Breadcrumb requests 1 last Workspace");
  await app.keyboard.press("right");
  await app.waitFor("Breadcrumb requests 1 last Workspace");
  await app.keyboard.press("enter");
  await app.waitFor("Breadcrumb requests 2 last Current");
  await app.type("label:Before pagination", "");
  await app.keyboard.press("tab");
  await app.keyboard.press("enter");
  await app.waitFor("Page source 1 requests 1");
  await app.keyboard.press("right");
  await app.waitFor("Page source 1 requests 1");
  await app.keyboard.press("enter");
  await app.waitFor("Page source 3 requests 2");
  await app.keyboard.press("home");
  await app.keyboard.press("enter");
  await app.waitFor("Page source 1 requests 3");
  await app.keyboard.press("end");
  await app.keyboard.press("enter");
  await app.waitFor("Page source 3 requests 4");

  await app.waitFor("label:Plan (active)");
  await app.waitFor("label:Build (pending)");
  await app.press("role:button[Advance step]");
  await app.waitFor("label:Plan (completed)");
  await app.waitFor("label:Build (active)");
  await app.press("role:button[Reorder stages]");
  await app.waitFor("Stages Ship,Build,Plan active 1");
  await app.waitFor("label:Ship (completed)");
  await app.waitFor("label:Build (active)");
  await app.waitFor("label:Plan (pending)");
  await app.press("role:button[Advance step]");
  await app.waitFor("label:Plan (active)");

  await app.press("role:button[Update activity]");
  await app.waitFor("Recompiled");
  await app.waitFor("Native compile verified");
  await app.waitFor("09:01");
  check(app.count("id:navigation-timeline >> text:legacy") === 0,
    "An authored icon takes precedence over the fallback indicator text");
  check(app.count("id:navigation-timeline >> text:R") === 1,
    "A TimelineItem without an icon retains its authored indicator");
  await app.press("role:button[Review]");
  await app.waitFor("Activity selected Review");
  // Selected fill and the clock -> check-circle glyph update require reviewing
  // these real light/dark screenshots; model status alone does not prove pixels.
  await app.setColorScheme("light");
  await app.screenshot("_build/nsh/navigation-native/activity-light.png");
  await app.setColorScheme("dark");
  await app.screenshot("_build/nsh/navigation-native/activity-dark.png");
  await app.scroll("id:navigation-scroll", -10000);
  await app.setColorScheme("light");
  await app.screenshot("_build/nsh/navigation-native/navigation-light.png");
  await app.setColorScheme("dark");
  await app.screenshot("_build/nsh/navigation-native/navigation-dark.png");

  // Equal panels own their user sizes, even when the model does not echo them.
  const equalState = () => {
    const match = /^Equal requests ([0-9]+) last ([0-9.]+)$/.exec(state("Equal requests "));
    check(match, "Malformed equal panel status");
    return { requests: Number(match[1]), last: Number(match[2]) };
  };
  await app.drag(equalHandle, { x: 40, y: 0 });
  const equalFirst = equalState();
  check(equalFirst.requests === 1 && equalFirst.last > 300,
    "Native equal panel reports its absolute width at drag completion");
  await app.drag(equalHandle, { x: 40, y: 0 });
  const equalSecond = equalState();
  check(equalSecond.requests === 2, "A second drag emits exactly one completion");
  near(equalSecond.last, equalFirst.last + 40, 1,
    "Native panel keeps its local width without model echo");

  await app.drag(pixelHandle, { x: 60, y: 0 });
  let pixels = splitState("Pixel");
  near(pixels.source, 240, 0.1, "Without echo the authored source stays unchanged");
  near(pixels.last, 300, 1, "Native pixel panel reports its actual completed width");
  await app.press("role:button[Echo resize]");
  await app.waitFor("Split echo enabled");
  const priorRequests = pixels.requests;
  await app.drag(pixelHandle, { x: 60, y: 0 });
  pixels = splitState("Pixel");
  near(pixels.source, 360, 1, "Echoed native width reaches the controlled pixel source");
  check(pixels.requests === priorRequests + 1, "Echo does not produce a duplicate resize");
  await app.press("role:button[Set first pane 180]");
  const programmedPixels = splitState("Pixel");
  near(programmedPixels.source, 180, 0.1, "Programmatic pixel source updates");
  check(programmedPixels.requests === pixels.requests,
    "Programmatic width update does not emit resize");

  await app.type("label:First draft", " +native");
  let firstDraft = app.value("label:First draft");
  check(firstDraft && firstDraft.includes("+native"), "First pane receives real native text input");
  await app.waitFor("text:First model " + firstDraft);
  // Establish that a hardware character reaches the focused editor before any move.
  await app.keyboard.press("z");
  await app.waitFor("text:/^First model .*z/");
  firstDraft = app.value("label:First draft");
  await app.type("label:Second draft", " +independent");
  const secondDraft = app.value("label:Second draft");
  check(secondDraft && secondDraft.includes("+independent"), "Second pane owns an independent native draft");
  await app.waitFor("text:Second model " + secondDraft);
  const beforeReorder = paneState();
  check(beforeReorder.order === "First,Second", "The first pane starts at the leading edge");

  // Arm a normal model edit to reorder while that editor has focus. A following
  // hardware key, without re-focusing through app.type, detects a lost editor.
  await app.press("role:button[Reorder on next edit]");
  await app.waitFor("Reorder armed");
  await app.type("label:First draft", "~");
  await app.waitFor("text:/^Pane order Second,First appears /");
  const reorderedDraft = app.value("label:First draft");
  check(reorderedDraft && reorderedDraft.replace("~", "") === firstDraft,
    "The edit that reorders panes reaches the original native editor");
  await app.keyboard.press("x");
  await app.waitFor("text:/^First model .*x/");
  const continuedDraft = app.value("label:First draft");
  check(continuedDraft && continuedDraft.length === reorderedDraft.length + 1 && continuedDraft.replace("x", "") === reorderedDraft,
    "Reordered First editor retains its native focus/draft");
  await app.waitFor("text:First model " + continuedDraft);
  check(app.value("label:Second draft") === secondDraft, "Reordered Second editor retains its native draft");
  const afterReorder = paneState();
  check(afterReorder.first === beforeReorder.first && afterReorder.second === beforeReorder.second,
    "Moving keyed panes does not remount either appeared pane");

  // Programmatic updates also change the native handle's subsequent geometry.
  await app.press("role:button[Stop resize echo]");
  await app.waitFor("Split echo disabled");
  await app.drag(pixelHandle, { x: 60, y: 0 });
  pixels = splitState("Pixel");
  near(pixels.source, 180, 0.1, "Without echo the source remains 180 points");
  near(pixels.last, 240, 1, "Native geometry starts from the programmed width");
  await app.scroll("id:navigation-scroll", 10000);
  await app.setColorScheme("light");
  await app.screenshot("_build/nsh/navigation-native/split-light.png");
  await app.setColorScheme("dark");
  await app.screenshot("_build/nsh/navigation-native/split-dark.png");
}
