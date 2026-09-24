// One retained FrameworkElement per node id. Sync re-applies node state in
// place — controls are never rebuilt, so focus survives across batches.
// Gesture wiring calls the protocol gates in LUIBackend; a rejected gesture
// is a no-op (LUIBackendException is swallowed), matching the other
// backends' behavior of never wiring disabled gestures.

using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;

namespace LUI.WinUI
{
    public sealed partial class LUIElement
    {
        internal LUIElement(long id, LUINodeKind kind, FrameworkElement control)
        {
            Id = id;
            Kind = kind;
            Control = control;
            WireGestures();
        }

        // Extension elements have no node kind — the visual was produced by
        // the host app's registered extension factory instead.
        internal LUIElement(
            long id, FrameworkElement control,
            LUIExtensionVisual visual)
        {
            Id = id;
            Kind = null;
            Control = control;
            _extensionVisual = visual;
            WireGestures();
        }

        public long Id { get; }
        public LUINodeKind? Kind { get; }
        public FrameworkElement Control { get; }
        internal LUISyncContext? Context { get; private set; }
        readonly LUIExtensionVisual? _extensionVisual;

        // True while this element hosts an open dropdown-menu flyout.
        internal FlyoutBase? Flyout;

        // The panel that receives this element's children, if the kind is a
        // container. Unwraps the Border/ScrollViewer/Expander shells the
        // factory places around the inner LUIGrid.
        internal Panel? ChildrenPanel => Control switch
        {
            LUIGrid grid => grid,
            Border { Child: Panel panel } => panel,
            ScrollViewer { Content: Panel panel } => panel,
            Expander { Content: Panel panel } => panel,
            InfoBar { Content: Panel panel } => panel,
            _ => null,
        };

        internal void Sync(LUINodeState state, LUISyncContext context)
        {
            Context = context;
            LUIPropertyApplier.Apply(Control, state, context);
            SyncKind(state, context);
            SyncOverlays(state, context);
        }

        internal void Sync(
            LUIExtensionNodeState state, LUISyncContext context)
        {
            Context = context;
            var children = new List<FrameworkElement>();
            foreach (long childId in state.Children)
            {
                children.Add(context.ElementFor(childId).Control);
            }
            _extensionVisual?.Update?.Invoke(
                new LUIExtensionContext(context, Id, state, children));
        }

        static void Gate(System.Action action)
        {
            try
            {
                action();
            }
            catch (LUIBackendException)
            {
                // Gesture fired on a control whose protocol gate is closed.
            }
        }

        void WireGestures()
        {
            Control.Loaded += (_, _) =>
            {
                LUISyncContext? context = Context;
                if (context != null)
                {
                    Gate(() => context.Backend.PerformAppear(Id));
                }
            };
            Control.Tapped += (_, _) =>
            {
                LUISyncContext? context = Context;
                if (context != null)
                {
                    Gate(() => context.Backend.PerformAction(Id));
                }
            };
            Control.DoubleTapped += (_, _) =>
            {
                LUISyncContext? context = Context;
                if (context != null)
                {
                    Gate(() => context.Backend.PerformDoublePress(Id));
                }
            };
            Control.RightTapped += (_, args) =>
            {
                LUISyncContext? context = Context;
                if (context != null && HasContextMenu(context))
                {
                    args.Handled = true;
                    Control.ContextFlyout?.ShowAt(
                        Control,
                        new Microsoft.UI.Xaml.Controls.Primitives.FlyoutShowOptions
                        {
                            Position = args.GetPosition(Control),
                        });
                }
            };
            Control.Holding += (_, args) =>
            {
                LUISyncContext? context = Context;
                if (context == null ||
                    args.HoldingState != Microsoft.UI.Input.HoldingState.Started)
                {
                    return;
                }
                if (HasContextMenu(context))
                {
                    Control.ContextFlyout?.ShowAt(Control);
                }
                else
                {
                    Gate(() => context.Backend.PerformLongPress(Id));
                }
            };
        }

        bool HasContextMenu(LUISyncContext context)
        {
            if (!context.Backend.States.TryGetValue(
                    Id, out LUINodeState? state))
            {
                return false;
            }
            foreach (long childId in state.Children)
            {
                if (context.Backend.States.TryGetValue(
                        childId, out LUINodeState? child) &&
                    child.Kind == LUINodeKind.ContextMenu)
                {
                    return true;
                }
            }
            return false;
        }

        // Attaches overlay children: context menus onto this control, and —
        // for `stack` — dropdown menus as anchored flyouts and tooltips via
        // ToolTipService. Modal surfaces and toasts are handled by the root
        // presenter instead.
        void SyncOverlays(LUINodeState state, LUISyncContext context)
        {
            FlyoutBase? contextFlyout = null;
            ToolTip? toolTip = null;
            LUINodeState? dropdown = null;
            long dropdownId = -1;
            foreach (long childId in state.Children)
            {
                if (!context.Backend.States.TryGetValue(
                        childId, out LUINodeState? child))
                {
                    continue;
                }
                switch (child.Kind)
                {
                    case LUINodeKind.ContextMenu:
                        contextFlyout =
                            LUIMenuBuilder.Build(context, childId, child);
                        break;
                    case LUINodeKind.DropdownMenu
                        when Kind == LUINodeKind.Stack:
                        dropdown = child;
                        dropdownId = childId;
                        break;
                    case LUINodeKind.Tooltip when Kind == LUINodeKind.Stack:
                        toolTip = LUIMenuBuilder.BuildToolTip(child);
                        break;
                    case LUINodeKind.Tooltip:
                        toolTip = LUIMenuBuilder.BuildToolTip(child);
                        break;
                }
            }
            Control.ContextFlyout = contextFlyout;
            if (Kind == LUINodeKind.Stack)
            {
                context.Host.SyncDropdown(this, dropdown, dropdownId);
                if (toolTip != null)
                {
                    ToolTipService.SetToolTip(Control, toolTip);
                }
            }
            else if (toolTip != null)
            {
                ToolTipService.SetToolTip(Control, toolTip);
            }
            else
            {
                ToolTipService.SetToolTip(Control, null);
            }
        }

        internal void Dispose()
        {
            Flyout?.Hide();
            Context = null;
        }
    }
}
