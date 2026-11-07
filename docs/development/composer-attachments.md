# Composer attachments

`Lui_element_combine.composer` places attachment previews above one row of
caller actions, the input and the send button. Its default attachment strip
height is 128pt. `composer_attachment` renders a 120pt square card: images
fill the preview, while documents show an icon, a single-line name and type.
An optional `status` overrides the type caption. The close control has a 44pt
hit target and a smaller circular decoration. Preview and removal controls
expose the complete filename to accessibility.

The component owns layout and preview state. The caller owns attachment
identity, file paths, selection policy, import errors and file lifetime.
The core composer does not open a picker or silently maintain a file list.

## Selecting a batch

Use `Lui_elements.file_picker ~multiple:true` on a host that implements its
request/completion contract. Decode the entire `Picked` payload with
`Lui_picked_files.decode`. The result contains the original request token,
an ordered `files` list and a partial-failure count. Valid siblings survive
invalid entries; an invalid envelope returns `Error`. Cancellation arrives
through `Dismiss` and should leave existing attachments unchanged.

Hosts own file lifetime and request acknowledgement. Copy/import every accepted
file before acknowledging its request token, and reject stale asynchronous
results after the caller scope or request generation changes.

The former Apple file/photo picker and gallery import actor are removed with
the Apple backend. Their security-scoped URL, ordered photo selection and staged
file cleanup behavior are not portable host guarantees. Shared card/layout
primitives and `Lui_picked_files` remain; downstream applications must implement
selection, import policy and file lifetime through supported MyGo or Web APIs.
