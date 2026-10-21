# G4、G5 执行记录

## G5c native jq capability and cache qualification checkpoint

Actual installed OpenWrt jq 1.8.1 is compiled without ONIGURUMA. The original cache matrix passes seventeen cases but refuses four qualified caches; the expanded matrix passes twenty-eight and refuses six qualified cases, including uppercase HTTPS and Unicode version tags. No unqualified execution was observed. Metadata qualification now uses jq codepoint/string operations rather than optional regex functions. The one bounded snapshot, schema, HTTPS provenance, version token and exact hexadecimal digest requirements remain. C0/C1, Unicode whitespace, trailing newline and NUL are rejected before Bash extraction.

All thirty-four cache cases pass on the actual native OpenWrt tools and private host Bash. The host fixture explicitly denies optional regex primitives while otherwise invoking real jq, so a regex-enabled CI host cannot mask this specific regression. Native candidate-source installer faults pass twenty-three cases. The actual installed writer helper/CLI/init/rpc source also passes fifteen real native-kernel lock cases with BusyBox ash; these are controlled component faults, not full procd lifecycle/real proxy acceptance. All parser test processes use network-disabled guest namespaces and harmless shell payloads. Receipt: native-jq-cache-portability.json.

The broader scan still finds regex-dependent candidate-rill, operational-health and observation paths; these require independent native reproducers and repairs. Standalone-copy parity, full concurrency/KILL/resource/retention, G4/G5 and new exact-SHA rebuilt package/offline/native-package gates remain OPEN. The preceding UI source 68d071b has passing host/RPC/legacy checks and SDK jobs in progress; those cannot qualify this newer cache source. No real-router/proxy or publication actions.

## G5 native LuCI forms and confirmed apply checkpoint

A private QEMU/HVF guest now runs actual OpenWrt 24.10.8/aarch64 kernel 6.6.144, procd, ubus/rpcd, UCI, uhttpd and Bootstrap LuCI 26.205.85413~cac97ed. The canonical IPK from run 39410052481 installed with actual opkg/dependencies. That preceding source passed same-byte offline IPK/APK preflight using real apk-tools 3.0.5 inside a network-isolated guest process; wrong attempt, actual byte mutation and advisory-lane substitution were rejected without success receipts. This does not qualify the new source overlays.

Native UI exposes concrete failures: optional proxy routes depend only on a Lua controller absent from a minimal modern LuCI runtime; Sources overflows 320/375px to 440px; four Intelligence sections use nonexistent main section type; Sources/Intelligence bypass shared validation/readback. Most significantly, the existing uci.apply() resolves before its delayed confirmation. The earlier page reload cancels that timer: an actual saved budget of 129 at 0/3 seconds rolls back to 128 by 12 seconds. Apply now uses explicit rollback-capable UCI RPC, verifies fresh exact readback and awaits transaction confirmation before success/reload/restart. Code-5 no-data requires matching state and confirmation/no active transaction; a started transaction with failed/malformed confirmation never reports success.

JSON optional routes, correct main/service binding, shared handlers, bounded MultiValue/grid widths and read-only footer controls are repaired. Sources preserves appended runtime controls through Map.renderContents after save; missing health observations show Unknown. The actual guest retains budget 129 and probe batch 5 beyond the new 30-second window at 35 seconds. Invalid candidates preserve committed hashes, display the root error and retain refresh controls. All eight views have screenshots at 320/375/768/1280 with no page overflow; Intelligence measurement waits for its policy input. Source selector Down/Escape and PassWall Tab focus were observed, not a full keyboard/action acceptance claim.

Proxy presence is an inert guest fixture, not proxy integration. The current LuCI dispatcher executable dependency checks top-level user_exec rather than perm.user_exec, so a regular nonexecutable fixture can retain a menu link; the independent backend reports not installed and the view hides save controls. Missing files hide both links in a fresh session. This upstream compatibility limitation and stale client menu cache are disclosed, not silently passed. Original test UCI bytes were restored and both fixtures removed. Receipt: native-luci-confirmed-apply.json. Changed-source rebuilt packages/latest-SHA CI/offline/native-package acceptance, all remaining named G4/G5 lifecycle/resource/fault/ACL/action gates remain OPEN. No production/device/proxy writes, Release/tag/feed or Docker restart.

## G5c cached/offline CFST qualification checkpoint

At baseline e4b0911, twenty-one cache cases expose thirteen failures: twelve unqualified cache entries execute a probe (including missing/malformed/legacy/unsafe provenance, oversized metadata and links), while a qualified uppercase digest is refused. A separate installer case accepts a missing expected digest by hashing its own input. The installer now requires a supplied expected digest. Cached/offline entry admits only regular non-symlink archives and bounded metadata, parses exactly one schema-1 snapshot, and binds a nonempty version, HTTPS source and matching digest from that snapshot. Invalid metadata preserves an existing executable; without one, it refuses bootstrap. Digest case is normalized. No release version is pinned: a future unknown tag with proper HTTPS provenance remains supported, while the old cached-archive bootstrap marker cannot authorize execution.

All twenty-one cache cases and twenty-three installer cases pass on private host Bash 5.3, plus cached-version/retry, version observation, security and syntax/ShellCheck/actionlint/diff. Receipt: cfst-cache-qualification.json; raw evidence records execution markers and file fingerprints. Payloads are shell fixtures, not genuine CFST/native target execution. Cache metadata is trusted filesystem provenance, not a publisher signature. Download/resource/concurrency/KILL/retention, full G4/G5 and latest exact-SHA hosted/package/offline/native UI gates remain OPEN. Existing QEMU availability was verified as a possible independent native-runtime path while Docker remains unavailable; no VM or native UI PASS is claimed here.

## G5c CFST installation preimage and recovery checkpoint

Actual installer/downloader tests at baseline 3d1139d fail ten of twenty-two cases: four failed preimage copies followed by commit failure lose old artifacts; version write failure reports success; failed restoration discards the binary preimage; installer and download paths parse before digest verification; symlink/directory targets are accepted. The update now checks version writes and every private preimage before any live rename, refuses nonregular mutable targets, and verifies digests before parsing. Commit recovery restores via fresh copies, retaining all originals until every restore succeeds. Failed recovery explicitly retains named preimages and reports their path instead of deleting the only old bytes. Fixed-PID backup paths are no longer used.

All twenty-two cases pass on private host Bash 5.3, including cached/same-archive and new bootstrap installation, each snapshot/commit failure, recovery failure with all four preimage hashes/modes retained, unsafe targets, execution rejection and both digest-order paths. Cached version/retry, version observation, security and synthetic byte/archive/architecture negatives pass, plus Bash/ShellCheck/actionlint/diff checks. Receipt: cfst-install-recovery.json; the raw before/after results include target fingerprints. Payloads are harmless shell fixtures, not real CFST or native OpenWrt acceptance. Sequential per-file replacement is not a durable generation/journal. KILL/reboot, resource/retention/concurrent-installer and full G4/G5/latest-SHA hosted/package/offline gates remain OPEN. The private test shell does not change the system shell or package dependencies.

## G4 native target utility results and APK diagnostic-log boundary

Run 39239175319 attempt 1 at exact source 3d1139d completes all four SDK jobs. Strict attempt-scoped downloads retain four actual target utility receipts, each with fifteen passing lock cases and a distinct compiled binary digest. This proves SDK-produced OpenWrt flock execution on the CI Linux kernel with host shells; it is not installed-package/native procd/rpcd/LuCI or router proof. Actual opkg missing/truncated input cases both pass with exit 255 and preservation evidence.

