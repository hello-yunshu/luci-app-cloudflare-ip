# Publisher fixture rewrite — live OpenWrt 24.10.8

Date: 2026-11-05. Result: **PASS** in a fresh `openwrt/rootfs:x86_64-24.10.8`
container; both fixtures are now wired into CI (`publisher-runtime`).

## Environment

| Item | Value |
|---|---|
| Image | `openwrt/rootfs@sha256:9972a4b4747cd136abd597475d7b88c51a49fd849d0d53f069a2f4bf446061b9` (`x86_64-24.10.8`) |
| Init | `/sbin/init` (procd, netifd, ubusd running) |
| uhttpd | `/usr/sbin/uhttpd` from 24.10.8 base |
| curl | `8.22.0-r1` (current 24.10.8 feed) |
| Test deps | `opkg update && opkg install bash curl jq` |

## Previous diagnosis was wrong

Phase I recorded:

- `publisher-uhttpd-readback.sh` exit 5 `publisher_generation_readback_failed`
  with the claim "uhttpd does not survive init script exit";
- `publisher-procd-rebind.sh` exit 1 `listener not reachable` with the claim
  "procd service not registered".

Re-checking the preserved temp state showed the uhttpd process alive, the procd
service registered and running, and the generation files present. Both fixtures
failed in the readiness check, not in service startup.

## Root cause

Product readiness uses `curl --connect-timeout 1 --max-time 1`. On the shipped
curl 8.22.0-r1 this is rejected before any request:

```
$ curl -fsS --noproxy '*' --max-time 1 http://127.0.0.1:PORT/result.json
curl: (28) remaining timeout of 999 too small to resolve via SIGALRM method
$ echo $?
28

$ curl -fsS --noproxy '*' --max-time 2 http://127.0.0.1:PORT/result.json
{...}          # HTTP 200, 808 bytes
```

`--connect-timeout 1 --max-time 2` fails the same way (the connect timeout is
the trigger), so both limits must be at least 2s. This was reproduced on a
separate clean 24.10.8 container that only installed the package, so it is a
runtime defect, not a test-environment artifact. On a device that has the
current curl feed, `v2.6.0-8` publisher can never become ready.

Fixed in `package/luci-app-cloudflare-ip/root/usr/libexec/cf-ip/publisher.sh`:

| Function | Before | After |
|---|---|---|
| `cfip_publisher_wait_ready` | `--connect-timeout 1 --max-time 1` | `--connect-timeout 2 --max-time 2` |
| `cfip_publisher_endpoint_open` | `--connect-timeout 1 --max-time 1` | `--connect-timeout 2 --max-time 2` |

Tracking entry: issue register P1-06. The fix is on `main` only and is **not**
part of the published `v2.6.0-8` bytes.

## Fixture changes

`tests/publisher-uhttpd-readback.sh`

- keeps the real isolated uhttpd fixture init;
- test-side polling switched to `--connect-timeout 2 --max-time 3`;
- UCI baseline now comes from the package's shipped
  `root/etc/config/cf_ip` instead of the container's `/etc/config/cf_ip`;
- isolates the rill state file under the test temp dir and sets a private
  `CFIP_STATUS_DIR`, so the backend `--publisher-status` validation does not
  depend on container `/etc/cf_ip` permissions.

`tests/publisher-procd-rebind.sh`

- uses the production init script registered by real procd and the real
  uhttpd instance;
- asserts the registered trigger payload (`interface.*`, `eq interface <fixture>`,
  `run_script <fixture> reload`) from `ubus call service list --verbose`;
- invokes that same registered command (`<fixture> reload`) for rebind, loss and
  restoration, and tolerates the production non-zero exit when no LAN bind can
  be resolved;
- readiness probes treat any HTTP status (403/404 from an empty docroot) as
  "listener up" and never mistake a curl timeout for "down";
- documents the remaining limit: synthetic ubus event dispatch
  (`ubus call service event`, `ubus send`) was not delivered to procd in this
  container even for a minimal `/etc/init.d` probe, so delivery itself is not
  claimed; trigger registration plus the executed command are verified.

## Passing output (fresh container)

```
PASS actual isolated uhttpd serves exact published bytes
PASS actual uhttpd serves pinned generation artifacts with matching digests
PASS backend publisher-status loads real isolated UCI enabled state
PASS stopped actual uhttpd fails readiness
uhttpd-rc=0

PASS real procd fixture starts actual HTTP listener
PASS procd registers the production interface trigger for this fixture
PASS trigger reload rebinds owned listener and closes old address
PASS interface loss removes actual listener
PASS interface restoration restarts actual listener through retained trigger
PASS disabled reload removes real owned procd listener
PASS disabled restart does not create a listener
PASS re-enabled reload restores actual listener
procd-rc=0
```

Run twice: `cfip-ui-phasef` (live init container used in phase I) and
`cfip-ci-probe` (fresh image, default bridge network, no privileged mode).

## CI

New job `publisher-runtime` in `.github/workflows/ci.yml`:

1. starts the pinned 24.10.8 image with `/sbin/init`;
2. waits for ubus, installs `bash curl jq`;
3. copies the tree and runs both fixtures plus `tests/opkg-status-recovery.sh`.

`tests/ci-test-inventory.py` no longer excludes them.

## Not covered

- procd event **delivery** on a real device (netifd -> procd -> trigger) is not
  exercised; only registration and the executed reload command are.
- No physical-device run; this evidence is container-only.
