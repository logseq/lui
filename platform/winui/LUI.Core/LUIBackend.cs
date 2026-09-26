// Port of platform/flutter/lib/lui_flutter_backend.dart's protocol core:
// patch-batch application, whole-tree validation, change diffing, and the
// gesture/event gates. Error strings intentionally match the reference
// backends so behavior is observable-identical across platforms.

using System.Collections.Generic;
using System.Text.Json;

namespace LUI
{
    public sealed class LUIBackend
    {
        readonly Dictionary<long, LUINodeState> _states =
            new Dictionary<long, LUINodeState>();
        readonly Dictionary<long, LUIExtensionNodeState> _extensionStates =
            new Dictionary<long, LUIExtensionNodeState>();
        readonly LUIExtensionRegistry _extensionRegistry =
            new LUIExtensionRegistry();

        public int Generation { get; private set; }

        public event System.Action<LUIEvent>? OnEvent;

        // Raised once per committed batch with the ids that render
        // differently, need dependency re-evaluation, or were removed.
        public event System.Action<LUIApplyResult>? Applied;

        // Raised (outside batch application) when a registered image or
        // media-surface frame changed and referencing nodes must repaint.
        public event System.Action<IReadOnlyCollection<long>>? MediaInvalidated;

        public LUIExtensionRegistry Extensions => _extensionRegistry;

        public IReadOnlyDictionary<long, LUINodeState> States => _states;
        public IReadOnlyDictionary<long, LUIExtensionNodeState> ExtensionStates =>
            _extensionStates;

        public bool ContainsNode(long id) =>
            _states.ContainsKey(id) || _extensionStates.ContainsKey(id);

        public LUINodeState RequireState(long id) =>
            _states.TryGetValue(id, out LUINodeState? state)
                ? state
                : throw new LUIBackendException($"unknown node {id}");

        public LUIExtensionNodeState RequireExtensionState(long id) =>
            RequireExtensionStateFrom(_extensionStates, id);

        public List<LUIRootSection> RootSections(long root)
        {
            LUINodeState rootState = RequireState(root);
            List<long> children =
                rootState.Kind == LUINodeKind.Root &&
                rootState.Children.Count == 1
                    ? RequireState(rootState.Children[0]).Children
                    : rootState.Children;
            var sections = new List<LUIRootSection>(children.Count);
            foreach (long pageId in children)
            {
                sections.Add(
                    new LUIRootSection(
                        pageId,
                        FirstSectionTitle(pageId) ?? $"Component {pageId}"));
            }
            return sections;
        }

        string? FirstSectionTitle(long node)
        {
            if (_states.TryGetValue(node, out LUINodeState? state))
            {
                if ((state.Kind == LUINodeKind.Heading ||
                     state.Kind == LUINodeKind.Text) &&
                    state.Properties.TryGetValue(
                        LUIProperty.TextValue, out LUIWireValue? text) &&
                    text is LUIWireValue.String { Value: not "" } heading)
                {
                    return heading.Value;
                }
                foreach (long child in state.Children)
                {
                    string? title = FirstSectionTitle(child);
                    if (title != null) return title;
                }
                return null;
            }
            if (!_extensionStates.TryGetValue(
                    node, out LUIExtensionNodeState? extension))
            {
                return null;
            }
            foreach (long child in extension.Children)
            {
                string? title = FirstSectionTitle(child);
                if (title != null) return title;
            }
            return null;
        }

        public void InvalidateImages(long imageId)
        {
            var changed = new List<long>();
            foreach (KeyValuePair<long, LUINodeState> entry in _states)
            {
                if ((entry.Value.Kind == LUINodeKind.Avatar ||
                     entry.Value.Kind == LUINodeKind.Image) &&
                    entry.Value.Properties.TryGetValue(
                        LUIProperty.ImageIdValue, out LUIWireValue? value) &&
                    value is LUIWireValue.Int id && id.Value == imageId)
                {
                    changed.Add(entry.Key);
                }
            }
            if (changed.Count > 0) MediaInvalidated?.Invoke(changed);
        }

        public void InvalidateSurfaces(long surfaceId)
        {
            var changed = new List<long>();
            foreach (KeyValuePair<long, LUINodeState> entry in _states)
            {
                if (entry.Value.Kind == LUINodeKind.MediaSurface &&
                    entry.Value.Properties.TryGetValue(
                        LUIProperty.SurfaceIdValue, out LUIWireValue? value) &&
                    value is LUIWireValue.Int id && id.Value == surfaceId)
                {
                    changed.Add(entry.Key);
                }
            }
            if (changed.Count > 0) MediaInvalidated?.Invoke(changed);
        }

        // ------------------------------------------------------------------
        // Patch application

        public void ApplyJson(string source)
        {
            JsonElement batch;
            try
            {
                batch = JsonDocument.Parse(source).RootElement;
            }
            catch (JsonException error)
            {
                throw new LUIBackendException(error.Message);
            }
            JsonElement batchRoot = ObjectMap(batch, "patch batch");
            long nextGeneration = Integer(batchRoot, "generation");
            long expectedGeneration = Generation + 1;
            if (nextGeneration != expectedGeneration)
            {
                throw new LUIBackendException(
                    $"expected patch generation {expectedGeneration}, " +
                    $"received {nextGeneration}");
            }
            var next = new Dictionary<long, LUINodeState>();
            foreach (KeyValuePair<long, LUINodeState> entry in _states)
            {
                next[entry.Key] = entry.Value.Copy();
            }
            var nextExtensions =
                new Dictionary<long, LUIExtensionNodeState>();
            foreach (KeyValuePair<long, LUIExtensionNodeState> entry in
                     _extensionStates)
            {
                nextExtensions[entry.Key] = entry.Value.Copy();
            }

            JsonElement operations =
                ObjectList(batchRoot.GetProperty("ops"), "ops");
            foreach (JsonElement operation in operations.EnumerateArray())
            {
                ApplyState(
                    next, nextExtensions, ObjectMap(operation, "operation"));
            }
            ValidateStates(next);
            ValidateExtensionStates(next, nextExtensions);

            var changed = new HashSet<long>();
            var removed = new List<long>();
            foreach (long id in _states.Keys)
            {
                if (!next.ContainsKey(id)) removed.Add(id);
            }
            foreach (long id in _extensionStates.Keys)
            {
                if (!nextExtensions.ContainsKey(id)) removed.Add(id);
            }
            foreach (KeyValuePair<long, LUINodeState> entry in next)
            {
                if (_states.TryGetValue(entry.Key, out LUINodeState? previous) &&
                    previous.RendersLike(entry.Value))
                {
                    continue;
                }
                if (_states.ContainsKey(entry.Key)) changed.Add(entry.Key);
            }
            foreach (KeyValuePair<long, LUIExtensionNodeState> entry in
                     nextExtensions)
            {
                if (_extensionStates.TryGetValue(
                        entry.Key, out LUIExtensionNodeState? previous) &&
                    previous.RendersLike(entry.Value))
                {
                    continue;
                }
                if (_extensionStates.ContainsKey(entry.Key))
                {
                    changed.Add(entry.Key);
                }
            }

            _states.Clear();
            foreach (KeyValuePair<long, LUINodeState> entry in next)
            {
                _states[entry.Key] = entry.Value;
            }
            _extensionStates.Clear();
            foreach (KeyValuePair<long, LUIExtensionNodeState> entry in
                     nextExtensions)
            {
                _extensionStates[entry.Key] = entry.Value;
            }
            Generation = (int)nextGeneration;

            var dependent = new HashSet<long>();
            foreach (long sourceId in new List<long>(changed))
            {
                _states.TryGetValue(sourceId, out LUINodeState? sourceState);
                long? parent = _states.TryGetValue(sourceId, out LUINodeState? n)
                    ? n.Parent
                    : _extensionStates[sourceId].Parent;
                while (parent != null)
                {
                    _states.TryGetValue(parent.Value, out LUINodeState? ancestor);
                    _extensionStates.TryGetValue(
                        parent.Value, out LUIExtensionNodeState? extensionAncestor);
                    if (ancestor == null && extensionAncestor == null) break;
                    if (ancestor?.Kind == LUINodeKind.RadioGroup)
                    {
                        changed.Add(parent.Value);
                    }
                    if (ancestor?.Kind == LUINodeKind.BottomTabs)
                    {
                        dependent.Add(parent.Value);
                    }
                    if (ancestor?.Kind == LUINodeKind.Stack &&
                        (sourceState?.Kind == LUINodeKind.DropdownMenu ||
                         sourceState?.Kind == LUINodeKind.Tooltip))
                    {
                        changed.Add(parent.Value);
                    }
                    if (extensionAncestor != null) changed.Add(parent.Value);
                    parent = ancestor?.Parent ?? extensionAncestor?.Parent;
                }
            }
            dependent.ExceptWith(changed);
            Applied?.Invoke(
                new LUIApplyResult
                {
                    Changed = changed,
                    Dependent = dependent,
                    Removed = removed,
                });
        }

