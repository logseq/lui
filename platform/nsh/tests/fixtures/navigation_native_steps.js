// Stdin for NSH's real native driver with the OCaml navigation fixture loaded.
// Screenshots qualify appearance separately from the model/native-input checks.
const check = (value, message) => { if (!value) throw new Error(message); };
const state = (prefix) => {
  const value = app.texts().find((text) => text.startsWith(prefix));
  check(value !== undefined, "Missing native status: " + prefix);
  return value;
};
const splitState = (name) => {
  const value = state(name + " source ");
  const match = /source ([0-9.]+) requests ([0-9]+) last ([0-9.]+)$/.exec(value);
  check(match, "Malformed Split status: " + value);
  return { source: Number(match[1]), requests: Number(match[2]), last: Number(match[3]) };
};
const near = (actual, expected, tolerance, message) => {
  check(Math.abs(actual - expected) <= tolerance, message + ": " + actual);
};
const paneState = () => {
  const value = state("Pane order ");
  const match = /^Pane order (First,Second|Second,First) appears First=([0-9]+) Second=([0-9]+)$/.exec(value);
  check(match, "Malformed pane status: " + value);
  return { order: match[1], first: Number(match[2]), second: Number(match[3]) };
};
// Both the semantic divider and its native band are labelled. A strict
// descendant selector names only the actual ResizeHandle inside the divider.
const ratioHandle = "label:Ratio layout divider >> label:Ratio layout divider";
const pixelHandle = "label:Pixel layout divider >> label:Pixel layout divider";

await app.waitFor("Navigation and Split qualification");
await app.setViewport(900, 760);
await app.waitFor("Split mode refusing");
check(!app.enabled("role:button[Archived]"), "The disabled breadcrumb is not interactive");
check(!app.enabled("role:button[Unavailable page]"), "The disabled page is not interactive");

// Arrow movement must skip disabled authored Buttons without activating one.
await app.press("role:button[Workspace]");
await app.waitFor("Breadcrumb requests 1 last Workspace");
await app.keyboard.press("right");
await app.waitFor("Breadcrumb requests 1 last Workspace");
await app.keyboard.press("enter");
await app.waitFor("Breadcrumb requests 2 last Current");
await app.press("role:button[Page one]");
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

// The fixed 609-point tracks have a 9-point gap and 600 usable points.
await app.drag(ratioHandle, { x: 60, y: 0 });
let ratio = splitState("Ratio");
near(ratio.source, 0.5, 0.001, "Refused ratio drag keeps the source");
check(ratio.requests > 0 && ratio.last > ratio.source,
  "The ratio drag emits a proposal even when the reducer refuses it");
await app.drag(pixelHandle, { x: 60, y: 0 });
let pixels = splitState("Pixel");
near(pixels.source, 240, 0.1, "Refused pixel drag keeps the source");
check(pixels.requests > 0 && pixels.last > pixels.source,
  "Pixel mode reports an absolute first-pane width proposal");

await app.press("role:button[Accept resize]");
await app.waitFor("Split mode accepting");
const ratioRefusedRequests = ratio.requests;
const pixelsRefusedRequests = pixels.requests;
await app.drag(ratioHandle, { x: 60, y: 0 });
ratio = splitState("Ratio");
near(ratio.source, 0.6, 0.003, "Accepted ratio drag updates the controlled value");
check(ratio.requests > ratioRefusedRequests, "Accepted ratio drag emits a fresh proposal");
await app.drag(pixelHandle, { x: 60, y: 0 });
pixels = splitState("Pixel");
near(pixels.source, 300, 1, "Accepted pixel drag updates the controlled width");
check(pixels.requests > pixelsRefusedRequests, "Accepted pixel drag emits a fresh proposal");

await app.press("role:button[Set ratio quarter]");
const programmedRatio = splitState("Ratio");
near(programmedRatio.source, 0.25, 0.001, "Programmatic ratio update reaches the native app");
check(programmedRatio.requests === ratio.requests, "Programmatic ratio update does not emit resize");
await app.press("role:button[Set first pane 180]");
const programmedPixels = splitState("Pixel");
near(programmedPixels.source, 180, 0.1, "Programmatic first-width update reaches the native app");
check(programmedPixels.requests === pixels.requests, "Programmatic width update does not emit resize");

await app.type("label:First draft", " +native");
const firstDraft = app.value("label:First draft");
check(firstDraft && firstDraft.includes("+native"), "First pane receives real native text input");
await app.waitFor("text:First model " + firstDraft);
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
const continuedDraft = app.value("label:First draft");
check(continuedDraft && continuedDraft.length === reorderedDraft.length + 1 && continuedDraft.replace("x", "") === reorderedDraft,
  "Reordered First editor retains its native focus/draft");
await app.waitFor("text:First model " + continuedDraft);
check(app.value("label:Second draft") === secondDraft, "Reordered Second editor retains its native draft");
const afterReorder = paneState();
check(afterReorder.first === beforeReorder.first && afterReorder.second === beforeReorder.second,
  "Moving keyed panes does not remount either appeared pane");

// Programmatic updates must have changed actual native drag geometry too.
// Start from the quarter/180 values; another refusal keeps those accepted values.
await app.press("role:button[Refuse resize]");
await app.waitFor("Split mode refusing");
await app.drag(ratioHandle, { x: 60, y: 0 });
ratio = splitState("Ratio");
near(ratio.source, 0.25, 0.001, "Refusal retains the programmatic ratio after reorder");
near(ratio.last, 0.35, 0.003, "Native ratio geometry starts from the programmatic value");
await app.drag(pixelHandle, { x: 60, y: 0 });
pixels = splitState("Pixel");
near(pixels.source, 180, 0.1, "Refusal retains the programmatic pixel width");
near(pixels.last, 240, 1, "Native pixel geometry starts from the programmatic width");
await app.scroll("id:navigation-scroll", 10000);
await app.setColorScheme("light");
await app.screenshot("_build/nsh/navigation-native/split-light.png");
await app.setColorScheme("dark");
await app.screenshot("_build/nsh/navigation-native/split-dark.png");
