# Contributing

Thank you for your interest in improving SafeDelete Explorer.

## Ground rules

- Keep the app **portable across orgs**.
- Avoid introducing custom objects unless there is a strong, documented reason.
- Prefer metadata-driven behavior over org-specific hard-coding.
- Preserve the public author credit in docs and UI.
- Keep delete execution conservative and opt-in.

## Development workflow

1. Create a feature branch.
2. Make focused changes.
3. Add or update Apex tests as needed.
4. Validate in a scratch org or sandbox.
5. Open a pull request with a clear description, screenshots if UI changes are involved, and deployment notes.

## Pull request checklist

- [ ] The change is backwards-compatible for existing metadata deployment
- [ ] Apex tests pass
- [ ] UI still works on a dark background and in standard Lightning containers
- [ ] README or setup docs are updated if behavior changed
- [ ] Security or permission implications are called out explicitly

## Commit style

Prefer concise, intention-revealing commit messages, for example:

- `feat: add relationship risk scoring`
- `fix: skip non-queryable child objects`
- `docs: clarify utility bar deployment`

## Questions

Use GitHub Issues for bug reports, enhancement requests, and portability concerns.