        void ApplyState(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions,
            JsonElement operation)
        {
            switch (StringProperty(operation, "op"))
            {
                case "create-node":
                {
                    long id = Integer(operation, "id");
                    if (ContainsState(states, extensions, id))
                    {
                        throw new LUIBackendException("node already exists");
                    }
                    string kindName = StringProperty(operation, "kind");
                    if (!LUIWireSchema.TryDecodeNodeKind(
                            kindName, out LUINodeKind kind))
                    {
                        throw new LUIBackendException(
                            $"unsupported node kind {kindName}");
                    }
                    states[id] = new LUINodeState(kind);
                    break;
                }
                case "create-extension":
                {
                    long id = Integer(operation, "id");
                    if (ContainsState(states, extensions, id))
                    {
                        throw new LUIBackendException("node already exists");
                    }
                    string identifier = StringProperty(operation, "identifier");
                    string fingerprint = StringProperty(operation, "fingerprint");
                    LUIExtensionSpec? registration =
                        _extensionRegistry.Registration(identifier);
                    if (registration == null)
                    {
                        throw new LUIBackendException("unknown extension");
                    }
                    if (registration.Fingerprint != fingerprint)
                    {
                        throw new LUIBackendException(
                            "extension fingerprint mismatch");
                    }
                    var node = new LUIExtensionNodeState(
                        identifier, fingerprint);
                    foreach (LUIExtensionProperty property in
                             registration.Properties)
                    {
                        if (property.DefaultValue != null)
                        {
                            node.Properties[property.Name] =
                                property.Kind.Normalize(property.DefaultValue);
                        }
                    }
                    extensions[id] = node;
                    break;
                }
                case "drop-node":
                {
                    long id = Integer(operation, "id");
                    long? parent = NodeParent(states, extensions, id);
                    List<long> children = NodeChildren(states, extensions, id);
                    if (parent != null || children.Count != 0)
                    {
                        throw new LUIBackendException(
                            "cannot drop an attached node");
                    }
                    if (!states.Remove(id) && !extensions.Remove(id))
                    {
                        throw new LUIBackendException($"unknown node {id}");
                    }
                    break;
                }
                case "set-prop":
                {
                    long id = Integer(operation, "id");
                    LUINodeState node = RequireStateFrom(states, id);
                    string propertyName = StringProperty(operation, "property");
                    if (!LUIWireSchema.TryDecodeProperty(
                            propertyName, out LUIProperty property))
                    {
                        throw new LUIBackendException(
                            $"unsupported property value: " +
                            $"{LUIWireSchema.WireName(node.Kind)}." +
                            $"{propertyName}");
                    }
                    LUIWireValue value = WireValue(
                        operation.GetProperty("value"), "value");
                    if (!LUISchema.PropertySupported(node.Kind, property) ||
                        !LUISchema.PropertyValueSupportedForKind(
                            node.Kind, property, value))
                    {
                        throw new LUIBackendException(
                            $"unsupported property value: " +
                            $"{LUIWireSchema.WireName(node.Kind)}." +
                            $"{propertyName}");
                    }
                    node.Properties[property] = value;
                    break;
                }
                case "remove-prop":
                {
                    long id = Integer(operation, "id");
                    LUINodeState node = RequireStateFrom(states, id);
                    string propertyName = StringProperty(operation, "property");
                    if (!LUIWireSchema.TryDecodeProperty(
                            propertyName, out LUIProperty property) ||
                        !node.Properties.Remove(property))
                    {
                        throw new LUIBackendException(
                            $"unsupported property: " +
                            $"{LUIWireSchema.WireName(node.Kind)}." +
                            $"{propertyName}");
                    }
                    break;
                }
                case "set-extension-prop":
                {
                    long id = Integer(operation, "id");
                    LUIExtensionNodeState node =
                        RequireExtensionStateFrom(extensions, id);
                    string propertyName =
                        StringProperty(operation, "property");
                    LUIExtensionSpec registration =
                        _extensionRegistry.Registration(node.Identifier)!;
                    LUIExtensionProperty? property =
                        registration.Property(propertyName);
                    LUIWireValue value;
                    try
                    {
                        value = WireValue(
                            operation.GetProperty("value"), "value");
                    }
                    catch (LUIBackendException)
                    {
                        throw new LUIBackendException(
                            "unsupported extension property value");
                    }
                    if (property == null || !property.Kind.Accepts(value))
                    {
                        throw new LUIBackendException(
                            "unsupported extension property value");
                    }
                    node.Properties[propertyName] =
                        property.Kind.Normalize(value);
                    break;
                }
                case "remove-extension-prop":
                {
                    long id = Integer(operation, "id");
                    LUIExtensionNodeState node =
                        RequireExtensionStateFrom(extensions, id);
                    string propertyName =
                        StringProperty(operation, "property");
                    LUIExtensionSpec registration =
                        _extensionRegistry.Registration(node.Identifier)!;
                    LUIExtensionProperty? property =
                        registration.Property(propertyName);
                    if (property == null)
                    {
                        throw new LUIBackendException(
                            "unknown extension property");
                    }
                    if (property.DefaultValue == null)
                    {
                        node.Properties.Remove(propertyName);
                    }
                    else
                    {
                        node.Properties[propertyName] =
                            property.Kind.Normalize(property.DefaultValue);
                    }
                    break;
                }
                case "insert-child":
                {
                    long parentId = Integer(operation, "parent");
                    long childId = Integer(operation, "child");
                    int index = (int)Integer(operation, "index");
                    if (!ContainsState(states, extensions, parentId) ||
                        !ContainsState(states, extensions, childId))
                    {
                        throw new LUIBackendException(
                            "unknown parent or child node");
                    }
                    if (NodeParent(states, extensions, childId) != null)
                    {
                        throw new LUIBackendException(
                            "child is already attached");
                    }
                    ValidateChildRelationship(
                        states, extensions, parentId, childId);
                    List<long> children =
                        NodeChildren(states, extensions, parentId);
                    if (index < 0 || index > children.Count)
                    {
                        throw new LUIBackendException(
                            "child index is out of bounds");
                    }
                    if (IsDescendantAny(
                            states, extensions, target: parentId,
                            root: childId))
                    {
                        throw new LUIBackendException(
                            "child insertion would create a cycle");
                    }
                    children.Insert(index, childId);
                    SetNodeParent(states, extensions, childId, parentId);
                    break;
                }
                case "remove-child":
                {
                    long parentId = Integer(operation, "parent");
                    long childId = Integer(operation, "child");
                    List<long> children =
                        NodeChildren(states, extensions, parentId);
                    if (!children.Remove(childId))
                    {
                        throw new LUIBackendException(
                            "child is not attached to parent");
                    }
                    SetNodeParent(states, extensions, childId, null);
                    break;
                }
                case "move-child":
                {
                    long parentId = Integer(operation, "parent");
                    List<long> children =
                        NodeChildren(states, extensions, parentId);
                    long childId = Integer(operation, "child");
                    int index = (int)Integer(operation, "index");
                    if (!children.Remove(childId))
                    {
                        throw new LUIBackendException(
                            "child is not attached to parent");
                    }
                    if (index < 0 || index > children.Count)
                    {
                        throw new LUIBackendException(
                            "child index is out of bounds");
                    }
                    children.Insert(index, childId);
                    break;
                }
                default:
                    throw new LUIBackendException("unknown patch operation");
            }
        }

