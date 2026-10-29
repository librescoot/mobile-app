# BLE hash reads

`ScooterActions.readHashFields(hash, fields)` is the reusable, capability-gated
reader. It requires an explicitly versioned `hash=1` in `cap:ext`; a missing,
unversioned or unknown-version capability is unsupported. No firmware release
number is inferred and there is no legacy command fallback.

The lower-level `readHashFieldsCommand` is exported by `scooter_flutter`. Its
caller must confirm the capability and supply a captured connection-generation
`isCurrent` guard. A whole snapshot exchange holds the extended-channel lease.

## Wire format

ASCII requests are at most 100 bytes. ATT long writes carry commands larger than
one ATT payload. The decimal notification budget is 20 through 244 and at most
`ATT_MTU - 3`. ATT MTU 23 therefore uses budget 20. Each reply is one bounded
notification; snapshot data can span many notifications.

```
hash:read:1234abcd:20:battery:0/present,serial-number
r:s:1234abcd:<length36>
hash:get:1234abcd:<offset36>:20
r:p:1234abcd:<offset36>:<unpadded-base64url>
```

The eight-character lowercase hexadecimal request ID is nonzero and fresh for
one logical read. The app allocates IDs without reuse throughout its process,
including reconnects and failed reads, and fails closed on exhaustion. Replies
with another ID, including `00000000`, cannot complete the read.

The server takes one atomic snapshot and encodes an ordered JSON array, with
unchanged strings or `null` for missing fields or hashes. Field names retain
exact spelling and order. At most two distinct fields are requested. The server
currently permits only `battery:0` and `battery:1`, with fields `present` and
`serial-number`; the client does not turn this into unrestricted Redis access.

Lengths and byte offsets use canonical lowercase base36. Each chunk is decoded
independently, then its decoded byte length advances the offset. UTF8 decoding
happens only after reassembly, so multibyte characters and JSON escapes may
cross chunk boundaries. The app rejects malformed/noncanonical base64, wrong
IDs or offsets, premature EOF, oversize packets, zero progress and overruns.
Foreign IDs are ignored until the correlated reply or timeout.

After consuming exactly the announced byte length, the client requests that
final offset to release the snapshot:

```
hash:get:1234abcd:<length36>:20
r:e:1234abcd:<length36>
```

The app requires this EOF handshake before returning data. It validates strict
UTF8, a JSON array of exactly the requested size, string-or-null element types,
valid Unicode strings, at most 256 UTF8 bytes per field and at most 4096 snapshot
bytes. Raw values, including empty strings and control characters encoded as
JSON escapes, are not normalized by the generic reader.

Errors have the form `r:x:<id>:<code>`, with codes `command`, `denied`, `redis`,
`large`, `utf8`, `busy`, `session`, `offset`, `budget` or `id`. They propagate as
`HashReadException`, never missing values or absent batteries. Responses and
writes have a five-second timeout; the complete read has a two-minute deadline.
Disconnects and superseded connection generations invalidate the read. There
are no automatic retries. Listeners are removed on success and failure.

The server holds at most four snapshots, with a fixed five-minute TTL and no
eviction. EOF frees a snapshot; disconnect clears connection-owned snapshots.
Failed partial reads expire server-side.

## Battery interpretation

`readBatteryIdentities()` reads `present,serial-number` separately for both
slots using this reader. Presence must be the exact string `"true"` or
`"false"`. False ignores any retained serial; true requires an existing valid
canonical serial. Null, empty or unknown presence is not absence. Any invalid
slot invalidates the complete read, rather than returning partial identities.

These are reported values, possibly cached by the scooter, not fresh hardware
measurements, ownership evidence or permission to change theft flags. The
physical-label check and explicit sharing/website consents remain unchanged.

The shared tests include service-generated wire vectors in
`packages/scooter_flutter/test/fixtures/hash_read_vectors.json`, ATT MTU 23,
Unicode/escaped data, bounds and correlation attacks, and same-device reconnects.
