# Workflow for the APIM developer portal PoC.
# Order: make up-1 -> make smoke -> admin click in the portal -> make up-2. Teardown: make down.
# Portal look: design in admin mode -> make portal-capture -> commit -> make up-2 (in every stage).
# AUTO_APPROVE=1 skips the apply/destroy confirmation (for non-interactive runs).
# Compatible with GNU Make 3.81 (macOS): every recipe is a single shell line.

SHELL := /bin/bash

# .env (if present) is loaded in every recipe so TF_VAR_state_passphrase is set.
LOAD_ENV    := set -e; set -a; if [ -f .env ]; then . ./.env; fi; set +a
TOFU1       := tofu -chdir=01-apim
TOFU2       := tofu -chdir=02-portal
APPROVE     := $(if $(AUTO_APPROVE),-auto-approve,)
STAGE1_VARS := 02-portal/stage1.auto.tfvars

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
	if [ ! -f $(STAGE1_VARS) ]; then \
	  echo "$(STAGE1_VARS) is missing. Run 'make up-1' first."; exit 1; \
	fi; \
	$(TOFU2) init -input=false; \
	$(TOFU2) apply $(APPROVE)

# Exports pages, styles, navigation and media of the current instance to 02-portal/content/.
portal-capture: check-env
	@$(LOAD_ENV); \
	$(TOFU1) init -input=false >/dev/null; \
	id="$$(az apim show -g "$$($(TOFU1) output -raw resource_group_name)" -n "$$($(TOFU1) output -raw apim_name)" --query id -o tsv)"; \
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
	if [ ! -f $(STAGE1_VARS) ]; then \
	  echo "$(STAGE1_VARS) is missing, 02-portal was probably never applied. Skipping."; exit 0; \
	fi; \
	$(TOFU2) init -input=false; \
	$(TOFU2) destroy $(APPROVE)

down-1: check-env
	@$(LOAD_ENV); \
	$(TOFU2) init -input=false >/dev/null; \
	if [ -n "$$($(TOFU2) state list 2>/dev/null)" ]; then \
	  echo "02-portal still has resources. Run 'make down-2' first."; exit 1; \
	fi; \
	$(TOFU1) init -input=false; \
	$(TOFU1) destroy $(APPROVE); \
	rm -f 02-portal/stage1.auto.tfvars

plan: check-env
	@$(LOAD_ENV); \
	for root in 01-apim 02-portal; do \
	  tofu -chdir=$$root init -input=false >/dev/null; \
	  set +e; \
	  tofu -chdir=$$root plan -detailed-exitcode -input=false; \
	  rc=$$?; \
	  set -e; \
	  if [ $$rc -eq 2 ]; then echo "$$root: tofu plan reports changes."; exit 1; fi; \
	  if [ $$rc -ne 0 ]; then exit $$rc; fi; \
	done
