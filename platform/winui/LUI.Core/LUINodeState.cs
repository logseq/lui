// Retained node state and event/result types shared between the protocol
// backend and the rendering layer.

using System.Collections.Generic;

namespace LUI
{
    public sealed class LUINodeState
    {
        public LUINodeState(LUINodeKind kind) => Kind = kind;

        public LUINodeKind Kind { get; }
        public long? Parent { get; set; }
        public List<long> Children { get; } = new List<long>();
        public Dictionary<LUIProperty, LUIWireValue> Properties { get; } =
            new Dictionary<LUIProperty, LUIWireValue>();

        public LUINodeState Copy()
        {
            LUINodeState copy = new LUINodeState(Kind) { Parent = Parent };
            copy.Children.AddRange(Children);
            foreach (KeyValuePair<LUIProperty, LUIWireValue> entry in Properties)
            {
                copy.Properties[entry.Key] = entry.Value;
            }
            return copy;
        }

        public bool RendersLike(LUINodeState other) =>
            Kind == other.Kind &&
            Parent == other.Parent &&
            ChildrenEqual(Children, other.Children) &&
            PropertiesEqual(Properties, other.Properties);

        internal static bool ChildrenEqual(List<long> a, List<long> b)
        {
            if (a.Count != b.Count) return false;
            for (int i = 0; i < a.Count; i++)
            {
                if (a[i] != b[i]) return false;
            }
            return true;
        }

        internal static bool PropertiesEqual<TKey>(
            Dictionary<TKey, LUIWireValue> a, Dictionary<TKey, LUIWireValue> b)
            where TKey : notnull
        {
            if (a.Count != b.Count) return false;
            foreach (KeyValuePair<TKey, LUIWireValue> entry in a)
            {
                if (!b.TryGetValue(entry.Key, out LUIWireValue? value) ||
                    !entry.Value.Equals(value))
                {
                    return false;
                }
            }
            return true;
        }
    }

    public sealed class LUIExtensionNodeState
    {
        public LUIExtensionNodeState(string identifier, string fingerprint)
        {
            Identifier = identifier;
            Fingerprint = fingerprint;
        }

        public string Identifier { get; }
        public string Fingerprint { get; }
        public long? Parent { get; set; }
        public List<long> Children { get; } = new List<long>();
        public Dictionary<string, LUIWireValue> Properties { get; } =
            new Dictionary<string, LUIWireValue>();

        public LUIExtensionNodeState Copy()
        {
            LUIExtensionNodeState copy =
                new LUIExtensionNodeState(Identifier, Fingerprint)
                { Parent = Parent };
            copy.Children.AddRange(Children);
            foreach (KeyValuePair<string, LUIWireValue> entry in Properties)
            {
                copy.Properties[entry.Key] = entry.Value;
            }
            return copy;
        }

        public bool RendersLike(LUIExtensionNodeState other) =>
            Identifier == other.Identifier &&
            Fingerprint == other.Fingerprint &&
            Parent == other.Parent &&
            LUINodeState.ChildrenEqual(Children, other.Children) &&
            LUINodeState.PropertiesEqual(Properties, other.Properties);
    }

    public sealed record LUIRootSection(long Id, string Title);

    public abstract record LUIEvent
    {
        private LUIEvent() { }

        public abstract long Node { get; init; }

        public sealed record Appear(long Node) : LUIEvent;
        public sealed record Press(long Node) : LUIEvent;
        public sealed record LongPress(long Node) : LUIEvent;
        public sealed record DoublePress(long Node) : LUIEvent;
        public sealed record Submit(long Node) : LUIEvent;
        public sealed record Dismiss(long Node) : LUIEvent;
        public sealed record Change(long Node) : LUIEvent;
        public sealed record TextChanged(long Node, string Text) : LUIEvent;
        public sealed record ToggleChanged(long Node, bool Checked) : LUIEvent;
        public sealed record ValueChanged(long Node, double Value) : LUIEvent;
        public sealed record Extension(
            long Node, string Identifier, string Name,
            IReadOnlyDictionary<string, LUIWireValue> Values) : LUIEvent;
    }

    // The node IDs a successfully committed batch touched: `Changed` nodes
    // render differently than before, `Dependent` nodes only need
    // re-evaluation against their children (e.g. bottom-tabs selection), and
    // `Removed` nodes no longer exist.
    public sealed class LUIApplyResult
    {
        public IReadOnlySet<long> Changed { get; internal set; } =
            new HashSet<long>();
        public IReadOnlySet<long> Dependent { get; internal set; } =
            new HashSet<long>();
        public IReadOnlyList<long> Removed { get; internal set; } =
            new List<long>();
    }
}
