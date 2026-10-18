# LAN result generations

A publication builds all output files in a private sibling directory. It validates selected public addresses, renders the three text files, records their byte sizes and SHA-256 digests, and writes `result.json`. Only a completed directory is moved under `publish/generations/`. Its generation URL is checked over HTTP before the single `current` symlink is switched. The compatibility paths `/ip.txt`, `/best-ipv4.txt`, `/best-ipv6.txt` and `/result.json` follow that pointer.

A pointer switch keeps each response within one complete generation. **Separate requests to the compatibility paths may still span a switch.** A consumer that needs several files from the same result must use the generation protocol:

1. Fetch `/result.json` without using a cached response. Read `generation`, `generationPath`, `generatedAt` and `artifacts`.
2. Fetch `generationPath + '/result.json'` and the named text artifacts from that same prefix. Require the manifest to match the first response, and verify each artifact's `sizeBytes` and `sha256`.
3. On a 404, digest mismatch or changed manifest, discard the incomplete read and fetch a fresh root manifest. Use a bounded retry limit; never substitute a compatibility-path file for a missing pinned artifact.

`generatedAt` lets consumers apply their own freshness policy. If an older manifest lacks `generationPath`, use its `ips`/`selected` from that **single JSON response** for consistency; do not infer a shared generation across the legacy text requests.

The default retention limit is three owned generations (`CFIP_PUBLISH_KEEP_GENERATIONS`, internal range 2–8). The current generation and the preceding cursor are retained after a successful publication. Other managed generations can be removed, so an older pinned URL is not a permanent archive. Directories without a matching publisher ownership marker are not pruned.

Legacy regular files are first copied into an immutable snapshot. Converting an individual compatibility path therefore keeps its previous bytes, even if conversion fails halfway through. This also handles regular files left by a downgrade. New content becomes current only after the compatibility links are ready. HTTP failure after a pointer switch attempts to restore the old cursor; clients must still handle a transient complete generation being retired with a 404.

This is software filesystem/HTTP evidence, not proof of power-loss durability or process ownership. Forced termination can leave private staging or link directories; repeated-interruption cleanup remains a separate open resource gate. Concurrent noncooperating writers are not covered by a universal CAS claim; normal backend publication runs under the application's run lock.
