// Ported from platform/qt/test/tst_backend.cpp (itself a port of the
// flutter backend tests) — covers the wire apply pipeline (generation
// checks, atomic rejection, op handling) and event gating.

using System.Collections.Generic;
using Xunit;

namespace LUI.Tests
{
    public class LUIBackendTests
    {
        static string InitialBatch() => @"{""generation"":1,""ops"":[
            {""op"":""create-node"",""id"":1,""kind"":""row""},
            {""op"":""create-node"",""id"":2,""kind"":""text""},
            {""op"":""set-prop"",""id"":2,""property"":""text"",""value"":""Before""},
            {""op"":""create-node"",""id"":3,""kind"":""button""},
            {""op"":""set-prop"",""id"":3,""property"":""text"",""value"":""Continue""},
            {""op"":""set-prop"",""id"":3,""property"":""enabled"",""value"":true},
            {""op"":""insert-child"",""parent"":1,""child"":2,""index"":0},
            {""op"":""insert-child"",""parent"":1,""child"":3,""index"":1}
        ]}";

        [Fact]
        public void RemovePropKeepsNode()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-node"",""id"":1,""kind"":""column""},
                {""op"":""set-prop"",""id"":1,""property"":""padding"",""value"":24}
            ]}");
            backend.ApplyJson(@"{""generation"":2,""ops"":[
                {""op"":""remove-prop"",""id"":1,""property"":""padding""}
            ]}");
            Assert.Equal(2, backend.Generation);
            Assert.True(backend.ContainsNode(1));
            Assert.False(
                backend.RequireState(1).Properties.ContainsKey(
                    LUIProperty.PaddingValue));
        }

        [Fact]
        public void RejectsRootWithTwoChildren()
        {
            var backend = new LUIBackend();
            LUIBackendException error = Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":1,""ops"":[
                    {""op"":""create-node"",""id"":1,""kind"":""root""},
                    {""op"":""create-node"",""id"":2,""kind"":""text""},
                    {""op"":""create-node"",""id"":3,""kind"":""text""},
                    {""op"":""insert-child"",""parent"":1,""child"":2,""index"":0},
                    {""op"":""insert-child"",""parent"":1,""child"":3,""index"":1}
                ]}"));
            Assert.Contains(
                "runtime root requires exactly one child", error.Message);
        }

        [Fact]
        public void RejectsInvalidBatchAtomically()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":2,""ops"":[
                    {""op"":""create-node"",""id"":4,""kind"":""text""},
                    {""op"":""insert-child"",""parent"":99,""child"":4,""index"":0}
                ]}"));
            Assert.False(backend.ContainsNode(4));
            Assert.Equal(1, backend.Generation);
        }

        [Fact]
        public void RejectsSkippedGeneration()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            LUIBackendException error = Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":3,""ops"":[
                    {""op"":""create-node"",""id"":4,""kind"":""text""}
                ]}"));
            Assert.Contains("expected patch generation 2", error.Message);
            Assert.False(backend.ContainsNode(4));
            Assert.Equal(1, backend.Generation);
        }

        [Fact]
        public void RejectsDuplicateNodeIds()
        {
            var backend = new LUIBackend();
            Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":1,""ops"":[
                    {""op"":""create-node"",""id"":1,""kind"":""text""},
                    {""op"":""create-node"",""id"":1,""kind"":""text""}
                ]}"));
        }

        [Fact]
        public void PropPatchMarksOnlyThatNode()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            LUIApplyResult? result = null;
            backend.Applied += applied => result = applied;
            backend.ApplyJson(@"{""generation"":2,""ops"":[
                {""op"":""set-prop"",""id"":2,""property"":""text"",""value"":""Updated""}
            ]}");
            Assert.NotNull(result);
            Assert.Equal(
                new HashSet<long> { 2 }, new HashSet<long>(result!.Changed));
            Assert.Empty(result.Removed);
            Assert.Equal(
                "Updated",
                ((LUIWireValue.String)
                    backend.RequireState(2)
                        .Properties[LUIProperty.TextValue]).Value);
        }

        [Fact]
        public void NewNodeIsNotMarkedChanged()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            LUIApplyResult? result = null;
            backend.Applied += applied => result = applied;
            backend.ApplyJson(@"{""generation"":2,""ops"":[
                {""op"":""create-node"",""id"":4,""kind"":""text""},
                {""op"":""set-prop"",""id"":4,""property"":""text"",""value"":""New""},
                {""op"":""insert-child"",""parent"":1,""child"":4,""index"":2}
            ]}");
            // Only the parent is marked changed (its children list changed);
            // the new node is rendered by its parent's re-sync.
            Assert.Equal(
                new HashSet<long> { 1 }, new HashSet<long>(result!.Changed));
        }

        [Fact]
        public void ChildOpsReorder()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            backend.ApplyJson(@"{""generation"":2,""ops"":[
                {""op"":""move-child"",""parent"":1,""child"":3,""index"":0}
            ]}");
            Assert.Equal(
                new List<long> { 3, 2 }, backend.RequireState(1).Children);
            backend.ApplyJson(@"{""generation"":3,""ops"":[
                {""op"":""remove-child"",""parent"":1,""child"":2},
                {""op"":""drop-node"",""id"":2}
            ]}");
            Assert.Equal(
                new List<long> { 3 }, backend.RequireState(1).Children);
            Assert.False(backend.ContainsNode(2));
        }

        [Fact]
        public void DropAttachedNodeRejected()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":2,""ops"":[
                    {""op"":""drop-node"",""id"":2}
                ]}"));
            Assert.True(backend.ContainsNode(2));
            Assert.Equal(1, backend.Generation);
        }

        [Fact]
        public void PressGate()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            var events = new List<LUIEvent>();
            backend.OnEvent += events.Add;
            // A plain text node is not pressable.
            Assert.Throws<LUIBackendException>(() => backend.PerformAction(2));
            Assert.Empty(events);
            backend.ApplyJson(@"{""generation"":2,""ops"":[
                {""op"":""set-prop"",""id"":2,""property"":""press-enabled"",""value"":true}
            ]}");
            backend.PerformAction(2);
            Assert.Single(events);
            Assert.Equal(new LUIEvent.Press(2), events[0]);
        }

        [Fact]
        public void DisabledButtonIsNotPressable()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-node"",""id"":1,""kind"":""button""},
                {""op"":""set-prop"",""id"":1,""property"":""text"",""value"":""Go""},
                {""op"":""set-prop"",""id"":1,""property"":""enabled"",""value"":false}
            ]}");
            Assert.Throws<LUIBackendException>(() => backend.PerformAction(1));
        }

        [Fact]
        public void ToggleGate()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-node"",""id"":1,""kind"":""checkbox""},
                {""op"":""set-prop"",""id"":1,""property"":""text"",""value"":""Opt in""}
            ]}");
            var events = new List<LUIEvent>();
            backend.OnEvent += events.Add;
            backend.PerformToggle(1, true);
            Assert.Single(events);
            Assert.Equal(new LUIEvent.ToggleChanged(1, true), events[0]);
        }

        [Fact]
        public void EventRoundTrip()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-node"",""id"":1,""kind"":""text-field""},
                {""op"":""set-prop"",""id"":1,""property"":""text"",""value"":""seed""}
            ]}");
            var events = new List<LUIEvent>();
            backend.OnEvent += events.Add;
            backend.PerformTextChanged(1, "hello");
            Assert.Single(events);
            Assert.Equal(new LUIEvent.TextChanged(1, "hello"), events[0]);
        }

        [Fact]
        public void ExtensionRegistryRules()
        {
            var registry = new LUIExtensionRegistry();
            // Extension identifiers cannot shadow standard node names.
            Assert.Throws<LUIBackendException>(
                () => registry.Register(
                    new LUIExtensionSpec("button", "shadow")));

            var ok = new LUIExtensionRegistry();
            var spec = new LUIExtensionSpec("native-card", "native-card-v1");
            ok.Register(spec);
            Assert.NotNull(ok.Registration("native-card"));
            // Any re-registration of the same identifier fails, fingerprint
            // match included — matching the OCaml/Flutter semantics.
            Assert.Throws<LUIBackendException>(() => ok.Register(spec));
            Assert.Throws<LUIBackendException>(
                () => ok.Register(
                    new LUIExtensionSpec("native-card", "native-card-v2")));
        }

        [Fact]
        public void TweakRegistrationRules()
        {
            var registry = new LUIExtensionRegistry();
            registry.RegisterTweak(
                "dense-row", "dense-row-v1",
                new List<LUIExtensionProperty>
                {
                    new LUIExtensionProperty(
                        "level", LUIExtensionValueKind.Integer,
                        defaultValue: new LUIWireValue.Int(1)),
                });
            LUIExtensionSpec spec = registry.Registration("dense-row")!;
            Assert.True(spec.IsTweak);
            Assert.True(spec.AcceptsStandardChildren);
        }

        [Fact]
        public void CreateExtensionAppliesDefaults()
        {
            var backend = new LUIBackend();
            backend.Extensions.Register(
                new LUIExtensionSpec(
                    "native-card", "native-card-v1",
                    properties: new List<LUIExtensionProperty>
                    {
                        new LUIExtensionProperty(
                            "elevation", LUIExtensionValueKind.Integer,
                            defaultValue: new LUIWireValue.Int(2)),
                    }));
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-extension"",""id"":1,""identifier"":""native-card"",""fingerprint"":""native-card-v1""}
            ]}");
            LUIExtensionNodeState state = backend.RequireExtensionState(1);
            Assert.Equal(
                2L, ((LUIWireValue.Int)state.Properties["elevation"]).Value);
        }

        [Fact]
        public void CreateExtensionRejectsFingerprintMismatch()
        {
            var backend = new LUIBackend();
            backend.Extensions.Register(
                new LUIExtensionSpec("native-card", "native-card-v1"));
            LUIBackendException error = Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":1,""ops"":[
                    {""op"":""create-extension"",""id"":1,""identifier"":""native-card"",""fingerprint"":""stale""}
                ]}"));
            Assert.Contains("fingerprint mismatch", error.Message);
        }

        [Fact]
        public void ExtensionEventRoundTrip()
        {
            var backend = new LUIBackend();
            backend.Extensions.Register(
                new LUIExtensionSpec(
                    "native-card", "native-card-v1",
                    events: new List<LUIExtensionEventSchema>
                    {
                        new LUIExtensionEventSchema(
                            "tapped",
                            new List<LUIExtensionEventField>
                            {
                                new LUIExtensionEventField(
                                    "index", LUIExtensionValueKind.Integer,
                                    isRequired: true),
                            }),
                    }));
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-extension"",""id"":1,""identifier"":""native-card"",""fingerprint"":""native-card-v1""}
            ]}");
            var events = new List<LUIEvent>();
            backend.OnEvent += events.Add;
            backend.PerformExtensionEvent(
                1, "tapped",
                new Dictionary<string, LUIWireValue>
                {
                    ["index"] = new LUIWireValue.Int(3),
                });
            Assert.Single(events);
            LUIEvent.Extension extension =
                Assert.IsType<LUIEvent.Extension>(events[0]);
            Assert.Equal(1L, extension.Node);
            Assert.Equal("native-card", extension.Identifier);
            Assert.Equal("tapped", extension.Name);
            Assert.Equal(
                3L, ((LUIWireValue.Int)extension.Values["index"]).Value);
        }

        [Fact]
        public void UnsupportedPropertyValueRejected()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(@"{""generation"":1,""ops"":[
                {""op"":""create-node"",""id"":1,""kind"":""text""}
            ]}");
            LUIBackendException error = Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":2,""ops"":[
                    {""op"":""set-prop"",""id"":1,""property"":""text"",""value"":42}
                ]}"));
            Assert.Contains("unsupported property value", error.Message);
        }

        [Fact]
        public void ChildCycleRejected()
        {
            var backend = new LUIBackend();
            backend.ApplyJson(InitialBatch());
            Assert.Throws<LUIBackendException>(
                () => backend.ApplyJson(@"{""generation"":2,""ops"":[
                    {""op"":""create-node"",""id"":4,""kind"":""row""},
                    {""op"":""insert-child"",""parent"":4,""child"":1,""index"":0},
                    {""op"":""remove-child"",""parent"":1,""child"":4},
                    {""op"":""insert-child"",""parent"":1,""child"":4,""index"":0},
                    {""op"":""insert-child"",""parent"":4,""child"":4,""index"":1}
                ]}"));
            Assert.Equal(1, backend.Generation);
        }
    }
}
