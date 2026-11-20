# Workflow for the APIM developer portal PoC.
# Order: make up-1 -> make smoke -> admin click in the portal -> make up-2. Teardown: make down.
# Portal look: design in admin mode -> make portal-capture -> commit -> make up-2 (in every stage).
# Stages (portal part only): STAGE=dev (default) uses the instance from 'make up-1' and 02-portal/stage1.auto.tfvars;
# STAGE=<name> uses OpenTofu workspace <name> and 02-portal/stages/<name>.tfvars (an existing APIM instance).
# AUTO_APPROVE=1 skips the apply/destroy confirmation (for non-interactive runs).
# Compatible with GNU Make 3.81 (macOS): every recipe is a single shell line.

SHELL := /bin/bash

# .env (if present) is loaded in every recipe so TF_VAR_state_passphrase is set.
LOAD_ENV    := set -e; set -a; if [ -f .env ]; then . ./.env; fi; set +a
TOFU1       := tofu -chdir=01-apim
TOFU2       := tofu -chdir=02-portal
APPROVE     := $(if $(AUTO_APPROVE),-auto-approve,)
STAGE1_VARS := 02-portal/stage1.auto.tfvars

STAGE       ?= dev
IS_DEV      := $(filter dev,$(STAGE))
WORKSPACE   := $(if $(IS_DEV),default,$(STAGE))
STAGE_VARS  := $(if $(IS_DEV),$(STAGE1_VARS),02-portal/stages/$(STAGE).tfvars)
VAR_FILE    := $(if $(IS_DEV),,-var-file=stages/$(STAGE).tfvars)
SELECT_WS   := $(TOFU2) workspace select -or-create $(WORKSPACE) >/dev/null
# Reads a string value from the stage's tfvars file: $(call stage_var,apim_name)
stage_var    = sed -n 's/^$(1)[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' $(STAGE_VARS)
REQUIRE_STAGE := if [ ! -f $(STAGE_VARS) ]; then echo "$(STAGE_VARS) is missing (STAGE=$(STAGE)). See docs/developer-portal.md."; exit 1; fi

.PHONY: check-env up-1 smoke up-2 portal-capture portal-tools-update down down-2 down-1 plan lint

check-env:
	@$(LOAD_ENV); \
	if [ -z "$${TF_VAR_state_passphrase:-}" ] || [ $${#TF_VAR_state_passphrase} -lt 16 ]; then \
	  echo "TF_VAR_state_passphrase is missing or shorter than 16 characters."; exit 1; \
	fi

up-1: check-env
	@$(LOAD_ENV); \
	$(TOFU1) init -input=false; \
	if command -v caffeinate >/dev/null 2>&1; then \
	  caffeinate -i $(TOFU1) apply $(APPROVE); \
	else \
	  $(TOFU1) apply $(APPROVE); \
	fi; \
	{ \
	  echo "resource_group_name  = \"$$($(TOFU1) output -raw resource_group_name)\""; \
	  echo "apim_name            = \"$$($(TOFU1) output -raw apim_name)\""; \
	  echo "developer_portal_url = \"$$($(TOFU1) output -raw developer_portal_url)\""; \
	} > $(STAGE1_VARS); \
	echo "$(STAGE1_VARS) written."

smoke: check-env
	@$(LOAD_ENV); \
	$(TOFU1) init -input=false >/dev/null; \
	export GATEWAY_URL="$$($(TOFU1) output -raw gateway_url)"; \
	export SMOKE_KEY="$$($(TOFU1) output -raw smoke_subscription_key)"; \
	bash scripts/smoke.sh

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
	echo "Review with git diff, commit, then 'make up-2' imports and publishes it."

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

down: down-2 down-1

down-2: check-env
	@$(LOAD_ENV); \
	if [ ! -f $(STAGE_VARS) ]; then \
	  echo "$(STAGE_VARS) is missing, 02-portal was probably never applied for stage $(STAGE). Skipping."; exit 0; \
	fi; \
	$(TOFU2) init -input=false; \
	$(SELECT_WS); \
	$(TOFU2) destroy $(VAR_FILE) $(APPROVE)

down-1: check-env
	@$(LOAD_ENV); \
	$(TOFU2) init -input=false >/dev/null; \
	$(TOFU2) workspace select default >/dev/null; \
	if [ -n "$$($(TOFU2) state list 2>/dev/null)" ]; then \
	  echo "02-portal (stage dev) still has resources. Run 'make down-2' first."; exit 1; \
	fi; \
	$(TOFU1) init -input=false; \
	$(TOFU1) destroy $(APPROVE); \
	rm -f 02-portal/stage1.auto.tfvars

# Drift check: 01-apim (only for STAGE=dev) and 02-portal for the selected stage.
plan: check-env
	@$(LOAD_ENV); \
	$(REQUIRE_STAGE); \
	if [ -n "$(IS_DEV)" ]; then \
	  $(TOFU1) init -input=false >/dev/null; \
	  set +e; $(TOFU1) plan -detailed-exitcode -input=false; rc=$$?; set -e; \
	  if [ $$rc -eq 2 ]; then echo "01-apim: tofu plan reports changes."; exit 1; fi; \
	  if [ $$rc -ne 0 ]; then exit $$rc; fi; \
	fi; \
	$(TOFU2) init -input=false >/dev/null; \
	$(SELECT_WS); \
	set +e; $(TOFU2) plan -detailed-exitcode -input=false $(VAR_FILE); rc=$$?; set -e; \
	if [ $$rc -eq 2 ]; then echo "02-portal ($(STAGE)): tofu plan reports changes."; exit 1; fi; \
	exit $$rc
