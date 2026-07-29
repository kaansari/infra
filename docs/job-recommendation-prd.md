# Job Recommendation Feature PRD

## 1. Summary

This feature introduces a personalized job recommendation experience for Career users. The system will use the existing Typesense deployment for retrieval and PostgreSQL as the source of truth, while adding a matching and reranking layer that produces a curated shortlist of jobs tailored to the candidate’s resume, preferences, and profile.

The goal is not only to improve retrieval quality, but also to make the Career experience feel more proactive, less manual, and easier to act on.

## 2. Problem Statement

Today, the Career experience is primarily search-driven. Users must manually search, filter, and evaluate jobs themselves. That creates friction, especially for candidates who want a system to surface jobs that are likely to fit them based on their background.

This feature addresses that gap by helping users discover jobs that are relevant based on:
- their resume-derived profile,
- stated preferences,
- relevant skills and experience,
- work location and salary expectations.

## 3. Product Goals

1. Help users discover relevant jobs faster than manual search.
2. Surface jobs that are more aligned with the candidate’s experience and preferences.
3. Make recommendations explainable and easy to act on.
4. Create a feedback loop so future recommendations improve over time.
5. Keep the architecture aligned with the existing service-owned platform model.

## 4. Non-Goals

The first release will not:
- replace manual job search,
- introduce a new vector database,
- fully automate hiring decisions,
- provide deep behavioral personalization before the first version is validated,
- make hiring or authorization decisions.

## 5. Users and Personas

### Primary User
- Candidate seeking jobs that match their background and preferences.

### Secondary User
- Career admin or product team reviewing recommendation quality and feedback signals.

## 6. User Stories

### US1. Resume-Based Recommendations
As a candidate, I want the system to generate recommendations from my resume so I can see jobs that are relevant without manually searching every time.

### US2. Explainable Matches
As a candidate, I want to understand why a job was recommended so I can trust the results and act on them quickly.

### US3. Save and Reject Actions
As a candidate, I want to save promising recommendations and dismiss poor matches so the system learns what I want.

### US4. Recommendation Refresh
As a candidate, I want the recommendation list to refresh when my profile or preferences change so the results stay relevant.

### US5. Search + Recommendations
As a candidate, I want recommendations to complement regular search so I can still use filters and manual exploration when needed.

## 7. Functional Requirements

### FR1. Profile Extraction
The system shall extract a structured candidate profile from uploaded or imported resume content.

The profile must include at least:
- target roles or titles,
- seniority,
- skills,
- work summary,
- location preferences,
- salary preferences.

### FR2. Job Indexing
The system shall index jobs in Typesense with the fields required for filtering and retrieval.

Required fields include:
- title,
- normalized title,
- description,
- skills,
- seniority,
- employment type,
- remote/hybrid/onsite flags,
- country/state/city,
- salary range,
- experience range,
- active status,
- published date,
- freshness-related ranking fields,
- embedding vector.

### FR3. Candidate Embedding
The system shall generate a candidate embedding from the normalized candidate profile for semantic matching.

### FR4. Hybrid Retrieval
The system shall run a hybrid search in Typesense combining:
- keyword matching,
- semantic similarity,
- filters,
- ranking fields.

### FR5. Reranking
The system shall rerank the Typesense shortlist using a business-aware scoring model.

The initial scoring model should consider:
- retrieval relevance,
- required-skill coverage,
- title fit,
- seniority fit,
- experience fit,
- location fit,
- salary fit,
- freshness.

### FR6. Normalization
The system shall normalize job and candidate attributes before ranking.

Normalization must support:
- skill synonyms and variants,
- title variants,
- seniority mapping,
- salary bands,
- work-mode expectations,
- required vs preferred attributes.

### FR7. Explanations
The system shall provide brief, human-readable reasons for why each job was recommended.

Examples include:
- strong skill overlap,
- remote preference match,
- title and seniority fit,
- salary band alignment,
- recent posting freshness.

### FR8. Persistence
The system shall save the top recommendations for each candidate in PostgreSQL.

Persisted recommendation data must include:
- candidate identifier,
- job identifier,
- score,
- explanation text,
- recommendation timestamp,
- feedback state.

### FR9. Feedback Loop
The system shall capture user actions such as:
- save,
- reject,
- hide,
- view details,
- apply.

These actions should later influence recommendation quality.

### FR10. Recommendation Interaction
The system shall allow users to:
- view the job detail page from a recommendation,
- save or dismiss the recommendation,
- see why it was shown.

