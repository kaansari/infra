# Job Recommendation System Requirements

## 1. Overview

This document defines the requirements for adding a personalized job recommendation feature to the Ceerat platform using the existing Typesense deployment as the primary retrieval engine and PostgreSQL as the source of truth.

The proposed solution will:
- use Typesense for keyword, filter, and semantic/hybrid retrieval,
- use PostgreSQL for durable storage of jobs, candidate profiles, resumes, recommendations, and feedback,
- add a matching and reranking service to produce the final top-100 recommendations,
- reuse existing Career and resume capabilities already present in the platform.

This feature should be implemented as an extension of the current Career experience rather than as a new standalone vector database project.

## 2. Problem Statement

The platform already supports job search and resume import. However, it does not yet provide a personalized recommendation experience that can:
- understand a candidate’s resume and expressed preferences,
- retrieve a broad set of relevant jobs efficiently,
- rank jobs using a business-aware scoring model,
- store the best matches for later review and feedback.

The new feature should close that gap by combining retrieval and ranking into a single recommendation workflow.

## 3. Goals

### Primary Goals
1. Recommend the most relevant jobs for a candidate using profile-aware retrieval.
2. Use Typesense for fast candidate generation and hybrid retrieval.
3. Keep PostgreSQL as the authoritative source for jobs and candidate-related records.
4. Produce explainable recommendations with a transparent score breakdown.
5. Persist the best recommendations so they can be reviewed, applied to, or refined over time.

### Secondary Goals
1. Support future personalization based on clicks, saves, applications, and rejections.
2. Keep the implementation compatible with the existing service-owned architecture.
3. Avoid introducing a second vector database in the first release.

## 4. Non-Goals

The first version will not:
- replace the PostgreSQL job store,
- implement a fully autonomous hiring agent,
- introduce a separate vector database such as Qdrant or Pinecone,
- make final hiring decisions or license/work authorization decisions,
- perform deep behavioral personalization before basic resume-based matching is stable.

## 5. Functional Requirements

### FR1. Resume-Based Profile Extraction
The system shall extract a structured candidate profile from uploaded or imported resume content.

The extracted profile must include, at minimum:
- target roles or job titles,
- seniority level,
- relevant skills,
- recent work summary,
- location preferences,
- salary preferences.

### FR2. Job Indexing in Typesense
The system shall index jobs in Typesense with fields needed for filtering and retrieval.

Required fields include:
- id,
- title,
- normalized title,
- description,
- skills,
- seniority,
- employment type,
- remote/hybrid/onsite flags,
- country/state/city,
- salary minimum/maximum,
- experience minimum,
- active status,
- published date,
- freshness-related ranking fields,
- embedding vector.

### FR3. Candidate Embedding Generation
The system shall generate a candidate embedding from the normalized candidate profile.

The embedding shall be used for semantic similarity matching in Typesense.

### FR4. Hybrid Retrieval
The system shall perform hybrid retrieval using Typesense with:
- keyword relevance,
- semantic similarity,
- filter-based narrowing,
- ranking fields.

The initial implementation may use one well-structured profile embedding and one hybrid search request.

### FR5. Detailed Reranking
The system shall rerank the retrieved candidate set using a domain-specific scoring model.

The initial scoring model should include components such as:
- Typesense relevance score,
- required-skill coverage,
- title fit,
- seniority fit,
- experience alignment,
- location and remote fit,
- salary fit,
- freshness.

### FR6. Required Skill Validation
The system shall validate whether the candidate’s profile satisfies the job’s required skill and experience expectations.

Jobs failing critical requirement checks should be demoted or excluded from the top recommendations.

### FR7. Recommendation Persistence
The system shall persist the top recommended jobs for a candidate in PostgreSQL.

Persisted recommendations should include:
- candidate id,
- job id,
- score,
- reasons/explanations,
- generation timestamp,
- optional feedback state.

### FR8. Explanation Output
The system shall provide human-readable reasons for why each recommended job was selected.

Example reasons include:
- strong skill overlap,
- title and seniority fit,
- salary preference alignment,
- recent posting freshness.

