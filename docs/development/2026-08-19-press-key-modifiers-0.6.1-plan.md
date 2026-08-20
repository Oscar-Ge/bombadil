# Bombadil 0.6.1 PressKey Modifiers Plan

Last updated: 2026-08-20 (America/Denver)

Repository: `/uufs/chpc.utah.edu/common/home/u6076945/bombadil`

Branch: `feature/press-key-modifiers-0.6.1`

Base: Bombadil `v0.6.1` (`e60f8588554f5dd246549becbd931dcf0ab976c1`)

Current status: **Bombadil implementation, review, and in-scope validation are
complete. Read-only review found no Shift+Tab blocker and its two hardening
suggestions have been applied: modified text-producing keys fail explicitly,
and each CDP modifier bit has an independent test. Final Granite job `1831912`
passed the relevant build, Clippy, schema tests, browser tests, and real Chrome
Shift+Tab test. LTL-UI now pins the tested fork commit and the SHA256 of the
binary used by its Shift+Tab campaign instead of accepting a PATH fallback.**

## Decision

Extend `PressKey` with optional, general modifier metadata rather than adding a
special Shift+Tab pseudo-key:

```ts
type KeyModifiers = {
  shift?: boolean;
  alt?: boolean;
  ctrl?: boolean;
  meta?: boolean;
};

type PressKeyAction = {
  PressKey: {
    code: number;
    modifiers?: KeyModifiers;
  };
};
```

The first supported and acceptance-tested modified key is Shift+Tab. The data
model carries all four CDP modifier bits. Modified text-producing keys are
explicitly rejected until their `Char` event semantics are implemented, rather
than being silently executed with incorrect text. This means combinations such
as Shift+A and Ctrl+K remain outside this change.

## Compatibility contract

- A legacy action with no modifiers still parses successfully.
- Empty modifiers serialize exactly as the legacy action:

  ```json
  {"PressKey":{"code":9}}
  ```

- A modified action records modifier identity in traces and replay:

  ```json
  {
    "PressKey": {
      "code": 9,
      "modifiers": {
        "shift": true,
        "alt": false,
        "ctrl": false,
        "meta": false
      }
    }
  }
  ```

- Shift+Tab is dispatched as Tab `RawKeyDown` and `KeyUp` with the CDP Shift
  bit set. Bombadil does not dispatch a separate Shift key event.

## Execution ledger

| Step | Status | Evidence / next action |
| --- | --- | --- |
| 1. Confirm the v0.6.1 action path | Complete | TypeScript → `JsAction` → `BrowserAction` → CDP → trace schema/replay → Inspect verified in source. |
| 2. Create an isolated branch from v0.6.1 | Complete | `feature/press-key-modifiers-0.6.1` created from `e60f858`. |
| 3. Extend the TypeScript and Rust action contracts | Complete | Optional `KeyModifiers` added without changing legacy call sites. |
| 4. Dispatch CDP modifier bits atomically | Complete | Alt=1, Ctrl=2, Meta=4, Shift=8; no standalone modifier key event. |
| 5. Preserve trace/replay compatibility | Complete | Schema defaults, omission of empty modifiers, conversion round-trip tests added. |
| 6. Distinguish modified keys in CLI and Inspect | Complete | Renderers now show names such as `Shift+Tab`. |
| 7. Add a real browser fixture | Complete | Fixture checks backward focus movement, exactly one trusted Tab keydown/keyup pair, and `shiftKey=true`. |
| 8. Static checks | Complete | `cargo fmt --all -- --check` and `git diff --check` pass. |
| 9. Hydrate the Cargo dependency cache | Complete | Locked GitHub and crates.io dependencies are cached at `/scratch/general/vast/u6076945/bombadil-0.6.1-cargo`. Nix/Cachix was not used because CHPC has no Nix executable/module. |
| 10. Select a CHPC compute partition | Complete | Portal selected Granite owner CPU `coe-class-grn`, QOS `coe-class-grn`, account `jiangy`; VAST scratch is healthy at 59% overall use. |
| 11. Run Rust build and clippy | Complete | Final job `1831912`: relevant workspace build and Clippy `--all-targets --fix --allow-dirty -- -D warnings` passed under Rust 1.92; pre/post-Clippy patches are byte-identical. The job reported one rustfmt-only compaction, applied afterward; the working tree now passes `cargo fmt --all -- --check`. |
| 12. Run the Shift+Tab Chromium integration test | Complete | Final job `1831912` ran Chrome 145 on `grn053`; one test passed in 1.61 s and observed the required trusted events and backward focus movement. |
| 13. Review and commit the Bombadil change | Complete | Review found no Shift+Tab blocker. It prompted explicit rejection of unsupported modified printable keys and one-hot bitmask tests. Transport commit: `724a5a8`; headless CLI build support: `d35ecee`. |
| 14. Integrate into LTL-UI | In progress | `feature/shift-tab-action-space-0.6.1` pins this fork and adds reverse-browser qualification. |

## Discovered compute environment

- System Rust/Cargo is available at version 1.92.0; CHPC also provides a
  `rust/1.87.0` module.
- Portal selection: Granite cluster, owner CPU partition `coe-class-grn`, QOS
  `coe-class-grn`, account `jiangy` (41% idle at selection time).
