# APIM Developer Portal PoC

Proof of concept for Azure API Management (Developer tier), built entirely with OpenTofu:

- **Developer portal with Entra ID sign-in**, restricted to accounts of your own tenant, no email/password registration.
- **Customer API with full CRUD** (`/crm/customers`) that APIM maps directly onto Azure Table Storage using policies. There is no backend code.
- **"Self-Service Customer Portal" product**: signed-in developers subscribe and try the API in the portal ("Try it").
- **Portal look as code**: pages, styles and images live as a snapshot in the repo and can be deployed from dev to prod.

> **Status:** PoC, demo data only. See [Security posture](#security-posture).

## Architecture

```text
                     Entra ID (own tenant)
                     App registration + service principal (MSAL-2)
                                  ▲
                                  │ sign-in
Browser ──► Developer portal  https://<apim>.developer.azure-api.net
   │
   └──► Gateway  https://<apim>.azure-api.net/crm/customers   (subscription key, CORS)
              └─ Policies: managed identity ──► Table Storage REST API
                                                └─ Storage account, table "customers"
```

All Azure resources live in the resource group `apim-dev-portal-poc` (swedencentral):

| Resource | Name |
| --- | --- |
| API Management (Developer_1) | `apim-devportal-poc-<suffix>` |
| Storage account | `stdevportal<suffix>` with table `customers` |
| API | `Customers API`, path `/crm` |
| Product | `Self-Service Customer Portal` (no approval, 60 calls/min) |
| Entra app registration | `apim-dev-portal-poc-portal` (lives in the tenant, not in the RG) |

### Repository layout

```text
01-apim/                 Step 1: RG, storage + seed data, APIM, API, policies, product
  api/                   OpenAPI contract of the customer API
  policies/              Policy XML (API scope, per operation, product)
02-portal/               Step 2: Entra app, identity provider, portal content, publishing
  content/               Snapshot of the portal content (data.json + media/)
scripts/                 Smoke test, preflight, publish, portal content capture/apply
tools/portal-content/    Microsoft's portal scripts (vendor/, pinned to a release) + update script
Makefile                 Workflow
```

## Prerequisites

- `az login` with access to the target subscription and permission to create app registrations in the tenant
- OpenTofu 1.13, GNU Make, `curl`, `jq`, `xmllint`
- Node.js 20 or newer (for the portal scripts)
- **Cost:** APIM Developer tier costs about $0.07 per hour (roughly $50 per month) while it exists. Storage costs cents. Run `make down` when you are done.

## Setup

1. Copy `.env.example` to `.env` and set a passphrase for state encryption (at least 16 characters). The `Makefile` loads `.env` automatically. For direct `tofu` calls run `set -a; . ./.env; set +a` first.
2. Copy `01-apim/terraform.tfvars.example` to `01-apim/terraform.tfvars` and fill in `subscription_id` and `publisher_email`.
3. Copy `02-portal/terraform.tfvars.example` to `02-portal/terraform.tfvars` and fill in `subscription_id` and `tenant_id`.

## Deployment

```bash
make up-1     # step 1 (30-60 min, because creating APIM takes that long)
make smoke    # checks the API through the gateway (20 checks)
```

**Manual step, once per new APIM instance:** Azure portal → APIM instance → "Developer portal" → "Developer portal" at the top (opens admin mode). Wait until the page has loaded, then close the tab. Only this makes APIM create the portal content. `make up-2` checks this first and stops with a hint otherwise.

```bash
make up-2     # step 2 (Entra app, identity provider, portal content, publishing)
```

`apply` and `destroy` ask for confirmation. `AUTO_APPROVE=1` (e.g. `make up-1 AUTO_APPROVE=1`) skips it.

**Check in the browser:**
1. Open the portal URL (`tofu -chdir=02-portal output developer_portal_url`) in a private window.
2. "Sign in" → "Azure Active Directory" → sign in with a test user of the tenant.
3. Products → "Self-Service Customer Portal" → Subscribe.
4. APIs → Customers API → pick an operation → "Try it".
5. Negative test: a personal Microsoft account is rejected.

Create the test user in the Entra admin center as a member. Your own account is not suitable: as subscription owner you are a portal admin and don't see what a regular developer sees.

## API

| Operation | Request | Success |
| --- | --- | --- |
| List | `GET /crm/customers` | 200 |
| Get | `GET /crm/customers/{id}` | 200 |
| Create | `POST /crm/customers` with `{"name","email","city?"}` | 201 + `Location` |
| Replace | `PUT /crm/customers/{id}` | 200 |
| Delete | `DELETE /crm/customers/{id}` | 204 |

Seed customers: `c001` to `c005`; `c005` intentionally has no `city`.

```bash
curl -H "Ocp-Apim-Subscription-Key: <key>" "$(tofu -chdir=01-apim output -raw gateway_url)/crm/customers"
```

## Portal look as code

APIM stores the portal's pages, layouts, colors, fonts, navigation and images as "content items" and media blobs. The azurerm provider has no resources for them, so the state lives in the repo as a snapshot:

```text
02-portal/content/data.json   all content items (sorted and indented for readable diffs)
02-portal/content/media/      uploaded images and files (+ .info with the content type)
```

**Workflow:**
1. Design in admin mode (Azure portal → APIM → Developer portal → "Developer portal") and save. **Don't** publish from admin mode; OpenTofu does that.
2. `make portal-capture` exports the instance's state to `02-portal/content/`.
3. Review with `git diff` and commit.
4. `make up-2`: when the snapshot changed, OpenTofu replaces the instance's content and media (`terraform_data.portal_content`) and republishes the portal.

> **Caution:** applying the snapshot **replaces** the instance's portal content, it does not merge. If you edit in the portal and don't run `make portal-capture` first, those edits are lost the next time a changed snapshot is applied.

### Media

An image uploaded in the editor ends up in two places in APIM:

1. A **blob** in the portal's internal media storage, which APIM manages and you don't see as a storage account.
2. A **content item** of type `blob` with metadata (`blobId`, `fileName`, `mimeType`, `permalink`). Pages reference the image by this content item's ID.

The scripts handle both:

| Step | What happens to media |
| --- | --- |
| `make portal-capture` | Gets a SAS URL for the media container (`portalconfigs/default/listMediaContentSecrets`) and downloads every blob to `media/<blobId>`, plus `<blobId>.info` with the content type. The content item goes into `data.json`. `media/` is wiped first, so images deleted in the portal disappear from the snapshot too. |
| `make up-2` (apply) | `cleanup.js` deletes **all** content items and **all** blobs in the target. `generate.js` recreates the content items, then uploads every file from `media/` under the same blob key. IDs are identical, so all references stay valid. |
| Publish | The published portal serves the image under its `permalink` (`https://<portal>/content/<fileName>`). |

Notes:
- The portal's default images are not in `media/`. They are loaded from Microsoft's public storage (`apimdeveloperportal.z22.web.core.windows.net`).
- Media files are binary and stored in git as they are. That is fine for a few images. For many or large files (videos, big PDFs), use Git LFS for `02-portal/content/media/**`.
- Captured snapshots work in any instance, so there is nothing instance-specific about media either.

### Multiple stages (dev → prod)

Design only in dev. Whatever is in the snapshot gets deployed: `make up-2` against prod imports the same snapshot there. The snapshot contains no instance-specific values such as host names or client IDs. The Entra app, identity provider and sign-up setting are not content; OpenTofu creates them per stage. Users and subscriptions are not part of the snapshot either. This matches Microsoft's guidance in [Automate developer portal deployments](https://learn.microsoft.com/azure/api-management/automate-portal-deployments). This repo currently has a single stage.

### Microsoft's scripts and updates

Capture and import use Microsoft's official scripts `capture.js`, `cleanup.js` and `generate.js` from [`Azure/api-management-developer-portal`](https://github.com/Azure/api-management-developer-portal) (`scripts.v3`, MIT license). They are vendored, pinned to a release, in `tools/portal-content/vendor/`:

- `vendor/UPSTREAM` records release tag and commit, `vendor/LICENSE` is Microsoft's license.
- Only the four required files are copied, not the whole repo (portal source, build, hundreds of packages).
- `package.json` and `package-lock.json` pin the npm dependencies to exact versions. `scripts/portal-content.sh` runs `npm ci` when needed.

Why not clone at runtime or use a submodule: cloning on every run depends on whatever is on Microsoft's default branch, and an upstream change can alter the workflow without warning. The scripts have been rewritten before (v2 → v3). A submodule pulls the entire repo and needs `git submodule update` on every clone. The vendored copy is small and reviewable, and it only changes through a deliberate commit.

**Updating (started manually):**

```bash
make portal-tools-update             # latest release
make portal-tools-update REF=2.36.0  # specific release
git diff tools/portal-content        # review the script changes
make portal-capture                  # test against dev; data.json must not change unexpectedly
```

The update script also prints the package versions Microsoft declares for `@azure/storage-blob` and `mime`. If they differ, adjust `package.json` and run `npm install` in `tools/portal-content`.

## Design decisions

- **Developer tier:** the cheapest tier with a developer portal. Consumption has no portal, Basic v2 costs more.
- **No backend code:** the policies translate the REST calls into Table Storage REST API calls. APIM authenticates with its system managed identity (role *Storage Table Data Contributor*). For a demo API this is enough; no Function App, no code deployment.
- **Hardened policies:**
  - `validate-parameters` only allows `A-Z a-z 0-9 -` in the `id`, so no OData injection via quotes or parentheses.
  - `validate-content` rejects unknown fields and bodies over 4 KB.
  - `PartitionKey` and `RowKey` are always set by the policy, never by the client.
  - `copy-unmatched-params="false"` stops clients from passing `$filter` or `$top` to storage.
  - `If-Match: *` makes PUT and DELETE on an unknown `id` return 404 instead of creating a customer.
  - APIM does not forward the subscription key to storage.
- **Two roots instead of one:** after APIM is created, the developer portal needs the manual admin click once. Without it the portal has no content and step 2 has nothing to publish. The roots exchange only three values, via a generated `02-portal/stage1.auto.tfvars`. There is no `terraform_remote_state`, because step 2 would otherwise have to configure step 1's state encryption as well.
- **Local, encrypted state:** OpenTofu native state encryption (pbkdf2 + AES-GCM, enforced for state and plan). The passphrase comes from `TF_VAR_state_passphrase`.
- **Publishing via script:** `terraform_data` + `local-exec` calls the management API (`portalRevisions`) and waits until publishing has completed. It republishes only when the client ID, secret ID, tenant or portal snapshot change.
- **Secret rotation without drift:** the client secret's expiry comes from `time_offset` instead of `timestamp()`.

## Known quirks

- The admin click is required: before it, the API returns 0 portal pages, after it 16.
- After `up-1`, the first calls may return **403** for a few minutes because the role assignment is not effective yet. `make smoke` retries automatically.
- Applying `01-apim` resets **only the five seed customers**. Customers created through the API stay. A seed customer changed through the API shows up as a change in `make plan`.
- The first Entra sign-in attempt may fail with `timed_out` (MSAL); a second attempt works.
- CORS allows all request headers, because depending on its settings the test console also sends `Ocp-Apim-Trace` or `Cache-Control`. With a fixed header list, "Try it" fails with a CORS error. The `cors` policy at API scope answers the preflight without a dedicated OPTIONS operation.
- Sign-up is off (`sign_up` in `01-apim/apim.tf`; azurerm 4.x has no separate resource for it).
- The smoke subscription pins `allow_tracing = false`, because Azure turns tracing off on subscriptions by itself; otherwise every plan reports drift.
- The list returns at most 1000 items. Errors (404, 409) are passed through unchanged in Table Storage's OData format.
- APIM creates the Starter and Unlimited products automatically. `developers` is an APIM group, not an Entra group.

## Operations

- **Check for drift:** `make plan` fails as soon as either root reports changes.
- **Static checks:** `make lint` (fmt, validate, XML, shell syntax, snapshot JSON). Needs no Azure access.
- **Rotate the secret:** `tofu -chdir=02-portal apply -replace=time_offset.secret_expiry`. The new expiry forces a new secret, and the portal is republished automatically. `tofu -chdir=02-portal output secret_expires_at` shows the current expiry.
- **Republish the portal manually:** `tofu -chdir=02-portal apply -replace=terraform_data.portal_publish`.
- **Troubleshooting:** Azure portal → APIM → APIs → Customers API → operation → "Test" tab → "Trace".

## Teardown

```bash
make down     # first 02-portal (Entra objects), then 01-apim (RG incl. APIM, purged)
```

**Recovery:**
- **Passphrase lost:** the states can no longer be read. Delete the resource group `apim-dev-portal-poc` and the app registration `apim-dev-portal-poc-portal` manually.
- **01 torn down before 02 by mistake:** run `tofu -chdir=02-portal state rm <address>` for every address from `tofu -chdir=02-portal state list`, then delete the app registration manually.

## Security posture

- Demo data only: anyone with a subscription key can read, change and delete all customers.
- The storage account is publicly reachable and has shared key access enabled, because seeding via azurerm needs it.
- The client secret is stored in the encrypted state and in the APIM identity provider configuration.

## Possible extensions

- Additionally protect the API with Entra tokens (`validate-jwt` at API scope, a second app registration, OAuth in the test console). Product, group and operations stay unchanged.
- Multiple stages: separate tfvars and state per stage, shared code and portal snapshot.
- Application Insights with a daily cap, budget alert on the resource group.
- Paged list via Table Storage continuation headers.
