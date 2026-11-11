import { open, test } from "nsh/test";
import { qualifyNavigation } from "./navigation_native_steps";

test("canonical navigation, native Split and focused keyed reorder", async () => {
  const app = await open("../../nsh.json", { width: 900, height: 760, network: "live" });
  await qualifyNavigation(app);
}, 60_000);
