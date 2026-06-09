You are working inside my existing ATS crawler / job import system.

Goal:
Add a simple but powerful job search system for imported ATS jobs using Typesense.


Context:

use, [Requirement doc ](search-req.md) file for requirement context.

Use the Ceerat builder agent first for security, architectural integrity, service ownership, API consistency, app-surface impact, and RBAC drift checks.

Run builder-agent discovery from the Ceerat workspace root:

```sh
cd /Users/kaansari/go/src/github.com/kaansari
```

Builder-agent commands to run before implementation:

```sh
ceerat-builder codex-context --output json
ceerat-builder docs all --output json
ceerat-builder inventory services --output json
ceerat-builder inventory contracts --output json
ceerat-builder inventory apps --output json
ceerat-builder decide-owner "Typesense job search for imported ATS jobs saved through career.JobService/ImportATSJobs" --output json
ceerat-builder evidence request "add Typesense search index for imported ATS jobs while keeping database as source of truth and frontend off Typesense admin key" --output json
ceerat-builder patterns service --output json
ceerat-builder patterns grpc-security --output json
ceerat-builder patterns testing --output json
ceerat-builder app-context --output json
ceerat-builder app-context ceerat-customer-ui --output json
ceerat-builder app-surface ceerat-customer-ui --output json
ceerat-builder app-match "job search page for imported ATS jobs using app backend API and Typesense behind the service boundary" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /customer/career/jobs" --surface "Typesense-backed imported job search UI" --output json
ceerat-builder app-impact ceerat-customer-ui --route "GET /api/jobs/search" --surface "server-owned job search API wrapper" --output json
ceerat-builder rbac check --output json
ceerat-builder check drift --output json
ceerat-builder check apps --output json
ceerat-builder plan --output json "add Typesense-backed search for imported ATS jobs from infra/requirement/search-req.md"
```

If any builder command fails because an inventory or repo is missing, stop and report the missing prerequisite before editing. Do not invent a parallel service path just to make the implementation fit.

Treat builder output as factual context, not final design. The final design must still be based on the actual code currently present in the workspace.

Builder-agent security and architecture rules for this task:

* `ceerat-user-service` / Career domain should own job import persistence, indexing, rebuild, and search orchestration unless builder explicitly identifies a better existing owner.
* The ATS crawler must continue to import through `career.JobService/ImportATSJobs`; it must not write directly to Typesense.
* The main database remains the source of truth. Typesense is only a derived search index.
* Indexing must happen only after a successful database save/update.
* Typesense indexing failure must be logged and must not fail the database import.
* Browser apps must call Ceerat backend APIs only; they must never call Typesense directly.
* Never expose `TYPESENSE_API_KEY` or any admin/search write key to frontend JavaScript, templates, logs, or API responses.
* Build search filters server-side from allowlisted query parameters only.
* Clamp pagination server-side and default `status=open`.
* If adding or changing gRPC methods, update `KnownGRPCMethods`, `DefaultRolePermissions`, generated protobufs, API docs, and builder inventories as appropriate.
* If adding HTTP app routes, update the customer UI app-surface inventory and add route/render tests.
* Preserve existing customer auth/session behavior and Career navigation standards.
* Keep provider-backed application flows separate from job search; search/view links may lead to the existing job detail/apply flow, but search must not submit applications.



* My crawler imports jobs from ATS providers like Greenhouse.
* Jobs are imported through the existing service layer into my main system.
* The database must remain the source of truth.
* Typesense should be added only as a search index.
* Do not make the crawler write directly to Typesense unless there is no better option.
* Prefer integrating indexing after jobs are successfully saved/imported by the existing service layer.
* Existing imported job fields likely include title, description, location, status, source, source_url, and external_job_id.

Main tasks:

1. Add Typesense support

* Add a Typesense client/config module.
* Read config from environment variables:

  * TYPESENSE_HOST
  * TYPESENSE_PORT
  * TYPESENSE_PROTOCOL
  * TYPESENSE_API_KEY
  * TYPESENSE_COLLECTION_JOBS
* Default collection name should be `jobs`.
* Do not expose the Typesense admin API key to the frontend.

2. Add local Docker support

* If a docker-compose file exists, add Typesense to it.
* If not, create one or add a documented example.
* Use:

  * image: typesense/typesense:latest
  * port: 8108
  * persistent volume
  * command with data-dir and api-key
* Add example environment variables to `.env.example` or documentation.

3. Create the Typesense jobs collection
   Create a collection named `jobs` with this schema:

{
"name": "jobs",
"fields": [
{ "name": "job_id", "type": "string" },
{ "name": "external_job_id", "type": "string" },
{ "name": "source", "type": "string", "facet": true },
{ "name": "source_url", "type": "string" },

```
{ "name": "title", "type": "string" },
{ "name": "company", "type": "string", "facet": true },
{ "name": "description", "type": "string" },

{ "name": "location", "type": "string", "facet": true },
{ "name": "locations", "type": "string[]", "facet": true },
{ "name": "country", "type": "string", "facet": true },

{ "name": "remote", "type": "bool", "facet": true },
{ "name": "hybrid", "type": "bool", "facet": true },
{ "name": "onsite", "type": "bool", "facet": true },

{ "name": "department", "type": "string", "facet": true, "optional": true },
{ "name": "employment_type", "type": "string", "facet": true, "optional": true },
{ "name": "seniority", "type": "string", "facet": true, "optional": true },
{ "name": "skills", "type": "string[]", "facet": true, "optional": true },

{ "name": "status", "type": "string", "facet": true },

{ "name": "posted_at", "type": "int64", "sort": true, "optional": true },
{ "name": "updated_at", "type": "int64", "sort": true },
{ "name": "imported_at", "type": "int64", "sort": true }
```

],
"default_sorting_field": "updated_at"
}

