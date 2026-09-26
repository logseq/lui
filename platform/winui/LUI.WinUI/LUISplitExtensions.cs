// Bonsplit-style tabbed split panes for the WinUI backend.
//
// The OCaml app owns the tree (see src/lui_split.ml); these controls own
// gesture-time visuals — drag feedback, drop-zone highlight, live divider —
// and only committed actions cross the bridge.
//
// Register both halves at startup:
//   LUISplitExtensions.Register(backend);
// (specs first so create-extension ops validate, then visuals so nodes
// render.)

using System;
using System.Collections.Generic;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using Windows.UI.Core;

namespace LUI.WinUI
{
    public static class LUISplitExtensions
    {
        const string ViewFingerprint =
            "lui-extension-v1|10:split-view|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:17:divider-thickness:float:optional:none,24:accessibility-identifier:string:optional:none,9:animation:bool:optional:none|events:";
        const string BranchFingerprint =
            "lui-extension-v1|12:split-branch|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:12:split-branch,10:split-pane|properties:11:orientation:string:required:none,5:ratio:float:required:none|events:13:ratio-changed[5:ratio:float:required]";
        const string PaneFingerprint =
            "lui-extension-v1|10:split-pane|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:0|children:9:split-tab|properties:24:accessibility-identifier:string:optional:none,7:focused:bool:optional:none,7:pane-id:string:required:none,8:selected:string:optional:none|events:10:split-drop[3:tab:string:required,4:edge:string:required,9:from-pane:string:required],10:tab-closed[3:tab:string:required],11:pane-closed[],12:pane-focused[],12:tab-selected[3:tab:string:required],15:split-requested[11:orientation:string:required],8:navigate[9:direction:string:required],9:tab-moved[3:tab:string:required,5:index:int:required,9:from-pane:string:required]";
        const string TabFingerprint =
            "lui-extension-v1|9:split-tab|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,linux/qml,macos/flutter,macos/qml,macos/swiftui,web/web,windows/flutter,windows/qml,windows/winui|standard-children:1|children:|properties:24:accessibility-identifier:string:optional:none,4:icon:string:optional:none,5:dirty:bool:optional:none,5:title:string:required:none,6:tab-id:string:required:none,8:closable:bool:optional:none|events:";

        static readonly LUIExtensionProperty AccessibilityIdentifier =
            new LUIExtensionProperty(
                "accessibility-identifier", LUIExtensionValueKind.String);

