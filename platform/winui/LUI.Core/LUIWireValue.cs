// Wire-level property/event values. Mirrors `wire_value` in
// src/lui_protocol.ml: JSON numbers arrive as Int (integral text) or Float
// (fractional/exponent text); strings and booleans map directly.

namespace LUI
{
    public abstract record LUIWireValue
    {
        private LUIWireValue() { }

        public sealed record String(string Value) : LUIWireValue;
        public sealed record Bool(bool Value) : LUIWireValue;
        public sealed record Int(long Value) : LUIWireValue;
        public sealed record Float(double Value) : LUIWireValue;

        public static LUIWireValue Of(string value) => new String(value);
        public static LUIWireValue Of(bool value) => new Bool(value);
        public static LUIWireValue Of(long value) => new Int(value);
        public static LUIWireValue Of(int value) => new Int(value);
        public static LUIWireValue Of(double value) => new Float(value);

        public string? AsString => (this as String)?.Value;
        public bool? AsBool => (this as Bool)?.Value;
        public long? AsInt => (this as Int)?.Value;
        // Numeric props arrive as Int or Float on the wire; consumers treat
        // both as a number (Dart `num` equivalent).
        public double? AsFloat =>
            (this as Float)?.Value ?? (this as Int)?.Value;
    }
}
