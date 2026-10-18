# Candidate source cache qualification

Remote sources retain their original HTTPS request URL identity even when HTTPS redirects are followed. A fallback list must have a schema-2 metadata marker binding the source ID, URL, parser, family, source class and SHA-256 of the bytes. A bare file or old schema-1 marker is retained on disk but is not fallback evidence; a successful remote refresh establishes a new marker.

Fallback reads use a bounded snapshot, recheck its digest and size/line limits, then parse it again with the current public-address and minimum-candidate checks. This prevents a valid-looking but changed list, or a list left by a differently configured source, from becoming trusted merely because the network failed.

`CFIP_SOURCE_CACHE_MAX_AGE_SECONDS` defaults to 604800 seconds (seven days). Last successful HTTPS validation must fall within this window and no more than sixty seconds into the future. An untrusted clock can therefore cause cache refusal; a successful remote fetch can re-establish qualification. A successful byte-identical refresh renews the marker timestamp. The source remains marked stale whenever fallback is used.

Runtime metadata preserves the refresh error in `lastError` and separately exposes `cacheError` when fallback cannot qualify. These values do not include remote response bodies.

New refreshes publish `last-good.json`, containing bytes and qualification metadata in one file. The private candidate is checked for byte-preserving JSON roundtrip and bounded size before a single same-directory rename replaces the published bundle. Allocation, rendering, readback, permission or rename failure leaves the old bundle intact and attempts a qualified stale fallback. Readers snapshot one bundle before extracting either component. A corrupt bundle never falls back to an older legacy pair. Qualified schema-2 `last-good.txt` / `metadata.json` pairs remain readable only while no bundle exists, so the first successful new publication is a one-way storage-format transition without deleting the old files.

Fault-injection and forced process termination immediately before/after rename are software evidence. They do not prove filesystem durability under power loss. A forced kill can leave an unreferenced private `.cache.*` candidate; it is never read as published data. Orphan retention/cleanup under repeated interruptions, resource exhaustion and device power-loss/soak acceptance remain separately open.