        void ValidateChildRelationship(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions,
            long parentId, long childId)
        {
            if (states.TryGetValue(childId, out LUINodeState? childNode) &&
                childNode.Kind == LUINodeKind.Root)
            {
                throw new LUIBackendException("runtime root cannot be nested");
            }
            if (extensions.TryGetValue(
                    childId, out LUIExtensionNodeState? transparentChild) &&
                _extensionRegistry.Registration(transparentChild.Identifier)!
                    .IsTweak)
            {
                if (transparentChild.Children.Count != 1)
                {
                    throw new LUIBackendException(
                        "platform tweak requires exactly one child");
                }
                ValidateChildRelationship(
                    states, extensions, parentId,
                    transparentChild.Children[0]);
                return;
            }
            LUINodeState? parent = states.GetValueOrDefault(parentId);
            LUINodeState? child = states.GetValueOrDefault(childId);
            if (parent != null && child == null)
            {
                if (!AcceptsExtensionChildren(parent.Kind))
                {
                    throw new LUIBackendException(
                        "standard node cannot contain extension");
                }
                return;
            }
            if (extensions.TryGetValue(
                    parentId, out LUIExtensionNodeState? extensionParent))
            {
                LUIExtensionSpec registration =
                    _extensionRegistry.Registration(extensionParent.Identifier)!;
                if (registration.IsTweak)
                {
                    if (extensionParent.Children.Count != 0)
                    {
                        throw new LUIBackendException(
                            "platform tweak requires exactly one child");
                    }
                    return;
                }
                if (child != null)
                {
                    if (!registration.AcceptsStandardChildren)
                    {
                        throw new LUIBackendException(
                            "extension does not accept standard children");
                    }
                    return;
                }
                if (!extensions.TryGetValue(
                        childId, out LUIExtensionNodeState? extensionChild) ||
                    !ContainsString(
                        registration.ChildIdentifiers,
                        extensionChild.Identifier))
                {
                    throw new LUIBackendException(
                        "extension child relationship is not registered");
                }
                return;
            }
            if (parent == null || child == null)
            {
                throw new LUIBackendException("unknown parent or child node");
            }
            if (!LUISchema.CanContainChildren(parent.Kind))
            {
                throw new LUIBackendException("parent cannot contain child");
            }
            if ((parent.Kind == LUINodeKind.DropdownMenu ||
                 parent.Kind == LUINodeKind.ContextMenu) &&
                child.Kind != LUINodeKind.MenuItem &&
                child.Kind != LUINodeKind.Divider)
            {
                throw new LUIBackendException(
                    "menu accepts only menu-item or separator children");
            }
            if (parent.Kind == LUINodeKind.MenuItem &&
                child.Kind != LUINodeKind.ContextMenu &&
                child.Kind != LUINodeKind.DropdownMenu)
            {
                throw new LUIBackendException(
                    "menu-item accepts only nested menu metadata");
            }
            if (parent.Kind != LUINodeKind.MenuItem &&
                LUISchema.ContextMenuLeafHostKind(parent.Kind) &&
                child.Kind != LUINodeKind.ContextMenu)
            {
                throw new LUIBackendException(
                    "interactive leaf accepts only context-menu metadata");
            }
            if (parent.Kind == LUINodeKind.Table &&
                child.Kind != LUINodeKind.TableRow)
            {
                throw new LUIBackendException(
                    "table can contain only table-row");
            }
            if (parent.Kind == LUINodeKind.TableRow &&
                child.Kind != LUINodeKind.TableCell)
            {
                throw new LUIBackendException(
                    "table-row can contain only table-cell");
            }
            if (parent.Kind == LUINodeKind.Tree &&
                !LUISchema.TreeRowKind(child.Kind) &&
                child.Kind != LUINodeKind.VirtualList)
            {
                throw new LUIBackendException(
                    "tree accepts only row containers");
            }
            if (parent.Kind == LUINodeKind.Stepper &&
                child.Kind != LUINodeKind.Step)
            {
                throw new LUIBackendException(
                    "stepper accepts only step children");
            }
            if (parent.Kind == LUINodeKind.Timeline &&
                child.Kind != LUINodeKind.TimelineItem)
            {
                throw new LUIBackendException(
                    "timeline accepts only timeline-item children");
            }
            if (parent.Kind == LUINodeKind.BottomTabs &&
                child.Kind != LUINodeKind.BottomTab)
            {
                throw new LUIBackendException(
                    "bottom-tabs accepts only bottom-tab children");
            }
            if (parent.Kind == LUINodeKind.BottomTab &&
                child.Kind == LUINodeKind.BottomTab)
            {
                throw new LUIBackendException(
                    "bottom-tab cannot directly contain bottom-tab");
            }
            if (parent.Kind == LUINodeKind.InputGroup &&
                child.Kind != LUINodeKind.Textarea &&
                child.Kind != LUINodeKind.InputGroupActions)
            {
                throw new LUIBackendException(
                    "input-group accepts only textarea and " +
                    "input-group-actions children");
            }
            if (parent.Kind == LUINodeKind.Toolbar &&
                !LUISchema.ToolbarChildKind(child.Kind))
            {
                throw new LUIBackendException(
                    "toolbar accepts only interactive controls and dividers");
            }
        }

