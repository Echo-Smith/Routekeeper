## Summary

Explain the behavior changed and why.

## Scope

- [ ] Bug fix
- [ ] Safety, privacy or credential boundary
- [ ] Network or sandbox behavior
- [ ] Accessibility
- [ ] Documentation or release process
- [ ] Internal maintainability only

## Impact and risks

Describe affected users, permissions, local files, network access and failure
behavior. For isolation or credential changes, state the threat boundary and
the fail-closed path.

## Verification

List the commands run and the actual result. Include skipped environment-gated
tests and explain why they were not run.

```sh
git diff --check
swift test --disable-sandbox --scratch-path /tmp/routekeeper-build
```

## Checklist

- [ ] The change is focused and does not include unrelated cleanup.
- [ ] Tests cover successful, rejected, cancelled and malformed-input paths where relevant.
- [ ] No credential, cookie, token, real IP address, personal path or unredacted report is included.
- [ ] No signing profile, provisioning profile, private key or local build cache is included.
- [ ] User-visible behavior and limitations match README, help and privacy/security documentation.
- [ ] The change does not move an existing release tag or silently alter a published release asset.
- [ ] UI changes were checked in Chinese and English at supported window sizes.
- [ ] Third-party code, data or assets and their licenses are identified.

## Visual evidence

Add sanitized screenshots or recordings for UI changes, or write `N/A`.
