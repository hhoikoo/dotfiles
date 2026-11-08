.DEFAULT_GOAL := help
SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
MAKEFLAGS += --no-print-directory

DOTFILES ?= $(CURDIR)
OS := $(shell uname -s)

.PHONY: help install link update verify

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-8s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

install: ## Full install: packages, tools, stow, post-stow steps
	@$(DOTFILES)/scripts/install.sh

link: ## Restow configs and run the post-stow steps
	@$(DOTFILES)/scripts/install.sh --no-packages

update: ## Upgrade system packages, mise, uv, antidote, Claude Code, tldr, Neovim plugins
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
	tldr --update
	nvim --headless "+lua vim.pack.update(nil, {force = true})" +qa

verify: ## Run the read-only health check
	@$(DOTFILES)/scripts/verify.sh