The actual APK matrix fails at its missing-input payload comparison. Exact-attempt artifact replay proves the only changed payload record is var/log/apk.log; owner listings, installed info and every other file record are identical. The test now excludes only this package-manager diagnostic log and retains before/after log copies separately. No user/product log subtree is broadly ignored, and installed DB/info/ownership/user hashes remain required. Receipt: sdk-and-migration-log-boundary.json. The APK truncated case was not reached and its automated matrix remains incomplete until a corrected-source rerun. The whole run failed; native component results cannot qualify the newer source, satisfy offline preflight, or close full G4/G5.

## G4 SDK writer gate host environment correction

The first actual SDK gate fails on both APK jobs after successful package compilation. Completed job 118005420386 in run 39236083235 identifies `jq: command not found` at sdk-writer-lock.sh line 28. The SDK host did not promise jq; the gate now uses its existing Python standard library to inspect metadata and emit the final receipt. It also uploads separate diagnostics after an attempted execution fails, so cases/binary/loader details are retained without entering the public package artifact. This corrects the test runtime requirement; it does not convert the failed execution into native PASS.

The actual 15-case writer matrix passes with jq invocation explicitly denied on the Darwin host kernel adapter. Both embedded Python blocks compile, and Bash syntax, ShellCheck error, actionlint and diff checks pass. Receipt: sdk-writer-host-runtime.json. Corrected-source target utility execution, all current-SHA SDK/migration/artifact/offline qualification and full G4/G5 remain OPEN. Superseded runs containing the known missing-host-tool defect may be cancelled rather than used as qualification.

## G5c cache-publication workspace recovery checkpoint

Three KILLs before the cache switch reproduce three abandoned candidate files even after a later successful publication. New candidates now use an owned, marked per-source private namespace and actual caller-PID directories. The next allocation quarantines recognized dead-owner directories atomically before deletion, preserves live/reused owners and unknown data, and refuses failed quarantine or unsafe/unowned namespaces. Empty-directory reservation precedes a sampled sixteen-directory admission check; overload preserves the prior bundle and the full fetch path can use qualified stale fallback. No stat dependency is added; actual Bash 3 caller-PPID capture is exercised.

Ten groups pass, including three KILLs on each side of the switch, live owners, old unmarked candidates/symlinks/unknown data, capacity refusal/reuse, full fetch fallback, unsafe namespace shapes and failed quarantine/retry. Existing cache publication fault/KILL/concurrent-snapshot, cache trust, output/status failures, source engine/policy/deadline/size and actual curl/local-HTTPS regressions pass, plus syntax/ShellCheck/actionlint/diff. Receipt: source-cache-workspaces.json. These are Host/Bash 3 software observations; native exact-source OpenWrt remains NOT EVALUATED locally while Docker is unavailable. Admission is not a kernel global quota. Old unmarked candidates and fetch/parser/snapshot temporaries remain separately OPEN, as do full resource/power-loss, G4/G5 and latest-SHA hosted/package/offline qualification.

## G4 invalid package input preservation gate checkpoint

The strict validator previously accepts missing negative-install evidence. Each real opkg/apk migration invocation now installs the candidate in a fresh isolated root, attempts both a missing package and a 32-byte truncation of the actual candidate, requires a nonzero manager exit, and compares installed package info, base ownership lists, payload hashes/modes/symlink targets and user data. Manager DB copies, snapshots, logs and exit codes are retained. Only after both execute successfully are their PASS records included in current-matrix.json. Release eligibility now requires both records per manager, exact evidence-directory names, all preservation checks and an integer exitCode in 1..255; missing/partial/false/invalid records are refused.

Host strict qualification mutation and synthetic byte-binding regressions pass, plus artifact-download API fixtures, seven package-identity tests and shell syntax/ShellCheck/diff. Receipt: migration-negative-inputs.json. The native manager cases are NOT RUN locally because opkg/apk and Docker are unavailable; hosted current-SHA migration must supply the actual evidence. These cases prove only early invalid-input refusal, not mid-install rollback, owner conflicts, uninstall/lifecycle or genuine dependency/Runtime installation. Those remaining G4 requirements and full G5 remain OPEN. Earlier SHA CI results cannot qualify this changed source or satisfy the new evidence contract.

## G5b/G5e Overview acknowledged task status checkpoint

The actual pre-change Overview click handler reloads after a fixed delay without observing any status for the acknowledged task. It now waits for both runId and requestId to match the startup acknowledgement, accepting either active or already-terminal status. Missing/incomplete/unconfirmed startup, stale or foreign status, hanging/network-failed RPC and navigation cancel cannot trigger a success-path reload. Polling is bounded, stops on settlement/navigation, and failure restores the button. Status-observation failure does not claim the backend task failed; the message asks the user to check status/logs before retrying. English/Chinese catalogs are included.

Ten actual-handler/utils module cases pass, plus readiness, refresh-error, fresh save readback and save singleflight regressions, JS/catalog/actionlint/diff checks. Receipt: luci-run-status.json. DOM/RPC are controlled fixtures; native LuCI/browser eight-view responsive/keyboard/actions acceptance remains OPEN. Current exact-SHA CI/package/offline and full G4/G5 remain OPEN. The preceding writer-lock candidate CI 39236083235 is separately in progress and cannot qualify this new source.

## G5e shared writer-lock recovery checkpoint

Baseline 3477494 admits two writers after simultaneous stale-PID recovery and falsely accepts a failed owner-PID write. CLI, init and RPC now share a persistent-inode kernel flock gate around PID metadata operations. The whole-task PID directory remains compatible; live/reused owners and unknown payloads are preserved. PID creation is checked, partial writes are cleaned for retry, symlink/unsafe metadata is refused, and kernel-tool failures retain their exit code. The gate is not held across task execution. The package explicitly depends on OpenWrt flock and installs the shared helper.

The 15-case actual-function regression passes on the Darwin kernel through a host-only fcntl adapter, including forced stale recovery scheduling, failed/partial PID writes, real process-group KILL and stable gate inode. Shared/nested lifecycle, 26 early-status cases, 141 RPC cases, eight startup groups and routing/staged validation/cron regressions pass. Syntax, ShellCheck error level, actionlint and diff checks pass. Receipt: writer-lock-recovery.json. The preceding exact-source PR run 39203838421 succeeded; this checkpoint requires new qualification. Four SDK jobs now build and execute the target flock utility with separate source-SHA/run/attempt receipts; that new execution gate is NOT EVALUATED until hosted results arrive. This is staging-target execution, not installed-package/native procd/rpcd/LuCI or router proof. Docker remains unavailable and was not restarted. Cooperating writers require the persistent gate inode and trusted runtime namespace; no universal noncooperating CAS, dead-transaction recovery or power-loss claim. Full G4/G5 remains OPEN.

## G5e early exit status identity checkpoint

Fourteen of eighteen initial actual RPC/CLI cases left stale success, missing state or an empty run identity after early failure. A run ID is now allocated before the startup acknowledgement and retained by later run-path setup. Status carries the matching run/request identity. The pre-start cache is fingerprinted under the shared lock without replacing it, preserving the actual current-IP reuse path. Post-entry EXIT can publish inactive failure for its own run record or the unchanged previous cache. Foreign edits/symlinks and lost lock ownership are preserved; initial snapshot failures refuse entry. Existing terminal root errors survive, with later recovery errors appended. Legacy recovery-only EXIT behavior outside full run_v2 remains scoped as before.

