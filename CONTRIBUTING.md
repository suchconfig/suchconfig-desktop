# Contributing to SuchConfig

Thanks for helping improve the open-core desktop vault. This repo is the **Community Edition (CE)** surface: Project Vault, Secrets Vault, Trusted Folder, LAN P2P, and Vault Importer.

**Personal Pro** engines (Security Sentinel scanners, Local Broker inject runtime) are **out of scope** for public PRs. Upgrade cards and license-gated UI may land here; engine code does not.

## Before you start

1. Read [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
2. Prefer issues labeled `good first issue` or `help wanted`.
3. Open an issue before large design changes.

## Good first contribution scope

| Welcome | Not accepted in public CE |
| --- | --- |
| Docs clarity, typos, public roadmap accuracy | `sentinel_core` / osv-scanner / grype engines |
| UX polish on free vault flows | Broker inject / CLI runtime internals |
| Tests for free CE paths | Private Hex org wiring, Pro packaging |
| Accessibility, error copy, importer how-tos | Secrets, signing keys, Hindsight / private ops |

## Development setup

See the root [README.md](README.md) quick start. From `phoenix-app/`:

```bash
mix format
mix precommit
```

Do not commit `.env`, signing material, or vault database files.

## Commit style

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add Trusted Folder empty-state copy
fix: handle missing peer during P2P pairing cancel
docs: clarify importer JSON export steps
test: cover secrets vault reveal cancel
```

Keep commits focused. Prefer small PRs.

## Developer Certificate of Origin (DCO)

By contributing, you certify the [Developer Certificate of Origin 1.1](https://developercertificate.org/).

Sign every commit:

```bash
git commit -s -m "docs: fix SECURITY.md link"
```

GitHub’s “Signed-off-by” line must match your commit author. Maintainers may ask you to amend unsigned commits before merge.

## Pull requests

1. Fork and branch from `main`.
2. Include tests or a clear reason why none apply.
3. Link the related issue.
4. Ensure CI is green (Phoenix compile + `vault_core` check).
5. Do not include Pro sidecars, private URLs, or API keys.

Community PRs are reviewed on GitHub. Maintainers may port accepted changes into the private development tree manually.

## Security reports

Do **not** open a public issue for vulnerabilities. Follow [SECURITY.md](SECURITY.md).

## License

Contributions are licensed under [Apache-2.0](LICENSE).
