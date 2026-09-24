// The WinUI rendering engine: owns the protocol backend, the element map,
// and the root surface. Each committed batch re-syncs only the elements the
// backend marked changed/dependent, disposes removed ones, and refreshes
// overlays (dropdowns, modals, toasts). Controls are diffed in place — a
// focused field keeps focus across every batch.

using System;
using System.Collections.Generic;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;

namespace LUI.WinUI
{
    public sealed class LUIWinUIBackend
    {
        readonly Dictionary<long, LUIElement> _elements =
            new Dictionary<long, LUIElement>();
        readonly Dictionary<UIElement, LUIElement> _byControl =
            new Dictionary<UIElement, LUIElement>();
        readonly Dictionary<string, LUIExtensionVisual> _extensionVisuals =
            new Dictionary<string, LUIExtensionVisual>();
        // Open dropdown flyouts keyed by their anchor element id.
        readonly Dictionary<long, MenuFlyout> _openDropdowns =
            new Dictionary<long, MenuFlyout>();
        readonly Dictionary<long, long> _dropdownMenuIds =
            new Dictionary<long, long>();
        readonly LUISyncContext _context;
        readonly LUIModalPresenter _presenter;
        readonly HashSet<Panel> _relativeSized = new HashSet<Panel>();
        long? _rootId;

        public LUIWinUIBackend()
        {
            Backend = new LUIBackend();
            Root = new LUIWinUIRoot();
            _context = new LUISyncContext(this, Backend);
            _presenter = new LUIModalPresenter(Root.Overlay, _context);
            Backend.Applied += OnApplied;
            Backend.MediaInvalidated += ids => MediaInvalidated?.Invoke(ids);
        }

        public LUIBackend Backend { get; }
        public LUIWinUIRoot Root { get; }

        // Raised when an image/media-surface frame is invalidated by the
        // runtime; the host app re-registers the fresh frame in
        // Context.Images / Context.Surfaces.
        public event Action<IReadOnlyCollection<long>>? MediaInvalidated;

        public LUISyncContext SyncContext => _context;

        public void ApplyJson(string json) => Backend.ApplyJson(json);

        // Registers the visual for an extension identifier. The Core
        // registry must already contain the spec (register specs first).
        public void RegisterExtensionVisual(
            string identifier, LUIExtensionVisual visual) =>
            _extensionVisuals[identifier] = visual;

        internal LUIElement ElementFor(long id)
        {
            if (_elements.TryGetValue(id, out LUIElement? existing))
            {
                return existing;
            }
            LUIElement element;
            if (Backend.States.TryGetValue(id, out LUINodeState? state))
            {
                element = new LUIElement(
                    id, state.Kind, LUIElementFactory.Create(state.Kind));
                _elements[id] = element;
                _byControl[element.Control] = element;
                element.Sync(state, _context);
            }
            else if (Backend.ExtensionStates.TryGetValue(
                         id, out LUIExtensionNodeState? extension))
            {
                element = CreateExtensionElement(id, extension);
            }
            else
            {
                // Node dropped between the parent's batch commit and this
                // lookup — render nothing.
                return new LUIElement(id, LUINodeKind.Spacer, new Grid());
            }
            return element;
        }

        LUIElement CreateExtensionElement(
            long id, LUIExtensionNodeState extension)
        {
            FrameworkElement control;
            if (!_extensionVisuals.TryGetValue(
                    extension.Identifier, out LUIExtensionVisual? visual))
            {
                // Unregistered extension identifier: placeholder keeps the
                // tree shaped correctly instead of throwing mid-sync.
                var placeholder = new Border();
                placeholder.Child = new TextBlock
                {
                    Text = $"unknown extension {extension.Identifier}",
                };
                control = placeholder;
                visual = new LUIExtensionVisual(_ => placeholder, null);
            }
            else
            {
                var children = new List<FrameworkElement>();
                var initial = new LUIExtensionContext(
                    _context, id, extension, children);
                control = visual.Factory(initial);
            }
            var element = new LUIElement(id, control, visual);
            _elements[id] = element;
            _byControl[control] = element;
            element.Sync(extension, _context);
            return element;
        }

        void RemoveElement(long id)
        {
            if (_elements.TryGetValue(id, out LUIElement? element))
            {
                element.Dispose();
                _byControl.Remove(element.Control);
                _elements.Remove(id);
            }
            if (_openDropdowns.TryGetValue(id, out MenuFlyout? flyout))
            {
                flyout.Hide();
                _openDropdowns.Remove(id);
                _dropdownMenuIds.Remove(id);
            }
        }