Twenty-six actual RPC/CLI/status cases pass across both provider modes, with fixture config/context/health; receipts include startup/observed identity and config/backup/history/user hashes. Startup sh/dash and 141-case RPC matrices, full→real-current-IP reuse, Adaptive/context requalification, OpenClash service/recovery/legacy-scope, signal rollback, stopped/v2 status and shared-lock regressions pass; syntax/ShellCheck/actionlint/diff pass. Evidence: run-early-failure-status.json. Publication storage faults, stale-lock recovery/concurrency, explicit Overview runId matching, full native/browser gates, broader G4/G5 and final exact-SHA hosted/artifact/offline qualification remain OPEN. This is guarded ownership/preimage checking, not universal noncooperating CAS. Docker remains unavailable; no shared runtime/business container restart.

## G5e acknowledged asynchronous run startup checkpoint

Actual RPC reproduced running:true for invalid config, missing backend, a held configured-runtime lock and all eight concurrent requests. RPC now uses a private anonymous pipe; actual run_v2 acknowledges only after both config reads and shared-lock acquisition. Missing/failed starts preserve failure details. Replies are bounded and require one matching startup object. Timeout/missing/malformed acknowledgements are explicitly unconfirmed with accepted/running null, not false certainty. A vanished reader before the acknowledgement stops the backend before context mutation. Source-only mode shares the existing normalizer without exposing a new ubus method; no FIFO utility or persistent IPC file is added.

Host sh and dash each pass eight grouped startup cases (including four malformed protocol variants), eight-way contention, helper failure, bounded timeout/late-mutation refusal and scratch absence. The actual capture test also exposed inherited stderr keeping RPC open for six/twelve seconds; detached stdin/stderr fixes nonblocking return. The 141-case synchronous/lifecycle matrix and shared-lock/Adaptive/staged validation/signal rollback/reuse/OpenClash regressions pass, plus syntax/ShellCheck/actionlint/diff. Receipt: rpc-run-acknowledgement.json. Configuration/context callbacks are fixtures; native rpcd/BusyBox/procd and browser proof remain NOT EVALUATED because Docker is unavailable. Post-ack early failure persistence and the full G5e matrix remain OPEN, as do broader G4/G5 and final exact-SHA hosted/artifact/offline qualification.

## G5e RPC failure and read-only method policy checkpoint

Actual dispatcher tests reproduced 99 failing cases across 22 methods: swallowed backend exits, malformed/multiple output and duplicate speedtest-status JSON. One common result path now requires exactly one object, preserves root failure details/exit codes and prevents backend failure from retaining success. Status/log failures remain independently visible in one merged envelope. Six additional cases proved UCI set/commit failures still invoked init; lifecycle RPC now stops at set/commit/enable failures and reports the exact step. The final matrix passes 132 backend cases, one independent log failure and eight lifecycle prerequisite failures, including shared-lock release.

Actual legacy environment refresh writes its cache, so refresh-env is moved from read to write ACL. Every declared RPC method has exactly one source policy class and all enumerated mutations are write-only. The actual Overview refresh handler previously displayed success for failed results; it now preserves prior badges, reports failure and restores busy state. Four module cases plus ready/readback/singleflight and existing RPC/OpenClash/backup/lock/security/cron regressions pass. Syntax/ShellCheck error/JSON/JS/actionlint/diff pass. Receipt: rpc-failure-policy.json. Dispatcher backend/UCI/init/parser and UI DOM/RPC are fixtures; this is not native rpcd session/browser acceptance. UCI pending/committed recovery, real service/procd/read-only session tests, full G4/G5 and final exact-SHA qualification remain OPEN. Docker socket remains unavailable; it was not restarted.

## G5d missing volatile publisher metadata checkpoint

Actual loopback HTTP reproduced disabled_or_not_started from a disabled configuration after deleting status metadata while the endpoint remained live. Missing/empty metadata now supplies a non-ready observation and continues through the disabled endpoint checks. The read-only query reports publisher_still_responding without recreating status. Existing actual HTTP valid/stale/oversized/500/slow/config-port/stop tests and host status/publisher modules pass; ShellCheck error/syntax/actionlint/diff pass. Native disabled reload/restart/re-enable cases are prepared in publisher-procd-rebind.sh but NOT RUN: the Docker socket disappeared, and shared Docker/business containers were not restarted. Real-UCI event delivery and native proof remain OPEN. Receipt: publisher-missing-metadata.json. Preceding-source c8b0c6d PR run 39151181681 succeeded; this changed SHA needs its own qualification. Full G4/G5 remains OPEN.

## G5d interrupted bootstrap generation retention checkpoint

Six KILLs immediately before the first current-pointer switch reproduced six accumulated owned legacy snapshots. Layout now validates any existing cursor, then prunes owned generations before adding the next bootstrap snapshot; the no-current retention count starts at zero. The same six-KILL regression leaves four owned snapshots with default retention, preserves the legacy bytes and an unknown user directory, and successfully completes migration. An invalid current pointer refuses layout before pruning any generation. Host and isolated OpenWrt pass; generation failure/KILL, workspace, native uhttpd and actual two-reader HTTP regressions pass. Receipt: publisher-bootstrap-retention.json. This bounds the listed software interruption case, not power-loss durability, unmarked or source-cache orphans, full G4/G5 resource/lifecycle matrix or final exact-SHA hosted/artifact qualification.

## G5d private publisher workspace recovery checkpoint

The pre-change KILL regression leaves one private link workspace after a subsequent successful publication. Staging/link/readback allocation now uses an owner-marked private namespace, captures the caller PID before command substitution and preserves live or reused PIDs. Dead-owner paths are atomically quarantined before deletion; failed quarantine refuses allocation. Unknown data/symlinks and nonempty unowned or unsafe writable namespaces are preserved/refused. Empty reservations are counted before payload admission, with a sampled sixteen-directory limit and explicit publisher_workspace_unavailable failure. Concurrent bursts may refuse all requests; a later retry is required. No new stat dependency is introduced: the real minimal OpenWrt runtime exposed its absence and the implementation uses Bash ownership checks plus available ls.

Host and isolated OpenWrt tests cover killed-writer recovery, active owners, quota refusal/reuse, unknown paths, unsafe namespace refusal and quarantine failure. Thirty-two concurrent reservation tests check observed admission and successful subsequent retry; they do not prove a kernel-enforced global quota. Generation/HTTP/status/native uhttpd regressions remain separate evidence. Receipt: publisher-workspace-leases.json. Old unmarked orphans, bootstrap public-generation orphans, source-cache cleanup, complete storage/process lifecycle matrix, remaining G4/G5 and final exact-SHA qualification remain OPEN.

## G5d versioned LAN generation checkpoint

The regression proves a partial artifact renderer failure was ignored. Publication now snapshots bounded selected input, validates public addresses/families, renders/checks every artifact privately and records hashes/sizes in a manifest. A complete generation directory is exposed, read back over its pinned HTTP URL, then a single current symlink switches all compatibility paths. Root readback failure restores the old cursor. Legacy conversion first snapshots the current byte view, so interrupted conversion and regular files left after downgrade retain old bytes. Ownership-scoped retention bounds managed generations while leaving unknown directories alone. Readback snapshots expected bytes and reports the matched generation/count even after a writer dies following the pointer commit.

Host and isolated OpenWrt pass render/cursor failures, interrupted legacy/re-upgrade, post-rename reported error readback and KILL on both sides of the switch. Two actual HTTP consumers during ten publications verify pinned manifests and all artifact digests; 404 eviction/bootstrap retries are allowed, mixed bytes fail. Actual native uhttpd serves pinned artifacts with matching digests; live status/UCI/stop/rebind regressions and syntax/ShellCheck error/actionlint/diff pass. Evidence: publisher-generations.json. Protocol/retention/retry semantics are in docs/LAN_RESULT_PROTOCOL.md. Separate compatibility HTTP requests can still span generations; pinned URLs are required for coherent multi-file reads. KILL private-orphan cleanup/resource exhaustion, broader G4/G5 and final exact-SHA hosted/package/offline qualification remain OPEN. No physical power-loss or universal CAS claim.

