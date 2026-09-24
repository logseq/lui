// Thin managed wrapper over platform/native/lui_ocaml_bridge.c. The native
// library starts the OCaml runtime, calls back with a JSON patch batch after
// every forwarded event, and this class applies each batch to a LUIBackend.
//
// Host code 5 selects WinUIHost on the OCaml side; OS code 5 is WindowsOS.

using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;

namespace LUI
{
    public sealed class LUIOcamlBridge : System.IDisposable
    {
        public const int PlatformMacOS = 1;
        public const int PlatformIOS = 2;
        public const int PlatformAndroid = 3;
        public const int PlatformLinux = 4;
        public const int PlatformWindows = 5;

        public const int HostWeb = 1;
        public const int HostSwiftUI = 2;
        public const int HostFlutter = 3;
        // Host code 4 is reserved for the Qt/QML backend.
        public const int HostWinUI = 5;

        const string LibraryName = "lui_ocaml_bridge";

        [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
        delegate void PatchCallback(
            [MarshalAs(UnmanagedType.LPUTF8Str)] string json);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_start(
            PatchCallback callback, int platformCode, int hostCode);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_appear(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_press(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_long_press(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_text_changed(
            long node, [MarshalAs(UnmanagedType.LPUTF8Str)] string text);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_submit(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_dismiss(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_double_press(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_toggle_changed(long node, int checkedValue);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_radio_changed(long node);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_slider_changed(long node, double fraction);

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_stop();

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern long lui_ocaml_root_node();

        [DllImport(LibraryName, CallingConvention = CallingConvention.Cdecl)]
        static extern int lui_ocaml_extension_event(
            long node,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string identifier,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string name,
            [MarshalAs(UnmanagedType.LPUTF8Str)] string jsonValues);

        readonly LUIBackend _backend;
        readonly PatchCallback _patchCallback;
        bool _started;

        public LUIOcamlBridge(LUIBackend backend)
        {
            _backend = backend;
            _backend.OnEvent += HandleBackendEvent;
            _patchCallback = ApplyPatch;
        }

        public LUIBackend Backend => _backend;

        // Starts the embedded OCaml runtime and applies the initial patch
        // batch. The returned value is the root node id, or -1 on failure.
        public long Start(
            int platformCode = PlatformWindows, int hostCode = HostWinUI)
        {
            if (lui_ocaml_start(_patchCallback, platformCode, hostCode) == 0)
            {
                return -1;
            }
            _started = true;
            return lui_ocaml_root_node();
        }

        public int Stop() => _started ? lui_ocaml_stop() : 0;

        void ApplyPatch(string json) => _backend.ApplyJson(json);

        void HandleBackendEvent(LUIEvent payload)
        {
            if (!_started) return;
            switch (payload)
            {
                case LUIEvent.Appear appear:
                    lui_ocaml_appear(appear.Node);
                    break;
                case LUIEvent.Press press:
                    lui_ocaml_press(press.Node);
                    break;
                case LUIEvent.LongPress longPress:
                    lui_ocaml_long_press(longPress.Node);
                    break;
                case LUIEvent.DoublePress doublePress:
                    lui_ocaml_double_press(doublePress.Node);
                    break;
                case LUIEvent.Submit submit:
                    lui_ocaml_submit(submit.Node);
                    break;
                case LUIEvent.Dismiss dismiss:
                    lui_ocaml_dismiss(dismiss.Node);
                    break;
                case LUIEvent.Change change:
                    lui_ocaml_radio_changed(change.Node);
                    break;
                case LUIEvent.TextChanged textChanged:
                    lui_ocaml_text_changed(textChanged.Node, textChanged.Text);
                    break;
                case LUIEvent.ToggleChanged toggleChanged:
                    lui_ocaml_toggle_changed(
                        toggleChanged.Node, toggleChanged.Checked ? 1 : 0);
                    break;
                case LUIEvent.ValueChanged valueChanged:
                    lui_ocaml_slider_changed(valueChanged.Node, valueChanged.Value);
                    break;
                case LUIEvent.Extension extension:
                    lui_ocaml_extension_event(
                        extension.Node, extension.Identifier, extension.Name,
                        SerializeValues(extension.Values));
                    break;
            }
        }

        static string SerializeValues(
            IReadOnlyDictionary<string, LUIWireValue> values)
        {
            var stream = new MemoryStream();
            using (var writer = new Utf8JsonWriter(stream))
            {
                writer.WriteStartObject();
                foreach (KeyValuePair<string, LUIWireValue> entry in values)
                {
                    writer.WritePropertyName(entry.Key);
                    switch (entry.Value)
                    {
                        case LUIWireValue.String text:
                            writer.WriteStringValue(text.Value);
                            break;
                        case LUIWireValue.Bool boolean:
                            writer.WriteBooleanValue(boolean.Value);
                            break;
                        case LUIWireValue.Int integer:
                            writer.WriteNumberValue(integer.Value);
                            break;
                        case LUIWireValue.Float number:
                            writer.WriteNumberValue(number.Value);
                            break;
                    }
                }
                writer.WriteEndObject();
            }
            return System.Text.Encoding.UTF8.GetString(stream.ToArray());
        }

        public void Dispose()
        {
            _backend.OnEvent -= HandleBackendEvent;
            if (_started)
            {
                lui_ocaml_stop();
                _started = false;
            }
        }
    }
}
