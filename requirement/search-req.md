# Requirements Document: Job Search Integration for Imported ATS Jobs

## 1. Project Overview

The existing `atscrawler` imports jobs from ATS providers such as Greenhouse into the main system through the existing service layer. The goal is to add a powerful job search experience to the web application, similar to Solr-style search, but simpler to operate and easier to integrate.

The recommended search engine is **Typesense**.

The existing database must remain the source of truth. Typesense will be used only as a search index.

---

## 2. Goals

Build a fast, modern, faceted job search system that allows users to search imported jobs by keyword and filter by multiple job attributes.

The search should support:

* Keyword search across job title, company, description, skills, and location.
* Typo-tolerant search.
* Search-as-you-type behavior.
* Faceted filters.
* Sorting.
* Pagination.
* Search API integration with the existing web application.
* Index synchronization when jobs are imported or updated.
* Full search index rebuild from the existing jobs database.

---

## 3. Recommended Architecture

```text
ATS Crawler
   ↓
Existing Import Service Layer
   ↓
Main Application Database
   ↓
Search Indexer
   ↓
Typesense Jobs Collection
   ↓
Application Search API
   ↓
Frontend Job Search UI
```

The crawler must not write directly to Typesense.

The import service should save jobs to the database first. After successful database save or update, the system should index the saved job into Typesense.

The database is the source of truth. Typesense is a fast searchable copy.

---

## 4. Search Engine Choice

Use **Typesense**.

Reasons:

* Simpler than Solr, Elasticsearch, and OpenSearch.
* Strong enough for job-board search.
* Supports typo tolerance.
* Supports faceted filtering.
* Supports sorting.
* Supports autocomplete/search-as-you-type.
* Can be self-hosted with Docker.
* Can later support semantic/vector search if needed.
* Easy to rebuild from database records.

---

## 5. Core Search Features

### 5.1 Keyword Search

Users should be able to search for jobs using natural text, such as:

```text
golang engineer
remote nurse
frontend react
senior backend developer
project manager dallas
```

Search should query these fields:

* title
* company
* description
* skills
* location
* department

### 5.2 Filters

The search API should support filters for:

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
* posted_at range
* updated_at range

### 5.3 Facets

The API should return facet counts for:

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
* country

### 5.4 Sorting

The API should support sorting by:

* relevance
* newest
* updated_at descending
* posted_at descending
* company A-Z
* title A-Z

### 5.5 Pagination

The API should support:

* page
* per_page

Default:

```text
page = 1
per_page = 20
```

Maximum:

```text
per_page = 100
```

---

## 6. Job Search Document Model

Each job indexed into Typesense should follow this normalized shape:

```json
{
  "id": "greenhouse_123456",
  "job_id": "internal-db-id",
  "external_job_id": "123456",
  "source": "greenhouse",
  "source_url": "https://boards.greenhouse.io/company/jobs/123456",

  "title": "Senior Software Engineer, Backend",
  "company": "Stripe",
  "description": "Plain text job description",
  "location": "New York, NY",
  "locations": ["New York, NY"],
  "country": "US",

  "remote": true,
  "hybrid": false,
  "onsite": false,

  "department": "Engineering",
  "employment_type": "Full-time",
  "seniority": "Senior",

  "skills": ["Go", "Kubernetes", "PostgreSQL", "AWS"],
  "status": "open",

  "posted_at": 1719000000,
  "updated_at": 1719600000,
  "imported_at": 1719600000
}
```

---

## 7. Required Field Normalization

The system should enrich imported jobs before indexing.

### 7.1 Description Cleanup

Convert HTML job descriptions into plain text.

Requirements:

* Remove HTML tags.
* Decode HTML entities.
* Normalize whitespace.
* Preserve meaningful text.
* Avoid storing large raw HTML in the search index.

### 7.2 Remote / Hybrid / Onsite Detection

Detect remote status using title, location, and description.

Example rules:

Remote if text contains:

```text
remote
work from home
anywhere
distributed
```

Hybrid if text contains:

```text
hybrid
office days
in-office 2 days
```

Onsite if text contains:

```text
onsite
on-site
office-based
```

### 7.3 Seniority Detection

Detect seniority from title and description.

Possible values:

```text
Intern
Junior
Mid
Senior
Staff
Principal
Lead
Manager
Director
VP
Executive
Unknown
```

### 7.4 Employment Type Detection

Detect employment type when possible.

Possible values:

```text
Full-time
Part-time
Contract
Temporary
Internship
Unknown
```

### 7.5 Skills Extraction

Start with a simple keyword-based skills extractor.

Initial skills list:

```text
Go
Golang
JavaScript
TypeScript
React
Node.js
Python
Java
C#
PHP
Ruby
AWS
Azure
GCP
Docker
Kubernetes
PostgreSQL
MySQL
MongoDB
Redis
GraphQL
REST
HTML
CSS
Vue
Angular
Next.js
Linux
Terraform
CI/CD
```