## G5d live status and disable acknowledgement checkpoint

The regression reproduced cached success after listener loss and retained ready state after disabling. Status now loads committed configuration through its independent CLI, bounds persisted JSON, follows the current configured endpoint and rechecks matching HTTP bytes without rewriting the last-publication observation. Effective bind/port and query check time are returned. Disabled state is explicitly non-ready; failed stop or an endpoint still responding after a bounded grace interval remains an error. Stop checks both previous and current endpoints. Ubus network lookups have a client timeout. Status semantics are documented in docs/LAN_PUBLISHER_STATUS.md.

Host cases cover stale/missing listeners, stop failure, malformed/oversized metadata, automatic LAN selection and current/previous endpoint checks. Actual local HTTP covers ready/stale/ready queries with unchanged stored bytes, configured-port migration and a no-op stop that leaves the server alive. Native isolated uhttpd disable, independent backend CLI with actual sandbox UCI config and the real-procd rebind regression pass, along with publisher/root-status regressions and syntax/ShellCheck error/actionlint/diff. Evidence: publisher-status-honesty.json. HTTP absence is not process-ownership/physical-isolation proof. Generation publication, full disabled/procd configuration propagation, remaining G4/G5 and final exact-SHA qualification remain OPEN; preceding-source run 39145150770 was still live.

## G5d LAN ownership and interface-event checkpoint

Preceding-source 90a13fe PR run 39143422601 completed SUCCESS; exact source SHA/run attempt/API identity is retained in the receipt. The current init change still requires its own final qualification.

Old start_service accepted a private address not owned by LAN. The init now validates strict IPv4/private ranges, reads only an up LAN interface, and requires explicit bind membership in its current address list; auto bind chooses the first qualified address. A native interface.* LAN trigger reloads the service after interface changes. Existing native reload semantics are retained: a clean-runtime comparison proved extra instance deletion/restart code unnecessary and it was removed.

Host/OpenWrt policy fixtures cover private boundaries, malformed/foreign/public/wildcard/loopback addresses, multiple LAN addresses, address changes/loss and trigger arguments. A dedicated isolated real procd/uhttpd runtime passes event-driven rebind, old-address closure, interface loss listener removal and restoration. Exact pre-fix init fails the rebind test. The runtime has network none/no published ports; network status, loopback private policy and event interface name are fixture-controlled, while production trigger body and native reload/listener mechanics run. Initial tests against the broader LuCI rootfs were interfered with by default network-service callbacks and are not PASS. Final proof uses a separate minimal runtime; no business container or production network was restarted. HTTP/module/package regressions and syntax/ShellCheck error/actionlint/diff pass. Evidence: publisher-lan-rebind.json. Physical LAN/netifd delivery, generation publication, disabled/status reconciliation, other G4/G5 and final exact-SHA hosted qualification remain OPEN.

## G5d publisher HTTP readiness checkpoint

The actual HTTP regression proves init exit 0 produced success despite stale response bytes. Publisher now performs bounded direct, proxy-free HTTP readback and compares the response to newly published result.json before success. Default readiness has three one-second transport attempts with one-second gaps and a sink bounded to expected size plus one byte. Failed readback records publisher_http_readback_failed and returns failure.

Actual loopback HTTP/curl accepts matching bytes (even with a deliberately invalid proxy environment) and rejects stale/oversized/HTTP-500/slow responses without leftover readback temporaries. Actual uhttpd in isolated OpenWrt rootfs accepts exact published bytes and fails readiness after stopping its own fixture listener. Fixture init/loopback tests do not qualify production LAN membership, procd ownership or rebind policy. Module publisher/status, syntax/ShellCheck error/actionlint/diff checks pass. Evidence: publisher-http-readback.json. Multi-file generation publication, LAN address changes, disabled cleanup, port conflicts and remaining G4/G5/final hosted requirements stay OPEN.

Preceding-source b18db38 PR run 39142760572 Host, Legacy, real-CFST, RPC, identity, workflow and Docker jobs succeeded at observation; four SDK jobs remained live. These are preceding-source checkpoint results, not this publisher change's qualification.

## Shared atomic-write failed-rename cleanup checkpoint

The new regression proves a failed publication rename leaves its private tmp file. cfip_atomic_write now attempts to unlink exactly that candidate and returns failure. Eight repeated rename/stream/allocation failures preserve old destination bytes and an unrelated preexisting temporary-name file, remove private candidates when unlink is possible, and permit successful retry. Host and actual isolated OpenWrt rootfs pass; source runtime/publication, transaction, LAN publisher and status regressions plus syntax/ShellCheck error/actionlint/diff checks pass. Evidence: atomic-write-cleanup.json. This does not cover KILL orphans, read-only filesystem transitions or physical ENOSPC, and does not close G4/G5.

Latest aa81e04 PR CI 39142461047 was retained while six duplicate/superseded live runs were requested cancelled. Older push run 39140849991 failed its APK SDK preparation because git.openwrt.org could not connect; the exact failure log is retained, and that run remains FAIL rather than being waived. New source requires final exact-SHA qualification.

## G5c runtime write failure propagation checkpoint

Injected runtime metadata rename failure reproduced a fresh fetch returning success. Fresh and cached paths now propagate status publication failure, and publish records before success status so an output failure cannot publish a new success first. Built-in/custom collectors skip failed remote sources instead of aggregating preexisting records; invalid custom URLs also skip aggregation.

Host and actual isolated OpenWrt rootfs pass fresh/cache status and output failure cases, qualified-cache reuse after recovery and rejected built-in/custom record exclusion. Source cache trust/publication, real local HTTPS and source-engine regressions passed; ShellCheck error/syntax/actionlint/diff pass. Evidence: source-runtime-write-failure.json. Faults are injected renames, not physical disk/flash exhaustion. Orphan cleanup, broader resource/aggregate deadline cases, remaining G4/G5 and final hosted qualification remain OPEN.

## G5c atomic cache bundle publication checkpoint

A real failure injection reproduced changed raw last-good bytes after metadata rename failed, losing the previous qualified pair. New refreshes write a private bounded JSON bundle with content plus qualification fields, verify byte-preserving roundtrip, chmod it and switch it with one same-directory rename. Readers extract raw bytes and marker from one bounded snapshot. Qualified legacy schema-2 pairs remain readable only before a bundle exists; malformed new bundles cannot downgrade to legacy pairs. Publication failure attempts the old qualified cache and reports cache_publication_failed. Cache trust/TLS fixtures now inspect the authoritative bundle format.

Candidate allocation/render/readback/chmod/rename failures and forced KILL immediately before/after publication pass on both the host and the actual isolated OpenWrt ARM64 rootfs. Pre-rename termination preserves old bytes; post-rename termination exposes a complete new qualified bundle. Twenty-four concurrent snapshots during twelve generation replacements retain matching content/metadata on both platforms. Source trust/legacy fallback/corrupt-bundle refusal, real trusted-local HTTPS, source engine, size/deadline, ShellCheck error/syntax/actionlint/diff checks pass. Evidence: source-cache-publication.json. The rootfs fixture contains only source/tests under /tmp, with mocked transport; it is not a router/proxy write or physical device qualification. Physical power-loss durability and repeated-kill orphan cleanup/resource exhaustion remain OPEN, along with remaining G4/G5 and final hosted exact-SHA qualification.

## G5c cache trust and age checkpoint