- CHPC provides no Nix or Chromium module.
- A user-owned Puppeteer Chrome binary already exists at
  `/uufs/chpc.utah.edu/common/home/u6076945/.cache/puppeteer/chrome/linux-145.0.7632.77/chrome-linux64/chrome`.
- Chrome has not been executed on the login node. The existing binary will be
  used only inside the allocated compute job.
- No existing Cargo registry/cache was found in the inspected home or VAST
  scratch paths.
- Bombadil's configured Cachix endpoint cannot currently be used because CHPC
  provides no Nix executable or module; no user-space Nix installation will be
  added for this task.
- The v0.6.1 Inspect crate contains an existing call to unstable
  `array_windows` in `lib/bombadil-inspect/src/timeline.rs:162`. Injecting only
  that feature then reaches three additional pre-existing DOM numeric-type
  errors in `list_autoscroll.rs` and `timeline.rs`. The available non-Nix CHPC
  environment therefore cannot provide a clean standalone Inspect check. None
  of those failing files is changed on this branch; the modified renderer was
  also reviewed directly.

## Validation evidence

Final Granite job `1831912` ran on compute node `grn053` with system Rust/Cargo
1.92 and Chrome 145 copied to node-local scratch. Its per-step results were:

| Check | Result |
| --- | --- |
| Relevant workspace build | Pass |
| Relevant workspace Clippy, all targets, warnings denied | Pass |
| Rust formatting | One single-line compaction reported and applied afterward; current working tree passes |
| Inspect standalone check | Non-Nix baseline limitation: existing unstable API and DOM numeric-type errors |
| `bombadil-schema` unit tests | Pass, 4/4 |
| `bombadil-browser` unit tests | Pass, 36/36 |
| Shift+Tab Chromium integration | Pass, 1/1 |

The browser observation after the action was equivalent to:

```json
{
  "activeId": "previous",
  "events": [
    {
      "type": "keydown",
      "key": "Tab",
      "code": "Tab",
      "shiftKey": true,
      "altKey": false,
      "ctrlKey": false,
      "metaKey": false,
      "trusted": true
    },
    {
      "type": "keyup",
      "key": "Tab",
      "code": "Tab",
      "shiftKey": true,
      "altKey": false,
      "ctrlKey": false,
      "metaKey": false,
      "trusted": true
    }
  ]
}
```

The final SLURM job is recorded as `FAILED (1:0)` because its source snapshot
predated the local rustfmt correction and because the harness still aggregated
the independent Inspect baseline/toolchain failure. All modifier-related build,
Clippy, unit, and real-browser acceptance checks passed. The landed job
script now treats that best-effort non-Nix Inspect probe as non-blocking while
retaining its result in the log. Attempts are retained for diagnostic
provenance:

- `1831908`: Cargo sparse/git cache protocol mismatch; no Chrome launch.
- `1831909`: CHPC `rust/1.87.0` module is below Boa's Rust 1.91 MSRV; cancelled
  before Chrome launch.
- `1831910`: core validation and Chrome acceptance passed; aggregate status 1
  due only to the pre-existing Inspect nightly requirement.
- `1831912`: review-hardened code passed build, Clippy, schema 4/4, browser
  36/36, and Chrome 1/1; aggregate status 1 reflects the now-corrected formatting
  snapshot plus unrelated Inspect baseline errors.

## Required compute-node checks

Run these only after `mychpc batch` supplies exact `partition`, `qos`, and
`account` values. The job must specify `--nodes`, `--ntasks`, `--account`, and
`--time`, and must keep Cargo/Nix build output in scratch.

```text
cargo build --workspace --exclude bombadil-inspect
cargo clippy --workspace --exclude bombadil-inspect --fix --allow-dirty
cargo fmt --all -- --check
cargo test -p bombadil-schema --lib
cargo test -p bombadil-browser --lib
cargo test -p bombadil-browser-integration-tests test_shift_tab -- --exact
```

The integration test must prove all of the following:

- the page receives trusted `keydown` and `keyup` events for Tab;
- both events have `shiftKey=true` and all other modifiers false;
- no separate Shift event is observed;
- focus moves from the second control to the first control;
- legacy `{ "PressKey": { "code": 9 } }` traces remain readable;
- ordinary Tab continues to serialize without a `modifiers` field.

## LTL-UI follow-up boundary

The Bombadil branch intentionally does not change LTL-UI. A subsequent LTL-UI
branch must:

1. add Shift+Tab to `tier1_generated_actions.ts`;
2. propagate full keyboard identity through qualification request/receipt and
   evidence artifacts;
3. bump the LTL qualification request schema;
4. keep AP-FM3-01 forward-only initially;
5. allow AP-PS1-01 to observe both directions;
6. keep AP-N2-02's verification action as forward Tab;
7. cover both the canonical `tier1_vertical_validation.ts` entrypoint and the
   GenUI campaign entrypoint `genui_vertical_smoke.ts`;
8. rerun experiments because the action distribution changes.

## Release boundary

The current integration pins the immutable binary SHA256 and source commits
without publishing a package. A later release can package the fork with a
distinguishable version such as `0.6.1-ltl.1`; that packaging step remains
separate from the modifier transport and browser qualification.
