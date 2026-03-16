# Security Policy

## Supported versions

The latest version on the default branch is the supported version.

## Reporting a vulnerability

Please report suspected vulnerabilities privately before public disclosure.

Include:

- a description of the issue
- reproduction steps
- affected Salesforce edition or context if known
- screenshots or logs if relevant

## Security design notes

SafeDelete Explorer is designed to avoid unnecessary data persistence. It does not require custom objects, external APIs, or outbound callouts.

Current safeguards include:

- inherited sharing in Apex
- describe-based visibility checks before querying child objects
- preview-first UX with delete execution hidden by default
- no hard dependency on org-specific schema customizations

## Safe deployment guidance

Review the permission set before assigning it broadly. Place the component on pages intentionally, and leave the delete action disabled unless your governance model explicitly allows it.
