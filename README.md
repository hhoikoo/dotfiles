# dotfiles

Personal configuration for macOS and Ubuntu, managed with GNU Stow. Agents: see [AGENTS.md](AGENTS.md).

## First install

```sh
curl -fsSL https://raw.githubusercontent.com/hhoikoo/dotfiles/main/scripts/bootstrap.sh | bash
```

## Afterwards

Run `make` in `~/.dotfiles`.

| Target | Does |
|---|---|
| `make help` | list the targets |
| `make install` | full install: packages, tools, stow, post-stow steps |
| `make link` | restow configs and run the post-stow steps |
| `make update` | upgrade system packages, mise, uv, antidote, Claude Code, tldr, Neovim plugins |
| `make verify` | read-only health check |

## Environment

- `GIT_NAME`, `GIT_EMAIL`: git identity, skips the prompt
- `GIT_SIGN=1`: enable SSH commit signing
- `DOTFILES`: repo location (default `~/.dotfiles`)
- `DOTFILES_REF`: branch or tag that bootstrap clones (default `main`)

## License

Apache-2.0, see [LICENSE](LICENSE).
