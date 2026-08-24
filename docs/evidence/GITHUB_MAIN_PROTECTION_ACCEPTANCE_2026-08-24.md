# GitHub `main` protection acceptance — 2026-08-24

Purpose: non-product governance acceptance after repository owner migration.

This file exists only to create a harmless pull request that verifies the restored `main` protection contract.

Acceptance sequence:

1. Open PR from this branch to `main`.
2. Attempt merge before required `build` completes; GitHub must reject the merge.
3. Wait for required checks to pass.
4. Merge only after the gate is satisfied.
5. Verify the resulting `main` is mirrored to GitVerse with `gitverse-mirror=success`.

No product/runtime behavior is changed by this acceptance record.