4. Add job search document normalization
   Create a function that converts an imported/saved job into a Typesense document.

The document should include:

* id: stable unique id, preferably `${source}_${external_job_id}` or internal job id
* job_id
* external_job_id
* source
* source_url
* title
* company
* description as plain text
* location
* locations array
* country
* remote boolean
* hybrid boolean
* onsite boolean
* department
* employment_type
* seniority
* skills array
* status
* posted_at as Unix timestamp if available
* updated_at as Unix timestamp
* imported_at as Unix timestamp

Add simple rule-based extraction:

* Convert HTML description to plain text.
* Detect remote from title/location/description containing words like remote, work from home, anywhere, distributed.
* Detect hybrid from words like hybrid, office days, in-office.
* Detect onsite from words like onsite, on-site, office-based.
* Detect seniority from title keywords:
  Intern, Junior, Associate, Mid, Senior, Sr, Staff, Principal, Lead, Manager, Director, VP, Executive.
* Detect employment type from title/description:
  Full-time, Part-time, Contract, Temporary, Internship.
* Extract skills from a predefined keyword list:
  Go, Golang, JavaScript, TypeScript, React, Node.js, Python, Java, C#, PHP, Ruby, AWS, Azure, GCP, Docker, Kubernetes, PostgreSQL, MySQL, MongoDB, Redis, GraphQL, REST, HTML, CSS, Vue, Angular, Next.js, Linux, Terraform, CI/CD.

Keep the normalizer simple and testable.

5. Index jobs after import
   Find the existing import flow where jobs are saved into the main system.
   After successful database save/update:

* Build the search document.
* Upsert it into Typesense.
* If Typesense indexing fails, log the error but do not fail the database import.
* Make indexing behavior easy to disable by config if needed.

6. Add a rebuild index command
   Add an admin command, script, or endpoint named conceptually:
   `rebuild-job-search-index`

It should:

* Ensure the Typesense jobs collection exists.
* Optionally clear/recreate the collection.
* Read all jobs from the main database.
* Normalize each job.
* Bulk import/upsert documents into Typesense.
* Log total jobs processed, success count, and failure count.

7. Add backend search API
   Create:

GET /api/jobs/search

Supported query params:

* q
* company
* location
* source
* remote
* hybrid
* onsite
* employment_type
* seniority
* department
* skills
* status
* country
* sort
* page
* per_page

Behavior:

* Default q to `*` if empty.
* Default status to `open`.
* Default page to 1.
* Default per_page to 20.
* Max per_page should be 100.
* Search fields:
  title,company,description,skills,location,department
* Return facets for:
  company,location,source,remote,hybrid,onsite,seniority,employment_type,department,skills,country
* Build Typesense `filter_by` safely from query params.
* Support sort values:

  * relevance
  * newest
  * updated_desc
  * posted_desc
  * company_asc
  * title_asc

Response shape:
{
"jobs": [],
"facets": {},
"total": 0,
"page": 1,
"per_page": 20
}

8. Add frontend search UI
   If the application has an existing frontend, add or update a job search page/component.

The UI should include:

* Search box
* Company filter
* Location filter
* Remote checkbox
* Source filter
* Skills filter
* Seniority filter
* Employment type filter
* Sort dropdown
* Pagination
* Job cards

Each job card should show:

* title
* company
* location
* remote/hybrid/onsite
* skills
* source
* updated or posted date
* apply/view link

The frontend must call the backend endpoint `/api/jobs/search`.
Do not call Typesense directly from the frontend using the admin key.

9. Add tests
   Add tests for:

* Job normalization
* HTML description cleanup
* Remote/hybrid/onsite detection
* Seniority detection
* Skills extraction
* Search filter construction
* Pagination defaults and max limit
* Indexing failure not breaking import

10. Add documentation
    Update README or docs with:

* How to run Typesense locally
* Required environment variables
* How indexing works
* How to rebuild the search index
* Example search API calls

Important implementation rules:

* Keep the solution simple.
* Do not rewrite the crawler architecture.
* Do not replace the existing database.
* Do not make Typesense the source of truth.
* Do not expose admin API keys to the browser.
* Prefer small, clear modules:

  * search/typesense_client
  * search/schema
  * search/normalizer
  * search/indexer
  * search/search_service
* Make the code production-safe but not over-engineered.

Deliverables:

* Typesense local setup.
* Jobs collection creation.
* Job normalization.
* Job indexing after import.
* Rebuild index command.
* `/api/jobs/search` backend endpoint.
* Frontend job search UI if this repo contains the web app.
* Tests.
* Documentation.
