# APK ownership admission and failed installations

Actual apk-tools can return an ownership error after registering the candidate and extracting its other files. Run 39628261369 attempt 1 shows this with a real foreign package owning `/usr/bin/cf-ip-auto`: the foreign file remains, but the candidate appears in the installed DB and many other candidate paths are created. A nonzero `apk add` exit is not an unchanged-system guarantee. Do not force overwrite or interpret this as a successful install.

`scripts/apk-ownership-preflight.py` is read-only Python tooling for an available target root and an actual APK metadata reader. Before adding a candidate to that root, run:

```sh
python3 scripts/apk-ownership-preflight.py candidate.apk --root /path/to/root --apk-bin /path/to/apk
```

Exit 0 admits the observed ownership state; exit 65 refuses or cannot establish it. Only then proceed with the corresponding package-manager install. The tool reads the actual candidate's complete payload metadata and installed APK ownership records. It permits the same base package's existing paths, rejects any other owner, malformed/missing DB, unsafe paths, duplicate ownership and symlinked parent directories, and binds package/DB digests. A detected in-process change refuses admission. It never modifies the target DB or payload. This is offline/developer tooling; Python is not added as a router package dependency.

This preflight does not wrap or change raw APK behavior, acquire a package-manager transaction lock, guarantee against concurrent changes after inspection, recover interrupted installs, or prove online hooks. It does not replace digest/source qualification. Existing source/byte/version/preflight gates still apply. A failed raw install requires examination of the installed DB, payload and user preimages before recovery; blindly deleting the package or restoring a full old filesystem could destroy unrelated user changes.

Migration evidence separates guarded admission (original root) from actual raw-manager failure (a private root copy). It retains raw manager exit, installed DB and payload, including any partial installation, without treating those as unchanged-system evidence. Full interrupted-install/recovery and online lifecycle acceptance remain OPEN.

A separate controlled initial-install recovery case now exercises actual native APK: after the foreign-owner collision, `apk del --no-scripts luci-app-cloudflare-ip` removes the partial candidate while retaining the original foreign file, user payload and prior package set. All original file hashes/modes/sizes and the checksum-pinned world match afterward, with no additional regular payload files apart from the manager diagnostic log. This fixture starts with no installed base candidate and no concurrent edits. It is not a general recovery command for failed upgrades; inspect the preimages and partial ownership before taking action. The migration matrix retains both pre-recovery failure evidence and post-recovery checks, and qualification explicitly labels this as initial-install recovery.
