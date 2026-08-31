## Summary

Describe what this pull request changes and why.

## Related work

Closes #

## Type of change

- [ ] New script
- [ ] Bug fix
- [ ] Enhancement
- [ ] Security hardening
- [ ] Documentation
- [ ] Tests / CI
- [ ] Breaking change

## PowerShell quality checklist

- [ ] The code is customer-neutral and contains no customer-specific data.
- [ ] No passwords, secrets, access tokens, tenant IDs, private certificate material or confidential information are included.
- [ ] A clearly marked Configuration Block with safe defaults is present where applicable.
- [ ] The script can run without mandatory parameters where safe operation permits it.
- [ ] Optional parameters override corresponding configuration values where applicable.
- [ ] PowerShell 7 compatibility was considered and documented.
- [ ] Functions use approved Verb-SingularNoun naming where applicable.
- [ ] Reusable logic is separated from orchestration.
- [ ] Modifying/destructive operations support ShouldProcess / WhatIf where technically possible.
- [ ] Error handling and logging are appropriate for the risk level.
- [ ] Comment-based help and usage examples are current.
- [ ] A matching `-TEST.ps1` exists or the reason it is not applicable is documented.
- [ ] PowerShell parser checks pass.
- [ ] PSScriptAnalyzer passes without Error/Warning findings or exceptions are justified.
- [ ] Lab/live testing was completed where infrastructure access is required.
- [ ] Documentation was added or updated.
- [ ] `SCRIPT-CATALOG.md` was added/updated for a new or changed published script.
- [ ] `CHANGELOG.md` was updated when appropriate.
- [ ] Compatibility Matrix was reviewed/updated when compatibility changed.

## Test evidence

Describe the environment and tests performed. Do not paste confidential customer information.

```text
PowerShell version:
Operating system:
Modules:
Tests performed:
Result:
```

## Risk and rollback

**Risk:** Low / Medium / High

Describe possible impact and, for modifying changes, the rollback/recovery approach.

## Module candidate review

- [ ] Reusable functions were reviewed as candidates for a shared module.
- [ ] Not applicable.