The new regression proves that a bare syntactically valid IP file was accepted as last-good without metadata. Fallback now snapshots bounded bytes, requires a schema-2 marker binding ID/URL/parser/family/source class/digest and a recent successful validation, then reparses with current checks. Bare, schema-1, changed, reconfigured, expired/future, oversized and malformed caches reject; runtime metadata separates cacheError from the original transport failure. Default age is seven days with sixty-second future-clock tolerance. Byte-identical successful refreshes renew age and repair altered local bytes. Old files remain on disk but require a successful remote refresh to establish qualification; policy is documented in docs/SOURCE_CACHE_POLICY.md.

The exact pre-fix source fails the new regression. Valid fallback, all rejection cases, identical-refresh repair, actual local trusted-TLS source suite, size/deadline and full source-engine regression pass, with ShellCheck error/syntax/actionlint/diff checks. The HTTPS test now changes server behavior behind one stable request URL, avoiding an invalid expectation of fallback across different source URLs. Evidence: source-cache-trust.json. This is not full N02 closure: preserving the previous generation across every storage/publication interruption remains OPEN, as do remaining G4/G5 and final exact-SHA hosted gates. Prior-source 386a025 PR run 39140855082 was still live at observation.

## G5c real HTTPS streaming source cap checkpoint

With max-filesize feature support disabled, actual curl previously wrote 1,126,400 bytes from a local TLS chunked response despite a 2,048-byte source cap. The same regression fails against pre-fix source. A bounded head sink now accepts at most cap+1 bytes, checks both pipeline statuses and rejects overflow before parsing/cache publication; curl still enforces total/connect deadlines and HTTPS-only redirects. Existing max-filesize support remains an additional guard.

Actual trusted-local TLS covers valid, exact-cap, one-byte-over, large chunked, slow response, HTTPS redirect and blocked HTTP downgrade. Post-fix observed temporary bytes never exceed 2,049; slow response finishes near its one-second transport deadline, and rejected responses preserve prior cached bytes. OpenWrt ARM64 BusyBox sink separately passes with a mocked producer; it is not a TLS/device claim. Host source engine, size-cap/deadline, ShellCheck error, syntax, actionlint and diff checks pass. Curl mocks now stream bytes with cat rather than filesystem cp metadata operations on a pipe. New real-TLS test is in Host CI. Evidence: source-streaming-cap.json. Cache trust/age/publication-failure cases and remaining G5c/G4/G5 DoDs stay OPEN; no production device or Release action.

## Actual View save/apply integration checkpoint

Real native View.addFooter calls View.handleSaveApply, but all four plugin forms had installed the shared handlers on form.Map. Actual Settings Save & Apply bypassed backend validation and persisted the unsupported no-proxy sentinel none. The four forms now pass their View owner to shared save/apply hooks; Map.root remains the connectivity boundary. The no-proxy choice is readonly and retains a valid stored target instead of writing none. Backend validation remains strict.

The regression fails against pre-fix utils and passes after repair. Actual browser Settings rejects an empty PassWall target without changing the committed IP count. With a controlled one.example target fixture, actual Save & Apply produces the success notification after independent readback, then a fresh page and CLI confirm count 5, mode passwall and enabled 0. A later save restores count 4. An expired 30-second fixture login was honestly reported as an error; after reauthentication the positive path passed. No service was enabled and no proxy/device configuration was written. Payload was regenerated using actual Makefile macros, preserving the compiled footer version. Readiness/readback/singleflight modules, staged validation, installed routing, JS syntax and diff checks pass. Only Settings was browser-exercised here; remaining views, enabled-service paths, full responsive/keyboard actions, final exact-SHA qualification and other G4/G5 requirements remain OPEN. Evidence: luci-view-binding-fix.json and retained screenshots/logs under Downloads/luci-runtime. Temporary viewport override was reset.

## Real Bootstrap light/dark contrast checkpoint

Actual computed styles reproduced navy body text rgb(36,52,71) on rgb(34,34,34), dim footer text and an inline GitHub link override. Plugin-only tokens now inherit normal theme text, provide readable dark surfaces/muted/link/semantic foregrounds, and use darker light-mode foregrounds for badges and auxiliary text. Overview status/statistic copy uses those same tokens; the GitHub link no longer overrides them and is underlined. Native LuCI global theme variables and layout were not changed.

Twelve actual overview text samples were measured with alpha-composited ancestor backgrounds in real Bootstrap dark and Bootstrap-light: minima 7.19:1 dark and 4.87:1 light. Both screenshots were visually reviewed. The isolated container's theme was restored to its original /luci-static/bootstrap setting. Source/deployed hashes, all sampled colors and screenshots are indexed in overview-contrast-fix.json. These samples do not constitute all-view, responsive, keyboard or complete accessibility acceptance; those remain OPEN.

At observation, preceding-source PR run 39120847735 Host and real-CFST jobs completed SUCCESS; remaining workflow jobs were still running. Same-SHA duplicate push run 39120843880 was requested cancelled. The contrast change requires its own later exact-SHA qualification.

## G5c authenticated CFST smoke byte qualification

The previous hosted real-CFST job failed on unauthenticated release-metadata curl HTTP 403 and executed an archive without prior digest binding. CI now reads metadata through authenticated gh, requires one official amd64 asset with published SHA256/size/URL identity, bounds its HTTPS download, verifies archive bytes before parsing, and prepares only one regular-file amd64 ELF binary. Archive traversal/link/device/duplicate-binary cases reject; output must be new, preserving existing qualified bytes. GH tokens are removed from the smoke child environment. Metadata/qualification receipts plus raw input/CSV/parsed JSON are uploaded with exact run/attempt artifact names after successful smoke.

Synthetic metadata/digest/archive/architecture negatives pass, including proof that a bad digest rejects before tar parsing and same-size changed bytes reject. The actual upstream v2.3.5 asset (491252222) passed byte qualification and bounded execution/parser smoke in an isolated amd64 Linux container; one observation was parsed. Original archive, metadata, receipts and outputs are retained in Downloads/cfip-g4-g5-evidence/cfst-byte-qualification and indexed in cfst-verified-execution.json. The preparation receipt says execution NOT RUN by design; the separate execution receipt records the actual local run. This does not prove router/soak/production updater behavior or close full G5c. New hosted exact-SHA qualification remains required. actionlint, syntax and diff checks passed.

## Real overview display repair

The actual initial page showed TAR/JQ Missing despite status.env and check-env reporting true, and its footer displayed v2.6.0 despite the compiled full identity 2.6.0-r5. Overview now combines legacy root environment fields with canonical nested env (nested values take precedence), and lets the compiled footer identity supply the package version instead of overriding it with script_version. After deploying the identical-hash overview component, a fresh browser reload (no environment-refresh click) shows both tools Installed and footer v2.6.0-r5. Actual screenshot/AX state, RPC version and source/runtime hashes are indexed in overview-display-fix.json. Node syntax, installed-routing and package-authority checks passed. Dark-theme contrast and the rest of the eight-view/action/viewport matrix remain OPEN; this is source-payload runtime evidence, not current SDK package/device qualification.

## Real LuCI runtime established

Official OpenWrt 24.10.8 ARM64 rootfs SHA256 was checked before import. A separate non-privileged cfip-luci-qualification container runs real procd/ubus/rpcd/LuCI, bound only to 127.0.0.1:32768. Existing business containers were not changed. The actual current Makefile prepare/compile/install macros generated a 38-file source payload for 48af71d, then rpcd registered cf_ip and its status/check-env/version methods. This is development runtime evidence, not SDK package/installed DB qualification.