### FR9. Feedback Support
The system shall support later feedback events such as:
- opened,
- saved,
- applied,
- rejected,
- hidden,
- marked more-like-this.

These signals will be used for future personalization improvements.

## 6. Non-Functional Requirements

### NFR1. Performance
The retrieval phase should return a useful shortlist quickly enough for interactive use.

Target for the first release:
- initial retrieval of the top shortlist in under 2 seconds for a typical candidate profile,
- final ranking for a shortlist of 500 to 1000 jobs in under 5 seconds.

### NFR2. Reliability
The feature must degrade gracefully when Typesense is unavailable.

If Typesense is disabled or unreachable, the system should fall back to a basic PostgreSQL-based job search or return a clear error state.

### NFR3. Security
The feature must respect existing ownership and authentication rules.

Candidate profiles, resumes, and recommendations must remain scoped to the authenticated user and must not be exposed to other customers.

### NFR4. Observability
The system should log recommendation generation, ranking outcomes, and failures.

Logs should support troubleshooting of:
- retrieval failures,
- indexing failures,
- scoring anomalies,
- recommendation persistence issues.

### NFR5. Extensibility
The implementation should be structured so that future enhancements can add:
- additional ranking factors,
- personalization vectors,
- multi-embedding retrieval,
- natural-language query understanding.

## 7. Proposed Solution

The recommended design is:

- PostgreSQL remains the source of truth for jobs and candidate records.
- Typesense becomes the retrieval engine for:
  - filtering,
  - keyword matching,
  - semantic similarity,
  - hybrid search.
- A matching service performs the final business-aware scoring, validation, and explanation generation.
- The service stores only the best results in PostgreSQL.

### High-Level Flow
1. Candidate uploads or imports a resume.
2. The system extracts a structured profile.
3. The system generates a candidate embedding.
4. The system sends a hybrid search request to Typesense.
5. Typesense returns a shortlist of potentially relevant jobs.
6. The matching service reranks and validates the shortlist.
7. The system saves the top 100 recommendations to PostgreSQL.
8. The UI displays the recommendations with explanation text.

## 8. Implementation Plan

### Phase 1: Foundation
Goal: establish the basic retrieval and scoring pipeline.

Tasks:
- extend the job schema in Typesense,
- add embedding fields to indexed job documents,
- create a candidate profile builder from the existing resume import flow,
- add a basic hybrid search request,
- implement a simple scoring service,
- persist the top recommendations to PostgreSQL.

Deliverables:
- job documents indexed with embeddings,
- candidate profile built from existing resume data,
- basic recommendation generation endpoint or service,
- top-100 persistence.

### Phase 2: Ranking and Validation
Goal: improve match quality.

Tasks:
- add skill coverage validation,
- add title and seniority matching,
- add location, salary, and experience scoring,
- improve explanation generation,
- add confidence and score breakdown fields.

Deliverables:
- richer scoring output,
- improved relevance quality,
- explainable recommendation results.

### Phase 3: Personalization
Goal: make recommendations adapt to candidate behavior over time.

Tasks:
- capture feedback events,
- build behavior-based preference signals,
- blend resume-based and behavior-based vectors,
- adjust recommendations over time.

Deliverables:
- adaptive recommendations,
- better long-term personalization,
- feedback-driven ranking improvements.

## 9. Components That Need Updates

### 1. Career Job Search Service
Location:
- services-repo/services/ceerat-user-service/careers/jobsearch

Updates needed:
- extend the Typesense schema,
- support hybrid search parameters,
- include embedding and ranking fields in the indexed document model,
- add search request support for vector-based retrieval.

### 2. Resume Parsing and Profile Extraction
Location:
- services-repo/services/ceerat-user-service/careers/resume_import.go

Updates needed:
- reuse and extend the existing resume parsing logic,
- generate a normalized profile from the parsed resume,
- create a structured candidate profile object for embedding generation.

### 3. Matching and Recommendation Service
Location:
- services-repo/services/ceerat-user-service/careers

