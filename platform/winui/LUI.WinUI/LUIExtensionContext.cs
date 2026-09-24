// Extension elements: the host app registers a factory+update pair per
// extension identifier. The factory creates the control once; update
// reapplies state. Child controls resolve through the element map so
// extension specs that allow standard children compose normally.

using System.Collections.Generic;
using Microsoft.UI.Xaml;

namespace LUI.WinUI
{
    public sealed class LUIExtensionContext
    {
        internal LUIExtensionContext(
            LUISyncContext sync, long nodeId, LUIExtensionNodeState state,
            IReadOnlyList<FrameworkElement> children)
        {
            Sync = sync;
            NodeId = nodeId;
            State = state;
            Children = children;
        }

        internal LUISyncContext Sync { get; }
        public long NodeId { get; }
        public LUIExtensionNodeState State { get; }
        public IReadOnlyList<FrameworkElement> Children { get; }
        public LUIBackend Backend => Sync.Backend;

        public void EmitEvent(string name) =>
            EmitEvent(name, new Dictionary<string, LUIWireValue>());

        public void EmitEvent(
            string name, Dictionary<string, LUIWireValue> values) =>
            Backend.PerformExtensionEvent(NodeId, name, values);
    }

    public delegate FrameworkElement LUIExtensionFactory(
        LUIExtensionContext context);

    public delegate void LUIExtensionUpdate(LUIExtensionContext context);

    public sealed class LUIExtensionVisual
    {
        public LUIExtensionVisual(
            LUIExtensionFactory factory, LUIExtensionUpdate? update = null)
        {
            Factory = factory;
            Update = update;
        }

        public LUIExtensionFactory Factory { get; }
        public LUIExtensionUpdate? Update { get; }
    }
}
