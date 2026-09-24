// Port of platform/flutter/lib/lui_flutter_extension.dart: the extension
// schema registry. Rendering-side builder delegates live in LUI.WinUI;
// this registry only tracks the schema each `create-extension` op must
// match by identifier and fingerprint.

using System.Collections.Generic;
using System.Text.RegularExpressions;

namespace LUI
{
    public enum LUIExtensionValueKind
    {
        String,
        Boolean,
        Integer,
        DoubleValue,
    }

    public static class LUIExtensionValueKindExtensions
    {
        public static bool Accepts(
            this LUIExtensionValueKind kind, LUIWireValue value) =>
            kind switch
            {
                LUIExtensionValueKind.String => value is LUIWireValue.String,
                LUIExtensionValueKind.Boolean => value is LUIWireValue.Bool,
                LUIExtensionValueKind.Integer => value is LUIWireValue.Int,
                LUIExtensionValueKind.DoubleValue =>
                    value is LUIWireValue.Float ||
                    value is LUIWireValue.Int,
                _ => false,
            };

        public static LUIWireValue Normalize(
            this LUIExtensionValueKind kind, LUIWireValue value) =>
            kind == LUIExtensionValueKind.DoubleValue &&
            value is LUIWireValue.Int number
                ? new LUIWireValue.Float(number.Value)
                : value;
    }

    public sealed class LUIExtensionProperty
    {
        public LUIExtensionProperty(
            string name, LUIExtensionValueKind kind, bool isRequired = false,
            LUIWireValue? defaultValue = null)
        {
            Name = name;
            Kind = kind;
            IsRequired = isRequired;
            DefaultValue = defaultValue;
        }

        public string Name { get; }
        public LUIExtensionValueKind Kind { get; }
        public bool IsRequired { get; }
        public LUIWireValue? DefaultValue { get; }
    }

    public sealed class LUIExtensionEventField
    {
        public LUIExtensionEventField(
            string name, LUIExtensionValueKind kind, bool isRequired = false)
        {
            Name = name;
            Kind = kind;
            IsRequired = isRequired;
        }

        public string Name { get; }
        public LUIExtensionValueKind Kind { get; }
        public bool IsRequired { get; }
    }

    public sealed class LUIExtensionEventSchema
    {
        public LUIExtensionEventSchema(
            string name = "", IReadOnlyList<LUIExtensionEventField>? fields = null)
        {
            Name = name;
            Fields = fields ?? (IReadOnlyList<LUIExtensionEventField>)
                System.Array.Empty<LUIExtensionEventField>();
        }

        public string Name { get; }
        public IReadOnlyList<LUIExtensionEventField> Fields { get; }
    }

    public sealed class LUIExtensionSpec
    {
        public LUIExtensionSpec(
            string identifier, string fingerprint,
            bool acceptsStandardChildren = false,
            IReadOnlyList<string>? childIdentifiers = null,
            IReadOnlyList<LUIExtensionProperty>? properties = null,
            IReadOnlyList<LUIExtensionEventSchema>? events = null)
        {
            Identifier = identifier;
            Fingerprint = fingerprint;
            AcceptsStandardChildren = acceptsStandardChildren;
            ChildIdentifiers = childIdentifiers ??
                (IReadOnlyList<string>)System.Array.Empty<string>();
            Properties = properties ??
                (IReadOnlyList<LUIExtensionProperty>)
                System.Array.Empty<LUIExtensionProperty>();
            Events = events ??
                (IReadOnlyList<LUIExtensionEventSchema>)
                System.Array.Empty<LUIExtensionEventSchema>();
        }

        internal static LUIExtensionSpec Tweak(
            string identifier, string fingerprint,
            IReadOnlyList<LUIExtensionProperty>? properties) =>
            new LUIExtensionSpec(
                identifier, fingerprint,
                acceptsStandardChildren: true,
                properties: properties)
            { IsTweak = true };

        public string Identifier { get; }
        public string Fingerprint { get; }
        public bool AcceptsStandardChildren { get; }
        public IReadOnlyList<string> ChildIdentifiers { get; }
        public IReadOnlyList<LUIExtensionProperty> Properties { get; }
        public IReadOnlyList<LUIExtensionEventSchema> Events { get; }
        public bool IsTweak { get; private set; }

