# Developer portal as code for Azure API Management.
#
# Portal (main use case, any existing APIM instance):
#   make up-2 STAGE=<stage>            deploy Entra sign-in + portal content to the stage's instance
#   make portal-capture STAGE=dev      export the portal content of dev into 02-portal/content/
#   make plan STAGE=<stage>            drift check of the portal part
#   make down-2 STAGE=<stage>          remove the portal part (Entra app, identity provider)
# Each stage is described by 02-portal/stages/<stage>.tfvars; STAGE defaults to dev.
#
# Optional demo APIM instance (docs/demo-apim.md):
#   make up-1 / smoke / plan-apim / down
#
# AUTO_APPROVE=1 skips the apply/destroy confirmation (for non-interactive runs).
# Compatible with GNU Make 3.81 (macOS): every recipe is a single shell line.

SHELL := /bin/bash

# .env (if present) is loaded in every recipe so TF_VAR_state_passphrase is set.
LOAD_ENV   := set -e; set -a; if [ -f .env ]; then . ./.env; fi; set +a
TOFU1      := tofu -chdir=01-apim
TOFU2      := tofu -chdir=02-portal
APPROVE    := $(if $(AUTO_APPROVE),-auto-approve,)

STAGE      ?= dev
# dev uses the "default" workspace (state created before stages existed); other stages get their own.
WORKSPACE  := $(if $(filter dev,$(STAGE)),default,$(STAGE))
STAGE_VARS := 02-portal/stages/$(STAGE).tfvars
VAR_FILE   := -var-file=stages/$(STAGE).tfvars
SELECT_WS  := $(TOFU2) workspace select -or-create $(WORKSPACE) >/dev/null
# Reads a string value from the stage file: $(call stage_var,apim_name)
stage_var   = sed -n 's/^$(1)[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' $(STAGE_VARS)
REQUIRE_STAGE := if [ ! -f $(STAGE_VARS) ]; then echo "$(STAGE_VARS) is missing. Copy 02-portal/stages/example.tfvars.example and fill it in."; exit 1; fi

.PHONY: check-env up-2 portal-capture plan down-2 portal-tools-update lint up-1 smoke plan-apim down down-1

check-env:
	@$(LOAD_ENV); \
	if [ -z "$${TF_VAR_state_passphrase:-}" ] || [ $${#TF_VAR_state_passphrase} -lt 16 ]; then \
	  echo "TF_VAR_state_passphrase is missing or shorter than 16 characters."; exit 1; \
	fi

# ---------- Developer portal ----------

up-2: check-env
	@$(LOAD_ENV); \
	$(REQUIRE_STAGE); \
	$(TOFU2) init -input=false; \
	$(SELECT_WS); \
	echo "02-portal: stage $(STAGE) (workspace $(WORKSPACE))"; \
	$(TOFU2) apply $(VAR_FILE) $(APPROVE)

# Exports pages, styles, navigation and media of the stage's instance (normally dev) to 02-portal/content/.
portal-capture: check-env
	@$(LOAD_ENV); \
	$(REQUIRE_STAGE); \
	rg="$$($(call stage_var,resource_group_name))"; name="$$($(call stage_var,apim_name))"; \
	echo "Capturing portal content from $$name (stage $(STAGE)) ..."; \
	id="$$(az apim show -g "$$rg" -n "$$name" --query id -o tsv)"; \
	bash scripts/portal-content.sh capture "$$id" 02-portal/content; \
	echo "Review with git diff, commit, then 'make up-2 STAGE=<stage>' imports and publishes it."

plan: check-env
	@$(LOAD_ENV); \
	$(REQUIRE_STAGE); \
	$(TOFU2) init -input=false >/dev/null; \
	$(SELECT_WS); \
	set +e; $(TOFU2) plan -detailed-exitcode -input=false $(VAR_FILE); rc=$$?; set -e; \
	if [ $$rc -eq 2 ]; then echo "02-portal ($(STAGE)): tofu plan reports changes."; exit 1; fi; \
	exit $$rc

down-2: check-env
	@$(LOAD_ENV); \
	if [ ! -f $(STAGE_VARS) ]; then echo "$(STAGE_VARS) is missing, nothing to tear down for stage $(STAGE)."; exit 0; fi; \
	$(TOFU2) init -input=false; \
	$(SELECT_WS); \
	$(TOFU2) destroy $(VAR_FILE) $(APPROVE)

# Re-fetches Microsoft's portal scripts (default: latest release, or REF=<tag>). Review the diff afterwards.
portal-tools-update:
	@bash tools/portal-content/update.sh $(REF)

# Static checks without Azure access and without the passphrase.
lint:
	@set -e; \
	tofu fmt -check -recursive -diff; \
	for root in 01-apim 02-portal; do \
	  tofu -chdir=$$root init -backend=false -input=false >/dev/null; \
	  tofu -chdir=$$root validate -no-color; \
	done; \
	for f in 01-apim/policies/*.xml 01-apim/policies/*.tftpl; do xmllint --noout "$$f"; done; \
	for f in scripts/*.sh tools/portal-content/update.sh; do bash -n "$$f"; done; \
	if command -v shellcheck >/dev/null 2>&1; then shellcheck scripts/*.sh tools/portal-content/update.sh; fi; \
	jq empty 02-portal/content/data.json; \
	echo "lint: all good."

# ---------- Optional demo APIM instance (docs/demo-apim.md) ----------

up-1: check-env
	@$(LOAD_ENV); \
	$(TOFU1) init -input=false; \
	if command -v caffeinate >/dev/null 2>&1; then \
	  caffeinate -i $(TOFU1) apply $(APPROVE); \
	else \
	  $(TOFU1) apply $(APPROVE); \
	fi; \
	mkdir -p 02-portal/stages; \
	{ \
	  echo "# Written by 'make up-1' (demo instance)."; \
	  echo "resource_group_name  = \"$$($(TOFU1) output -raw resource_group_name)\""; \
	  echo "apim_name            = \"$$($(TOFU1) output -raw apim_name)\""; \
	  echo "developer_portal_url = \"$$($(TOFU1) output -raw developer_portal_url)\""; \
	} > 02-portal/stages/dev.tfvars; \
	echo "02-portal/stages/dev.tfvars written."

smoke: check-env
	@$(LOAD_ENV); \
	$(TOFU1) init -input=false >/dev/null; \
	export GATEWAY_URL="$$($(TOFU1) output -raw gateway_url)"; \
	export SMOKE_KEY="$$($(TOFU1) output -raw smoke_subscription_key)"; \
	bash scripts/smoke.sh

plan-apim: check-env
	@$(LOAD_ENV); \
	$(TOFU1) init -input=false >/dev/null; \
	set +e; $(TOFU1) plan -detailed-exitcode -input=false; rc=$$?; set -e; \
	if [ $$rc -eq 2 ]; then echo "01-apim: tofu plan reports changes."; exit 1; fi; \
	exit $$rc

down:
	@$(MAKE) --no-print-directory down-2 STAGE=dev
	@$(MAKE) --no-print-directory down-1

down-1: check-env
	@$(LOAD_ENV); \
	$(TOFU2) init -input=false >/dev/null; \
	$(TOFU2) workspace select default >/dev/null; \
	if [ -n "$$($(TOFU2) state list 2>/dev/null)" ]; then \
	  echo "02-portal (stage dev) still has resources. Run 'make down-2 STAGE=dev' first."; exit 1; \
	fi; \
	$(TOFU1) init -input=false; \
	$(TOFU1) destroy $(APPROVE); \
	rm -f 02-portal/stages/dev.tfvars