The browser loaded the actual plugin overview and clicked Refresh Environment, observing TAR/JQ become Installed with a success message. Initial page + backend JSON reproduce two open defects: initial nested env ignored and package-release suffix omitted from footer. Before/after screenshots, rootfs/payload hashes and JSON are retained in Downloads/cfip-g4-g5-evidence/luci-runtime and indexed in docs/audits/g4-g5-evidence/luci-runtime-initial.json. Eight-view responsive/keyboard/save/apply/restart coverage remains OPEN. The browser tab and container are retained for continuation.

Latest candidate PR run 39119216911 real-cfst-smoke failed because the unauthenticated GitHub metadata curl returned 403. A separate authenticated read confirms the current asset has a SHA256 digest. Authentication plus pre-execution digest binding still need implementation; the failed gate was not bypassed. Duplicate same-SHA push run 39119212740 was requested cancelled.

## G5b duplicate-save and stale-response checkpoint

The real-utils harness reproduced two saves from duplicate clicks. The shared handler now returns one pending operation, marks the originating button busy, restores it after success/failure, and permits a later retry. Form.root connectivity and handler generation prevent stale responses from restarting, notifying or scheduling a reload after view replacement. Delayed reload callbacks also recheck activity. Button ownership prevents an older operation from unlocking a newer operation sharing that button; original labels survive overlapping generations. Module tests cover duplicate calls, rejected/synchronous saves, retry, disconnected form, replaced handler and overlapping old/new readback completions. These tests and readiness/full-readback/catalog/static checks pass, but real browser interaction, eight-view responsive/keyboard coverage and other action paths remain OPEN.

The staged-validation state snapshot now uses portable Python filename/hash enumeration and rejects an empty fixture, removing macOS find -printf warnings. It passed again with actual state hashes. Before/after concurrency evidence is under Downloads/cfip-g4-g5-evidence/luci-concurrency. These changes need new remote qualification.

## G5b fresh full-config readback candidate

An actual-utils save-handler regression reproduces false success when uci.load reuses staged cache after apply/code-5 while backend settings differ. The handler now snapshots every staged cf_ip section/type/option (including custom sources), reads through an independent reject-enabled UCI get RPC, and checks fresh UCI changes for that package. It compares normalized full snapshots before restart/success. Pending changes, differing/deleted sections/options, malformed data and RPC failure stop success/restart; matching code-5 readback and enabled-service restart/ready pass. Unrelated packages' pending changes do not block cf_ip. No ACL expansion or shared-cache unload was added; errors do not print setting values. Catalog and module/static checks pass. This remains module/API evidence; real LuCI browser/rpcd verification, busy/generation and concurrent change windows are OPEN. Source/API inspection and before/after logs are retained under Downloads/cfip-g4-g5-evidence/luci-readback.

The isolated Linux invocation with jq installed completed both TERM and child-tree rollback successfully. PR CI 39102692151 at eb1b2c6 completed SUCCESS; it does not cover this newer readback candidate.

## G5b readiness promise checkpoint

The actual utils module returned a non-ready status normally on timeout, allowing the save chain to display ready success; the new module regression reproduces this against the old source. Readiness now resolves only for an idle ready service, rejects timeout/cancellation with explicit codes, preserves RPC failures, bounds a hanging RPC with an independent total deadline, and clears polling timers after settlement. The real-module Node harness covers active jobs, hanging RPC, inactive view, cancellation during a hanging request, network failure, late failure and no polling after timeout. English/Chinese catalogs and template include the new messages; msgfmt, module syntax, staged-validation and workflow checks pass. These are module tests, not browser/device proof. Fresh UCI readback, generation/busy handling and eight-view browser acceptance remain OPEN.

The pre-readiness-change full V2 Host driver completed all 137 workflow commands with return code zero; its source/diff provenance and individual logs are preserved under /Users/yunshu/Downloads/cfip-g4-g5-evidence/host-baseline-fcb9f5e. The macOS child-tree case is explicitly skipped. The first isolated Linux invocation failed for missing jq; a fresh disposable invocation installing jq is still running, not PASS. Existing business containers were not restarted.

## Hosted Host failure and fixture alignment

Run 39100843086 Host failed immediately after recovery-deadline, at sync-single-restart. Job 117596612910 raw logs and a local traced reproduction show the old UCI fixture lacks `changes`; the new transaction correctly rejects an unreadable pending-delta state before snapshot. Sync/signal fixtures now explicitly return no pending delta. Signal cases call the actual journaled owned-write helper and model real option reads instead of bypassing it with raw writes. Local sync single-restart, stop-failure cleanup and TERM rollback pass. The child-tree case is SKIPPED on macOS; an isolated Linux container invocation is still pending, not PASS. A frozen driver is executing all current V2 Host commands, recording individual return codes under /tmp/cfip-g4-g5/current-host-full; completion is not yet asserted. Production guards are unchanged by this fixture repair.

## Y01 duplicate-field ambiguity checkpoint

The actual mapping reader accepted a second server field silently before this change. All three support checks now reject duplicate mapped fields and node identity fields nested below their supported direct depth, reporting line plus reason. Duplicate type/server/tls/network/servername/Host and nested-type negatives pass; supported block, both self-contained engines, section isolation, protocol/readback and renderer regressions pass. docs/OPENCLASH_YAML_SUPPORT.md records the exact current boundary and the still-open full-document/escaping/other duplicate-key requirements; this is not a complete YAML validator or Y01 closure. Static checks passed.

## Legacy/standalone unsupported-proxy entry gate

Both self-contained engines now invoke the conservative proxy support check before creating config temp files/backups. The two-engine rejection regression verifies unsupported mixed inline input fails, config bytes remain identical, and no temp/backup is created. It also compares the embedded function definitions with the canonical mapping-reader definition to prevent drift without adding runtime file dependencies to the standalone script. Supported section, protocol, first/second/third, suffix, actual renderer and readback regressions pass; ShellCheck/actionlint/diff checks pass. Whole-document syntax/duplicate-key handling and complete Y01 support policy remain OPEN.

## Legacy/standalone transform section checkpoint

The original standalone transformer changed the proxy-groups tail while generating two variants: a top-level section header was carried inside the final proxy template. Both standalone and Legacy now process blocks only within top-level proxies and emit missing variants before leaving that section. A real two-engine regression runs transformation twice and verifies unchanged tested group/rule tails, one group header and exactly two proxy server entries. Protocol matrix, actual renderer, suffix, first/second/third run, backup roundtrip and review regressions pass, as do ShellCheck/actionlint/diff checks. Host CI includes the two-engine test. Whole-document YAML validity and Legacy unsupported-syntax rejection remain OPEN.

## OpenClash mapping section isolation

A supported proxy followed by a proxy-groups selector produced two actual mapping records before the fix: the selector was incorrectly parsed as a proxy node. Mapping extraction now starts only at top-level proxies and emits/resets at the next top-level section. The new group-isolation case, mixed-YAML boundary suite, positive/negative readback, real renderer isolation and protocol matrix pass, together with ShellCheck/actionlint/diff checks. Legacy transformer section handling and full-document support validation still require work; this is not complete Y01 evidence. Before log: /tmp/cfip-g4-g5/yaml-groups-before.log.

## Y01 mixed-proxy mapping checkpoint

Before evidence: a supported block proxy plus an inline proxy returned successful actual mapping containing only one proxy. A conservative proxy-boundary check now runs before actual/intended mapping generation and rejects mixed inline maps, alias/merge forms, folded values, inline root proxies, duplicate proxies roots and tabs. Supported block mapping, positive/negative readback and real renderer isolation tests pass; boundary negatives produce no partial output. Host CI includes the boundary regression. This is explicitly a mapping-reader support boundary, not general YAML validation: whole-file grammar, duplicate/nested-key rules and standalone Legacy entry coverage remain OPEN. Y01/G5a are not complete.

