using LUI.WinUI;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace LUI.Demo
{
    public sealed class MainWindow : Window
    {
        public MainWindow()
        {
            Title = "LUI WinUI Demo";
            _host = new LUIWinUIHost();
            try
            {
                // The embedded OCaml runtime emits the initial patch batch
                // through the bridge; gestures flow back via lui_ocaml_*.
                _host.Start();
            }
            catch (System.Exception)
            {
                // The native lui_ocaml_bridge library must be built first
                // (see platform/native/ and the README). Still exercise the
                // full C# pipeline — parse + validate + retained sync — by
                // feeding a canned patch batch straight into ApplyJson.
                _host.Backend.ApplyJson(SmokeTestBatch);
            }
            Content = _host.Root;
            Closed += (_, _) => _host.Dispose();
        }

        const string SmokeTestBatch =
            "{\"generation\":1,\"ops\":["
            + "{\"op\":\"create-node\",\"id\":1,\"kind\":\"root\"},"
            + "{\"op\":\"create-node\",\"id\":2,\"kind\":\"column\"},"
            + "{\"op\":\"set-prop\",\"id\":2,\"property\":\"padding\",\"value\":32},"
            + "{\"op\":\"set-prop\",\"id\":2,\"property\":\"gap\",\"value\":16},"
            + "{\"op\":\"insert-child\",\"parent\":1,\"child\":2,\"index\":0},"
            + "{\"op\":\"create-node\",\"id\":3,\"kind\":\"heading\"},"
            + "{\"op\":\"set-prop\",\"id\":3,\"property\":\"text\",\"value\":\"LUI on WinUI 3\"},"
            + "{\"op\":\"set-prop\",\"id\":3,\"property\":\"heading-level\",\"value\":1},"
            + "{\"op\":\"insert-child\",\"parent\":2,\"child\":3,\"index\":0},"
            + "{\"op\":\"create-node\",\"id\":4,\"kind\":\"alert\"},"
            + "{\"op\":\"set-prop\",\"id\":4,\"property\":\"variant\",\"value\":\"warning\"},"
            + "{\"op\":\"set-prop\",\"id\":4,\"property\":\"text\",\"value\":\"OCaml bridge unavailable — this tree comes from a canned patch batch via ApplyJson.\"},"
            + "{\"op\":\"insert-child\",\"parent\":2,\"child\":4,\"index\":1},"
            + "{\"op\":\"create-node\",\"id\":5,\"kind\":\"text\"},"
            + "{\"op\":\"set-prop\",\"id\":5,\"property\":\"text\",\"value\":\"Retained sync: controls below update in place per batch.\"},"
            + "{\"op\":\"insert-child\",\"parent\":2,\"child\":5,\"index\":2},"
            + "{\"op\":\"create-node\",\"id\":6,\"kind\":\"row\"},"
            + "{\"op\":\"set-prop\",\"id\":6,\"property\":\"gap\",\"value\":12},"
            + "{\"op\":\"insert-child\",\"parent\":2,\"child\":6,\"index\":3},"
            + "{\"op\":\"create-node\",\"id\":7,\"kind\":\"button\"},"
            + "{\"op\":\"set-prop\",\"id\":7,\"property\":\"text\",\"value\":\"Primary button\"},"
            + "{\"op\":\"set-prop\",\"id\":7,\"property\":\"variant\",\"value\":\"primary\"},"
            + "{\"op\":\"set-prop\",\"id\":7,\"property\":\"enabled\",\"value\":true},"
            + "{\"op\":\"insert-child\",\"parent\":6,\"child\":7,\"index\":0},"
            + "{\"op\":\"create-node\",\"id\":8,\"kind\":\"checkbox\"},"
            + "{\"op\":\"set-prop\",\"id\":8,\"property\":\"text\",\"value\":\"A checkbox\"},"
            + "{\"op\":\"set-prop\",\"id\":8,\"property\":\"checked\",\"value\":true},"
            + "{\"op\":\"insert-child\",\"parent\":6,\"child\":8,\"index\":1},"
            + "{\"op\":\"create-node\",\"id\":9,\"kind\":\"toggle\"},"
            + "{\"op\":\"set-prop\",\"id\":9,\"property\":\"text\",\"value\":\"A toggle\"},"
            + "{\"op\":\"insert-child\",\"parent\":6,\"child\":9,\"index\":2},"
            + "{\"op\":\"create-node\",\"id\":10,\"kind\":\"text-field\"},"
            + "{\"op\":\"set-prop\",\"id\":10,\"property\":\"placeholder\",\"value\":\"Type here…\"},"
            + "{\"op\":\"insert-child\",\"parent\":2,\"child\":10,\"index\":4},"
            + "{\"op\":\"create-node\",\"id\":11,\"kind\":\"slider\"},"
            + "{\"op\":\"insert-child\",\"parent\":2,\"child\":11,\"index\":5}"
            + "]}";

        readonly LUIWinUIHost _host;
    }
}