        void OnApplied(LUIApplyResult result)
        {
            foreach (long removed in result.Removed)
            {
                RemoveElement(removed);
            }
            long? rootId = FindRoot();
            if (rootId == null) return;
            _rootId = rootId;
            // The root element renders its children into Root.Content; it
            // re-syncs whenever its own state changed or it does not exist
            // yet.
            bool rootChanged = result.Changed.Contains(rootId.Value) ||
                result.Dependent.Contains(rootId.Value) ||
                !_elements.ContainsKey(rootId.Value);
            LUIElement root = ElementFor(rootId.Value);
            if (rootChanged)
            {
                root.Sync(Backend.RequireState(rootId.Value), _context);
            }
            if (Root.Content.Children.Count == 0 ||
                !ReferenceEquals(Root.Content.Children[0], root.Control))
            {
                Root.Content.Children.Clear();
                Root.Content.Children.Add(root.Control);
            }
            foreach (long id in result.Changed)
            {
                if (id == rootId.Value) continue;
                if (_elements.TryGetValue(id, out LUIElement? element))
                {
                    if (Backend.States.TryGetValue(
                            id, out LUINodeState? state))
                    {
                        element.Sync(state, _context);
                    }
                    else if (Backend.ExtensionStates.TryGetValue(
                                 id, out LUIExtensionNodeState? extension))
                    {
                        element.Sync(extension, _context);
                    }
                }
            }
            foreach (long id in result.Dependent)
            {
                if (id == rootId.Value) continue;
                if (_elements.TryGetValue(id, out LUIElement? element) &&
                    Backend.States.TryGetValue(id, out LUINodeState? state))
                {
                    element.Sync(state, _context);
                }
            }
            _presenter.Sync(SurfaceIds());
        }

        long? FindRoot()
        {
            foreach (KeyValuePair<long, LUINodeState> entry in Backend.States)
            {
                if (entry.Value.Kind == LUINodeKind.Root)
                {
                    return entry.Key;
                }
            }
            return null;
        }

        List<long> SurfaceIds()
        {
            var surfaces = new List<long>();
            foreach (KeyValuePair<long, LUINodeState> entry in Backend.States)
            {
                if (LUISchema.ModalSurface(entry.Value.Kind) ||
                    entry.Value.Kind == LUINodeKind.Toast)
                {
                    surfaces.Add(entry.Key);
                }
            }
            return surfaces;
        }

        // Retained dropdown flyout for a `stack` element: present in the
        // tree means open. Item content refreshes in place each batch; the
        // menu node id changes (or disappears) -> rebuild/hide.
        internal void SyncDropdown(
            LUIElement anchor, LUINodeState? menu, long menuId)
        {
            if (menu == null)
            {
                if (anchor.Flyout != null)
                {
                    anchor.Flyout.Hide();
                    anchor.Flyout = null;
                    _openDropdowns.Remove(anchor.Id);
                    _dropdownMenuIds.Remove(anchor.Id);
                }
                return;
            }
            if (anchor.Flyout is MenuFlyout open &&
                _dropdownMenuIds.TryGetValue(anchor.Id, out long openMenu) &&
                openMenu == menuId)
            {
                LUIMenuBuilder.Fill(_context, open.Items, menu);
                return;
            }
            anchor.Flyout?.Hide();
            var flyout = (MenuFlyout)LUIMenuBuilder.Build(
                _context, menuId, menu);
            anchor.Flyout = flyout;
            _openDropdowns[anchor.Id] = flyout;
            _dropdownMenuIds[anchor.Id] = menuId;
            string anchorEdge = LUIPropertyApplier.Prop(
                menu, LUIProperty.AnchorValue)?.AsString ?? "below";
            flyout.Placement = anchorEdge switch
            {
                "above" => FlyoutPlacementMode.Top,
                "left" => FlyoutPlacementMode.Left,
                "right" => FlyoutPlacementMode.Right,
                _ => FlyoutPlacementMode.Bottom,
            };
            flyout.ShowAt(anchor.Control);
        }