## PassWall value-preservation checkpoint

A real-UCI multiline/tab/trailing-newline remarks case failed recovery: shell substitution discarded trailing newlines and line-oriented delta scanning treated continuation text as unrelated changes. UCI and JSON value reads now preserve trailing bytes; pending validation matches complete canonical quoted records, never evals text, and checks both owned key and permitted value. The actual CLI now restores byte-identical exports for multiline/tab/trailing-newline values, single/double quotes, backslashes, glob characters and literal shell text. Existing real-UCI rollback and five fault cases, commit-failure/managed/transaction regressions, ShellCheck/actionlint/diff checks pass. Hosted run 39100627336 remains in progress; this value fix requires new qualification and does not complete G5a.

## Real-UCI storage/read fault checkpoint

Five actual-CLI injection cases now pass: get failure, journal jq failure, journal rename failure, set-before-mutation failure and set-after-mutation failure. Before the read fix, a failed get was accepted as an absent original option. The read helper now verifies the parent section and rejects a failed get for a field that still exists, rather than journaling it as absent. Existing eight real-UCI cases and transaction commit-failure regression still pass; ShellCheck/actionlint/diff checks pass. The fault suite is wired into the same pinned-source real-UCI Host CI step. Hosted run 39100627336 was queued at observation; duplicate push run 39100624844 was requested cancelled. This is not the full storage/signal/concurrency matrix and does not close G5a.

## Real-UCI CI and managed-state conflict checkpoint

tests/build-real-uci.sh builds pinned upstream libubox/UCI in a fresh absolute prefix. A fresh local rebuild passed all eight real-CLI rollback/commit/entry cases, including external managed-state edits, changed state before commit and preexisting pending changes. Host CI now builds and runs this real test with explicit cmake/pkg-config/json-c dependencies. The managed-state expected-after snapshot is copied before publication; rollback accepts only original or transaction-written state, refusing third-party state bytes before restoring fields or restarting. Seven related local regressions, ShellCheck, actionlint and diff checks passed. Hosted execution for this candidate is pending; complete storage/signal/concurrency fault coverage and durable journal policy remain OPEN.

## G5a PassWall owned-field candidate

Real UCI (74f6277aabffc943d026f406df57c22595134c42) and libubox (da2d205a5cf3e877c45a2eec488218cbaf452e7d) were built under /tmp/cfip-g4-g5 only. The original full-export rollback demonstrably overwrote an unrelated committed user edit. The candidate journals each address/remarks write before mutation and restores only matching owned fields, preserving unrelated committed edits. Real CLI tests pass for unrelated-edit preservation, owned-field conflict refusal with retained journal, originally absent field restoration, jq row-decode failure and unrelated pending-delta preservation without implicit commit. Pending changes at transaction entry are rejected. Recovery checks pending keys before writes and commit; this is detectable conflict protection, not universal CAS against noncooperating writers. Full export remains diagnostic only.

Seven related transaction/service regression scripts plus ShellCheck, actionlint and diff checks pass. The commit-failure fixture explicitly models an empty UCI changes result. Real UCI regression is not yet wired into hosted CI. Pending-delta concurrency windows, managed-state-file conflict handling, every storage/parse/commit failure and durable failed-journal policy remain OPEN; T02/G5a are not complete. Evidence: /Users/yunshu/Downloads/cfip-g4-g5-evidence/passwall-external-edit.

## G5a external-conflict recovery checkpoint

The new rollback regression reproduced an unsafe restart after detecting an externally edited OpenClash file (stopped=true, serviceApplied=true). Rollback now returns failure immediately, preserving external bytes and both journal snapshots without starting the unvalidated configuration. Four stopped/applied combinations and repeated recovery attempts pass; a positive known-bytes recovery restores the original and restarts exactly once. Existing write-failure, review-regression, commit-failure, single-restart and original-service-state tests passed, as did ShellCheck/actionlint/diff checks. This closes this specific conflict path only; PassWall owned-field recovery, YAML boundaries and the full G5 fault matrix remain OPEN. Before evidence: /tmp/cfip-g4-g5/rollback-external-before.log.

## Hosted migration and offline preflight checkpoint

Run 39000051779 attempt 1 completed SUCCESS at head 07802d4. The tested merge commit 229363fb1c900df6b484a5246645395ec628b689 and head have identical tree 04d32482234e8b388775f284cd94e2018fb93ec1. Downloaded details independently confirm all ten final installed DB snapshots and matching before/final hashes for four controlled user files. Actual public IPK/APK bytes passed offline metadata/byte preflight; wrong attempt and a one-byte mutation of the actual IPK copy failed without a success receipt. Receipt and reproduction guidance are in docs/RELEASE_PREFLIGHT.md. Full downloaded evidence is retained in /Users/yunshu/Downloads/cfip-g4-g5-evidence/run-39000051779. This does not close broader negative migration, uninstall/lifecycle, final changed-SHA qualification or G5 requirements. Publication NOT RUN; device acceptance NOT EVALUATED.

## G4b strict current-matrix checkpoint

Strict release validation now requires one IPK and one APK matrix, all five input roles, valid metadata/size/digest, matching candidate base/addon versions and public asset version identity. All five scenario operations and runtime/user-data assertions are checked; unsafe evidence paths and malformed IDs are rejected. Synthetic positive and tamper tests, source-authority contracts, ShellCheck, actionlint and diff checks passed. Real package execution and G4b/G4d completion remain OPEN. JSON assertions do not constitute device or online lifecycle proof.

基线：CF `cb06c61bc09ec2dbb98e249d46c212e2d80238bd`，G3 十二包资格 run 38928695476 attempt 1 不变。工作分支 `codex/reliability-contracts`。当前未完成 G4/G5，不具备新的 Stable 资格。保留旧分支、已发布资产、用户配置及既有 G3 证据。

## 完成定义

以 `stable-cross-repo-remediation-plan.md` 的 G4a–d、G5a–e 及逐阶段 DoD 为完整范围。G4 必须覆盖 Host/Legacy、真实 SDK/两格式迁移、统一 Release predicate、同 bytes 的离线 preflight；G5 必须覆盖事务、真实 LuCI 八视图交互、来源/CFST、LAN generation 与重绑定、生命周期/RPC。UI/HTTP/运行/包/设备证据分别记录，未执行不得视为 PASS。

## 当前证据

- G4a/C01：原后缀测试因缺少 OpenClash UCI 状态 fixture 失败。只修改该 fixture，模拟显式禁用且无 core 的服务；保留真实 pre-write guard。增加未知状态、enable 外部改变、core 外部启动三个拒绝反例，逐一比对配置未改变。25 个 Legacy 组脚本本地通过，ShellCheck error 级与 diff 检查通过；最终 exact-SHA 远程资格仍 OPEN。
- G5a/T01：新回归用例复现两类失败：transform 写后失败留下新 live 内容且恢复冲突；written snapshot 复制失败留下 MUTATED 与 applyActive=true。修复前日志已保存，不降低断言。现已改为私有候选渲染、预先保存 expected-after journal、候选 readback、相邻临时文件发布前检查及原子 rename；手动备份恢复也复用这一顺序。旧引擎新增内部 render 入口，不再让该子进程处理服务生命周期。

## 未完成项

G4b/c/d、G5a 修复及完整故障矩阵、G5b 浏览器和 UCI readback、G5c 网络与二进制更新、G5d 真实 HTTP/地址变化、G5e 生命周期/RPC，以及整合提交的远程 CI 都保持 OPEN。真实设备/持续运行属于后续 G6，未授权不写设备。合并、tag、Release/feed 发布不执行。