Later, this can be improved with AI extraction.

---

## 8. Typesense Collection Schema

Create a Typesense collection named:

```text
jobs
```

Schema:

```json
{
  "name": "jobs",
  "fields": [
    { "name": "job_id", "type": "string" },
    { "name": "external_job_id", "type": "string" },
    { "name": "source", "type": "string", "facet": true },
    { "name": "source_url", "type": "string" },

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
  ],
  "default_sorting_field": "updated_at"
}
```

---

## 9. Backend API Requirements

Create a search endpoint in the existing web application.

Endpoint:

```http
GET /api/jobs/search
```

Query parameters:

```text
q
company
location
source
remote
hybrid
onsite
employment_type
seniority
department
skills
status
country
sort
page
per_page
```

Example request:

```http
GET /api/jobs/search?q=golang&remote=true&skills=Go,AWS&page=1&per_page=20
```

The backend should convert this into a Typesense search request.

Example Typesense search:

```json
{
  "q": "golang",
  "query_by": "title,company,description,skills,location,department",
  "filter_by": "status:=open && remote:=true && skills:=[Go,AWS]",
  "facet_by": "company,location,source,remote,hybrid,onsite,seniority,employment_type,department,skills,country",
  "sort_by": "updated_at:desc",
  "page": 1,
  "per_page": 20
}
```

Response shape:

```json
{
  "jobs": [],
  "facets": {
    "company": [],
    "location": [],
    "source": [],
    "skills": []
  },
  "total": 0,
  "page": 1,
  "per_page": 20
}
```

---

## 10. Indexing Requirements

### 10.1 Upsert on Import

After jobs are imported and saved to the database, each saved job should be upserted into Typesense.

Flow:

```text
Import ATS jobs
Save/update jobs in database
Build normalized search document
Upsert document into Typesense
```

### 10.2 Rebuild Index

Add an admin or command-line function to rebuild the entire Typesense index from the main database.

Required command:

```text
rebuild-job-search-index
```

Expected behavior:

```text
Delete/recreate jobs collection if needed
Fetch all active jobs from database
Normalize each job
Bulk import into Typesense
Log success/failure counts
```

### 10.3 Failed Indexing

If indexing fails, the database import must still succeed.

Log the error and allow a later rebuild to fix the index.

---

## 11. Docker / Environment Requirements

Add Typesense to local development using Docker.

Example:

```yaml
services:
  typesense:
    image: typesense/typesense:latest
    ports:
      - "8108:8108"
    volumes:
      - typesense-data:/data
    command: >
      --data-dir /data
      --api-key=dev_typesense_key
      --enable-cors

volumes:
  typesense-data:
```

Environment variables:

```env
TYPESENSE_HOST=localhost
TYPESENSE_PORT=8108
TYPESENSE_PROTOCOL=http
TYPESENSE_API_KEY=dev_typesense_key
TYPESENSE_COLLECTION_JOBS=jobs
```

Production API keys must not be exposed to the frontend.

---

## 12. Frontend Requirements

Add a job search page or component to the existing web application.

UI should include:

* Search input.
* Company filter.
* Location filter.
* Remote checkbox.
* Source filter.
* Skills filter.
* Seniority filter.
* Employment type filter.
* Sort dropdown.
* Pagination.
* Job cards.

Each job card should show:

* Job title.
* Company.
* Location.
* Remote/hybrid/onsite label.
* Skills, if available.
* Source.
* Posted or updated date.
* Link to view/apply.

Frontend should call only the application backend endpoint:

```text
/api/jobs/search
```

Frontend should not call Typesense directly with the admin API key.

---

## 13. Security Requirements

* Keep Typesense admin key server-side only.
* Do not expose write/indexing keys to frontend.
* Validate and sanitize all query parameters.
* Limit `per_page` to a safe maximum.
* Only return jobs with allowed statuses, usually `status=open`.
* Avoid exposing internal-only job fields.

---

## 14. Acceptance Criteria

The implementation is complete when:

1. Typesense runs locally through Docker.
2. The `jobs` collection can be created automatically.
3. Imported jobs are indexed into Typesense after database save.
4. Existing jobs can be reindexed from the database.
5. `/api/jobs/search` returns relevant results.
6. Search supports keyword query.
7. Search supports filters.
8. Search returns facets.
9. Search supports sorting.
10. Search supports pagination.
11. Frontend displays search results.
12. Frontend filters update results.
13. Typesense API key is not exposed to the browser.
14. Indexing errors do not break job imports.
15. Documentation is added for setup and rebuild.

---

## 15. Future Enhancements

After the first version works, add:

* Semantic search.
* AI-based skill extraction.
* Salary extraction.
* Location geocoding.
* Saved searches.
* Job alerts.
* Similar jobs.
* Recommended jobs.
* Admin search diagnostics.
* Search analytics.
