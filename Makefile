.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --no-print-directory

DOTFILES ?= $(CURDIR)
OS := $(shell uname -s)
# KB=personal|work sets up this host's kb; empty (the default) installs none
KB ?=

.PHONY: help install link update verify kb kb-exclude ssh git-maintenance

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Full install: packages, tools, stow, post-stow steps
	@KB=$(KB) $(DOTFILES)/scripts/install.sh

link: ## Restow configs and run the post-stow steps
	@KB=$(KB) $(DOTFILES)/scripts/install.sh --no-packages

update: ## Upgrade system packages, mise, uv, antidote, Claude Code, herdr-core, tldr, Neovim plugins
ifeq ($(OS),Darwin)
	brew update && brew upgrade
else
	sudo apt-get update && sudo apt-get upgrade -y
endif
	mise self-update -y || true
	mise upgrade
	uv self update
	zsh -c 'source $(HOME)/.antidote/antidote.zsh && antidote update'
	claude update || true
	# The Herdr app updates itself and core; only a core-only host needs this
	if [[ $$($(DOTFILES)/scripts/herdr-mode.sh) == core ]] && command -v hc >/dev/null; then hc update || true; fi
	tldr --update
	nvim --headless "+lua vim.pack.update(nil, {force = true})" +qa

verify: ## Run the read-only health check
	@$(DOTFILES)/scripts/verify.sh

kb: ## Set up this host's kb only: KB=personal|work
	@KB=$(KB) $(DOTFILES)/scripts/kb-setup.sh

kb-exclude: ## Keep a repo out of the kb: REPO=<dir>
	@test -n "$(REPO)" || { echo "usage: make kb-exclude REPO=<dir>" >&2; exit 2; }
	@$(DOTFILES)/scripts/kb-exclude.sh "$(REPO)"

ssh: ## Install the GitHub connection sharing config into ~/.ssh
	@$(DOTFILES)/scripts/ssh-setup.sh

git-maintenance: ## Register ~/.kb and this host's repo folders for background git maintenance
	@$(DOTFILES)/scripts/git-maintenance.sh
