# Composer attachments

`Lui_element_combine.composer` places attachment previews above one row of
caller actions, the input and the send button. Its default attachment strip
height is 128pt. `composer_attachment` renders a 120pt square card: images
fill the preview, while documents show an icon, a single-line name and type.
An optional `status` overrides the type caption. The close control has a 44pt
hit target and a smaller circular decoration. Preview and removal controls
expose the complete filename to accessibility. Apple bounds only the compact
card labels to XXXL Dynamic Type; the composer input retains full text scaling.

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

The Apple file importer preserves the order supplied by the operating system;
the Apple photo picker explicitly requests ordered selection. Native URLs keep
their security scope or temporary-file lease until `completion` acknowledges
the request token, or the node is dropped. Copy/import every accepted file
before acknowledgement. Check both the request generation and the caller's
scope after asynchronous work; release copies belonging to stale results.

## Gallery example

The Combine example enables file and photo import on the Apple host. Its
native bridge stages the whole selection on an actor before forwarding the
batch to the OCaml reducer. File copying streams to disk rather than loading
all bytes into memory. The example keeps at most eight attachments, each at
most 50 MiB. Duplicate source paths reuse the active staged copy; duplicate
result paths are skipped without changing existing order. Removing an item
allows it to be added again at the end. Partial failures and limits produce
inline feedback. Send clears the synthetic draft rather than persisting it.

The bridge tracks retained nodes and recursive subtree disposal. Revision and
scope checks prevent stale cleanup tasks from deleting current files. Remove,
Send and scope disposal release demo-owned files. Abrupt process termination
cleanup is best effort; the actor never deletes another instance's directory.

Web, Android and GPUI do not currently implement the same native picker
contract. Their Gallery import actions are disabled with an explanation;
host applications can provide their own picker actions and ordered model.
Shared card/layout primitives and the public result model remain portable.
