# Job Recommendation Implementation Backlog

## 1. Overview

This backlog breaks the job recommendation feature into a practical engineering plan. It is organized by workstream so backend, UI, and infrastructure work can be executed in parallel where appropriate.

The work should follow the platform profiling guidance from the builder agent:
- Career job search remains owned by the existing Career service boundary.
- PostgreSQL remains the source of truth.
- Typesense remains a service-owned derived index and must not be exposed directly to clients.
- Customer-facing AI and UI surfaces must use the backend APIs rather than writing directly to Postgres or Typesense.
- Resume import and persistence should continue to flow through the established Career profile service APIs rather than bypassing them.

## 2. Backend Backlog

### B1. Extend Job Search Indexing for Hybrid Retrieval
- Update the Typesense job collection schema to include:
  - embedding field,
  - freshness scoring field,
  - quality ranking field,
  - any additional metadata needed for reranking.
- Ensure the indexed document model includes these fields.
- Verify existing job upsert flow writes the new fields correctly.
- Keep this work inside the existing Career job search implementation and do not introduce a parallel indexing path.

Profile-alignment note:
- This task must stay behind the Career service boundary and use the existing service-owned job indexing flow.

Acceptance criteria:
- Jobs can be indexed with semantic fields.
- Existing job search still works without breaking current filters.

### B2. Add Candidate Profile Builder
- Create a service that builds a normalized candidate profile from resume data.
- Use existing resume parsing output as the source.
- Include fields such as target titles, skills, seniority, preferences, and recent work summary.
- Ensure the profile is derived from the authenticated customer’s owned resume/profile records rather than from untrusted client input.

Profile-alignment note:
- Resume parsing and profile creation should remain service-owned and should not be implemented as a client-side or AI-side bypass.

Acceptance criteria:
- A parsed resume produces a structured profile object.
- The profile can be used as input to embedding generation.

### B3. Add Embedding Generation Flow
- Add a candidate embedding generation step for recommendation runs.
- Support a simple first-version embedding approach that does not require introducing a new vector database.
- Ensure the generated embedding is passed into the retrieval request.
- Keep embedding generation server-side and configurable through backend settings.

Profile-alignment note:
- Embedding generation should not expose the model or vector data to the UI or agent surfaces directly.

Acceptance criteria:
- A recommendation request produces a candidate embedding.
- The embedding is included in the Typesense retrieval request.

### B4. Implement Hybrid Search Request
- Extend the existing job search client to send hybrid search requests.
- Combine:
  - keyword search,
  - semantic similarity,
  - filters,
  - ranking fields.
- Keep the request backward compatible with the existing search flow.

Acceptance criteria:
- The system can retrieve a shortlist of jobs using hybrid retrieval.
- Existing search behavior remains intact.

### B5. Add Matching and Reranking Service
- Implement a recommendation service that:
  - receives retrieved jobs,
  - applies scoring weights,
  - validates required skills and experience,
  - builds explanation text,
  - ranks the final results.
- Keep the ranking logic deterministic and auditable so the reasons can be explained clearly.

Profile-alignment note:
- This service should enforce the same ownership and authorization rules as the rest of the Career backend.

Acceptance criteria:
- The service produces a ranked list of recommended jobs.
- Explanation text is generated for each result.

### B6. Add Recommendation Persistence
- Create persistence support for stored recommendations.
- Save the top recommendations for each candidate in PostgreSQL.
- Store score breakdown and explanation text.
- Ensure recommendations remain scoped to the authenticated customer and do not leak across accounts.

Profile-alignment note:
- Recommendation persistence should be implemented through the backend service layer and use the authenticated customer context.

Acceptance criteria:
- Recommendation results are stored durably.
- The stored data can be queried later for display or feedback.

### B7. Add Feedback Recording
- Capture user actions such as save, reject, hide, view, and apply.
- Persist feedback in a way that can be used for future personalization.
- Store only the minimum necessary metadata for feedback analysis and do not persist sensitive or unnecessary user content.

Profile-alignment note:
- Feedback should be recorded by the service layer, not by the frontend or AI tool directly.

