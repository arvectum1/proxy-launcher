# GitHub `main` protection recovery after owner migration

Date: 2026-08-24
Repository: `arvectum1/proxy-launcher`
Branch: `main`

## Observed post-migration state

The GitHub branch API reports:

- `protected: false`;
- `protection.enabled: false`;
- required status-check enforcement: `off`;
- required status contexts/checks: empty.

This is a real governance regression from the pre-migration protected-main contract. The fact that roadmap PR #1 could be merged while its Actions checks were still queued is consistent with this state.

## Required restored contract

Restore the following effective policy for `main`:

1. changes reach `main` through a pull request;
2. approvals required: 0 (review is optional unless separately requested; PR boundary itself remains mandatory);
3. required status check: `build`;
4. require the branch to be up to date before merging (`strict` status checks);
5. require conversation resolution before merging;
6. do not allow force pushes;
7. do not allow branch deletion;
8. apply the protection to administrators / do not permit an administrator bypass that silently defeats the gate during normal project operation.

Do not add unrelated rules such as signed-commit requirements or linear history unless a separate governance decision explicitly introduces them.

## Minimal GitHub UI path

Repository **Settings -> Branches** (or **Settings -> Rules -> Rulesets**, if GitHub presents the newer ruleset UI) -> protect target branch `main` with the contract above.

## Verification evidence

After saving the rule, verify via the GitHub branch API that:

- `protected` is `true`;
- protection is enabled;
- required status checks include `build` with strict/up-to-date enforcement;
- force-push/delete are not allowed;
- PR/conversation/admin enforcement matches the restored contract.

Then perform a negative acceptance check: open a harmless documentation PR and attempt to merge it while `build` is still queued. GitHub must reject the merge. Only after `build` succeeds should merge become available.

## Automation boundary

The ChatGPT GitHub connector available during this recovery can read the branch-protection state and mutate repository contents/PRs, but it does not expose the GitHub branch-protection/ruleset administration mutation. No suitable GitHub-administration plugin or existing admin-token workflow was available. Therefore the settings save itself is an explicit repository-owner/admin boundary; it must not be falsely recorded as automated PASS.
