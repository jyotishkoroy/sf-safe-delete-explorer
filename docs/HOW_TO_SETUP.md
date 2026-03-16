# How to Set Up SafeDelete Explorer

This guide assumes a standard Salesforce DX workflow.

## Prerequisites

- Salesforce CLI (`sf`)
- a target org you can deploy metadata to
- permission to assign permission sets and edit Lightning pages

## 1. Clone the repository

```bash
git clone https://github.com/<your-account>/safe-delete-explorer.git
cd safe-delete-explorer
```

## 2. Authenticate to your org

```bash
sf org login web --alias my-org
```

## 3. Deploy the metadata

```bash
sf project deploy start --target-org my-org --source-dir force-app
```

Alternative using the package manifest:

```bash
sf project deploy start --target-org my-org --manifest manifest/package.xml
```

## 4. Run Apex tests

```bash
sf apex run test --target-org my-org --test-level RunLocalTests --result-format human
```

## 5. Assign the permission set

```bash
sf org assign permset --target-org my-org --name SafeDeleteExplorerUser
```

## 6. Add the component to a record page

1. Open **Lightning App Builder**.
2. Edit a record page for a supported object.
3. Drag **Safe Delete Explorer** onto the page.
4. Save and activate the page.

Recommended property values:

- **Show Delete Action**: `false` for preview-only deployments
- **Maximum Count Queries**: `70`
- **Show Zero-Count Rows**: `false`

## 7. Optional: add it to the utility bar

1. Open **App Manager**.
2. Edit the target Lightning app.
3. Add **Safe Delete Explorer** as a utility item.
4. Save.

In utility bar mode, the user can paste a record ID when there is no record-page context.

## 8. Optional: tune Custom Metadata rules

The `SafeDeleteRule__mdt` Custom Metadata type allows you to:

- exclude noisy child objects
- force high-risk badges for specific child objects
- override the displayed category text

## What is intentionally not required

- no custom objects
- no flows
- no Python, Java, C++, or C runtime
- no callouts or named credentials
- no post-install scripts

## Troubleshooting

### The component loads but shows fewer relationships than expected

Check:

- running-user object access
- child object queryability in that org
- the configured maximum count query budget
- custom metadata rules that may be excluding child objects

### The delete button is hidden

That is the default behavior. Enable **Show Delete Action** in Lightning App Builder only if your admins want in-component delete execution.
