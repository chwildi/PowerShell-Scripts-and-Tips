# PowerShell Coding Standards

## General rules

- Use approved PowerShell verbs where practical.
- Use descriptive function, parameter and variable names.
- Use `[CmdletBinding()]` for advanced scripts and functions.
- Use `Set-StrictMode -Version Latest` for new scripts where compatible.
- Use structured error handling with `try`, `catch` and `finally` when appropriate.
- Avoid hard-coded customer, tenant, domain, host, IP and path values.
- Never store passwords, tokens, private keys or other secrets in source code.
- Document prerequisites, required modules and tested PowerShell versions.
- Add comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` and `.NOTES`.
- For modifying operations, implement `SupportsShouldProcess` / `-WhatIf` where technically possible.
- Prefer UTF-8 text files and consistent formatting.

## Before publishing

Run syntax validation, PSScriptAnalyzer where possible, test in a non-production environment and perform a final privacy/security review.