        static bool AcceptsExtensionChildren(LUINodeKind kind)
        {
            switch (kind)
            {
                case LUINodeKind.Root:
                case LUINodeKind.Row:
                case LUINodeKind.Column:
                case LUINodeKind.Grid:
                case LUINodeKind.Stack:
                case LUINodeKind.Panel:
                case LUINodeKind.Card:
                case LUINodeKind.Box:
                case LUINodeKind.Scroll:
                case LUINodeKind.ListContainer:
                case LUINodeKind.VirtualList:
                case LUINodeKind.ListItem:
                case LUINodeKind.Dialog:
                case LUINodeKind.Sheet:
                case LUINodeKind.Accordion:
                case LUINodeKind.Resizable:
                case LUINodeKind.Split:
                case LUINodeKind.Drawer:
                case LUINodeKind.Alert:
                case LUINodeKind.Bubble:
                case LUINodeKind.Toast:
                case LUINodeKind.Toolbar:
                case LUINodeKind.BottomTab:
                    return true;
                default:
                    return false;
            }
        }

        // ------------------------------------------------------------------
        // Whole-tree validation

        static void ValidateStates(Dictionary<long, LUINodeState> states)
        {
            foreach (LUINodeState state in states.Values)
            {
                ValidateSizeAxis(
                    state, LUIProperty.WidthValue, LUIProperty.MinWidth,
                    LUIProperty.MaxWidth);
                ValidateSizeAxis(
                    state, LUIProperty.HeightValue, LUIProperty.MinHeight,
                    LUIProperty.MaxHeight);
                if (state.Kind == LUINodeKind.Root)
                {
                    if (state.Parent != null)
                    {
                        throw new LUIBackendException(
                            "runtime root cannot have a parent");
                    }
                    if (state.Children.Count != 1)
                    {
                        throw new LUIBackendException(
                            "runtime root requires exactly one child");
                    }
                }
                if (state.Kind == LUINodeKind.Icon &&
                    !state.Properties.ContainsKey(LUIProperty.IconName))
                {
                    throw new LUIBackendException("icon requires name");
                }
                if (LUISchema.ButtonKind(state.Kind))
                {
                    string text = TextProperty(state, LUIProperty.TextValue);
                    string label =
                        TextProperty(state, LUIProperty.AccessibilityLabel);
                    string icon =
                        TextProperty(state, LUIProperty.InlineIconName);
                    if (text.Length == 0 && icon.Length != 0 &&
                        label.Length == 0)
                    {
                        throw new LUIBackendException(
                            "icon-only button requires label");
                    }
                    if (text.Length == 0 && label.Length == 0)
                    {
                        throw new LUIBackendException(
                            "button requires an accessible name");
                    }
                }
                if (state.Kind == LUINodeKind.Toggle ||
                    state.Kind == LUINodeKind.Radio)
                {
                    if (TextProperty(state, LUIProperty.TextValue).Length == 0 &&
                        TextProperty(state, LUIProperty.AccessibilityLabel)
                            .Length == 0)
                    {
                        throw new LUIBackendException(
                            "value control requires an accessible name");
                    }
                }
                if (state.Kind == LUINodeKind.RadioGroup ||
                    state.Kind == LUINodeKind.Slider)
                {
                    if (TextProperty(state, LUIProperty.AccessibilityLabel)
                            .Length == 0)
                    {
                        throw new LUIBackendException(
                            "value control requires an accessibility label");
                    }
                }
                if (state.Kind == LUINodeKind.Split)
                {
                    if (state.Children.Count != 2)
                    {
                        throw new LUIBackendException(
                            "split requires exactly two children");
                    }
                    if (!state.Properties.TryGetValue(
                            LUIProperty.ProgressValue,
                            out LUIWireValue? value) ||
                        value is not LUIWireValue.Float progress ||
                        double.IsNaN(progress.Value) ||
                        double.IsInfinity(progress.Value))
                    {
                        throw new LUIBackendException(
                            "split requires a finite fractional value");
                    }
                    long duration = IntProperty(
                        state, LUIProperty.ResizeDuration, 0);
                    if ((state.Properties.ContainsKey(
                            LUIProperty.ResizeEasing) ||
                         state.Properties.ContainsKey(
                            LUIProperty.ResizeOrigin)) && duration <= 0)
                    {
                        throw new LUIBackendException(
                            "split animation options require a positive " +
                            "duration");
                    }
                }
                if (state.Kind == LUINodeKind.Drawer &&
                    state.Children.Count != 2)
                {
                    throw new LUIBackendException(
                        "drawer requires exactly two children");
                }
                if (state.Kind == LUINodeKind.Radio &&
                    !HasAncestor(states, state.Parent, LUINodeKind.RadioGroup))
                {
                    throw new LUIBackendException(
                        "radio must be contained by a radio-group");
                }
                if (state.Kind == LUINodeKind.Select ||
                    state.Kind == LUINodeKind.Combobox)
                {
                    if (TextProperty(state, LUIProperty.TextValue).Length == 0 &&
                        TextProperty(state, LUIProperty.PlaceholderValue)
                            .Length == 0)
                    {
                        throw new LUIBackendException(
                            "picker trigger requires text or placeholder");
                    }
                }
                if (state.Kind == LUINodeKind.MenuItem &&
                    TextProperty(state, LUIProperty.TextValue).Length == 0)
                {
                    throw new LUIBackendException("menu-item requires text");
                }
                if (state.Kind == LUINodeKind.ContextMenu)
                {
                    LUINodeState? parent = state.Parent == null
                        ? null
                        : states.GetValueOrDefault(state.Parent.Value);
                    if (parent == null || !IsContextMenuHost(parent))
                    {
                        throw new LUIBackendException(
                            "context-menu requires an interactive direct host");
                    }
                    int count = 0;
                    foreach (long childId in parent.Children)
                    {
                        if (states.TryGetValue(
                                childId, out LUINodeState? sibling) &&
                            sibling.Kind == LUINodeKind.ContextMenu)
                        {
                            count += 1;
                        }
                    }
                    if (count != 1)
                    {
                        throw new LUIBackendException(
                            "host accepts at most one context-menu");
                    }
                    foreach (long childId in state.Children)
                    {
                        LUINodeState child = RequireStateFrom(states, childId);
                        if (child.Kind == LUINodeKind.MenuItem)
                        {
                            if (!LUISchema.TrueProperty(
                                    child.Properties,
                                    LUIProperty.PressEnabled))
                            {
                                throw new LUIBackendException(
                                    "context-menu menu-item requires press " +
                                    "support");
                            }
                            if (child.Children.Count != 0)
                            {
                                throw new LUIBackendException(
                                    "context-menu does not support nested " +
                                    "menus");
                            }
                            foreach (LUIProperty key in child.Properties.Keys)
                            {
                                switch (key)
                                {
                                    case LUIProperty.TextValue:
                                    case LUIProperty.InlineIconName:
                                    case LUIProperty.ForegroundValue:
                                    case LUIProperty.Enabled:
                                    case LUIProperty.PressEnabled:
                                    case LUIProperty.VariantValue:
                                        break;
                                    default:
                                        throw new LUIBackendException(
                                            "context-menu menu-item has " +
                                            "unsupported metadata");
                                }
                            }
                        }
                        else if (child.Properties.Count != 0 &&
                            !(child.Properties.Count == 2 &&
                              child.Properties.TryGetValue(
                                  LUIProperty.OrientationValue,
                                  out LUIWireValue? orientation) &&
                              orientation is LUIWireValue.String
                                  { Value: "horizontal" } &&
                              child.Properties.TryGetValue(
                                  LUIProperty.StyleClass,
                                  out LUIWireValue? styleClass) &&
                              styleClass is LUIWireValue.String
                                  { Value: "lui-separator" }))
                        {
                            throw new LUIBackendException(
                                "context-menu separator accepts no attributes");
                        }
                    }
                }
                if (LUISchema.ModalSurface(state.Kind) &&
                    TextProperty(state, LUIProperty.TextValue).Length == 0)
                {
                    throw new LUIBackendException("modal surface requires text");
                }
                if (state.Kind == LUINodeKind.Tooltip)
                {
                    if (TextProperty(state, LUIProperty.TextValue).Length == 0)
                    {
                        throw new LUIBackendException("tooltip requires text");
                    }
                    if (state.Properties.ContainsKey(
                            LUIProperty.TooltipDelay) &&
                        !state.Properties.ContainsKey(LUIProperty.AnchorValue))
                    {
                        throw new LUIBackendException(
                            "tooltip-delay requires anchor");
                    }
                }
                if (state.Kind == LUINodeKind.Accordion &&
                    TextProperty(state, LUIProperty.TextValue).Length == 0)
                {
                    throw new LUIBackendException("accordion requires text");
                }
                if (state.Kind == LUINodeKind.Tree &&
                    TextProperty(state, LUIProperty.AccessibilityLabel)
                        .Length == 0)
                {
                    throw new LUIBackendException(
                        "tree requires an accessibility label");
                }
                if (state.Kind == LUINodeKind.Toolbar &&
                    TextProperty(state, LUIProperty.AccessibilityLabel)
                        .Length == 0)
                {
                    throw new LUIBackendException(
                        "toolbar requires an accessibility label");
                }
                if (state.Kind == LUINodeKind.BottomTabs)
                {
                    if (TextProperty(state, LUIProperty.AccessibilityLabel)
                            .Length == 0)
                    {
                        throw new LUIBackendException(
                            "bottom-tabs requires an accessibility label");
                    }
                    if (state.Children.Count < 2 || state.Children.Count > 5)
                    {
                        throw new LUIBackendException(
                            "bottom-tabs requires two to five destinations");
                    }
                }
                if (state.Kind == LUINodeKind.BottomTab)
                {
                    LUINodeState? parent = state.Parent == null
                        ? null
                        : states.GetValueOrDefault(state.Parent.Value);
                    if (TextProperty(state, LUIProperty.TitleValue).Length == 0 ||
                        !LUISchema.TrueProperty(
                            state.Properties, LUIProperty.PressEnabled) ||
                        state.Children.Count == 0 ||
                        parent == null ||
                        parent.Kind != LUINodeKind.BottomTabs)
                    {
                        throw new LUIBackendException(
                            "bottom-tab requires title, press support, " +
                            "content, and a direct bottom-tabs parent");
                    }
                }
                bool hasTreeMetadata =
                    state.Properties.ContainsKey(LUIProperty.RoleValue) ||
                    state.Properties.ContainsKey(LUIProperty.TreeLevel) ||
                    state.Properties.ContainsKey(LUIProperty.Expanded);
                if (hasTreeMetadata)
                {
                    if (!(state.Properties.TryGetValue(
                            LUIProperty.RoleValue, out LUIWireValue? role) &&
                          role is LUIWireValue.String
                              { Value: "treeitem" }) ||
                        !HasAncestor(states, state.Parent, LUINodeKind.Tree))
                    {
                        throw new LUIBackendException(
                            "tree row metadata requires a treeitem inside " +
                            "tree");
                    }
                    if (state.Properties.ContainsKey(LUIProperty.Expanded) &&
                        !LUISchema.TrueProperty(
                            state.Properties, LUIProperty.ToggleEnabled))
                    {
                        throw new LUIBackendException(
                            "expanded treeitem requires toggle support");
                    }
                }
                if (state.Kind == LUINodeKind.DropdownMenu ||
                    state.Kind == LUINodeKind.Tooltip)
                {
                    if (state.Properties.ContainsKey(
                            LUIProperty.AnchorAlignmentValue) &&
                        !state.Properties.ContainsKey(LUIProperty.AnchorValue))
                    {
                        throw new LUIBackendException(
                            "anchor-alignment requires anchor");
                    }
                    if (state.Properties.ContainsKey(
                            LUIProperty.AnchorOffset) &&
                        !state.Properties.ContainsKey(LUIProperty.AnchorValue))
                    {
                        throw new LUIBackendException(
                            "anchor-offset requires anchor");
                    }
                }
                if (state.Kind == LUINodeKind.ListItem)
                {
                    bool hasText =
                        TextProperty(state, LUIProperty.TextValue).Length != 0;
                    bool hasChildren = false;
                    foreach (long childId in state.Children)
                    {
                        if (states.TryGetValue(
                                childId, out LUINodeState? childNode) &&
                            childNode.Kind != LUINodeKind.ContextMenu)
                        {
                            hasChildren = true;
                            break;
                        }
                    }
                    if (!hasText && !hasChildren)
                    {
                        throw new LUIBackendException(
                            "list-item requires text or children");
                    }
                    if (hasText && hasChildren)
                    {
                        throw new LUIBackendException(
                            "list-item accepts text or children, not both");
                    }
                }
                if (state.Kind == LUINodeKind.Avatar ||
                    state.Kind == LUINodeKind.Image)
                {
                    if (state.Kind == LUINodeKind.Avatar &&
                        TextProperty(state, LUIProperty.TextValue).Length == 0)
                    {
                        throw new LUIBackendException("avatar requires initials");
                    }
                    bool hasImage =
                        state.Properties.ContainsKey(LUIProperty.ImageIdValue);
                    if (state.Kind == LUINodeKind.Image && !hasImage)
                    {
                        throw new LUIBackendException("image requires image");
                    }
                    int sourceCount =
                        (state.Properties.ContainsKey(LUIProperty.SourceX)
                            ? 1 : 0) +
                        (state.Properties.ContainsKey(LUIProperty.SourceY)
                            ? 1 : 0) +
                        (state.Properties.ContainsKey(LUIProperty.SourceWidth)
                            ? 1 : 0) +
                        (state.Properties.ContainsKey(LUIProperty.SourceHeight)
                            ? 1 : 0);
                    string mediaKind =
                        state.Kind == LUINodeKind.Avatar ? "avatar" : "image";
                    if (sourceCount != 0 && sourceCount != 4)
                    {
                        throw new LUIBackendException(
                            $"{mediaKind} source crop requires all four " +
                            "coordinates");
                    }
                    if (sourceCount == 4)
                    {
                        if (!hasImage)
                        {
                            throw new LUIBackendException(
                                $"{mediaKind} source crop requires an image");
                        }
                        double x = FloatProperty(
                            state, LUIProperty.SourceX, 0.0);
                        double y = FloatProperty(
                            state, LUIProperty.SourceY, 0.0);
                        double width = FloatProperty(
                            state, LUIProperty.SourceWidth, 0.0);
                        double height = FloatProperty(
                            state, LUIProperty.SourceHeight, 0.0);
                        if (x < 0 || y < 0)
                        {
                            throw new LUIBackendException(
                                $"{mediaKind} source crop coordinates must " +
                                "be non-negative");
                        }
                        if (width <= 0 || height <= 0)
                        {
                            throw new LUIBackendException(
                                $"{mediaKind} source crop dimensions must " +
                                "be positive");
                        }
                    }
                }
                if (state.Kind == LUINodeKind.MediaSurface &&
                    !state.Properties.ContainsKey(LUIProperty.SurfaceIdValue))
                {
                    throw new LUIBackendException(
                        "media-surface requires surface");
                }
                if (state.Kind == LUINodeKind.Stepper &&
                    !state.Properties.ContainsKey(LUIProperty.ActiveIndex))
                {
                    throw new LUIBackendException("stepper requires active");
                }
                if (state.Kind == LUINodeKind.Step)
                {
                    LUINodeState? parent = state.Parent == null
                        ? null
                        : states.GetValueOrDefault(state.Parent.Value);
                    if (TextProperty(state, LUIProperty.TextValue).Length == 0 ||
                        parent == null ||
                        parent.Kind != LUINodeKind.Stepper)
                    {
                        throw new LUIBackendException(
                            "step requires text and a direct stepper parent");
                    }
                }
                if (state.Kind == LUINodeKind.TimelineItem)
                {
                    if (TextProperty(state, LUIProperty.TitleValue).Length == 0)
                    {
                        throw new LUIBackendException(
                            "timeline-item requires title");
                    }
                    LUINodeState? parent = state.Parent == null
                        ? null
                        : states.GetValueOrDefault(state.Parent.Value);
                    if (parent == null ||
                        parent.Kind != LUINodeKind.Timeline)
                    {
                        throw new LUIBackendException(
                            "timeline-item requires a direct timeline parent");
                    }
                }
                if (state.Kind == LUINodeKind.InputGroup)
                {
                    if (state.Children.Count == 0 || state.Children.Count > 2)
                    {
                        throw new LUIBackendException(
                            "input-group requires one textarea and optional " +
                            "actions");
                    }
                    LUINodeState? first =
                        states.GetValueOrDefault(state.Children[0]);
                    LUINodeState? second = state.Children.Count == 2
                        ? states.GetValueOrDefault(state.Children[1])
                        : null;
                    if (first?.Kind != LUINodeKind.Textarea ||
                        (state.Children.Count == 2 &&
                         second?.Kind != LUINodeKind.InputGroupActions))
                    {
                        throw new LUIBackendException(
                            "input-group requires textarea first and actions " +
                            "second");
                    }
                }
                if (state.Kind == LUINodeKind.InputGroupActions)
                {
                    LUINodeState? parent = state.Parent == null
                        ? null
                        : states.GetValueOrDefault(state.Parent.Value);
                    if (parent == null ||
                        parent.Kind != LUINodeKind.InputGroup)
                    {
                        throw new LUIBackendException(
                            "input-group-actions requires a direct " +
                            "input-group parent");
                    }
                }
            }
        }

