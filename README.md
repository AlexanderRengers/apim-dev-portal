# APIM Developer Portal PoC

Proof of Concept für Azure API Management (Developer-Stufe), komplett mit OpenTofu aufgebaut:

- **Developer Portal mit Anmeldung über Entra ID**, nur Konten aus dem eigenen Tenant, ohne Registrierung per E-Mail und Passwort.
- **Kunden-API mit vollem CRUD** (`/crm/customers`), die APIM per Policy direkt auf Azure Table Storage abbildet. Es gibt keinen Backend-Code.
- **Produkt „Self-Service Customer Portal“**: Angemeldete Entwickler abonnieren es und probieren die API im Portal mit „Try it“ aus.
- **Portal-Aussehen als Code**: Seiten, Styles und Bilder liegen als Snapshot im Repo und lassen sich von dev nach prod deployen.

> **Status:** PoC, nur für Demo-Daten. Siehe [Sicherheitsstand](#sicherheitsstand).

## Architektur

```text
                     Entra ID (eigener Tenant)
                     App Registration + Service Principal (MSAL-2)
                                  ▲
                                  │ Anmeldung
Browser ──► Developer Portal  https://<apim>.developer.azure-api.net
   │
   └──► Gateway  https://<apim>.azure-api.net/crm/customers   (Subscription Key, CORS)
              └─ Policies: Managed Identity ──► Table Storage REST API
                                                └─ Storage Account, Tabelle "customers"
```

Alle Azure-Ressourcen liegen in der Resource Group `apim-dev-portal-poc` (swedencentral):

| Ressource | Name |
| --- | --- |
| API Management (Developer_1) | `apim-devportal-poc-<suffix>` |
| Storage Account | `stdevportal<suffix>` mit Tabelle `customers` |
| API | `Customers API`, Pfad `/crm` |
| Produkt | `Self-Service Customer Portal` (ohne Genehmigung, 60 Aufrufe/min) |
| Entra App Registration | `apim-dev-portal-poc-portal` (liegt im Tenant, nicht in der RG) |

### Repo-Struktur

```text
01-apim/                 Schritt 1: RG, Storage + Seed-Daten, APIM, API, Policies, Produkt
  api/                   OpenAPI-Vertrag der Kunden-API
  policies/              Policy-XML (API-Ebene, je Operation, Produkt)
02-portal/               Schritt 2: Entra App, Identity Provider, Portal-Inhalt, Veröffentlichung
  content/               Snapshot des Portal-Inhalts (data.json + media/)
scripts/                 Smoke-Test, Vorabprüfung, Veröffentlichen, Portal-Inhalt exportieren/einspielen
tools/portal-content/    Microsofts Portal-Skripte (vendor/, fest auf ein Release) + Update-Skript
Makefile                 Ablaufsteuerung
```

## Voraussetzungen

- `az login` mit Zugriff auf die Ziel-Subscription und dem Recht, im Tenant App Registrations anzulegen
- OpenTofu 1.13, GNU Make, `curl`, `jq`, `xmllint`
- Node.js 20 oder neuer, für die Portal-Skripte
- **Kosten:** APIM in der Developer-Stufe kostet etwa 0,07 $ pro Stunde (rund 50 $ im Monat), solange es existiert. Storage kostet Cent-Beträge. Nach dem Ausprobieren `make down`.

## Einrichtung

1. `.env.example` nach `.env` kopieren und eine Passphrase für die State-Verschlüsselung eintragen (mindestens 16 Zeichen). Das `Makefile` lädt `.env` automatisch. Für direkte `tofu`-Aufrufe vorher `set -a; . ./.env; set +a` ausführen.
2. `01-apim/terraform.tfvars.example` nach `01-apim/terraform.tfvars` kopieren und ausfüllen (`subscription_id`, `publisher_email`).
3. `02-portal/terraform.tfvars.example` nach `02-portal/terraform.tfvars` kopieren und ausfüllen (`subscription_id`, `tenant_id`).

## Ablauf

```bash
make up-1     # Schritt 1 (30-60 min, weil APIM so lange zum Anlegen braucht)
make smoke    # prüft die API über das Gateway (20 Prüfungen)
```

**Manueller Schritt, einmal pro neuer APIM-Instanz:** Azure-Portal → APIM-Instanz → „Developer portal“ → oben „Developer portal“ (öffnet den Admin-Modus). Warten, bis die Seite geladen ist, dann den Tab schließen. Erst dadurch legt APIM die Portal-Inhalte an. `make up-2` prüft das vorab und bricht sonst mit einem Hinweis ab.

```bash
make up-2     # Schritt 2 (Entra App, Identity Provider, Portal-Inhalt, Veröffentlichung)
```

`apply` und `destroy` fragen nach einer Bestätigung. Mit `AUTO_APPROVE=1` (zum Beispiel `make up-1 AUTO_APPROVE=1`) entfällt die Rückfrage.

**Im Browser prüfen:**
1. Portal-URL (`tofu -chdir=02-portal output developer_portal_url`) in einem privaten Fenster öffnen.
2. „Sign in“ → „Azure Active Directory“ → mit einem Test-User des Tenants anmelden.
3. Products → „Self-Service Customer Portal“ → Subscribe.
4. APIs → Customers API → eine Operation → „Try it“.
5. Gegenprobe: Ein privates Microsoft-Konto wird abgelehnt.

Den Test-User legst du im Entra Admin Center als Member an. Das eigene Konto ist dafür nicht geeignet: Als Subscription-Owner ist man im Portal Admin und sieht nicht, was ein normaler Entwickler sieht.

## API

| Operation | Aufruf | Erfolg |
| --- | --- | --- |
| Liste | `GET /crm/customers` | 200 |
| Lesen | `GET /crm/customers/{id}` | 200 |
| Anlegen | `POST /crm/customers` mit `{"name","email","city?"}` | 201 + `Location` |
| Ersetzen | `PUT /crm/customers/{id}` | 200 |
| Löschen | `DELETE /crm/customers/{id}` | 204 |

Seed-Kunden: `c001` bis `c005`, wobei `c005` absichtlich keine `city` hat.

```bash
curl -H "Ocp-Apim-Subscription-Key: <key>" "$(tofu -chdir=01-apim output -raw gateway_url)/crm/customers"
```

## Portal-Aussehen als Code

Seiten, Layouts, Farben, Schriften, Navigation und Bilder des Portals speichert APIM als „Content Items“ und Medien-Blobs. Der azurerm-Provider kennt dafür keine Ressourcen. Deshalb liegt der Stand als Snapshot im Repo:

```text
02-portal/content/data.json   alle Content Items (sortiert und eingerückt, für lesbare Diffs)
02-portal/content/media/      hochgeladene Bilder und Dateien (+ .info mit Content-Type)
```

**Ablauf:**
1. Im Admin-Modus gestalten (Azure-Portal → APIM → Developer portal → „Developer portal“). **Nicht** im Admin-Modus veröffentlichen, das übernimmt OpenTofu.
2. `make portal-capture` exportiert den Stand der Instanz nach `02-portal/content/`.
3. Mit `git diff` prüfen und committen.
4. Wenn sich der Snapshot geändert hat, ersetzt `make up-2` Inhalte und Medien der Instanz (`terraform_data.portal_content`) und veröffentlicht das Portal neu.

> **Achtung:** Das Einspielen **ersetzt** den Portal-Inhalt der Instanz, es führt nichts zusammen. Wer im Editor etwas ändert und nicht vorher `make portal-capture` ausführt, verliert diese Änderungen beim nächsten Einspielen eines geänderten Snapshots.

**Mehrere Stages (dev → prod):** Gestaltet wird nur in dev. Was im Snapshot steht, wird deployt, und `make up-2` gegen prod spielt diesen Stand dort ein. Der Snapshot enthält keine instanzspezifischen Werte wie Hostnamen oder Client-IDs. Entra-App, Identity Provider und Sign-up-Einstellung sind kein Content, OpenTofu legt sie pro Stage an. Benutzer und Subscriptions gehören nicht zum Snapshot. So empfiehlt Microsoft es auch in [Automate developer portal deployments](https://learn.microsoft.com/azure/api-management/automate-portal-deployments). Das Repo selbst hat bisher nur eine Stage.

### Microsofts Skripte und Updates

Export und Import machen Microsofts offizielle Skripte `capture.js`, `cleanup.js` und `generate.js` aus [`Azure/api-management-developer-portal`](https://github.com/Azure/api-management-developer-portal) (`scripts.v3`, MIT-Lizenz). Sie liegen als **feste Kopie** in `tools/portal-content/vendor/`:

- `vendor/UPSTREAM` hält Release-Tag und Commit fest, `vendor/LICENSE` ist Microsofts Lizenz.
- Kopiert sind nur die vier benötigten Dateien, nicht das ganze Repo (Portal-Quellcode, Build, hunderte Pakete).
- `package.json` und `package-lock.json` legen die npm-Abhängigkeiten auf exakte Versionen fest. `scripts/portal-content.sh` führt bei Bedarf `npm ci` aus.

Warum keine Kopie zur Laufzeit und kein Submodule: Ein `git clone` bei jedem Lauf hängt vom aktuellen Stand des Microsoft-Repos ab. Ein Update dort kann den Ablauf ohne Vorwarnung ändern, und die Skripte wurden schon einmal umgebaut (v2 → v3). Ein Submodule holt das ganze Repo und braucht `git submodule update` bei jedem Klon. Die feste Kopie ist klein, nachvollziehbar und ändert sich nur durch einen bewussten Commit.

**Update (manuell gestartet):**

```bash
make portal-tools-update             # neuestes Release
make portal-tools-update REF=2.36.0  # bestimmtes Release
git diff tools/portal-content        # Änderungen an den Skripten prüfen
make portal-capture                  # gegen dev testen; data.json darf sich nicht unerwartet ändern
```

Das Update-Skript gibt zusätzlich die Paketversionen aus, die Microsoft für `@azure/storage-blob` und `mime` angibt. Weichen sie ab, `package.json` anpassen und `npm install` in `tools/portal-content` ausführen.

## Design-Entscheidungen

- **Developer-Stufe:** Die günstigste Stufe mit Developer Portal. Consumption hat kein Portal, Basic v2 kostet mehr.
- **Kein Backend-Code:** Die Policies übersetzen die REST-Aufrufe in Aufrufe der Table Storage REST API. APIM authentifiziert sich mit seiner System Managed Identity (Rolle *Storage Table Data Contributor*). Für eine Demo-API reicht das, es braucht keine Function App und kein Deployment von Code.
- **Abgesicherte Policies:**
  - `validate-parameters` lässt in der `id` nur `A-Z a-z 0-9 -` zu, so kommt keine OData-Injection über Hochkommas oder Klammern durch.
  - `validate-content` lehnt unbekannte Felder und Bodies über 4 KB ab.
  - `PartitionKey` und `RowKey` setzt immer die Policy, nie der Client.
  - `copy-unmatched-params="false"` verhindert, dass Clients `$filter` oder `$top` an Storage durchreichen.
  - `If-Match: *` sorgt dafür, dass PUT und DELETE auf eine unbekannte `id` mit 404 antworten, statt einen Kunden anzulegen.
  - Den Subscription Key reicht APIM nicht an Storage weiter.
- **Zwei Roots statt einer:** Das Developer Portal braucht nach dem Anlegen von APIM einmal den manuellen Admin-Klick. Ohne diesen Klick hat das Portal keine Inhalte, und Schritt 2 kann nichts veröffentlichen. Die Roots tauschen nur drei Werte aus, über eine generierte `02-portal/stage1.auto.tfvars`. Es gibt kein `terraform_remote_state`, weil Schritt 2 sonst die Verschlüsselung von Schritt 1 mitkonfigurieren müsste.
- **Lokaler, verschlüsselter State:** Native State-Verschlüsselung von OpenTofu (pbkdf2 + AES-GCM, erzwungen für State und Plan). Die Passphrase kommt aus `TF_VAR_state_passphrase`.
- **Veröffentlichen per Skript:** `terraform_data` + `local-exec` ruft die Management-API (`portalRevisions`) auf und wartet, bis die Veröffentlichung fertig ist. Neu veröffentlicht wird nur, wenn sich Client-ID, Secret-ID, Tenant oder der Portal-Snapshot ändern.
- **Secret-Rotation ohne Drift:** Das Ablaufdatum des Client Secrets kommt aus `time_offset` statt aus `timestamp()`.

## Bekannte Eigenheiten

- Der Admin-Klick ist nötig: Vorher liefert die API 0 Portal-Seiten, danach 16.
- Nach `up-1` können die ersten Aufrufe einige Minuten lang **403** liefern, weil die Rollenzuweisung noch nicht wirkt. `make smoke` wiederholt dann von selbst.
- Ein `apply` von `01-apim` setzt **nur die fünf Seed-Kunden** zurück. Kunden, die über die API angelegt wurden, bleiben bestehen. Ein Seed-Kunde, der über die API geändert wurde, erscheint in `make plan` als Änderung.
- Der erste Entra-Anmeldeversuch kann mit `timed_out` (MSAL) scheitern, ein zweiter Versuch klappt.
- CORS erlaubt alle Request-Header, weil die Test-Konsole je nach Einstellung auch `Ocp-Apim-Trace` oder `Cache-Control` schickt. Mit einer festen Header-Liste schlägt „Try it“ mit einem CORS-Fehler fehl. Die `cors`-Policy auf API-Ebene beantwortet den Preflight ohne eigene OPTIONS-Operation.
- Sign-up ist aus (`sign_up` in `01-apim/apim.tf`, azurerm 4.x hat dafür keine eigene Ressource).
- Bei der Smoke-Subscription steht `allow_tracing = false` fest im Code, weil Azure Tracing auf Subscriptions von selbst abschaltet. Sonst würde jeder Plan Drift melden.
- Die Liste liefert höchstens 1000 Einträge. Fehler (404, 409) kommen unverändert im OData-Format von Table Storage zurück.
- Die Produkte Starter und Unlimited legt APIM automatisch an. `developers` ist eine APIM-Gruppe, keine Entra-Gruppe.

## Betrieb

- **Drift prüfen:** `make plan` bricht ab, sobald eine der beiden Roots Änderungen meldet.
- **Statische Prüfungen:** `make lint` (fmt, validate, XML, Shell-Syntax, Snapshot-JSON). Braucht keinen Azure-Zugriff.
- **Secret rotieren:** `tofu -chdir=02-portal apply -replace=time_offset.secret_expiry`. Das neue Ablaufdatum erzwingt ein neues Secret, und das Portal wird automatisch neu veröffentlicht. Das aktuelle Ablaufdatum zeigt `tofu -chdir=02-portal output secret_expires_at`.
- **Portal von Hand neu veröffentlichen:** `tofu -chdir=02-portal apply -replace=terraform_data.portal_publish`.
- **Fehlersuche:** Azure-Portal → APIM → APIs → Customers API → Operation → Tab „Test“ → „Trace“.

## Abbau

```bash
make down     # erst 02-portal (Entra-Objekte), dann 01-apim (RG inkl. APIM, endgültig gelöscht)
```

**Notfall:**
- **Passphrase verloren:** Die States lassen sich dann nicht mehr lesen. Resource Group `apim-dev-portal-poc` und App Registration `apim-dev-portal-poc-portal` von Hand löschen.
- **01 versehentlich vor 02 abgebaut:** Für jede Adresse aus `tofu -chdir=02-portal state list` einmal `tofu -chdir=02-portal state rm <adresse>` ausführen. Danach die App Registration von Hand löschen.

## Sicherheitsstand

- Nur für Demo-Daten geeignet: Wer einen Subscription Key hat, kann alle Kunden lesen, ändern und löschen.
- Der Storage Account ist öffentlich erreichbar und hat den Shared Key aktiviert, weil das Seeding über azurerm ihn braucht.
- Das Client Secret steht im verschlüsselten State und in der Konfiguration des APIM-Identity-Providers.

## Mögliche Erweiterungen

- API zusätzlich mit Entra-Tokens absichern (`validate-jwt` auf API-Ebene, zweite App Registration, OAuth in der Test-Konsole). Produkt, Gruppe und Operationen bleiben dabei unverändert.
- Mehrere Stages: pro Stage eigene tfvars und eigener State, Code und Portal-Snapshot gemeinsam.
- Application Insights mit Tageslimit, Budget-Alarm auf der Resource Group.
- Seitenweise Liste über die Continuation-Header von Table Storage.
