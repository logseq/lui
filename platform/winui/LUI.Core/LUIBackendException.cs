// Errors raised by the LUI backend while decoding or validating a patch
// batch, and by event entry points when a gesture is not enabled for the
// target node.

namespace LUI
{
    public sealed class LUIBackendException : System.Exception
    {
        public LUIBackendException(string message) : base(message) { }
    }
}