        void ValidateExtensionStates(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions)
        {
            foreach (KeyValuePair<long, LUIExtensionNodeState> entry in
                     extensions)
            {
                long id = entry.Key;
                LUIExtensionNodeState state = entry.Value;
                LUIExtensionSpec? registration =
                    _extensionRegistry.Registration(state.Identifier);
                if (registration == null ||
                    registration.Fingerprint != state.Fingerprint)
                {
                    throw new LUIBackendException(
                        "invalid extension registration");
                }
                if (registration.IsTweak && state.Children.Count != 1)
                {
                    throw new LUIBackendException(
                        "platform tweak requires exactly one child");
                }
                var allowed = new HashSet<string>();
                foreach (LUIExtensionProperty property in
                         registration.Properties)
                {
                    allowed.Add(property.Name);
                }
                foreach (string key in state.Properties.Keys)
                {
                    if (!allowed.Contains(key))
                    {
                        throw new LUIBackendException(
                            "unknown extension property");
                    }
                }
                foreach (LUIExtensionProperty property in
                         registration.Properties)
                {
                    if (!state.Properties.TryGetValue(
                            property.Name, out LUIWireValue? value))
                    {
                        if (property.IsRequired)
                        {
                            throw new LUIBackendException(
                                "missing required extension property");
                        }
                    }
                    else if (!property.Kind.Accepts(value))
                    {
                        throw new LUIBackendException(
                            "invalid extension property");
                    }
                }
                if (state.Parent != null &&
                    !NodeChildren(states, extensions, state.Parent.Value)
                        .Contains(id))
                {
                    throw new LUIBackendException(
                        "extension parent is inconsistent");
                }
                foreach (long child in state.Children)
                {
                    if (NodeParent(states, extensions, child) != id)
                    {
                        throw new LUIBackendException(
                            "extension child is inconsistent");
                    }
                }
            }
        }

