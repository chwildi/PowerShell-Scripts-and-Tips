# Security Policy

## Public repository policy

This is a public repository. Never commit secrets, credentials or confidential customer/environment information.

Before publishing a script, check for:

- Passwords and credentials
- API keys and access tokens
- Tenant IDs and subscription IDs
- Customer or company-specific names
- Internal domains and host names
- IP addresses that should not be public
- E-mail addresses and personal data
- Certificate private keys or secrets
- Connection strings
- Environment-specific file paths
- Exported logs containing sensitive information

Use obvious placeholders such as:

```text
contoso.example
server01.example.local
user@example.com
10.0.0.10
<YOUR-TENANT-ID>
<YOUR-PATH>
```

## Safe execution

Scripts that modify systems should provide clear warnings and, where technically possible, support `-WhatIf`, confirmation or a preview mode.

Always test scripts in a lab or non-production environment before production use.

## Reporting a security issue

Do not open a public issue containing credentials, secrets or sensitive environment information. Contact the repository owner privately when a security issue could expose confidential information.