Updates needed:
- add a new recommendation or matching service,
- implement scoring, required-skill validation, explanations, and persistence,
- coordinate between Typesense results and PostgreSQL-backed jobs.

### 4. Data Model and Persistence Layer
Location:
- services-repo/services/ceerat-user-service/internal/models
- services-repo/services/ceerat-user-service/services

Updates needed:
- add recommendation and feedback persistence models or repository support,
- store recommendation score breakdown and explanation text,
- support future feedback events.

### 5. Contracts and API Layer
Location:
- contracts-repo/packages/ceerat-contracts/proto/career

Updates needed:
- add Career RPCs for recommendation generation if the feature will be exposed through the public platform API,
- update request/response messages for recommendations and explanations.

### 6. UI and Agent Surface
Location:
- apps-repo/apps/ceerat-customer-ui
- apps-repo/ai/ceerat-agent-service

Updates needed:
- expose recommendations to the customer experience,
- optionally surface recommendation explanations in the UI or agent experience.

### 7. Infrastructure and Configuration
Location:
- infra

Updates needed:
- ensure Typesense configuration supports vector fields,
- add environment variables for embedding configuration if an external embedding provider is used,
- document deployment requirements and memory considerations.

## 10. Test Strategy

### Test Principles
The feature should be tested at three levels:
1. unit tests for profile extraction and scoring,
2. integration tests for Typesense retrieval and indexing,
3. end-to-end tests for recommendation generation and persistence.

### Good Test Case
A strong initial test case should verify the full flow from resume import to recommendation generation.

#### Test Scenario
- Input: a candidate resume that includes:
  - Go,
  - PostgreSQL,
  - AWS,
  - Kubernetes,
  - backend engineering experience,
  - remote work preference,
  - salary target above $130,000.
- Input jobs:
  - one strong backend Go job matching skills and salary,
  - one weaker job with partial skill overlap,
  - one irrelevant job with no relevant skills.

#### Expected Result
- the strong backend job appears at the top,
- the partial match appears lower,
- the irrelevant job is filtered out or ranked very low,
- the recommendation entry contains explanation text,
- the top recommendation is persisted in PostgreSQL.

### Unit Tests
Add unit tests for:
- resume profile normalization,
- candidate embedding text preparation,
- scoring weights,
- required-skill validation,
- explanation generation.

### Integration Tests
Add integration tests for:
- creating a Typesense collection with the new schema,
- indexing a sample job set,
- performing a hybrid search request,
- mapping search results back into recommendation candidates.

### End-to-End Tests
Add end-to-end tests for:
- creating a candidate profile from resume text,
- generating recommendations,
- saving recommendations to PostgreSQL,
- retrieving them for display.

### Manual Validation Checklist
1. Upload a sample resume.
2. Generate recommendations.
3. Confirm the top matches reflect the candidate’s experience and preferences.
4. Verify explanations are readable and relevant.
5. Confirm the stored recommendation entries appear in PostgreSQL.
6. Confirm the feature still works when Typesense is disabled.

## 11. Rollout and Success Metrics

Success should be measured by:
- recommendation relevance,
- retrieval latency,
- ranking stability,
- persistence correctness,
- explanation quality.

Suggested initial metrics:
- top-3 recommendation hit rate,
- percentage of recommendations with a meaningful explanation,
- average generation time,
- percentage of saved recommendations that receive positive user feedback.

## 12. Open Questions

1. Should the first version use a simple inline embedding generation approach or an external embedding provider?
2. Should recommendations be generated on demand only, or also asynchronously in the background?
3. Should the first version expose recommendations through the existing Career job search flow or through a dedicated recommendation endpoint?
4. What minimum scoring weights should be used before the feature is tuned with real feedback?

## 13. Recommendation

Implement the feature in three phases starting with hybrid search and basic reranking, then improve quality with stronger validation and scoring, and finally add personalization based on feedback.

This approach delivers value quickly, aligns with the current architecture, and avoids introducing unnecessary infrastructure complexity in the first release.
