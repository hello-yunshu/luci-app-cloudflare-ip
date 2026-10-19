# RPC failure and permission contract

Synchronous backend RPC methods accept exactly one JSON object. A nonzero backend exit forces success=false and retains its exit code in rc, alongside existing diagnostic fields and the root error. Empty, malformed, non-object or multiple-object output becomes a failure object. Successful existing status objects may omit success; their fields remain compatible. speedtest-status combines one status object with one normalized log_data object, so a log failure remains visible without duplicating the top-level response.

Service start/stop/restart must stop before invoking the lifecycle action if UCI set, UCI commit or required init enable fails. Errors identify the failed prerequisite and its exit code. This does not promise rollback of pending or already committed UCI changes after a later failure. Shared writer locks are released on these reported failures.

refresh-env writes the environment cache and therefore requires write permission. The source ACL classifies every declared RPC method exactly once; mutation methods are not in the read class. Overview treats a failed/missing refresh response as an error and keeps the last displayed environment state. The cached detection is updated only on a successful response.

The host matrix executes the production shell dispatcher with controlled backend/UCI/init/parser fixtures. Its ACL checks inspect source policy, and its UI checks execute the production handler in an isolated module DOM. Native authenticated read-only/write rpcd sessions, real UCI/procd event propagation and full browser/responsive/keyboard acceptance require separate evidence; these fixtures do not close those gates.
