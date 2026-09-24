// Composition root for host apps: wires the OCaml bridge to the rendering
// engine. Usage:
//
//   var host = new LUIWinUIHost();
//   host.Backend.ApplyJson(schemaJson);          // manual mode, or:
//   host.Start();                                 // embedded OCaml runtime
//   window.Content = host.Root;
//
// Register extension visuals before Start() so the initial patch renders.

namespace LUI.WinUI
{
    public sealed class LUIWinUIHost : System.IDisposable
    {
        LUIOcamlBridge? _bridge;

        public LUIWinUIHost()
        {
            Backend = new LUIWinUIBackend();
        }

        public LUIWinUIBackend Backend { get; }
        public LUIWinUIRoot Root => Backend.Root;
        public LUISyncContext SyncContext => Backend.SyncContext;

        // The OCaml runtime's root node id after Start, or null when the
        // runtime failed to boot (or Start was never called).
        public long? RootNode { get; private set; }

        public void Start(int platformCode = LUIOcamlBridge.PlatformWindows)
        {
            _bridge = new LUIOcamlBridge(Backend.Backend);
            long root = _bridge.Start(platformCode, LUIOcamlBridge.HostWinUI);
            RootNode = root < 0 ? null : root;
        }

        public void Dispose()
        {
            _bridge?.Dispose();
            _bridge = null;
        }
    }
}