        public LUIExtensionEventSchema? Event(string name)
        {
            foreach (LUIExtensionEventSchema candidate in Events)
            {
                if (candidate.Name == name) return candidate;
            }
            return null;
        }

        public LUIExtensionProperty? Property(string name)
        {
            foreach (LUIExtensionProperty candidate in Properties)
            {
                if (candidate.Name == name) return candidate;
            }
            return null;
        }
    }

    public sealed class LUIExtensionRegistry
    {
        static readonly Regex NamePattern =
            new Regex("^[a-z0-9]+(?:-[a-z0-9]+)*$", RegexOptions.Compiled);

        readonly Dictionary<string, LUIExtensionSpec> _registrations =
            new Dictionary<string, LUIExtensionSpec>();

        public bool IsFrozen { get; private set; }

        public static bool ValidExtensionName(string value) =>
            NamePattern.IsMatch(value);

        public void Register(LUIExtensionSpec registration)
        {
            if (IsFrozen)
            {
                throw new LUIBackendException("extension registry is frozen");
            }
            if (!ValidExtensionName(registration.Identifier))
            {
                throw new LUIBackendException("invalid extension identifier");
            }
            if (LUIWireSchema.IsStandardNodeName(registration.Identifier))
            {
                throw new LUIBackendException(
                    "extension identifier shadows a standard node");
            }
            if (_registrations.ContainsKey(registration.Identifier))
            {
                throw new LUIBackendException(
                    "extension identifier is already registered");
            }
            foreach (string child in registration.ChildIdentifiers)
            {
                if (!ValidExtensionName(child))
                {
                    throw new LUIBackendException(
                        "invalid extension child identifier");
                }
            }
            ValidateUniqueNames(registration.ChildIdentifiers, "child identifier");
            ValidateUniqueNames(
                Names(registration.Properties, property => property.Name),
                "property");
            ValidateUniqueNames(
                Names(registration.Events, evt => evt.Name), "event");
            foreach (LUIExtensionProperty property in registration.Properties)
            {
                if (!ValidExtensionName(property.Name))
                {
                    throw new LUIBackendException(
                        "invalid extension property name");
                }
                if (property.DefaultValue != null &&
                    !property.Kind.Accepts(property.DefaultValue))
                {
                    throw new LUIBackendException(
                        "invalid extension property default");
                }
            }
            foreach (LUIExtensionEventSchema evt in registration.Events)
            {
                if (!ValidExtensionName(evt.Name))
                {
                    throw new LUIBackendException(
                        "invalid extension event name");
                }
                ValidateUniqueNames(
                    Names(evt.Fields, field => field.Name), "event field");
                foreach (LUIExtensionEventField field in evt.Fields)
                {
                    if (!ValidExtensionName(field.Name))
                    {
                        throw new LUIBackendException(
                            "invalid extension event field name");
                    }
                }
            }
            _registrations[registration.Identifier] = registration;
        }

        public void RegisterTweak(
            string identifier, string fingerprint,
            IReadOnlyList<LUIExtensionProperty>? properties = null)
        {
            Register(LUIExtensionSpec.Tweak(identifier, fingerprint, properties));
        }

        internal void Freeze()
        {
            if (IsFrozen) return;
            foreach (LUIExtensionSpec registration in _registrations.Values)
            {
                foreach (string child in registration.ChildIdentifiers)
                {
                    if (!_registrations.ContainsKey(child))
                    {
                        throw new LUIBackendException(
                            "unknown extension child schema");
                    }
                }
            }
            IsFrozen = true;
        }

        public LUIExtensionSpec? Registration(string identifier) =>
            _registrations.TryGetValue(identifier, out LUIExtensionSpec? spec)
                ? spec
                : null;

        static IEnumerable<string> Names<T>(
            IEnumerable<T> items, System.Func<T, string> selector)
        {
            foreach (T item in items) yield return selector(item);
        }

        static void ValidateUniqueNames(IEnumerable<string> names, string label)
        {
            var seen = new HashSet<string>();
            foreach (string name in names)
            {
                if (!seen.Add(name))
                {
                    throw new LUIBackendException(
                        $"duplicate extension {label}");
                }
            }
        }
    }
}