## 8. Acceptance Criteria

### AC1. Resume-Based Recommendation Generation
Given a candidate with a parsed resume and preferences, when recommendation generation is triggered, then the system shall produce a ranked list of relevant jobs.

### AC2. Explanation Display
Given a generated recommendation, when the user views it, then the UI shall display a short explanation for why it was recommended.

### AC3. Feedback Capture
Given a recommendation shown to the user, when the user saves, rejects, or hides it, then the interaction shall be recorded for future personalization.

### AC4. Top Recommendations Persisted
Given a recommendation generation run, when processing completes, then the top recommendations shall be saved in PostgreSQL.

### AC5. Degraded Operation
Given Typesense is unavailable, when recommendation generation is triggered, then the system shall either fall back gracefully or return a clear failure state without corrupting the user experience.

### AC6. Search Compatibility
Given a user is browsing jobs, when they use recommendations and manual search, then both experiences shall remain available and complementary.

## 9. Implementation Phases

### Phase 1 — Foundation
Objective: deliver a usable first version of recommendations.

Scope:
- Typesense schema extension with embeddings and ranking fields,
- candidate profile extraction from resume data,
- hybrid retrieval request,
- initial reranking service,
- persistence of top recommendations,
- basic recommendation display in the Career experience.

Success Criteria:
- a candidate can receive a recommendation list,
- the list is explainable,
- the top recommendations are stored in PostgreSQL.

### Phase 2 — Ranking and UX Refinement
Objective: improve recommendation quality and usability.

Scope:
- normalization for skills, titles, seniority, salary, and location,
- stronger validation for required skills and experience,
- richer explanation text,
- save/reject/hide interactions,
- improved UI layout and explanation presentation.

Success Criteria:
- recommendation relevance improves measurably,
- users can act on recommendations without friction,
- feedback is captured consistently.

### Phase 3 — Personalization
Objective: make recommendations adapt over time.

Scope:
- behavior-based preference signals,
- blending of profile-based and behavior-based vectors,
- more dynamic recommendation updates,
- better long-term personalization.

Success Criteria:
- recommendations improve as users interact with the system,
- positive engagement metrics increase over time.

## 10. Proposed Technical Approach

The feature will be implemented using the existing architecture:
- PostgreSQL remains the source of truth.
- Typesense handles retrieval, filtering, and hybrid search.
- A matching and reranking service handles final scoring, explanation generation, and persistence.

This keeps the implementation pragmatic and avoids introducing a second vector database in the first release.

## 11. Components to Update

### Backend
- Career job search service
- resume parsing and profile extraction flow
- recommendation matching service
- persistence and repository layer
- Career contracts and API layer if recommendations are exposed via API

### UI
- Career jobs experience
- recommendation card/list components
- explanation panel or drawer
- feedback action controls

### Infrastructure
- Typesense configuration and schema
- environment settings for embedding support
- monitoring and logging

## 12. Test Plan

### Unit Tests
- resume profile extraction
- normalization logic
- scoring weights
- explanation generation
- feedback recording

### Integration Tests
- Typesense schema creation
- indexing sample jobs with embeddings
- hybrid search request execution
- ranking result mapping
- persistence of recommendations

### End-to-End Tests
- generate recommendations from a sample resume,
- display them in the UI,
- save or reject a recommendation,
- confirm the recommendation is persisted,
- confirm the next recommendation set reflects the user’s feedback.

### Manual Validation
1. Upload a sample resume.
2. Generate recommendations.
3. Confirm the results reflect the candidate profile.
4. Verify explanations are clear and relevant.
5. Save and reject a few recommendations.
6. Confirm feedback influences subsequent recommendations.

## 13. Success Metrics

### Core Metrics
- recommendation click-through rate,
- save rate,
- apply rate,
- rejection rate,
- time-to-first-relevant-job,
- average recommendation generation time,
- percentage of recommendations with meaningful explanation text.

### Product Success Criteria
The feature will be considered successful if users:
- reach relevant jobs faster than with manual search,
- act on recommendations more often than with traditional search,
- find the explanations useful and trustworthy,
- engage with the feedback loop.

## 14. Open Questions

1. Should recommendations be generated on-demand only, or also refreshed in the background?
2. Should the initial recommendation experience be a dedicated panel or integrated into the existing search page?
3. Which explanation format will feel most useful to users: short reasons, score breakdown, or both?
4. What minimum feedback volume is needed before personalization should begin influencing recommendations materially?