        static void ValidateSizeAxis(
            LUINodeState state, LUIProperty fixedProperty,
            LUIProperty minProperty, LUIProperty maxProperty)
        {
            long minimum = IntProperty(state, minProperty, 0);
            long maximum = IntProperty(
                state, maxProperty, long.MaxValue);
            long fixedValue = IntProperty(state, fixedProperty, minimum);
            if (minimum > maximum || fixedValue < minimum ||
                fixedValue > maximum)
            {
                throw new LUIBackendException(
                    "surface size constraints conflict");
            }
        }

        static bool IsContextMenuHost(LUINodeState state) =>
            LUISchema.ContextMenuHostKind(state.Kind) ||
            LUISchema.TrueProperty(
                state.Properties, LUIProperty.PressEnabled) ||
            LUISchema.TrueProperty(
                state.Properties, LUIProperty.DoublePressEnabled) ||
            LUISchema.TrueProperty(
                state.Properties, LUIProperty.ToggleEnabled) ||
            LUISchema.TrueProperty(
                state.Properties, LUIProperty.LongPressEnabled);

        static bool HasAncestor(
            Dictionary<long, LUINodeState> states, long? parent,
            LUINodeKind kind)
        {
            while (parent != null)
            {
                LUINodeState state = RequireStateFrom(states, parent.Value);
                if (state.Kind == kind) return true;
                parent = state.Parent;
            }
            return false;
        }

