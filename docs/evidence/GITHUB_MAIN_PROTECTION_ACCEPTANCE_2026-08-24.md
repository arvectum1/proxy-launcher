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

A normal merge was attempted before the required `build` check completed. GitHub rejected the merge twice during the acceptance sequence with HTTP `405 Repository rule violations found`: once while `build` was `in progress`, and again while the final PR head had `build` `queued`.

Result: **PASS** — required status check `build` is actively enforced by repository rules and cannot be bypassed by the normal merge operation used by the connected admin identity.

## Positive completion

- Final PR #3 head: `56cfecf27c384591caae32bab53d343d9e6b9085`.
- All eight final PR workflows completed successfully, including required `build`, SAST, Secret scan, SBOM, APL-IP-001 provenance, dependency vulnerability scan, Windows Russian-first Production Signing, and full Windows installer lifecycle/Gate R6 acceptance.
- Only after the required `build` became successful, the same normal merge operation was accepted by GitHub.
- PR #3 merged as canonical `main` commit `adc917e905acca1f8e97d560a3363b07adc279fb`.
- GitHub branch API continues to report `main.protected=true` on that merged state.
- The exact merged SHA `adc917e905acca1f8e97d560a3363b07adc279fb` received commit status `gitverse-mirror=success` from mirror workflow run `32771027411`.

Final result: **PASS / OWNER-MIGRATION REPOSITORY GOVERNANCE CLOSED**.

No product/runtime behavior is changed by this acceptance record.
