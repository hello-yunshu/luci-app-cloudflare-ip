# LAN publisher status observations

`publisher-status` loads committed configuration before inspecting the last published observation. A cached successful publication is rechecked with one bounded, proxy-free HTTP request. The response must exactly match the published result file. The query follows the current configured endpoint, including automatic LAN resolution, and returns the effective address and port. It does not rewrite the stored publication observation.

- `state: ready`, `success: true`, `listenerReady: true`: the last publication succeeded and the queried endpoint currently serves matching bytes.
- `state: unavailable`, `success: false`: the last successful publication cannot currently be confirmed by HTTP readback.
- `state: disabled`, `success: false`, `listenerReady: false`: publication is configured off; this is not a serving/ready state. A successful disable operation still exits zero. `stopAcknowledged` only records the init stop acknowledgement, not a physical absence guarantee.
- `state: error`, `success: false`: invalid stored status, failed stop, or an endpoint still responding after the stop attempt. Errors are retained instead of being replaced by a disabled success.

Stop attempts check both the previously published and current configured endpoint, allowing a bounded grace interval. Network-interface lookups use the ubus client timeout. Unknown/unreachable endpoints are not proof of process ownership or physical network isolation. Actual procd service, LAN membership and device acceptance remain distinct evidence layers.

Missing or empty volatile status metadata does not bypass disabled-state checks of the configured endpoint. A responding endpoint is still reported as publisher_still_responding, and the read-only query does not recreate the missing file. This cannot reconstruct a previous address lost with the metadata.

Stored observations are bounded before JSON parsing. Query timestamps are returned as `lastCheckedAt`; the original publication timestamp remains intact. HTTP listener checks and temporary files do not change UCI or restart services.

Generation consistency uses the versioned read protocol in LAN_RESULT_PROTOCOL.md. Readback compares a bounded private snapshot of the expected manifest and reports its matched generation/count, rather than combining metadata from two cursor states.