Acceptance criteria:
- User feedback is stored and associated with the relevant recommendation.
- Feedback can be queried for analysis.

### B8. Add Recommendation API or Service Endpoint
- Expose recommendation generation through the appropriate backend boundary.
- If needed, add RPCs or API wiring in the Career service layer.
- Ensure the API requires authenticated customer context and does not allow arbitrary customer id overrides.

Profile-alignment note:
- Any API exposure should be routed through existing Career backend contracts and ownership checks.

Acceptance criteria:
- A client can trigger recommendation generation through the platform API boundary.
- The service returns recommendations with explanations.

## 3. UI Backlog

### U1. Add Recommendation Section to Career Jobs Experience
- Add a new recommendation section or panel to the Career jobs experience.
- Place it prominently above or beside standard search results.
- Keep the UI experience aligned with the same-origin API bridge pattern used by the customer UI.

Profile-alignment note:
- The customer UI should consume recommendations through the backend API boundary and should not call Typesense or other internal services directly.

Acceptance criteria:
- Users can see recommendations when they open the Career jobs experience.
- The recommendations are visually distinct from traditional search results.

### U2. Render Recommendation Cards
- Create UI components for recommendation cards with:
  - title,
  - company,
  - summary,
  - match explanation,
  - actions such as save or dismiss.

Acceptance criteria:
- Each recommendation is displayed with relevant metadata.
- Users can quickly understand why a job was shown.

### U3. Add Explanation Display
- Show a short explanation for each recommendation.
- Keep the explanation concise and user-friendly.

Acceptance criteria:
- Users can read why a recommendation was surfaced.
- The explanation does not overwhelm the card layout.

### U4. Add Recommendation Actions
- Add buttons or actions for:
  - view details,
  - save,
  - reject,
  - hide.
- Ensure these interactions are routed through the backend so feedback is captured consistently and securely.

Profile-alignment note:
- UI actions must not bypass the backend ownership model or write directly to storage.

Acceptance criteria:
- Users can act on recommendations without leaving the page.
- Actions are reflected in the backend state.

### U5. Connect Recommendations to Search Flow
- Ensure recommendations and search remain complementary.
- Allow users to use filters and manual search while still seeing recommendations.

Acceptance criteria:
- Users can move between recommendation browsing and manual search without confusion.

## 4. Infrastructure and DevOps Backlog

### I1. Configure Typesense for Vector Support
- Verify that the existing Typesense deployment supports the required schema fields and vector capabilities.
- Update deployment documentation if needed.
- Keep Typesense access server-side and treat it as internal derived infrastructure.

Profile-alignment note:
- Secrets and API keys must remain server-side and never be exposed to browser clients or AI surfaces.

Acceptance criteria:
- The Typesense environment can host the new collection schema.
- The feature works in the configured environment.

### I2. Add Environment Configuration
- Add any needed environment variables for:
  - embedding configuration,
  - recommendation feature toggle,
  - retrieval settings.
- Keep configuration names consistent with the existing service environment conventions.

Profile-alignment note:
- Environment variables should be configured in the backend service environment, not in client-side bundles.

Acceptance criteria:
- The service can be configured without code changes.
- Feature flags can be toggled safely.

### I3. Add Logging and Monitoring
- Add logging for recommendation generation runs.
- Track retrieval latency, ranking failures, persistence errors, and feedback events.

Acceptance criteria:
- Engineering can troubleshoot recommendation runs using logs.
- Key performance and quality signals are observable.

## 5. Suggested Delivery Order

1. Backend indexing and profile extraction
2. Hybrid retrieval and initial reranking
3. Recommendation persistence
4. Basic UI rendering and explanation display
5. Feedback actions and personalization foundation

## 6. Definition of Done

The first release is done when:
- a candidate can receive a recommendation list from their resume profile,
- the results are explainable,
- the top recommendations are persisted,
- users can act on them through the UI,
- the feature can be tested and monitored in the current environment,
- the implementation follows the builder-agent ownership model,
- customer data remains scoped to the authenticated user,
- no frontend or AI surface bypasses the backend service boundary.
