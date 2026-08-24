# GitHub `main` protection acceptance — 2026-08-24

Purpose: non-product governance acceptance after repository owner migration.

This file records verification of the restored `main` protection contract.

## Observed state after owner/admin restoration

- canonical repository: `arvectum1/proxy-launcher`;
- canonical branch: `main`;
- baseline canonical SHA before this acceptance PR: `c888690928d61e03532de2a023d7870af52354e8`;
- GitHub branch API reports `protected=true` for `main`;
- authenticated GitHub identity `arvectum1` has repository permission `admin`;
- available ChatGPT GitHub connector surface does not expose repository-ruleset or branch-protection mutation actions, and its generic fetch action rejects `/rules/...` endpoints. This is a connector action-whitelist limitation, not a lack of GitHub admin permission.

## Negative merge test

PR: `#3 test(governance): verify restored main protection`

PR head at the negative test: `252caeaec601422de1d32d6c7620cfea4d6ea152`.

An immediate merge was attempted while the required `build` check was still running. GitHub rejected the merge with HTTP `405` and the rule violation:

`Required status check "build" is in progress.`

Result: **PASS** — required status check `build` is actively enforced by repository rules and cannot be bypassed by the normal merge operation used by the connected admin identity.

## Completion sequence

1. Keep PR #3 open until its current required checks complete successfully.
2. Merge only after the repository rule permits the merge.
3. Verify resulting canonical `main` receives `gitverse-mirror=success`.
4. Record the resulting merged SHA in the final task report.

No product/runtime behavior is changed by this acceptance record.
