"use strict";
const element = id => document.getElementById(id);
async function command(name) {
  return window.luiDesktop.request(name);
}
async function refresh() {
  const state = await command("state");
  const busy = ["checking", "downloading", "staging"].includes(state.status);
  element("message").textContent = state.message || ({
    checking: "Checking for updates…", downloading: "Downloading update…",
  })[state.status] || state.status;
  element("notes").textContent = state.notes || "";
  element("progress").hidden = !busy;
  if (state.status === "downloading" && state.total > 0) {
    element("progress").max = state.total;
    element("progress").value = Math.min(state.bytes, state.total);
  } else element("progress").removeAttribute("value");
  element("check").disabled = busy || state.status === "disabled" || state.status === "ready";
  element("install").hidden = state.status !== "available";
  element("restart").hidden = state.status !== "ready";
  element("skip").hidden = state.status !== "available";
}
for (const name of ["check", "install", "restart", "skip"]) {
  element(name).addEventListener("click", () => {
    element(name).disabled = true;
    command(name).then(refresh).catch(error => {
      element("message").textContent = error.message;
    }).finally(() => { element(name).disabled = false; });
  });
}
element("later").addEventListener("click", () => window.__lui_later());
async function poll() {
  try { await refresh(); }
  catch (error) { element("message").textContent = error.message; }
  setTimeout(poll, 500);
}
command("check").catch(() => {}).finally(poll);
