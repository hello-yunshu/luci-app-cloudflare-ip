# Candidate source cache qualification

Remote sources retain their original HTTPS request URL identity even when HTTPS redirects are followed. A fallback list must have a schema-2 metadata marker binding the source ID, URL, parser, family, source class and SHA-256 of the bytes. A bare file or old schema-1 marker is retained on disk but is not fallback evidence; a successful remote refresh establishes a new marker.

Fallback reads use a bounded snapshot, recheck its digest and size/line limits, then parse it again with the current public-address and minimum-candidate checks. This prevents a valid-looking but changed list, or a list left by a differently configured source, from becoming trusted merely because the network failed.

`CFIP_SOURCE_CACHE_MAX_AGE_SECONDS` defaults to 604800 seconds (seven days). Last successful HTTPS validation must fall within this window and no more than sixty seconds into the future. An untrusted clock can therefore cause cache refusal; a successful remote fetch can re-establish qualification. A successful byte-identical refresh renews the marker timestamp. The source remains marked stale whenever fallback is used.

Runtime metadata preserves the transport error in `lastError` and separately exposes `cacheError` when fallback cannot qualify. These values do not include remote response bodies.

This checkpoint does not provide a multi-file cache publication transaction. An interrupted or failed metadata publication can leave a digest mismatch; fallback refuses the pair rather than using uncertain bytes. Preserving the previous qualified generation across every storage/publication failure remains an open G5c requirement. No device or sustained-operation acceptance is implied.