证据见 `docs/audits/g4-g5-evidence/initial-evidence-index.json`。

## T01 本地修复检查点

- 八种正常 apply 故障（变换写后失败、journal/candidate/backup 复制、发布 rename、候选和 live readback、外部编辑）均正确拒绝；外部编辑保留，其余场景保留或恢复原 live 内容，applyActive 清理。
- 手动备份恢复四种场景通过，包括 journal 复制失败保留原文件、rename 失败、外部编辑拒绝和正常恢复。保留 pre-restore 备份语义。
- 真实 bounded adapter 调用真实 Legacy renderer，只修改私有候选；整条禁用服务事务通过真实 IntendedMapping/readback/发布/commit 与备份数量检查，没有 UCI 写、controller 或 init 副作用。
- 正向用例新发现 readback validator 缺少 jq -n，空 stdin 下返回 4；修复后正确映射通过，错误 network 和 duplicate 仍拒绝。原历史 negative-only 用例不是正向资格。
- 当前 15 个相关回归脚本通过，ShellCheck error 级及 actionlint 通过。证据：`transaction-checkpoint-index.json`。这不是 G5a 全部完成：PassWall owned-field 恢复、YAML 支持边界、完整中断/资源故障矩阵与失败 journal 持久化仍需继续。发布前比较只拒绝可检测的外部变更，不声称一次 POSIX rename 提供对所有不协作写入者的全局 CAS。

## G4c attempt 绑定检查点

- 最新已推送事务提交 `8a4013d8a20de9b3264a442519289035d74cf324` 的 PR CI run `38946835586` 已终态：Host、Legacy、RPC、四组 SDK、两格式真实迁移、Runtime 集成、CFST、Docker、资产合同与 workflow lint 均成功；development release guard 失败，qualification guard 因而失败。整体仍 FAIL，不具备发布资格。
- 修复前直接调用真实严格验证器，缺少 runAttempt、布尔 true、零和任意 attempt 2 都被接受。现在严格验证要求调用者传入正整数 expected attempt，manifest 同字段必须正整数且精确相等。manifest writer 要求 GITHUB_RUN_ATTEMPT，release 两个验证入口传递 workflow_run.run_attempt。
- 七类 manifest attempt 负向、五类 expected attempt 负向、严格校验/manifest 默认值/合成字节绑定/下载文档/渠道/预发布工作流合同通过；actionlint、ShellCheck error、diff 检查通过。修复旧负向用例未传 expected commit 导致提前拒绝的问题，避免掩盖被测字段。
- 本检查点尚未关闭 G4c：artifact 名称/下载的 exact-attempt 来源、统一 required-job predicate 以及真实同 bytes 离线 preflight 仍 OPEN。开发分支版本策略冲突待按源版本合同修复，不豁免失败门禁。

## G4c artifact 来源检查点

- CI 上传的 SDK、迁移、Runtime 集成与 qualification evidence artifact 全部使用 `BASE-run-ID-attempt-N` 名称；同一 run 的不同 attempt 不再共享名称。下载保留逻辑目录，包内路径/metadata/bytes 合同不变。部分 rerun 缺少本 attempt 所需产物时拒绝，不借用旧 attempt。
- 新只读下载工具先检查 GitHub run attempt API 的 id/attempt/head_sha，再检查全部分页的 artifact 列表，拒绝缺失/重复/过期精确名称，之后调用 gh download。PR 使用 workflow run 的 head SHA 作来源校验，包测试 manifest 仍保留实际 GITHUB_SHA；release 使用同一来源 SHA。
- mock API 边界正向与错误 run/attempt/SHA、旧 attempt 名称、缺失/重复/过期产物负向通过；已接入 Host。严格证据、下载指南、预发布工作流合同及 actionlint/diff 检查通过。真实 hosted 新命名下载尚待本提交 CI，不将 mock 视作 hosted 通过。

## G4c required-job predicate 检查点

- 修复前从 HEAD 提取真实旧验证器，使用 releaseEligible=true 且 jobs={} 的完整合成 manifest，严格验证实际通过，证明缺陷。旧 jq all() 对空集合也为 true。
- 新增共享 qualification_jobs.py，定义 12 个必需 job（包含 package-identity），严格要求集合完全相等且每项 result=success。CI qualification guard、manifest writer 与严格发布验证共用该函数/CLI，缺失、额外、跳过、失败、取消或未完成均拒绝。两个 CI needs 列表同步包含 identity。
- 对每个必需 job 分别删除并注入六种非成功状态，另测空/错误类型/额外集合；全部拒绝。正向、manifest diagnostic、合成字节绑定、版本源合同七项、预发布合同、ShellCheck error、actionlint/diff 通过。不是 hosted/真实包新资格结论。
- artifact 新命名提交的 PR run 38999749248 已回读 in_progress；同 SHA 重复 push run 38999746629 已请求取消。

## G4 版本构建策略修复

- 原 CI 38946835586 的 package-release-guard 已证明：候选分支继承 2.6.0-r5 时，旧逻辑强制任意非 main/release 分支必须为 -dev，导致隔离 exact-SHA 候选测试无法全绿。
- 新 source build policy 允许 feature 分支测试源权威给出的最终候选版本，同时 main/release 分支及其 PR base 拒绝 -dev；Stable 渠道在任何分支拒绝 -dev。只改变构建资格，不授予发布资格，release 工作流的 main/head/channel/非-dev/完整资格门禁保留。
- 24 种 ref/event/base、version 与 channel 组合通过；实际当前候选 source 检查通过；预发布工作流合同、actionlint、diff 检查通过。
- 远程 run 38999749248 仍 in_progress，Legacy/RPC/identity/workflow/Docker/CFST 已成功，Host 与四 SDK 在执行。

## G4b installed DB 与用户数据证据候选

- 原迁移脚本退出清除 root，artifact 仅含固定布尔值，无法复核 installed DB/owner/用户数据。新增逐 install/remove/final 阶段原始 installed DB 复制、包 files 清单、etc SHA256；details 随 migration artifact 上传，失败也上传已有详情。
- 当前 base 安装前植入受控测试 UCI（含自定义 URL）、backup/history/用户 cron，并在安装后、addon 卸载后及最终逐项核对 SHA256。只使用隔离 root，不接触宿主配置或设备。移除测试 opkg --force-maintainer，按正常 conffile 保留行为验证。
- bash syntax、ShellCheck error、actionlint/diff 通过。真实两种包管理器尚待新 CI 执行，未视为通过；通用 from/to metadata、最近公开输入来源、卸载/生命周期和负向矩阵仍 OPEN。APK --no-scripts 与 IPKG_INSTROOT 隔离边界明确，不能代表在线 postinst/procd 行为。

## G4b 通用 current matrix 候选

- 新矩阵记录实际 legacy/current base/addon 与 recentBase 五类输入的真实包 metadata、size、SHA256；历史输入若从固定源码重建，证据记录实际重建 bytes，不假称公开下载 bytes。
- a–e 场景明确 from/to role、addon absent/retained/replaced/removed、runtime absence/presence、用户数据核对和对应详情目录。只在真实场景全部成功后生成 PASS 矩阵；CI 合并 IPK/APK currentMatrices，历史 r3ToR4 字段保留并注明不描述当前目标版本。
- jq 合成 metadata 渲染及五场景结构检查通过；bash syntax、ShellCheck error、actionlint、diff 通过。尚需严格 matrix validator、真实包管理器运行与输入来源策略校验，G4b 未完成。
- 最新既有 PR run 38999920322 仍 queued；其同 SHA push run 38999916824 与旧候选重复 push run 38999847002 已请求取消，保留 PR 验证。