        static string TextProperty(LUINodeState state, LUIProperty property) =>
            state.Properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.String text
                ? text.Value
                : "";

        static long IntProperty(
            LUINodeState state, LUIProperty property, long fallback) =>
            state.Properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.Int number
                ? number.Value
                : fallback;

        static double FloatProperty(
            LUINodeState state, LUIProperty property, double fallback) =>
            state.Properties.TryGetValue(property, out LUIWireValue? value) &&
            value is LUIWireValue.Float number
                ? number.Value
                : fallback;

        // ------------------------------------------------------------------
        // Event gates

        public void PerformAction(long node)
        {
            LUINodeState state = RequireState(node);
            bool treeItem = LUISchema.TreeitemProperties(state.Properties);
            bool pressable =
                state.Kind == LUINodeKind.Button ||
                state.Kind == LUINodeKind.Select ||
                state.Kind == LUINodeKind.Combobox ||
                state.Kind == LUINodeKind.MenuItem ||
                state.Kind == LUINodeKind.ListItem ||
                (state.Kind == LUINodeKind.BottomTab &&
                 LUISchema.TrueProperty(
                     state.Properties, LUIProperty.PressEnabled)) ||
                (state.Kind == LUINodeKind.TimelineItem &&
                 LUISchema.TrueProperty(
                     state.Properties, LUIProperty.PressEnabled)) ||
                (treeItem &&
                 LUISchema.TrueProperty(
                     state.Properties, LUIProperty.PressEnabled)) ||
                (state.Kind == LUINodeKind.TableCell &&
                 LUISchema.TrueProperty(
                     state.Properties, LUIProperty.PressEnabled)) ||
                (state.Kind == LUINodeKind.Column &&
                 LUISchema.TrueProperty(
                     state.Properties, LUIProperty.PressEnabled)) ||
                (state.Kind == LUINodeKind.Text &&
                 LUISchema.TrueProperty(
                     state.Properties, LUIProperty.PressEnabled));
            if (!pressable || IsDisabled(state))
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled pressable control");
            }
            OnEvent?.Invoke(new LUIEvent.Press(node));
        }