        // Diffs a panel's element children against `want`: removes controls
        // for dropped ids (disposing their elements), inserts missing ones,
        // and reorders to match. Non-element children (splitter thumbs, tree
        // row wrappers) are left alone — owners manage them.
        internal void SyncPanelChildren(
            Panel panel, IReadOnlyList<long> want,
            Func<int, (int Column, int Row)>? place = null)
        {
            var desired = new List<UIElement>(want.Count);
            var desiredSet = new HashSet<UIElement>();
            foreach (long id in want)
            {
                UIElement control = ElementFor(id).Control;
                desired.Add(control);
                desiredSet.Add(control);
            }
            for (int i = panel.Children.Count - 1; i >= 0; i--)
            {
                UIElement child = panel.Children[i];
                if (_byControl.TryGetValue(child, out LUIElement? element) &&
                    !desiredSet.Contains(child))
                {
                    DetachChildren(child);
                    panel.Children.RemoveAt(i);
                    RemoveElement(element.Id);
                }
            }
            // Enforce ordering among element children: move each to its
            // desired index slot counting element children only.
            int slot = 0;
            foreach (UIElement control in desired)
            {
                int position = ElementChildIndex(panel, control);
                if (position < 0)
                {
                    panel.Children.Insert(slot, control);
                }
                else if (position != slot)
                {
                    panel.Children.RemoveAt(position);
                    panel.Children.Insert(slot, control);
                }
                slot++;
            }
            if (place != null && panel is Grid grid)
            {
                for (int i = 0; i < desired.Count; i++)
                {
                    (int column, int row) = place(i);
                    Grid.SetColumn((FrameworkElement)desired[i], column);
                    Grid.SetRow((FrameworkElement)desired[i], row);
                }
            }
            HookRelativeFrameSizing(panel, want);
        }

        int ElementChildIndex(Panel panel, UIElement control)
        {
            int slot = 0;
            foreach (UIElement child in panel.Children)
            {
                if (!_byControl.ContainsKey(child)) continue;
                if (ReferenceEquals(child, control)) return slot;
                slot++;
            }
            return -1;
        }

        // Full replacement for computed containers (tree rows, bottom-tab
        // bars). Detaches element controls before clearing so they stay
        // parentable.
        internal void ReplaceChildren(Panel panel, List<UIElement> items)
        {
            foreach (UIElement child in panel.Children)
            {
                DetachChildren(child);
            }
            panel.Children.Clear();
            foreach (UIElement item in items)
            {
                panel.Children.Add(item);
            }
        }

        static void DetachChildren(UIElement element)
        {
            if (element is Panel panel)
            {
                foreach (UIElement child in panel.Children)
                {
                    DetachChildren(child);
                }
                panel.Children.Clear();
            }
        }

        // Children carrying container-relative-frame get an explicit size =
        // fraction of the parent box minus the inset, recomputed whenever
        // the panel's actual size changes.
        void HookRelativeFrameSizing(Panel panel, IReadOnlyList<long> want)
        {
            bool any = false;
            foreach (long id in want)
            {
                if (Backend.States.TryGetValue(id, out LUINodeState? child) &&
                    child.Properties.ContainsKey(
                        LUIProperty.ContainerRelativeFrameValue))
                {
                    any = true;
                    break;
                }
            }
            if (!any) return;
            if (!_relativeSized.Add(panel)) return;
            panel.SizeChanged += (_, _) => ApplyRelativeSizes(panel);
            ApplyRelativeSizes(panel);
        }

        void ApplyRelativeSizes(Panel panel)
        {
            foreach (UIElement child in panel.Children)
            {
                if (!_byControl.TryGetValue(child, out LUIElement? element) ||
                    !Backend.States.TryGetValue(
                        element.Id, out LUINodeState? state))
                {
                    continue;
                }
                string? mode = LUIPropertyApplier.Prop(
                    state, LUIProperty.ContainerRelativeFrameValue)?.AsString;
                if (mode == null || child is not FrameworkElement fe)
                {
                    continue;
                }
                double inset = LUIPropertyApplier.Prop(
                    state, LUIProperty.ContainerRelativeFrameInset)
                    ?.AsFloat ?? 0;
                switch (mode)
                {
                    case "horizontal":
                    case "both":
                        fe.Width = Math.Max(
                            0, panel.ActualWidth - 2 * inset);
                        fe.HorizontalAlignment = HorizontalAlignment.Left;
                        fe.Margin = new Thickness(inset, fe.Margin.Top,
                            inset, fe.Margin.Bottom);
                        if (mode == "horizontal") break;
                        goto case "vertical";
                    case "vertical":
                        fe.Height = Math.Max(
                            0, panel.ActualHeight - 2 * inset);
                        fe.VerticalAlignment = VerticalAlignment.Top;
                        fe.Margin = new Thickness(fe.Margin.Left, inset,
                            fe.Margin.Right, inset);
                        break;
                }
            }
        }
    }
}
