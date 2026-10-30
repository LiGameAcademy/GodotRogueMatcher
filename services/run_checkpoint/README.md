# Checkpoint compatibility

The automatic slot contains a verified primary and its preceding verified generation.
An unfinished transaction restores the old pair. Per-run invalidation takes priority
over both generations. A failed operation is not a durable success; if the first
invalidation write leaves no file, a later process can still discover the old slot.

## Payload and package versions

The rule payload remains `run-checkpoint-prefix-v1`. It includes the full replay
prefix, exact endpoint, frozen offer, continuation, identities and six random streams.
Application takeover follows complete independent reconstruction and validation.

New writes use `run-checkpoint-package-v3`: `schema`, `run_id`, `payload_json`,
and an independent `telemetry` trace. Inside `payload_json`, every float is represented
by a single-entry object `{"$checkpoint_float64":"<16 lowercase hex digits>"}`.
The bytes are the eight little-endian IEEE 754 binary64 bytes. This preserves finite
values, including negative zero, without depending on decimal JSON parser rounding.
The tag is reserved: source dictionaries containing that key are rejected, not escaped
or reinterpreted. Unknown types, malformed tags, nonfinite values and excessive nesting
are rejected. Decoding produces values only and never instantiates objects.

Before a save touches the Store, the actual serialized text is parsed, decoded and
independently reconstructed. Reading requires the decoded root to be a dictionary and
continues to verify the entire rule payload and compatibility manifest.

Known decimal wrappers remain readable: the three-field `run-checkpoint-prefix-v1`
package and four-field `run-checkpoint-package-v2`. They retain strict endpoint
validation. Decimal precision already lost in an old file cannot be recovered by
relaxing comparison. Known corruption may fall back to the verified previous generation;
unknown protocols or incompatible configurations are rejected. Older builds do not
understand package v3; no downgrade migration is provided.

## Limits

The rule payload is limited to 4096 records and 15 MiB, with a separate 16 MiB container
limit including the encoded package. Exact-float transport adds space and processing
cost; a long run can hit the size limit earlier. A rejected save preserves the old slot.
The desktop rebuild budget is a soft acceptance check after replay, not a preemptive
timeout or an end-to-end latency guarantee. Threaded waiting does not establish a
bound on final scene adoption or rendering stalls.

## Web backend

The single-threaded Web path creates no Thread. It reconstructs frozen values on the
main thread, then waits for an IndexedDB read/write transaction to complete before
acknowledging the checkpoint. Replay yields between bounded groups of records;
all records and the exact endpoint still require verification before adoption or IO.
A single rule command, initialization, JSON/float transport and file-map encoding
remain synchronous and can stall a frame. The rebuild guard includes yield time;
it is not a per-frame guarantee. Desktop measurements do not describe Web responsiveness.

The database `skill-lines-checkpoints-v1` stores one `automatic` value in `state`.
Its revision is checked inside the same transaction to reject a stale tab's overwrite.
The payload is `checkpoint-web-files-v1`, with a map of restricted checkpoint file
names to canonical base64 bytes. The private file set includes rollback/invalidity
records and corrupt originals, is limited to 2048 files and 64 MiB of decoded bytes,
and is committed atomically. It contains data only, never executable objects.

A failed transaction restores the last acknowledged local file set and revokes the
unacknowledged completed ticket. Retry must stage again. A stale revision or closed
connection requires reload; it does not reuse the stale local slot. Opening an
unknown, unreadable or malformed snapshot never clears or replaces it. Invalidation
must be acknowledged before the application permits a replacement run or exit;
cancelling the UI does not release a pending IO owner.

Web telemetry collection is currently disabled. Rule persistence is independent of
telemetry persistence and does not establish a complete Web observation parent chain.
Desktop process-death checks and actual Web refresh/retention are separate acceptance
paths. Browser retention depends on storage permissions and profile lifetime; private
contexts, clearing site data and forced termination do not provide a zero-loss promise.
No power-loss durability or support for unbounded run lengths is implied.