        public void PerformDoublePress(long node)
        {
            LUINodeState state = RequireState(node);
            if (state.Kind != LUINodeKind.ListItem || IsDisabled(state) ||
                !LUISchema.TrueProperty(
                    state.Properties, LUIProperty.DoublePressEnabled))
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled double-press control");
            }
            OnEvent?.Invoke(new LUIEvent.DoublePress(node));
        }

        public void PerformSubmit(long node)
        {
            LUINodeState state = RequireState(node);
            if (state.Kind != LUINodeKind.ListItem || IsDisabled(state) ||
                !LUISchema.TrueProperty(
                    state.Properties, LUIProperty.SubmitEnabled))
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled submit control");
            }
            OnEvent?.Invoke(new LUIEvent.Submit(node));
        }

        public void PerformLongPress(long node)
        {
            LUINodeState state = RequireState(node);
            if (!(LUISchema.ButtonKind(state.Kind) ||
                  state.Kind == LUINodeKind.ListItem) ||
                IsDisabled(state) ||
                !LUISchema.TrueProperty(
                    state.Properties, LUIProperty.LongPressEnabled))
            {
                throw new LUIBackendException(
                    $"node {node} is not enabled for long press");
            }
            OnEvent?.Invoke(new LUIEvent.LongPress(node));
        }

        public void PerformToggle(long node, bool checkedValue)
        {
            LUINodeState state = RequireState(node);
            bool treeItem = LUISchema.TreeitemProperties(state.Properties);
            bool isToggle =
                state.Kind == LUINodeKind.ToggleButton ||
                state.Kind == LUINodeKind.Toggle ||
                state.Kind == LUINodeKind.Checkbox ||
                state.Kind == LUINodeKind.SwitchControl ||
                state.Kind == LUINodeKind.Accordion ||
                state.Kind == LUINodeKind.Drawer ||
                treeItem;
            bool hasHandler =
                (state.Kind != LUINodeKind.Accordion &&
                 state.Kind != LUINodeKind.Drawer && !treeItem) ||
                LUISchema.TrueProperty(
                    state.Properties, LUIProperty.ToggleEnabled);
            if (!isToggle || IsDisabled(state) || !hasHandler)
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled toggle button");
            }
            OnEvent?.Invoke(new LUIEvent.ToggleChanged(node, checkedValue));
        }

        public void PerformChange(long node)
        {
            LUINodeState state = RequireState(node);
            if ((state.Kind != LUINodeKind.Radio &&
                 !LUISchema.TreeitemProperties(state.Properties)) ||
                IsDisabled(state))
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled change control");
            }
            if (LUISchema.TrueProperty(
                    state.Properties, LUIProperty.ChangeEnabled))
            {
                if (!LUISchema.TrueProperty(
                        state.Properties, LUIProperty.Checked))
                {
                    OnEvent?.Invoke(new LUIEvent.Change(node));
                }
            }
            else if (LUISchema.TrueProperty(
                         state.Properties, LUIProperty.ToggleEnabled))
            {
                OnEvent?.Invoke(new LUIEvent.ToggleChanged(node, true));
            }
            else if (LUISchema.TrueProperty(
                         state.Properties, LUIProperty.PressEnabled))
            {
                OnEvent?.Invoke(new LUIEvent.Press(node));
            }
        }

        public void PerformValueChange(long node, double value)
        {
            LUINodeState state = RequireState(node);
            if ((state.Kind != LUINodeKind.Slider &&
                 state.Kind != LUINodeKind.Split) ||
                IsDisabled(state) ||
                double.IsNaN(value) || double.IsInfinity(value))
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled value control");
            }
            OnEvent?.Invoke(
                new LUIEvent.ValueChanged(
                    node, System.Math.Clamp(value, 0.0, 1.0)));
        }

        public void PerformDismiss(long node)
        {
            LUINodeState state = RequireState(node);
            if (state.Kind != LUINodeKind.Select &&
                state.Kind != LUINodeKind.Combobox &&
                state.Kind != LUINodeKind.DropdownMenu &&
                state.Kind != LUINodeKind.Toast &&
                !LUISchema.ModalSurface(state.Kind))
            {
                throw new LUIBackendException($"node {node} is not dismissible");
            }
            OnEvent?.Invoke(new LUIEvent.Dismiss(node));
        }

        public void PerformTextChanged(long node, string text)
        {
            LUINodeState state = RequireState(node);
            if (!LUISchema.TextControlKind(state.Kind) || IsDisabled(state))
            {
                throw new LUIBackendException(
                    $"node {node} is not an enabled text control");
            }
            OnEvent?.Invoke(new LUIEvent.TextChanged(node, text));
        }

        // Appear is best-effort: nodes without appear-enabled simply do not
        // emit, and no error is raised.
        public void PerformAppear(long node)
        {
            LUINodeState state = RequireState(node);
            if (state.Kind == LUINodeKind.Root ||
                !LUISchema.TrueProperty(
                    state.Properties, LUIProperty.AppearEnabled))
            {
                return;
            }
            OnEvent?.Invoke(new LUIEvent.Appear(node));
        }

        public void PerformExtensionEvent(
            long node, string name,
            IReadOnlyDictionary<string, LUIWireValue>? values = null)
        {
            LUIExtensionNodeState state = RequireExtensionState(node);
            LUIExtensionSpec? registration =
                _extensionRegistry.Registration(state.Identifier);
            if (registration == null)
            {
                throw new LUIBackendException(
                    $"unknown extension {state.Identifier}");
            }
            LUIExtensionEventSchema? eventSchema = registration.Event(name);
            if (eventSchema == null)
            {
                throw new LUIBackendException("unknown extension event");
            }
            var fields = new Dictionary<string, LUIExtensionEventField>();
            foreach (LUIExtensionEventField field in eventSchema.Fields)
            {
                fields[field.Name] = field;
            }
            values ??= new Dictionary<string, LUIWireValue>();
            foreach (string key in values.Keys)
            {
                if (!fields.ContainsKey(key))
                {
                    throw new LUIBackendException(
                        "unknown extension event field");
                }
            }
            foreach (LUIExtensionEventField field in eventSchema.Fields)
            {
                if (!values.TryGetValue(field.Name, out LUIWireValue? value))
                {
                    if (field.IsRequired)
                    {
                        throw new LUIBackendException(
                            "missing required extension event field");
                    }
                }
                else if (!field.Kind.Accepts(value))
                {
                    throw new LUIBackendException(
                        "invalid extension event field");
                }
            }
            var normalized = new Dictionary<string, LUIWireValue>();
            foreach (KeyValuePair<string, LUIWireValue> entry in values)
            {
                normalized[entry.Key] =
                    fields[entry.Key].Kind.Normalize(entry.Value);
            }
            OnEvent?.Invoke(
                new LUIEvent.Extension(
                    node, state.Identifier, name, normalized));
        }

        static bool IsDisabled(LUINodeState state) =>
            state.Properties.TryGetValue(
                LUIProperty.Enabled, out LUIWireValue? value) &&
            value is LUIWireValue.Bool { Value: false };

        // ------------------------------------------------------------------
        // Tree helpers shared by the operation handlers

        static bool ContainsState(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions, long id) =>
            states.ContainsKey(id) || extensions.ContainsKey(id);

        static LUINodeState RequireStateFrom(
            Dictionary<long, LUINodeState> states, long id) =>
            states.TryGetValue(id, out LUINodeState? state)
                ? state
                : throw new LUIBackendException($"unknown node {id}");

        static LUIExtensionNodeState RequireExtensionStateFrom(
            Dictionary<long, LUIExtensionNodeState> extensions, long id) =>
            extensions.TryGetValue(id, out LUIExtensionNodeState? state)
                ? state
                : throw new LUIBackendException($"unknown extension node {id}");

        static long? NodeParent(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions, long id)
        {
            if (states.TryGetValue(id, out LUINodeState? standard))
            {
                return standard.Parent;
            }
            return RequireExtensionStateFrom(extensions, id).Parent;
        }

        static List<long> NodeChildren(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions, long id)
        {
            if (states.TryGetValue(id, out LUINodeState? standard))
            {
                return standard.Children;
            }
            return RequireExtensionStateFrom(extensions, id).Children;
        }

        static void SetNodeParent(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions,
            long id, long? parent)
        {
            if (states.TryGetValue(id, out LUINodeState? standard))
            {
                standard.Parent = parent;
                return;
            }
            RequireExtensionStateFrom(extensions, id).Parent = parent;
        }

        static bool IsDescendantAny(
            Dictionary<long, LUINodeState> states,
            Dictionary<long, LUIExtensionNodeState> extensions,
            long target, long root)
        {
            if (target == root) return true;
            foreach (long child in NodeChildren(states, extensions, root))
            {
                if (IsDescendantAny(states, extensions, target, child))
                {
                    return true;
                }
            }
            return false;
        }

        static bool ContainsString(
            IReadOnlyList<string> items, string value)
        {
            foreach (string item in items)
            {
                if (item == value) return true;
            }
            return false;
        }

        // ------------------------------------------------------------------
        // JSON decoding helpers

        static JsonElement ObjectMap(JsonElement element, string label)
        {
            if (element.ValueKind != JsonValueKind.Object)
            {
                throw new LUIBackendException($"invalid {label}");
            }
            return element;
        }

        static JsonElement ObjectList(JsonElement element, string label)
        {
            if (element.ValueKind != JsonValueKind.Array)
            {
                throw new LUIBackendException($"invalid {label}");
            }
            return element;
        }

        static string StringProperty(JsonElement element, string name)
        {
            if (!element.TryGetProperty(name, out JsonElement value) ||
                value.ValueKind != JsonValueKind.String)
            {
                throw new LUIBackendException($"invalid {name}");
            }
            return value.GetString()!;
        }

        static long Integer(JsonElement element, string name)
        {
            if (!element.TryGetProperty(name, out JsonElement value) ||
                value.ValueKind != JsonValueKind.Number ||
                !value.TryGetInt64(out long number))
            {
                throw new LUIBackendException($"invalid {name}");
            }
            return number;
        }

        internal static LUIWireValue WireValue(JsonElement element, string label)
        {
            switch (element.ValueKind)
            {
                case JsonValueKind.String:
                    return new LUIWireValue.String(element.GetString()!);
                case JsonValueKind.True:
                case JsonValueKind.False:
                    return new LUIWireValue.Bool(element.GetBoolean());
                case JsonValueKind.Number:
                    if (element.TryGetInt64(out long integer))
                    {
                        return new LUIWireValue.Int(integer);
                    }
                    if (element.TryGetDouble(out double number))
                    {
                        return new LUIWireValue.Float(number);
                    }
                    break;
            }
            throw new LUIBackendException($"invalid {label}");
        }
    }
}