        public static void Register(LUIWinUIBackend backend)
        {
            LUIExtensionRegistry registry = backend.Backend.Extensions;
            registry.Register(new LUIExtensionSpec(
                "split-view", ViewFingerprint,
                childIdentifiers: new[] { "split-branch", "split-pane" },
                properties: new[]
                {
                    new LUIExtensionProperty(
                        "divider-thickness", LUIExtensionValueKind.DoubleValue),
                    new LUIExtensionProperty(
                        "animation", LUIExtensionValueKind.Boolean),
                    AccessibilityIdentifier,
                }));
            registry.Register(new LUIExtensionSpec(
                "split-branch", BranchFingerprint,
                childIdentifiers: new[] { "split-branch", "split-pane" },
                properties: new[]
                {
                    new LUIExtensionProperty(
                        "orientation", LUIExtensionValueKind.String,
                        isRequired: true),
                    new LUIExtensionProperty(
                        "ratio", LUIExtensionValueKind.DoubleValue,
                        isRequired: true),
                },
                events: new[]
                {
                    new LUIExtensionEventSchema(
                        "ratio-changed",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "ratio", LUIExtensionValueKind.DoubleValue,
                                isRequired: true),
                        }),
                }));
            registry.Register(new LUIExtensionSpec(
                "split-pane", PaneFingerprint,
                childIdentifiers: new[] { "split-tab" },
                properties: new[]
                {
                    new LUIExtensionProperty(
                        "pane-id", LUIExtensionValueKind.String,
                        isRequired: true),
                    new LUIExtensionProperty(
                        "selected", LUIExtensionValueKind.String),
                    new LUIExtensionProperty(
                        "focused", LUIExtensionValueKind.Boolean),
                    AccessibilityIdentifier,
                },
                events: new[]
                {
                    new LUIExtensionEventSchema(
                        "tab-selected",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "tab", LUIExtensionValueKind.String,
                                isRequired: true),
                        }),
                    new LUIExtensionEventSchema(
                        "tab-closed",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "tab", LUIExtensionValueKind.String,
                                isRequired: true),
                        }),
                    new LUIExtensionEventSchema(
                        "tab-moved",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "tab", LUIExtensionValueKind.String,
                                isRequired: true),
                            new LUIExtensionEventField(
                                "index", LUIExtensionValueKind.Integer,
                                isRequired: true),
                            new LUIExtensionEventField(
                                "from-pane", LUIExtensionValueKind.String,
                                isRequired: true),
                        }),
                    new LUIExtensionEventSchema("pane-focused"),
                    new LUIExtensionEventSchema(
                        "navigate",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "direction", LUIExtensionValueKind.String,
                                isRequired: true),
                        }),
                    new LUIExtensionEventSchema(
                        "split-requested",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "orientation", LUIExtensionValueKind.String,
                                isRequired: true),
                        }),
                    new LUIExtensionEventSchema(
                        "split-drop",
                        new[]
                        {
                            new LUIExtensionEventField(
                                "tab", LUIExtensionValueKind.String,
                                isRequired: true),
                            new LUIExtensionEventField(
                                "from-pane", LUIExtensionValueKind.String,
                                isRequired: true),
                            new LUIExtensionEventField(
                                "edge", LUIExtensionValueKind.String,
                                isRequired: true),
                        }),
                    new LUIExtensionEventSchema("pane-closed"),
                }));
            registry.Register(new LUIExtensionSpec(
                "split-tab", TabFingerprint,
                acceptsStandardChildren: true,
                properties: new[]
                {
                    new LUIExtensionProperty(
                        "tab-id", LUIExtensionValueKind.String,
                        isRequired: true),
                    new LUIExtensionProperty(
                        "title", LUIExtensionValueKind.String,
                        isRequired: true),
                    new LUIExtensionProperty(
                        "icon", LUIExtensionValueKind.String),
                    new LUIExtensionProperty(
                        "dirty", LUIExtensionValueKind.Boolean),
                    new LUIExtensionProperty(
                        "closable", LUIExtensionValueKind.Boolean),
                    AccessibilityIdentifier,
                }));

            backend.RegisterExtensionVisual(
                "split-view", new LUIExtensionVisual(
                    _ => new SplitViewControl(),
                    context =>
                    {
                        var control = (SplitViewControl)FindControl(context);
                        control.Update(context);
                    }));
            backend.RegisterExtensionVisual(
                "split-branch", new LUIExtensionVisual(
                    _ => new SplitBranchControl(),
                    context =>
                    {
                        var control = (SplitBranchControl)FindControl(context);
                        control.Update(context);
                    }));
            backend.RegisterExtensionVisual(
                "split-pane", new LUIExtensionVisual(
                    _ => new SplitPaneControl(),
                    context =>
                    {
                        var control = (SplitPaneControl)FindControl(context);
                        control.Update(context);
                    }));
            backend.RegisterExtensionVisual(
                "split-tab", new LUIExtensionVisual(
                    _ => new SplitTabControl(),
                    context =>
                    {
                        var control = (SplitTabControl)FindControl(context);
                        control.Update(context);
                    }));
        }

        // The factory returned the control itself; Update receives a fresh
        // context — recover the control via the element map.
        static FrameworkElement FindControl(LUIExtensionContext context) =>
            context.Sync.ElementFor(context.NodeId).Control;

        internal static string? StringProp(
            LUIExtensionNodeState state, string name) =>
            state.Properties.TryGetValue(name, out LUIWireValue? value)
                ? value.AsString
                : null;

        internal static bool BoolProp(
            LUIExtensionNodeState state, string name, bool fallback = false) =>
            state.Properties.TryGetValue(name, out LUIWireValue? value)
                ? value.AsBool ?? fallback
                : fallback;

        internal static double DoubleProp(
            LUIExtensionNodeState state, string name, double fallback) =>
            state.Properties.TryGetValue(name, out LUIWireValue? value)
                ? value.AsFloat ?? fallback
                : fallback;

        internal static string ChildString(
            LUIExtensionContext context, long childId, string name)
        {
            var state = context.Backend.RequireExtensionState(childId);
            return StringProp(state, name) ?? "";
        }

        internal static bool ChildBool(
            LUIExtensionContext context, long childId, string name,
            bool fallback = false)
        {
            var state = context.Backend.RequireExtensionState(childId);
            return BoolProp(state, name, fallback);
        }

        // Drag payload: pane-id TAB tab-id.
        internal static string PackDrag(string pane, string tab) =>
            pane + "\t" + tab;

        internal static bool UnpackDrag(
            string payload, out string pane, out string tab)
        {
            int split = payload.IndexOf('\t');
            pane = split < 0 ? "" : payload.Substring(0, split);
            tab = split < 0 ? "" : payload.Substring(split + 1);
            return split > 0;
        }
    }

    // MARK: - split-view

    /// Hosts the single split-tree child and broadcasts view settings.
    public sealed class SplitViewControl : Grid
    {
        public double DividerThickness { get; private set; } = 9;
        public bool AnimationEnabled { get; private set; } = true;

        public void Update(LUIExtensionContext context)
        {
            DividerThickness = Math.Clamp(
                LUISplitExtensions.DoubleProp(
                    context.State, "divider-thickness", 9),
                1, double.MaxValue);
            AnimationEnabled = LUISplitExtensions.BoolProp(
                context.State, "animation", true);
            Children.Clear();
            if (context.Children.Count > 0)
            {
                Children.Add(context.Children[0]);
            }
        }
    }

    // MARK: - split-branch

    public sealed class SplitBranchControl : Grid
    {
        readonly ContentControl _divider = new ContentControl();
        readonly Border _dividerLine = new Border();
        LUIExtensionContext? _context;
        IReadOnlyList<FrameworkElement> _children =
            Array.Empty<FrameworkElement>();
        bool _horizontal = true;
        double _ratio = 0.5;
        bool _dragging;
        double _dragStartRatio;
        double _dragStartPoint;

        public SplitBranchControl()
        {
            // ContentControl gives the divider keyboard focus for arrow-key
            // nudging; the visible 1px line is its content.
            _dividerLine.Background = (Brush)Application.Current.Resources[
                "CardStrokeColorDefaultBrush"];
            _divider.Content = _dividerLine;
            _divider.HorizontalContentAlignment =
                HorizontalAlignment.Center;
            _divider.VerticalContentAlignment =
                VerticalAlignment.Center;
            _divider.VerticalAlignment = VerticalAlignment.Stretch;
            _divider.HorizontalAlignment = HorizontalAlignment.Stretch;
            _divider.PointerPressed += OnDividerPressed;
            _divider.PointerMoved += OnDividerMoved;
            _divider.PointerReleased += OnDividerReleased;
            _divider.PointerCaptureLost += OnDividerCaptureLost;
            _divider.KeyDown += OnDividerKeyDown;
            _divider.IsTabStop = true;
            _divider.UseSystemFocusVisuals = true;
        }

        public void Update(LUIExtensionContext context)
        {
            _context = context;
            _children = context.Children;
            _horizontal = LUISplitExtensions.StringProp(
                              context.State, "orientation") != "vertical";
            if (!_dragging)
            {
                _ratio = Math.Clamp(
                    LUISplitExtensions.DoubleProp(
                        context.State, "ratio", 0.5),
                    0, 1);
            }
            Relayout();
        }

        void Relayout()
        {
            double gap = DividerThickness();
            Children.Clear();
            RowDefinitions.Clear();
            ColumnDefinitions.Clear();
            if (_horizontal)
            {
                ColumnDefinitions.Add(
                    new ColumnDefinition(
                        new GridLength(_ratio, GridUnitType.Star)));
                ColumnDefinitions.Add(
                    new ColumnDefinition(
                        new GridLength(gap, GridUnitType.Pixel)));
                ColumnDefinitions.Add(
                    new ColumnDefinition(
                        new GridLength(1 - _ratio, GridUnitType.Star)));
                Place(0, 0, 0);
                Place(1, 0, 2);
                SetColumn(_divider, 1);
                _divider.Width = gap;
                _divider.Height = double.NaN;
                _divider.Padding = new Thickness(0);
                _dividerLine.Width = 1;
                _dividerLine.Height = double.NaN;
            }
            else
            {
                RowDefinitions.Add(
                    new RowDefinition(
                        new GridLength(_ratio, GridUnitType.Star)));
                RowDefinitions.Add(
                    new RowDefinition(
                        new GridLength(gap, GridUnitType.Pixel)));
                RowDefinitions.Add(
                    new RowDefinition(
                        new GridLength(1 - _ratio, GridUnitType.Star)));
                Place(0, 0, 0);
                Place(1, 2, 0);
                SetRow(_divider, 1);
                _divider.Width = double.NaN;
                _divider.Height = gap;
                _divider.Padding = new Thickness(0);
                _dividerLine.Width = double.NaN;
                _dividerLine.Height = 1;
            }
            Children.Add(_divider);
        }

        void Place(int index, int row, int column)
        {
            if (index >= _children.Count) return;
            SetRow(_children[index], row);
            SetColumn(_children[index], column);
            Children.Add(_children[index]);
        }

        double DividerThickness()
        {
            // Read the nearest ancestor split-view's thickness.
            var context = _context;
            if (context == null) return 9;
            long? parent = context.State.Parent;
            while (parent != null)
            {
                if (context.Backend.ExtensionStates.TryGetValue(
                        parent.Value, out LUIExtensionNodeState? state))
                {
                    if (state.Identifier == "split-view")
                    {
                        return LUISplitExtensions.DoubleProp(
                            state, "divider-thickness", 9);
                    }
                    parent = state.Parent;
                }
                else
                {
                    return 9;
                }
            }
            return 9;
        }

        void OnDividerPressed(
            object sender, PointerRoutedEventArgs args)
        {
            _dragging = true;
            _dragStartRatio = _ratio;
            Windows.Foundation.Point point =
                args.GetCurrentPoint(this).Position;
            _dragStartPoint = _horizontal ? point.X : point.Y;
            _divider.CapturePointer(args.Pointer);
            args.Handled = true;
        }

        void OnDividerMoved(
            object sender, PointerRoutedEventArgs args)
        {
            if (!_dragging) return;
            double extent = _horizontal ? ActualWidth : ActualHeight;
            double gap = DividerThickness();
            double available = Math.Max(extent - gap, 1);
            Windows.Foundation.Point point =
                args.GetCurrentPoint(this).Position;
            double current = _horizontal ? point.X : point.Y;
            _ratio = Math.Clamp(
                _dragStartRatio + (current - _dragStartPoint) / available,
                0, 1);
            Relayout();
            args.Handled = true;
        }

        void OnDividerReleased(
            object sender, PointerRoutedEventArgs args)
        {
            if (!_dragging) return;
            _dragging = false;
            EmitRatio();
            args.Handled = true;
        }

        void OnDividerCaptureLost(object sender, PointerRoutedEventArgs args)
        {
            if (!_dragging) return;
            _dragging = false;
            EmitRatio();
        }

        void OnDividerKeyDown(object sender, KeyRoutedEventArgs args)
        {
            double delta = 0;
            switch (args.Key)
            {
                case VirtualKey.Left when _horizontal:
                case VirtualKey.Up when !_horizontal:
                    delta = -0.05;
                    break;
                case VirtualKey.Right when _horizontal:
                case VirtualKey.Down when !_horizontal:
                    delta = 0.05;
                    break;
            }
            if (delta != 0)
            {
                _ratio = Math.Clamp(_ratio + delta, 0, 1);
                Relayout();
                EmitRatio();
                args.Handled = true;
            }
        }

        void EmitRatio() =>
            _context?.EmitEvent(
                "ratio-changed",
                new Dictionary<string, LUIWireValue>
                {
                    ["ratio"] = LUIWireValue.Of(_ratio),
                });
    }

    // MARK: - split-pane

    public sealed class SplitPaneControl : Grid
    {
        readonly StackPanel _strip = new StackPanel
        {
            Orientation = Orientation.Horizontal,
        };
        readonly Grid _contentHost = new Grid();
        readonly Border _dropOverlay = new Border();
        readonly Border _focusRing = new Border();
        LUIExtensionContext? _context;
        string _dropZone = "";

        public SplitPaneControl()
        {
            RowDefinitions.Add(new RowDefinition(
                new GridLength(32, GridUnitType.Pixel)));
            RowDefinitions.Add(new RowDefinition(
                new GridLength(1, GridUnitType.Star)));

            var stripScroller = new ScrollViewer
            {
                HorizontalScrollMode = ScrollMode.Auto,
                HorizontalScrollBarVisibility =
                    ScrollBarVisibility.Auto,
                VerticalScrollMode = ScrollMode.Disabled,
                Content = _strip,
            };
            SetRow(stripScroller, 0);

            _dropOverlay.IsHitTestVisible = false;
            _dropOverlay.Visibility = Visibility.Collapsed;
            _dropOverlay.Background =
                new SolidColorBrush(
                    Windows.UI.Color.FromArgb(40, 96, 205, 255));
            _dropOverlay.BorderBrush =
                new SolidColorBrush(
                    Windows.UI.Color.FromArgb(160, 96, 205, 255));
            _dropOverlay.BorderThickness = new Thickness(2);
            _contentHost.Children.Add(_dropOverlay);
            _contentHost.AllowDrop = true;
            _contentHost.DragOver += OnContentDragOver;
            _contentHost.Drop += OnContentDrop;
            _contentHost.DragLeave += (_, _) => ClearDropZone();
            SetRow(_contentHost, 1);

            _focusRing.IsHitTestVisible = false;
            _focusRing.BorderThickness = new Thickness(2);
            _focusRing.CornerRadius = new CornerRadius(4);

            Children.Add(stripScroller);
            Children.Add(_contentHost);
            Children.Add(_focusRing);

            Tapped += (_, _) =>
            {
                Focus(FocusState.Programmatic);
                _context?.EmitEvent("pane-focused");
            };
            KeyDown += OnKeyDown;
        }

        public void Update(LUIExtensionContext context)
        {
            _context = context;
            bool focused = LUISplitExtensions.BoolProp(
                context.State, "focused");
            _focusRing.BorderBrush = focused
                ? new SolidColorBrush(
                    Windows.UI.Color.FromArgb(140, 96, 205, 255))
                : new SolidColorBrush(
                    Windows.UI.Color.FromArgb(0, 0, 0, 0));

            string selected = SelectedTab(context);
            RebuildStrip(context, selected);
            RebuildContent(context, selected);
        }

        string PaneId() =>
            _context == null
                ? ""
                : LUISplitExtensions.StringProp(
                      _context.State, "pane-id") ?? "";

        static string SelectedTab(LUIExtensionContext context)
        {
            string? selected = LUISplitExtensions.StringProp(
                context.State, "selected");
            if (!string.IsNullOrEmpty(selected)) return selected;
            if (context.State.Children.Count > 0)
            {
                return LUISplitExtensions.ChildString(
                    context, context.State.Children[0], "tab-id");
            }
            return "";
        }

        void RebuildStrip(LUIExtensionContext context, string selected)
        {
            _strip.Children.Clear();
            for (int i = 0; i < context.State.Children.Count; i++)
            {
                _strip.Children.Add(
                    MakeChip(context, context.State.Children[i], selected));
            }
        }

        FrameworkElement MakeChip(
            LUIExtensionContext context, long tabNode, string selected)
        {
            string tabId = LUISplitExtensions.ChildString(
                context, tabNode, "tab-id");
            string title = LUISplitExtensions.ChildString(
                context, tabNode, "title");
            bool dirty = LUISplitExtensions.ChildBool(
                context, tabNode, "dirty");
            bool closable = LUISplitExtensions.ChildBool(
                context, tabNode, "closable", true);
            bool active = tabId == selected;

            var row = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                Spacing = 6,
            };
            if (dirty)
            {
                row.Children.Add(new FontIcon
                {
                    Glyph = "●",
                    FontSize = 6,
                    VerticalAlignment = VerticalAlignment.Center,
                });
            }
            row.Children.Add(new TextBlock
            {
                Text = title.Length == 0 ? tabId : title,
                VerticalAlignment = VerticalAlignment.Center,
                Opacity = active ? 1 : 0.65,
            });
            if (closable)
            {
                var close = new Button
                {
                    Content = new FontIcon { Glyph = "", FontSize = 8 },
                    Padding = new Thickness(2),
                    MinWidth = 20,
                    MinHeight = 20,
                    Background = null,
                };
                close.Click += (_, _) =>
                    _context?.EmitEvent(
                        "tab-closed",
                        new Dictionary<string, LUIWireValue>
                        {
                            ["tab"] = LUIWireValue.Of(tabId),
                        });
                row.Children.Add(close);
            }

            var chip = new Border
            {
                Child = row,
                Padding = new Thickness(10, 0, 6, 0),
                Height = 32,
                CanDrag = true,
                AllowDrop = true,
                Background = active
                    ? (Brush)Application.Current.Resources[
                        "LayerFillColorDefaultBrush"]
                    : new SolidColorBrush(
                        Windows.UI.Color.FromArgb(0, 0, 0, 0)),
            };
            chip.Tapped += (_, _) =>
            {
                Focus(FocusState.Programmatic);
                _context?.EmitEvent(
                    "tab-selected",
                    new Dictionary<string, LUIWireValue>
                    {
                        ["tab"] = LUIWireValue.Of(tabId),
                    });
                _context?.EmitEvent("pane-focused");
            };
            chip.DragStarting += (_, args) =>
                args.Data.SetText(
                    LUISplitExtensions.PackDrag(PaneId(), tabId));
            chip.DragOver += (_, args) =>
            {
                args.AcceptedOperation = DataPackageOperation.Move;
                args.Handled = true;
            };
            chip.Drop += (_, args) =>
            {
                // Half of the chip chooses before/after insertion.
                Windows.Foundation.Point point =
                    args.GetPosition(chip);
                int index = context.State.Children.IndexOf(tabNode);
                if (index < 0) index = context.State.Children.Count;
                if (point.X >= chip.ActualWidth / 2) index++;
                args.Handled = true;
                CompleteDrop(args, index);
            };
            return chip;
        }

        async void CompleteDrop(DragEventArgs args, int index)
        {
            var deferral = args.GetDeferral();
            string payload = await args.DataView.GetTextAsync();
            deferral.Complete();
            if (!LUISplitExtensions.UnpackDrag(
                    payload, out string fromPane, out string tab))
            {
                return;
            }
            _context?.EmitEvent(
                "tab-moved",
                new Dictionary<string, LUIWireValue>
                {
                    ["tab"] = LUIWireValue.Of(tab),
                    ["index"] = LUIWireValue.Of((long)index),
                    ["from-pane"] = LUIWireValue.Of(fromPane),
                });
        }

        void RebuildContent(LUIExtensionContext context, string selected)
        {
            _contentHost.Children.Clear();
            var children = context.Children;
            var ids = context.State.Children;
            for (int i = 0; i < children.Count && i < ids.Count; i++)
            {
                FrameworkElement child = children[i];
                child.Visibility =
                    LUISplitExtensions.ChildString(
                        context, ids[i], "tab-id") == selected
                        ? Visibility.Visible
                        : Visibility.Collapsed;
                _contentHost.Children.Add(child);
            }
            _contentHost.Children.Add(_dropOverlay);
        }

        void OnContentDragOver(object sender, DragEventArgs args)
        {
            Windows.Foundation.Point point =
                args.GetPosition(_contentHost);
            double ex = Math.Clamp(
                _contentHost.ActualWidth * 0.25, 48, 160);
            double ey = Math.Clamp(
                _contentHost.ActualHeight * 0.25, 48, 160);
            string zone;
            if (point.X < ex) zone = "left";
            else if (point.X > _contentHost.ActualWidth - ex) zone = "right";
            else if (point.Y < ey) zone = "top";
            else if (point.Y > _contentHost.ActualHeight - ey)
            {
                zone = "bottom";
            }
            else zone = "center";
            if (zone != _dropZone)
            {
                _dropZone = zone;
                ShowDropZone(zone);
            }
            args.AcceptedOperation = DataPackageOperation.Move;
            args.Handled = true;
        }

        void ShowDropZone(string zone)
        {
            _dropOverlay.Visibility = Visibility.Visible;
            _dropOverlay.Margin = new Thickness(0);
            _dropOverlay.HorizontalAlignment = zone switch
            {
                "left" => HorizontalAlignment.Left,
                "right" => HorizontalAlignment.Right,
                _ => HorizontalAlignment.Stretch,
            };
            _dropOverlay.VerticalAlignment = zone switch
            {
                "top" => VerticalAlignment.Top,
                "bottom" => VerticalAlignment.Bottom,
                _ => VerticalAlignment.Stretch,
            };
            _dropOverlay.Width = zone is "left" or "right"
                ? Math.Clamp(_contentHost.ActualWidth * 0.35, 48,
                    double.MaxValue)
                : double.NaN;
            _dropOverlay.Height = zone is "top" or "bottom"
                ? Math.Clamp(_contentHost.ActualHeight * 0.35, 48,
                    double.MaxValue)
                : double.NaN;
        }

        void ClearDropZone()
        {
            _dropZone = "";
            _dropOverlay.Visibility = Visibility.Collapsed;
        }

        async void OnContentDrop(object sender, DragEventArgs args)
        {
            string zone = _dropZone.Length == 0 ? "center" : _dropZone;
            ClearDropZone();
            var deferral = args.GetDeferral();
            string payload = await args.DataView.GetTextAsync();
            deferral.Complete();
            if (!LUISplitExtensions.UnpackDrag(
                    payload, out string fromPane, out string tab))
            {
                return;
            }
            args.Handled = true;
            if (zone == "center")
            {
                var children = _context?.State.Children;
                _context?.EmitEvent(
                    "tab-moved",
                    new Dictionary<string, LUIWireValue>
                    {
                        ["tab"] = LUIWireValue.Of(tab),
                        ["index"] = LUIWireValue.Of(
                            (long)(children?.Count ?? 0)),
                        ["from-pane"] = LUIWireValue.Of(fromPane),
                    });
            }
            else
            {
                _context?.EmitEvent(
                    "split-drop",
                    new Dictionary<string, LUIWireValue>
                    {
                        ["tab"] = LUIWireValue.Of(tab),
                        ["from-pane"] = LUIWireValue.Of(fromPane),
                        ["edge"] = LUIWireValue.Of(zone),
                    });
            }
        }

        void OnKeyDown(object sender, KeyRoutedEventArgs args)
        {
            VirtualKeyModifiers modifiers =
                InputKeyboardSource.GetKeyStateForCurrentThread(
                    VirtualKey.Control)
                    .HasFlag(CoreVirtualKeyStates.Down)
                    ? VirtualKeyModifiers.Control
                    : VirtualKeyModifiers.None;
            if (InputKeyboardSource.GetKeyStateForCurrentThread(
                    VirtualKey.Menu).HasFlag(CoreVirtualKeyStates.Down))
            {
                modifiers |= VirtualKeyModifiers.Menu;
            }
            if (InputKeyboardSource.GetKeyStateForCurrentThread(
                    VirtualKey.Shift).HasFlag(CoreVirtualKeyStates.Down))
            {
                modifiers |= VirtualKeyModifiers.Shift;
            }

            bool nav = modifiers.HasFlag(VirtualKeyModifiers.Control) &&
                modifiers.HasFlag(VirtualKeyModifiers.Menu);
            if (nav)
            {
                string? direction = args.Key switch
                {
                    VirtualKey.Left => "left",
                    VirtualKey.Right => "right",
                    VirtualKey.Up => "up",
                    VirtualKey.Down => "down",
                    _ => null,
                };
                if (direction != null)
                {
                    EmitNavigate(direction);
                    args.Handled = true;
                    return;
                }
                if (args.Key == VirtualKey.D)
                {
                    EmitSplit(
                        modifiers.HasFlag(VirtualKeyModifiers.Shift)
                            ? "vertical"
                            : "horizontal");
                    args.Handled = true;
                    return;
                }
            }
            if (modifiers.HasFlag(VirtualKeyModifiers.Control) &&
                args.Key == (VirtualKey)220)
            {
                EmitSplit(
                    modifiers.HasFlag(VirtualKeyModifiers.Shift)
                        ? "vertical"
                        : "horizontal");
                args.Handled = true;
                return;
            }
            if (modifiers.HasFlag(VirtualKeyModifiers.Control) &&
                args.Key == VirtualKey.W)
            {
                if (modifiers.HasFlag(VirtualKeyModifiers.Shift))
                {
                    _context?.EmitEvent("pane-closed");
                }
                else if (_context != null)
                {
                    string selected = SelectedTab(_context);
                    if (selected.Length > 0)
                    {
                        _context.EmitEvent(
                            "tab-closed",
                            new Dictionary<string, LUIWireValue>
                            {
                                ["tab"] = LUIWireValue.Of(selected),
                            });
                    }
                }
                args.Handled = true;
            }
        }

        void EmitNavigate(string direction) =>
            _context?.EmitEvent(
                "navigate",
                new Dictionary<string, LUIWireValue>
                {
                    ["direction"] = LUIWireValue.Of(direction),
                });

        void EmitSplit(string orientation) =>
            _context?.EmitEvent(
                "split-requested",
                new Dictionary<string, LUIWireValue>
                {
                    ["orientation"] = LUIWireValue.Of(orientation),
                });
    }

    // MARK: - split-tab

    /// Tab nodes are data carriers; a bare split-tab stacks its children.
    public sealed class SplitTabControl : Grid
    {
        public void Update(LUIExtensionContext context)
        {
            Children.Clear();
            foreach (FrameworkElement child in context.Children)
            {
                Children.Add(child);
            }
        }
    }
}
