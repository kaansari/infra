# Database object model catalog

Verified on 2026-10-07 from the local `public` schema after all 16 migrations.
Hosted deployments use `ceerat`; this is a physical local schema inventory, not
a claim that Render has been migrated. It contains metadata only, no row values.

See [architecture](database-architecture.md) and [operations](database-create-restore.md).

46 tables. Go models live in `services-repo/services/ceerat-user-service/internal/models/models.go`
and `preferences/repository.go`; SQL constraints and the checksum ledger are authoritative.

## Table index

- [ai_thread_messages](#ai_thread_messages) — `AIThreadMessageEntity`
- [ai_threads](#ai_threads) — `AIThreadEntity`
- [calendar_events](#calendar_events) — `CalendarEventEntity`
- [career_market_metrics](#career_market_metrics) — `CareerMarketMetricsEntity`
- [cart_idempotency_keys](#cart_idempotency_keys) — `CartIdempotencyKeyEntity`
- [cart_items](#cart_items) — `CartItemEntity`
- [carts](#carts) — `CartEntity`
- [catalog_discounts](#catalog_discounts) — `CatalogDiscountEntity`
- [catalog_image_contents](#catalog_image_contents) — `CatalogImageContentEntity`
- [catalog_images](#catalog_images) — `CatalogImageEntity`
- [companies](#companies) — `CompanyEntity`
- [customer_career_metrics](#customer_career_metrics) — `CustomerCareerMetricsEntity`
- [customer_preference_history](#customer_preference_history) — `HistoryRow`
- [customer_preference_profiles](#customer_preference_profiles) — `ProfileRow`
- [customer_preferences](#customer_preferences) — `PreferenceRow`
- [customer_services](#customer_services) — `CustomerServiceEntity`
- [customers](#customers) — `CustomerEntity`
- [employment_records](#employment_records) — `EmploymentRecordEntity`
- [external_identities](#external_identities) — `ExternalIdentityEntity`
- [job_application_submissions](#job_application_submissions) — `JobApplicationSubmissionEntity`
- [job_applications](#job_applications) — `JobApplicationEntity`
- [job_cart_items](#job_cart_items) — `JobCartItemEntity`
- [job_carts](#job_carts) — `JobCartEntity`
- [jobs](#jobs) — `JobEntity`
- [order_operations](#order_operations) — `OrderOperationEntity`
- [order_pricing_rules](#order_pricing_rules) — `OrderPricingRuleEntity`
- [order_products](#order_products) — `OrderProductEntity`
- [order_services](#order_services) — `OrderServiceEntity`
- [orders](#orders) — `OrderEntity`
- [payment_sessions](#payment_sessions) — `PaymentSessionEntity`
- [preference_definitions](#preference_definitions) — `DefinitionRow`
- [preference_operations](#preference_operations) — `OperationRow`
- [product_categories](#product_categories) — `ProductCategoryEntity`
- [product_category_assignments](#product_category_assignments) — `ProductCategoryAssignmentEntity`
- [product_variants](#product_variants) — `ProductVariantEntity`
- [resume_employment_records](#resume_employment_records) — `ResumeEmploymentRecordEntity`
- [resumes](#resumes) — `ResumeEntity`
- [role_permissions](#role_permissions) — `RolePermissionEntity`
- [roles](#roles) — `RoleEntity`
- [schema_migration_lock](#schema_migration_lock) — `Migration lease`
- [schema_migrations](#schema_migrations) — `Migration ledger`
- [services](#services) — `ServiceEntity`
- [skill_profile_skills](#skill_profile_skills) — `SkillProfileSkillEntity`
- [skill_profiles](#skill_profiles) — `SkillProfileEntity`
- [skills](#skills) — `SkillEntity`
- [users](#users) — `UserEntity`

## ai_thread_messages

Model: `AIThreadMessageEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `thread_id` | `text` | no | `—` |
| `user_id` | `text` | no | `—` |
| `profile` | `text` | no | `—` |
| `role` | `text` | no | `—` |
| `content` | `text` | no | `—` |
| `metadata_json` | `jsonb` | no | `'{}'::jsonb` |
| `created_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `ai_thread_messages_pkey`: `PRIMARY KEY (id)`
- `fk_ai_thread_messages_user`: `FOREIGN KEY (user_id) REFERENCES users(id)`
- `fk_ai_threads_messages`: `FOREIGN KEY (thread_id) REFERENCES ai_threads(id) ON DELETE CASCADE`

Indexes:

- `CREATE UNIQUE INDEX ai_thread_messages_pkey ON public.ai_thread_messages USING btree (id)`
- `CREATE INDEX idx_ai_thread_messages_thread_created ON public.ai_thread_messages USING btree (thread_id, created_at)`
- `CREATE INDEX idx_ai_thread_messages_user_profile_created ON public.ai_thread_messages USING btree (user_id, profile, created_at DESC)`

## ai_threads

Model: `AIThreadEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `user_id` | `text` | no | `—` |
| `profile` | `text` | no | `—` |
| `external_thread_id` | `text` | no | `—` |
| `title` | `text` | no | `''::text` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `ai_threads_pkey`: `PRIMARY KEY (id)`
- `fk_ai_threads_user`: `FOREIGN KEY (user_id) REFERENCES users(id)`

Indexes:

- `CREATE UNIQUE INDEX ai_threads_pkey ON public.ai_threads USING btree (id)`
- `CREATE UNIQUE INDEX idx_ai_thread_identity ON public.ai_threads USING btree (user_id, profile, external_thread_id)`
- `CREATE INDEX idx_ai_threads_user_profile_updated ON public.ai_threads USING btree (user_id, profile, updated_at DESC)`

## calendar_events

Model: `CalendarEventEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `title` | `text` | no | `—` |
| `description` | `text` | yes | `—` |
| `event_type` | `text` | no | `—` |
| `starts_at` | `timestamp with time zone` | no | `—` |
| `ends_at` | `timestamp with time zone` | no | `—` |
| `timezone` | `text` | yes | `—` |
| `location` | `text` | yes | `—` |
| `meeting_url` | `text` | yes | `—` |
| `related_entity_type` | `text` | yes | `—` |
| `related_entity_id` | `text` | yes | `—` |
| `job_id` | `text` | yes | `—` |
| `job_title` | `text` | yes | `—` |
| `company` | `text` | yes | `—` |
| `reminder_minutes_before` | `integer` | yes | `—` |
| `status` | `text` | no | `'scheduled'::text` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `calendar_events_pkey`: `PRIMARY KEY (id)`
- `fk_calendar_events_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`

Indexes:

- `CREATE UNIQUE INDEX calendar_events_pkey ON public.calendar_events USING btree (id)`
- `CREATE INDEX idx_calendar_events_customer_id ON public.calendar_events USING btree (customer_id)`
- `CREATE INDEX idx_calendar_events_ends_at ON public.calendar_events USING btree (ends_at)`
- `CREATE INDEX idx_calendar_events_event_type ON public.calendar_events USING btree (event_type)`
- `CREATE INDEX idx_calendar_events_job_id ON public.calendar_events USING btree (job_id)`
- `CREATE INDEX idx_calendar_events_related_entity_id ON public.calendar_events USING btree (related_entity_id)`
- `CREATE INDEX idx_calendar_events_related_entity_type ON public.calendar_events USING btree (related_entity_type)`
- `CREATE INDEX idx_calendar_events_starts_at ON public.calendar_events USING btree (starts_at)`
- `CREATE INDEX idx_calendar_events_status ON public.calendar_events USING btree (status)`

## career_market_metrics

Model: `CareerMarketMetricsEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `scope_type` | `text` | no | `—` |
| `scope_id` | `text` | no | `—` |
| `metric_date` | `text` | no | `—` |
| `available_jobs` | `bigint` | yes | `—` |
| `company_count` | `bigint` | yes | `—` |
| `job_type_count` | `bigint` | yes | `—` |
| `remote_job_count` | `bigint` | yes | `—` |
| `jobs_by_month_json` | `text` | yes | `—` |
| `jobs_by_type_json` | `text` | yes | `—` |
| `jobs_by_location_json` | `text` | yes | `—` |
| `jobs_by_company_json` | `text` | yes | `—` |
| `jobs_by_source_json` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `career_market_metrics_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX career_market_metrics_pkey ON public.career_market_metrics USING btree (id)`
- `CREATE UNIQUE INDEX idx_career_market_metrics_scope ON public.career_market_metrics USING btree (scope_type, scope_id, metric_date)`

## cart_idempotency_keys

Model: `CartIdempotencyKeyEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `operation` | `text` | no | `—` |
| `idempotency_key` | `character varying(128)` | no | `—` |
| `request_hash` | `character(64)` | no | `—` |
| `state` | `text` | no | `—` |
| `result_cart_id` | `text` | no | `—` |
| `result_cart_version` | `bigint` | no | `0` |
| `expires_at` | `timestamp with time zone` | no | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `cart_idempotency_cart_fk`: `FOREIGN KEY (result_cart_id) REFERENCES carts(id) ON DELETE CASCADE`
- `cart_idempotency_customer_fk`: `FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE`
- `cart_idempotency_key_length_check`: `CHECK (((char_length((idempotency_key)::text) >= 1) AND (char_length((idempotency_key)::text) <= 128)))`
- `cart_idempotency_keys_pkey`: `PRIMARY KEY (id)`
- `cart_idempotency_operation_check`: `CHECK ((operation = ANY (ARRAY['add'::text, 'update'::text, 'remove'::text, 'clear'::text])))`
- `cart_idempotency_request_hash_check`: `CHECK ((request_hash ~ '^[0-9a-f]{64}$'::text))`
- `cart_idempotency_state_check`: `CHECK ((state = ANY (ARRAY['in_progress'::text, 'completed'::text])))`
- `cart_idempotency_unique`: `UNIQUE (customer_id, operation, idempotency_key)`

Indexes:

- `CREATE UNIQUE INDEX cart_idempotency_keys_pkey ON public.cart_idempotency_keys USING btree (id)`
- `CREATE UNIQUE INDEX cart_idempotency_unique ON public.cart_idempotency_keys USING btree (customer_id, operation, idempotency_key)`
- `CREATE INDEX idx_cart_idempotency_customer ON public.cart_idempotency_keys USING btree (customer_id)`
- `CREATE INDEX idx_cart_idempotency_expiry ON public.cart_idempotency_keys USING btree (expires_at)`
- `CREATE INDEX idx_cart_idempotency_reconciliation ON public.cart_idempotency_keys USING btree (state, updated_at) WHERE (state = 'in_progress'::text)`
- `CREATE UNIQUE INDEX idx_cart_idempotency_unique ON public.cart_idempotency_keys USING btree (customer_id, operation, idempotency_key)`

## cart_items

Model: `CartItemEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `cart_id` | `text` | no | `—` |
| `item_type` | `text` | no | `—` |
| `service_id` | `text` | yes | `—` |
| `product_id` | `text` | yes | `—` |
| `product_variant_id` | `text` | yes | `—` |
| `quantity` | `integer` | no | `1` |
| `unit_price_minor_units` | `bigint` | no | `0` |
| `list_price_minor_units` | `bigint` | no | `0` |
| `discount_basis_points` | `integer` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `discount_label` | `text` | yes | `—` |
| `clearance` | `boolean` | no | `false` |
| `closeout` | `boolean` | no | `false` |
| `total_price_minor_units` | `bigint` | no | `0` |
| `notes` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `cart_items_pkey`: `PRIMARY KEY (id)`
- `fk_cart_items_product`: `FOREIGN KEY (product_id) REFERENCES services(id)`
- `fk_cart_items_product_variant`: `FOREIGN KEY (product_variant_id) REFERENCES product_variants(id)`
- `fk_cart_items_service`: `FOREIGN KEY (service_id) REFERENCES services(id)`
- `fk_carts_items`: `FOREIGN KEY (cart_id) REFERENCES carts(id)`

Indexes:

- `CREATE UNIQUE INDEX cart_items_pkey ON public.cart_items USING btree (id)`
- `CREATE INDEX idx_cart_items_cart_id ON public.cart_items USING btree (cart_id)`
- `CREATE INDEX idx_cart_items_item_type ON public.cart_items USING btree (item_type)`
- `CREATE INDEX idx_cart_items_product_id ON public.cart_items USING btree (product_id)`
- `CREATE INDEX idx_cart_items_product_variant_id ON public.cart_items USING btree (product_variant_id)`
- `CREATE INDEX idx_cart_items_service_id ON public.cart_items USING btree (service_id)`

## carts

Model: `CartEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `subtotal_minor_units` | `bigint` | no | `0` |
| `total_minor_units` | `bigint` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `version` | `bigint` | no | `1` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `carts_pkey`: `PRIMARY KEY (id)`
- `fk_carts_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`

Indexes:

- `CREATE UNIQUE INDEX carts_pkey ON public.carts USING btree (id)`
- `CREATE UNIQUE INDEX idx_carts_customer_id ON public.carts USING btree (customer_id)`

## catalog_discounts

Model: `CatalogDiscountEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `scope` | `text` | no | `—` |
| `target_id` | `text` | yes | `—` |
| `percentage_basis_points` | `integer` | no | `0` |
| `active` | `boolean` | no | `true` |
| `starts_at` | `timestamp with time zone` | yes | `—` |
| `ends_at` | `timestamp with time zone` | yes | `—` |
| `closeout` | `boolean` | no | `false` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `catalog_discounts_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX catalog_discounts_pkey ON public.catalog_discounts USING btree (id)`
- `CREATE INDEX idx_catalog_discounts_active ON public.catalog_discounts USING btree (active)`
- `CREATE INDEX idx_catalog_discounts_ends_at ON public.catalog_discounts USING btree (ends_at)`
- `CREATE INDEX idx_catalog_discounts_scope_target ON public.catalog_discounts USING btree (scope, target_id)`
- `CREATE INDEX idx_catalog_discounts_starts_at ON public.catalog_discounts USING btree (starts_at)`

## catalog_image_contents

Model: `CatalogImageContentEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `image_id` | `text` | no | `—` |
| `data` | `bytea` | no | `—` |

Constraints:

- `catalog_image_contents_pkey`: `PRIMARY KEY (image_id)`

Indexes:

- `CREATE UNIQUE INDEX catalog_image_contents_pkey ON public.catalog_image_contents USING btree (image_id)`

## catalog_images

Model: `CatalogImageEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `owner_type` | `text` | no | `—` |
| `owner_id` | `text` | no | `—` |
| `file_name` | `text` | no | `—` |
| `content_type` | `text` | no | `—` |
| `size_bytes` | `bigint` | no | `—` |
| `sort_order` | `integer` | no | `0` |
| `is_primary` | `boolean` | no | `false` |
| `created_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `catalog_images_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX catalog_images_pkey ON public.catalog_images USING btree (id)`
- `CREATE INDEX idx_catalog_images_owner ON public.catalog_images USING btree (owner_type, owner_id)`
- `CREATE INDEX idx_catalog_images_primary ON public.catalog_images USING btree (is_primary)`

## companies

Model: `CompanyEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `website` | `text` | yes | `—` |
| `description` | `text` | yes | `—` |
| `industry` | `text` | yes | `—` |
| `location` | `text` | yes | `—` |
| `source` | `text` | yes | `—` |
| `external_id` | `text` | yes | `—` |
| `source_url` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `companies_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX companies_pkey ON public.companies USING btree (id)`
- `CREATE INDEX idx_companies_external_id ON public.companies USING btree (external_id)`
- `CREATE INDEX idx_companies_industry ON public.companies USING btree (industry)`
- `CREATE INDEX idx_companies_location ON public.companies USING btree (location)`
- `CREATE INDEX idx_companies_name ON public.companies USING btree (name)`
- `CREATE INDEX idx_companies_source ON public.companies USING btree (source)`

## customer_career_metrics

Model: `CustomerCareerMetricsEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `metric_date` | `text` | no | `—` |
| `saved_jobs` | `bigint` | yes | `—` |
| `active_resumes` | `bigint` | yes | `—` |
| `skill_profiles` | `bigint` | yes | `—` |
| `applications` | `bigint` | yes | `—` |
| `applications_by_status_json` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `customer_career_metrics_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX customer_career_metrics_pkey ON public.customer_career_metrics USING btree (id)`
- `CREATE UNIQUE INDEX idx_customer_career_metrics_scope ON public.customer_career_metrics USING btree (customer_id, metric_date)`

## customer_preference_history

Model: `HistoryRow`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `preference_id` | `text` | no | `—` |
| `operation_id` | `text` | yes | `—` |
| `change_kind` | `character varying(16)` | no | `—` |
| `before_digest` | `character(64)` | no | `''::bpchar` |
| `after_digest` | `character(64)` | no | `''::bpchar` |
| `preference_version` | `bigint` | no | `—` |
| `profile_version` | `bigint` | no | `—` |
| `actor_subject_digest` | `character(64)` | no | `—` |
| `oauth_client_id` | `character varying(128)` | no | `—` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `retain_until` | `timestamp with time zone` | no | `—` |

Constraints:

- `customer_preference_history_customer_id_fkey`: `FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE`
- `customer_preference_history_kind_check`: `CHECK (((change_kind)::text = ANY ((ARRAY['created'::character varying, 'updated'::character varying, 'deleted'::character varying])::text[])))`
- `customer_preference_history_operation_id_fkey`: `FOREIGN KEY (operation_id) REFERENCES preference_operations(id)`
- `customer_preference_history_owned_operation_fkey`: `FOREIGN KEY (customer_id, operation_id) REFERENCES preference_operations(customer_id, id)`
- `customer_preference_history_pkey`: `PRIMARY KEY (id)`
- `customer_preference_history_shape_check`: `CHECK ((preference_opaque_valid(id) AND preference_opaque_valid(customer_id) AND preference_opaque_valid(preference_id) AND ((operation_id IS NULL) OR preference_opaque_valid(operation_id)) AND ((before_digest = ''::bpchar) OR (before_digest ~ '^[a-f0-9]{64}$'::text)) AND ((after_digest = ''::bpchar) OR (after_digest ~ '^[a-f0-9]{64}$'::text)) AND (actor_subject_digest ~ '^[a-f0-9]{64}$'::text) AND preference_opaque_valid((oauth_client_id)::text) AND isfinite(retain_until)))`
- `customer_preference_history_version_check`: `CHECK (((preference_version >= 1) AND (profile_version >= 1)))`

Indexes:

- `CREATE UNIQUE INDEX customer_preference_history_pkey ON public.customer_preference_history USING btree (id)`
- `CREATE INDEX idx_preference_history_customer ON public.customer_preference_history USING btree (customer_id, created_at DESC, id DESC)`
- `CREATE INDEX idx_preference_history_operation ON public.customer_preference_history USING btree (operation_id) WHERE (operation_id IS NOT NULL)`
- `CREATE INDEX idx_preference_history_retention ON public.customer_preference_history USING btree (retain_until)`

## customer_preference_profiles

Model: `ProfileRow`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `customer_id` | `text` | no | `—` |
| `version` | `bigint` | no | `1` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `customer_preference_profiles_customer_id_fkey`: `FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE`
- `customer_preference_profiles_identity_check`: `CHECK (preference_opaque_valid(customer_id))`
- `customer_preference_profiles_pkey`: `PRIMARY KEY (customer_id)`
- `customer_preference_profiles_version_check`: `CHECK ((version >= 1))`

Indexes:

- `CREATE UNIQUE INDEX customer_preference_profiles_pkey ON public.customer_preference_profiles USING btree (customer_id)`

## customer_preferences

Model: `PreferenceRow`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `definition_id` | `text` | yes | `—` |
| `preference_key` | `character varying(128)` | no | `—` |
| `category` | `character varying(64)` | no | `—` |
| `display_name` | `character varying(128)` | no | `—` |
| `level` | `smallint` | no | `—` |
| `value_kind` | `character varying(16)` | no | `—` |
| `text_value` | `character varying(1024)` | yes | `—` |
| `bool_value` | `boolean` | yes | `—` |
| `integer_value` | `bigint` | yes | `—` |
| `decimal_value` | `character varying(64)` | yes | `—` |
| `money_minor_units` | `bigint` | yes | `—` |
| `money_currency` | `character(3)` | yes | `—` |
| `option_value` | `character varying(128)` | yes | `—` |
| `option_values` | `text[]` | yes | `—` |
| `scope_kind` | `character varying(16)` | no | `—` |
| `context_key` | `character varying(128)` | no | `''::character varying` |
| `entity_type` | `character varying(128)` | no | `''::character varying` |
| `entity_id` | `character varying(128)` | no | `''::character varying` |
| `enabled` | `boolean` | no | `true` |
| `is_custom` | `boolean` | no | `false` |
| `version` | `bigint` | no | `1` |
| `definition_version` | `bigint` | no | `1` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `customer_preferences_custom_check`: `CHECK (((is_custom AND ((preference_key)::text ~~ 'custom.%'::text) AND (definition_id IS NULL)) OR ((NOT is_custom) AND (definition_id IS NOT NULL))))`
- `customer_preferences_customer_id_fkey`: `FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE`
- `customer_preferences_definition_id_fkey`: `FOREIGN KEY (definition_id) REFERENCES preference_definitions(id)`
- `customer_preferences_kind_check`: `CHECK (((value_kind)::text = ANY ((ARRAY['text'::character varying, 'boolean'::character varying, 'integer'::character varying, 'decimal'::character varying, 'money'::character varying, 'option'::character varying, 'options'::character varying])::text[])))`
- `customer_preferences_level_check`: `CHECK (((level >= 1) AND (level <= 5)))`
- `customer_preferences_pkey`: `PRIMARY KEY (id)`
- `customer_preferences_scope_check`: `CHECK (((((scope_kind)::text = 'global'::text) AND ((context_key)::text = ''::text) AND ((entity_type)::text = ''::text) AND ((entity_id)::text = ''::text)) OR (((scope_kind)::text = 'context'::text) AND ((context_key)::text <> ''::text) AND ((entity_type)::text = ''::text) AND ((entity_id)::text = ''::text)) OR (((scope_kind)::text = 'entity'::text) AND ((context_key)::text = ''::text) AND ((entity_type)::text <> ''::text) AND ((entity_id)::text <> ''::text))))`
- `customer_preferences_shape_check`: `CHECK ((preference_opaque_valid(id) AND preference_opaque_valid(customer_id) AND ((definition_id IS NULL) OR preference_opaque_valid(definition_id)) AND (octet_length((preference_key)::text) <= 128) AND ((preference_key)::text ~ '^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$'::text) AND ((category)::text = ANY (ARRAY['general'::text, 'communication'::text, 'recommendations'::text, 'food'::text, 'restaurants'::text, 'shopping'::text, 'home'::text, 'travel'::text, 'vehicles'::text, 'jobs'::text, 'technology'::text, 'real_estate'::text, 'entertainment'::text, 'services'::text, 'markets'::text])) AND preference_text_valid((display_name)::text, 128, true) AND ((is_custom AND ((preference_key)::text ~ (('^custom\.'::text || (category)::text) || '\.[a-z][a-z0-9_-]*$'::text)) AND ((category)::text <> 'markets'::text)) OR ((NOT is_custom) AND ((preference_key)::text !~~ 'custom.%'::text))) AND (((scope_kind)::text <> 'context'::text) OR preference_opaque_valid((context_key)::text)) AND (((scope_kind)::text <> 'entity'::text) OR (preference_opaque_valid((entity_type)::text) AND preference_opaque_valid((entity_id)::text)))))`
- `customer_preferences_value_bounds_check`: `CHECK ( CASE value_kind     WHEN 'text'::text THEN preference_text_valid((text_value)::text, 1024, true)     WHEN 'decimal'::text THEN ((octet_length((decimal_value)::text) <= 64) AND ((decimal_value)::text ~ '^-?(0|[1-9][0-9]*)(\.[0-9]*[1-9])?$'::text) AND ((decimal_value)::text <> '-0'::text))     WHEN 'money'::text THEN ((money_minor_units >= 0) AND (money_currency IS NOT NULL) AND (money_currency = 'USD'::bpchar))     WHEN 'option'::text THEN preference_opaque_valid((option_value)::text)     WHEN 'options'::text THEN ((cardinality(option_values) > 0) AND preference_tokens_valid(option_values, 32))     ELSE true END)`
- `customer_preferences_value_check`: `CHECK (((((value_kind)::text = 'text'::text) AND (text_value IS NOT NULL) AND (bool_value IS NULL) AND (integer_value IS NULL) AND (decimal_value IS NULL) AND (money_minor_units IS NULL) AND (money_currency IS NULL) AND (option_value IS NULL) AND (option_values IS NULL)) OR (((value_kind)::text = 'boolean'::text) AND (bool_value IS NOT NULL) AND (text_value IS NULL) AND (integer_value IS NULL) AND (decimal_value IS NULL) AND (money_minor_units IS NULL) AND (money_currency IS NULL) AND (option_value IS NULL) AND (option_values IS NULL)) OR (((value_kind)::text = 'integer'::text) AND (integer_value IS NOT NULL) AND (text_value IS NULL) AND (bool_value IS NULL) AND (decimal_value IS NULL) AND (money_minor_units IS NULL) AND (money_currency IS NULL) AND (option_value IS NULL) AND (option_values IS NULL)) OR (((value_kind)::text = 'decimal'::text) AND (decimal_value IS NOT NULL) AND ((decimal_value)::text ~ '^-?[0-9]+(\.[0-9]+)?$'::text) AND (text_value IS NULL) AND (bool_value IS NULL) AND (integer_value IS NULL) AND (money_minor_units IS NULL) AND (money_currency IS NULL) AND (option_value IS NULL) AND (option_values IS NULL)) OR (((value_kind)::text = 'money'::text) AND (money_minor_units IS NOT NULL) AND (money_currency ~ '^[A-Z]{3}$'::text) AND (text_value IS NULL) AND (bool_value IS NULL) AND (integer_value IS NULL) AND (decimal_value IS NULL) AND (option_value IS NULL) AND (option_values IS NULL)) OR (((value_kind)::text = 'option'::text) AND (option_value IS NOT NULL) AND (text_value IS NULL) AND (bool_value IS NULL) AND (integer_value IS NULL) AND (decimal_value IS NULL) AND (money_minor_units IS NULL) AND (money_currency IS NULL) AND (option_values IS NULL)) OR (((value_kind)::text = 'options'::text) AND (option_values IS NOT NULL) AND ((cardinality(option_values) >= 1) AND (cardinality(option_values) <= 32)) AND (text_value IS NULL) AND (bool_value IS NULL) AND (integer_value IS NULL) AND (decimal_value IS NULL) AND (money_minor_units IS NULL) AND (money_currency IS NULL) AND (option_value IS NULL))))`
- `customer_preferences_version_check`: `CHECK (((version >= 1) AND ((is_custom AND (definition_version = 0)) OR ((NOT is_custom) AND (definition_version >= 1)))))`

Indexes:

- `CREATE UNIQUE INDEX customer_preferences_logical_unique ON public.customer_preferences USING btree (customer_id, preference_key, scope_kind, context_key, entity_type, entity_id)`
- `CREATE UNIQUE INDEX customer_preferences_pkey ON public.customer_preferences USING btree (id)`
- `CREATE INDEX idx_customer_preferences_context ON public.customer_preferences USING btree (customer_id, category, scope_kind, context_key, entity_type, entity_id) WHERE enabled`
- `CREATE INDEX idx_customer_preferences_page ON public.customer_preferences USING btree (customer_id, updated_at DESC, id DESC)`

## customer_services

Model: `CustomerServiceEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | yes | `—` |
| `service_id` | `text` | yes | `—` |
| `status` | `text` | yes | `—` |
| `ordered_at` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `customer_services_pkey`: `PRIMARY KEY (id)`
- `fk_customer_services_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`
- `fk_customer_services_service`: `FOREIGN KEY (service_id) REFERENCES services(id)`

Indexes:

- `CREATE UNIQUE INDEX customer_services_pkey ON public.customer_services USING btree (id)`
- `CREATE INDEX idx_customer_services_customer_id ON public.customer_services USING btree (customer_id)`
- `CREATE INDEX idx_customer_services_service_id ON public.customer_services USING btree (service_id)`

## customers

Model: `CustomerEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `first_name` | `text` | yes | `—` |
| `last_name` | `text` | yes | `—` |
| `email` | `text` | yes | `—` |
| `phone` | `text` | yes | `—` |
| `address_line1` | `text` | yes | `—` |
| `address_line2` | `text` | yes | `—` |
| `address_city` | `text` | yes | `—` |
| `address_state` | `text` | yes | `—` |
| `address_country` | `text` | yes | `—` |
| `address_postal_code` | `text` | yes | `—` |
| `shipping_address_line1` | `text` | yes | `—` |
| `shipping_address_line2` | `text` | yes | `—` |
| `shipping_address_city` | `text` | yes | `—` |
| `shipping_address_state` | `text` | yes | `—` |
| `shipping_address_country` | `text` | yes | `—` |
| `shipping_address_postal_code` | `text` | yes | `—` |
| `billing_address_line1` | `text` | yes | `—` |
| `billing_address_line2` | `text` | yes | `—` |
| `billing_address_city` | `text` | yes | `—` |
| `billing_address_state` | `text` | yes | `—` |
| `billing_address_country` | `text` | yes | `—` |
| `billing_address_postal_code` | `text` | yes | `—` |
| `user_id` | `text` | yes | `—` |
| `version` | `bigint` | no | `1` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `customers_pkey`: `PRIMARY KEY (id)`
- `fk_customers_user`: `FOREIGN KEY (user_id) REFERENCES users(id)`

Indexes:

- `CREATE UNIQUE INDEX customers_pkey ON public.customers USING btree (id)`
- `CREATE UNIQUE INDEX idx_customers_user_id_unique ON public.customers USING btree (user_id) WHERE (user_id <> ''::text)`

## employment_records

Model: `EmploymentRecordEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `company_name` | `text` | no | `—` |
| `title` | `text` | no | `—` |
| `location` | `text` | yes | `—` |
| `start_date` | `text` | yes | `—` |
| `end_date` | `text` | yes | `—` |
| `is_current` | `boolean` | yes | `—` |
| `summary` | `text` | yes | `—` |
| `employment_type` | `text` | yes | `—` |
| `status` | `text` | no | `'active'::text` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `employment_records_pkey`: `PRIMARY KEY (id)`
- `fk_employment_records_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`

Indexes:

- `CREATE UNIQUE INDEX employment_records_pkey ON public.employment_records USING btree (id)`
- `CREATE INDEX idx_employment_records_customer_id ON public.employment_records USING btree (customer_id)`
- `CREATE INDEX idx_employment_records_employment_type ON public.employment_records USING btree (employment_type)`
- `CREATE INDEX idx_employment_records_is_current ON public.employment_records USING btree (is_current)`
- `CREATE INDEX idx_employment_records_status ON public.employment_records USING btree (status)`

## external_identities

Model: `ExternalIdentityEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `issuer` | `text` | no | `—` |
| `subject` | `text` | no | `—` |
| `user_id` | `text` | no | `—` |
| `email` | `text` | no | `—` |
| `client_id` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `external_identities_pkey`: `PRIMARY KEY (id)`
- `fk_external_identities_user`: `FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE`

Indexes:

- `CREATE UNIQUE INDEX external_identities_pkey ON public.external_identities USING btree (id)`
- `CREATE INDEX idx_external_identities_user_id ON public.external_identities USING btree (user_id)`
- `CREATE UNIQUE INDEX idx_external_identity_subject ON public.external_identities USING btree (issuer, subject)`
- `CREATE UNIQUE INDEX idx_external_identity_subject_unique ON public.external_identities USING btree (issuer, subject)`

## job_application_submissions

Model: `JobApplicationSubmissionEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `job_application_id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `job_id` | `text` | no | `—` |
| `provider` | `text` | yes | `—` |
| `provider_job_id` | `text` | yes | `—` |
| `provider_submission_id` | `text` | yes | `—` |
| `provider_status` | `text` | yes | `—` |
| `application_url` | `text` | yes | `—` |
| `request_summary_json` | `text` | yes | `—` |
| `response_summary_json` | `text` | yes | `—` |
| `error_summary` | `text` | yes | `—` |
| `submitted_at` | `timestamp with time zone` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_job_application_submissions_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`
- `fk_job_application_submissions_job`: `FOREIGN KEY (job_id) REFERENCES jobs(id)`
- `fk_job_application_submissions_job_application`: `FOREIGN KEY (job_application_id) REFERENCES job_applications(id)`
- `job_application_submissions_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_job_application_submission_once ON public.job_application_submissions USING btree (customer_id, job_id)`
- `CREATE INDEX idx_job_application_submissions_customer_id ON public.job_application_submissions USING btree (customer_id)`
- `CREATE INDEX idx_job_application_submissions_job_application_id ON public.job_application_submissions USING btree (job_application_id)`
- `CREATE INDEX idx_job_application_submissions_job_id ON public.job_application_submissions USING btree (job_id)`
- `CREATE INDEX idx_job_application_submissions_provider ON public.job_application_submissions USING btree (provider)`
- `CREATE INDEX idx_job_application_submissions_provider_job_id ON public.job_application_submissions USING btree (provider_job_id)`
- `CREATE INDEX idx_job_application_submissions_provider_status ON public.job_application_submissions USING btree (provider_status)`
- `CREATE INDEX idx_job_application_submissions_provider_submission_id ON public.job_application_submissions USING btree (provider_submission_id)`
- `CREATE UNIQUE INDEX job_application_submissions_pkey ON public.job_application_submissions USING btree (id)`

## job_applications

Model: `JobApplicationEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `job_id` | `text` | no | `—` |
| `skill_profile_id` | `text` | no | `—` |
| `resume_id` | `text` | no | `—` |
| `status` | `text` | no | `'submitted'::text` |
| `cover_letter` | `text` | yes | `—` |
| `resume_snapshot_text` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_job_applications_job`: `FOREIGN KEY (job_id) REFERENCES jobs(id)`
- `fk_job_applications_resume`: `FOREIGN KEY (resume_id) REFERENCES resumes(id)`
- `fk_job_applications_skill_profile`: `FOREIGN KEY (skill_profile_id) REFERENCES skill_profiles(id)`
- `job_applications_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_job_application_once ON public.job_applications USING btree (customer_id, job_id)`
- `CREATE INDEX idx_job_applications_customer_id ON public.job_applications USING btree (customer_id)`
- `CREATE INDEX idx_job_applications_job_id ON public.job_applications USING btree (job_id)`
- `CREATE INDEX idx_job_applications_resume_id ON public.job_applications USING btree (resume_id)`
- `CREATE INDEX idx_job_applications_skill_profile_id ON public.job_applications USING btree (skill_profile_id)`
- `CREATE INDEX idx_job_applications_status ON public.job_applications USING btree (status)`
- `CREATE UNIQUE INDEX job_applications_pkey ON public.job_applications USING btree (id)`

## job_cart_items

Model: `JobCartItemEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `job_cart_id` | `text` | no | `—` |
| `job_id` | `text` | no | `—` |
| `notes` | `text` | yes | `—` |
| `selected_skill_profile_id` | `text` | yes | `—` |
| `selected_resume_id` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_job_cart_items_job`: `FOREIGN KEY (job_id) REFERENCES jobs(id)`
- `fk_job_cart_items_selected_resume`: `FOREIGN KEY (selected_resume_id) REFERENCES resumes(id)`
- `fk_job_cart_items_selected_skill_profile`: `FOREIGN KEY (selected_skill_profile_id) REFERENCES skill_profiles(id)`
- `fk_job_carts_items`: `FOREIGN KEY (job_cart_id) REFERENCES job_carts(id)`
- `job_cart_items_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_job_cart_item ON public.job_cart_items USING btree (job_cart_id, job_id)`
- `CREATE INDEX idx_job_cart_items_job_cart_id ON public.job_cart_items USING btree (job_cart_id)`
- `CREATE INDEX idx_job_cart_items_job_id ON public.job_cart_items USING btree (job_id)`
- `CREATE INDEX idx_job_cart_items_selected_resume_id ON public.job_cart_items USING btree (selected_resume_id)`
- `CREATE INDEX idx_job_cart_items_selected_skill_profile_id ON public.job_cart_items USING btree (selected_skill_profile_id)`
- `CREATE UNIQUE INDEX job_cart_items_pkey ON public.job_cart_items USING btree (id)`

## job_carts

Model: `JobCartEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `status` | `text` | no | `'active'::text` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_job_carts_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`
- `job_carts_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_job_carts_customer_id ON public.job_carts USING btree (customer_id)`
- `CREATE INDEX idx_job_carts_status ON public.job_carts USING btree (status)`
- `CREATE UNIQUE INDEX job_carts_pkey ON public.job_carts USING btree (id)`

## jobs

Model: `JobEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `company_id` | `text` | no | `—` |
| `title` | `text` | no | `—` |
| `description` | `text` | yes | `—` |
| `category` | `text` | yes | `—` |
| `location` | `text` | yes | `—` |
| `remote_type` | `text` | yes | `—` |
| `employment_type` | `text` | yes | `—` |
| `status` | `text` | no | `'open'::text` |
| `salary_min` | `numeric` | yes | `—` |
| `salary_max` | `numeric` | yes | `—` |
| `posted_date` | `text` | yes | `—` |
| `closing_date` | `text` | yes | `—` |
| `source` | `text` | yes | `—` |
| `source_url` | `text` | yes | `—` |
| `external_job_id` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_jobs_company`: `FOREIGN KEY (company_id) REFERENCES companies(id)`
- `jobs_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_jobs_category ON public.jobs USING btree (category)`
- `CREATE INDEX idx_jobs_company_id ON public.jobs USING btree (company_id)`
- `CREATE INDEX idx_jobs_employment_type ON public.jobs USING btree (employment_type)`
- `CREATE INDEX idx_jobs_external_job_id ON public.jobs USING btree (external_job_id)`
- `CREATE INDEX idx_jobs_location ON public.jobs USING btree (location)`
- `CREATE INDEX idx_jobs_remote_type ON public.jobs USING btree (remote_type)`
- `CREATE INDEX idx_jobs_source ON public.jobs USING btree (source)`
- `CREATE INDEX idx_jobs_status ON public.jobs USING btree (status)`
- `CREATE INDEX idx_jobs_title ON public.jobs USING btree (title)`
- `CREATE UNIQUE INDEX jobs_pkey ON public.jobs USING btree (id)`

## order_operations

Model: `OrderOperationEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `user_id` | `text` | no | `—` |
| `operation_kind` | `text` | no | `—` |
| `idempotency_key` | `character varying(128)` | no | `—` |
| `request_hash` | `character(64)` | no | `—` |
| `state` | `text` | no | `—` |
| `result_order_id` | `text` | yes | `—` |
| `error_code` | `text` | no | `''::text` |
| `expires_at` | `timestamp with time zone` | no | `—` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `order_operations_customer_id_fkey`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`
- `order_operations_kind_check`: `CHECK ((operation_kind = ANY (ARRAY['checkout'::text, 'update'::text, 'cancel'::text])))`
- `order_operations_pkey`: `PRIMARY KEY (id)`
- `order_operations_result_order_id_fkey`: `FOREIGN KEY (result_order_id) REFERENCES orders(id)`
- `order_operations_state_check`: `CHECK ((state = ANY (ARRAY['in_progress'::text, 'completed'::text, 'failed'::text, 'outcome_unknown'::text])))`
- `order_operations_unique`: `UNIQUE (customer_id, operation_kind, idempotency_key)`

Indexes:

- `CREATE INDEX idx_order_operations_customer ON public.order_operations USING btree (customer_id, user_id, created_at DESC)`
- `CREATE INDEX idx_order_operations_expiry ON public.order_operations USING btree (expires_at) WHERE (state = ANY (ARRAY['completed'::text, 'failed'::text]))`
- `CREATE INDEX idx_order_operations_reconciliation ON public.order_operations USING btree (updated_at) WHERE (state = ANY (ARRAY['in_progress'::text, 'outcome_unknown'::text]))`
- `CREATE UNIQUE INDEX order_operations_pkey ON public.order_operations USING btree (id)`
- `CREATE UNIQUE INDEX order_operations_unique ON public.order_operations USING btree (customer_id, operation_kind, idempotency_key)`

## order_pricing_rules

Model: `OrderPricingRuleEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `kind` | `text` | no | `—` |
| `code` | `text` | yes | `—` |
| `calculation` | `text` | no | `—` |
| `percentage_basis_points` | `integer` | no | `0` |
| `fixed_minor_units` | `bigint` | no | `0` |
| `minimum_subtotal_minor_units` | `bigint` | no | `0` |
| `free_shipping_over_minor_units` | `bigint` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `country` | `text` | yes | `—` |
| `state` | `text` | yes | `—` |
| `taxable_shipping` | `boolean` | yes | `—` |
| `active` | `boolean` | no | `—` |
| `starts_at` | `timestamp with time zone` | yes | `—` |
| `ends_at` | `timestamp with time zone` | yes | `—` |
| `priority` | `integer` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `order_pricing_rules_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_order_pricing_rules_active ON public.order_pricing_rules USING btree (active)`
- `CREATE INDEX idx_order_pricing_rules_code ON public.order_pricing_rules USING btree (code)`
- `CREATE INDEX idx_order_pricing_rules_country ON public.order_pricing_rules USING btree (country)`
- `CREATE INDEX idx_order_pricing_rules_ends_at ON public.order_pricing_rules USING btree (ends_at)`
- `CREATE INDEX idx_order_pricing_rules_kind ON public.order_pricing_rules USING btree (kind)`
- `CREATE INDEX idx_order_pricing_rules_starts_at ON public.order_pricing_rules USING btree (starts_at)`
- `CREATE INDEX idx_order_pricing_rules_state ON public.order_pricing_rules USING btree (state)`
- `CREATE UNIQUE INDEX order_pricing_rules_pkey ON public.order_pricing_rules USING btree (id)`

## order_products

Model: `OrderProductEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `order_id` | `text` | no | `—` |
| `product_id` | `text` | no | `—` |
| `product_variant_id` | `text` | yes | `—` |
| `product_name` | `text` | no | `—` |
| `variant_name` | `text` | yes | `—` |
| `sku` | `text` | yes | `—` |
| `model` | `text` | yes | `—` |
| `size` | `text` | yes | `—` |
| `color` | `text` | yes | `—` |
| `unit_price_minor_units` | `bigint` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `quantity` | `integer` | yes | `—` |
| `total_price_minor_units` | `bigint` | no | `0` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_order_products_product`: `FOREIGN KEY (product_id) REFERENCES services(id)`
- `fk_order_products_product_variant`: `FOREIGN KEY (product_variant_id) REFERENCES product_variants(id)`
- `fk_orders_products`: `FOREIGN KEY (order_id) REFERENCES orders(id)`
- `order_products_pkey`: `PRIMARY KEY (id)`
- `order_products_quantity_check`: `CHECK (((quantity >= 1) AND (quantity <= 99)))`

Indexes:

- `CREATE INDEX idx_order_products_order_id ON public.order_products USING btree (order_id)`
- `CREATE INDEX idx_order_products_order_variant ON public.order_products USING btree (order_id, product_variant_id)`
- `CREATE INDEX idx_order_products_product_id ON public.order_products USING btree (product_id)`
- `CREATE INDEX idx_order_products_product_variant_id ON public.order_products USING btree (product_variant_id)`
- `CREATE UNIQUE INDEX order_products_pkey ON public.order_products USING btree (id)`

## order_services

Model: `OrderServiceEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `order_id` | `text` | yes | `—` |
| `service_id` | `text` | yes | `—` |
| `service_name` | `text` | no | `—` |
| `category` | `text` | yes | `—` |
| `type` | `text` | yes | `—` |
| `unit_price_minor_units` | `bigint` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `quantity` | `integer` | yes | `—` |
| `total_price_minor_units` | `bigint` | no | `0` |
| `agent_name` | `text` | yes | `—` |
| `schedule_date` | `text` | yes | `—` |
| `start_date` | `text` | yes | `—` |
| `due_date` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_order_services_service`: `FOREIGN KEY (service_id) REFERENCES services(id)`
- `fk_orders_services`: `FOREIGN KEY (order_id) REFERENCES orders(id)`
- `order_services_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_order_services_order_id ON public.order_services USING btree (order_id)`
- `CREATE INDEX idx_order_services_service_id ON public.order_services USING btree (service_id)`
- `CREATE UNIQUE INDEX order_services_pkey ON public.order_services USING btree (id)`

## orders

Model: `OrderEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | yes | `—` |
| `user_id` | `text` | yes | `—` |
| `order_number` | `text` | no | `—` |
| `status` | `text` | no | `'draft'::text` |
| `payment_status` | `text` | no | `'not_configured'::text` |
| `idempotency_key` | `text` | yes | `—` |
| `schedule_date` | `text` | yes | `—` |
| `start_date` | `text` | yes | `—` |
| `due_date` | `text` | yes | `—` |
| `subtotal_minor_units` | `bigint` | no | `0` |
| `discount_minor_units` | `bigint` | no | `0` |
| `taxable_amount_minor_units` | `bigint` | no | `0` |
| `tax_minor_units` | `bigint` | no | `0` |
| `shipping_minor_units` | `bigint` | no | `0` |
| `total_minor_units` | `bigint` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `discount_code` | `text` | yes | `—` |
| `discount_label` | `text` | yes | `—` |
| `shipping_method_id` | `text` | yes | `—` |
| `shipping_label` | `text` | yes | `—` |
| `tax_rate_basis_points` | `integer` | no | `0` |
| `tax_label` | `text` | yes | `—` |
| `shipping_address_line1` | `text` | yes | `—` |
| `shipping_address_line2` | `text` | yes | `—` |
| `shipping_address_city` | `text` | yes | `—` |
| `shipping_address_state` | `text` | yes | `—` |
| `shipping_address_country` | `text` | yes | `—` |
| `shipping_address_postal_code` | `text` | yes | `—` |
| `billing_address_line1` | `text` | yes | `—` |
| `billing_address_line2` | `text` | yes | `—` |
| `billing_address_city` | `text` | yes | `—` |
| `billing_address_state` | `text` | yes | `—` |
| `billing_address_country` | `text` | yes | `—` |
| `billing_address_postal_code` | `text` | yes | `—` |
| `notes` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |
| `version` | `bigint` | no | `1` |

Constraints:

- `fk_orders_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`
- `orders_payment_status_check`: `CHECK ((payment_status = ANY (ARRAY['not_configured'::text, 'payment_setup_required'::text, 'unpaid'::text, 'pending'::text, 'paid'::text, 'failed'::text, 'refunded'::text])))`
- `orders_pkey`: `PRIMARY KEY (id)`
- `orders_status_check`: `CHECK ((status = ANY (ARRAY['draft'::text, 'pending_payment'::text, 'confirmed'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text])))`
- `orders_taxable_amount_check`: `CHECK ((taxable_amount_minor_units >= 0))`
- `orders_version_check`: `CHECK ((version >= 1))`

Indexes:

- `CREATE INDEX idx_orders_customer_id ON public.orders USING btree (customer_id)`
- `CREATE UNIQUE INDEX idx_orders_customer_idempotency ON public.orders USING btree (customer_id, idempotency_key) WHERE (idempotency_key <> ''::text)`
- `CREATE INDEX idx_orders_customer_page ON public.orders USING btree (customer_id, created_at DESC, id DESC)`
- `CREATE UNIQUE INDEX idx_orders_order_number ON public.orders USING btree (order_number)`
- `CREATE UNIQUE INDEX idx_orders_order_number_unique ON public.orders USING btree (order_number)`
- `CREATE INDEX idx_orders_payment_status ON public.orders USING btree (payment_status)`
- `CREATE INDEX idx_orders_status ON public.orders USING btree (status)`
- `CREATE INDEX idx_orders_user_id ON public.orders USING btree (user_id)`
- `CREATE UNIQUE INDEX orders_pkey ON public.orders USING btree (id)`

## payment_sessions

Model: `PaymentSessionEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `order_id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `idempotency_key` | `text` | yes | `—` |
| `amount_minor_units` | `bigint` | no | `0` |
| `currency` | `text` | no | `'USD'::text` |
| `provider` | `text` | no | `'none'::text` |
| `provider_session_id` | `text` | yes | `—` |
| `status` | `text` | no | `'not_configured'::text` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `payment_sessions_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_payment_customer_idempotency ON public.payment_sessions USING btree (customer_id, idempotency_key) WHERE (idempotency_key <> ''::text)`
- `CREATE INDEX idx_payment_sessions_customer_id ON public.payment_sessions USING btree (customer_id)`
- `CREATE INDEX idx_payment_sessions_order_id ON public.payment_sessions USING btree (order_id)`
- `CREATE INDEX idx_payment_sessions_status ON public.payment_sessions USING btree (status)`
- `CREATE UNIQUE INDEX payment_sessions_pkey ON public.payment_sessions USING btree (id)`

## preference_definitions

Model: `DefinitionRow`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `preference_key` | `character varying(128)` | no | `—` |
| `category` | `character varying(64)` | no | `—` |
| `display_name` | `character varying(128)` | no | `—` |
| `description` | `character varying(512)` | no | `—` |
| `value_kind` | `character varying(16)` | no | `—` |
| `supported_levels` | `smallint[]` | no | `—` |
| `allowed_values` | `text[]` | no | `'{}'::text[]` |
| `supported_scopes` | `character varying(16)[]` | no | `—` |
| `consumer_domains` | `character varying(64)[]` | no | `'{}'::character varying[]` |
| `version` | `bigint` | no | `1` |
| `enabled` | `boolean` | no | `true` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `preference_definitions_consumer_check`: `CHECK ((consumer_domains <@ ARRAY['general'::character varying, 'commerce'::character varying, 'career'::character varying, 'txse_intelligence'::character varying]))`
- `preference_definitions_key_check`: `CHECK (((preference_key)::text ~ '^[a-z][a-z0-9_.-]{2,127}$'::text))`
- `preference_definitions_kind_check`: `CHECK (((value_kind)::text = ANY ((ARRAY['text'::character varying, 'boolean'::character varying, 'integer'::character varying, 'decimal'::character varying, 'money'::character varying, 'option'::character varying, 'options'::character varying])::text[])))`
- `preference_definitions_pkey`: `PRIMARY KEY (id)`
- `preference_definitions_preference_key_key`: `UNIQUE (preference_key)`
- `preference_definitions_shape_check`: `CHECK ((preference_opaque_valid(id) AND (octet_length((preference_key)::text) <= 128) AND ((preference_key)::text ~ '^[a-z][a-z0-9_-]*(\.[a-z][a-z0-9_-]*)+$'::text) AND ((preference_key)::text !~~ 'custom.%'::text) AND ((category)::text = ANY (ARRAY['general'::text, 'communication'::text, 'recommendations'::text, 'food'::text, 'restaurants'::text, 'shopping'::text, 'home'::text, 'travel'::text, 'vehicles'::text, 'jobs'::text, 'technology'::text, 'real_estate'::text, 'entertainment'::text, 'services'::text, 'markets'::text])) AND preference_text_valid((display_name)::text, 128, true) AND preference_text_valid((description)::text, 512, false) AND ((cardinality(supported_levels) >= 1) AND (cardinality(supported_levels) <= 5)) AND (array_ndims(supported_levels) = 1) AND (array_lower(supported_levels, 1) = 1) AND (array_position(supported_levels, NULL::smallint) IS NULL) AND (supported_levels <@ ARRAY[(1)::smallint, (2)::smallint, (3)::smallint, (4)::smallint, (5)::smallint]) AND preference_unique_levels(supported_levels) AND ((cardinality(supported_scopes) >= 1) AND (cardinality(supported_scopes) <= 3)) AND preference_tokens_valid((supported_scopes)::text[], 3) AND ((supported_scopes)::text[] <@ ARRAY['global'::text, 'context'::text, 'entity'::text]) AND preference_tokens_valid((consumer_domains)::text[], 4) AND preference_tokens_valid(allowed_values, 32) AND ((((value_kind)::text = ANY ((ARRAY['option'::character varying, 'options'::character varying])::text[])) AND (cardinality(allowed_values) > 0)) OR (((value_kind)::text <> ALL ((ARRAY['option'::character varying, 'options'::character varying])::text[])) AND (cardinality(allowed_values) = 0)))))`
- `preference_definitions_txse_policy_check`: `CHECK ((((((category)::text <> 'markets'::text) AND ((preference_key)::text !~~ 'txse.%'::text)) OR ('txse_intelligence'::text = ANY ((consumer_domains)::text[]))) AND (('txse_intelligence'::text <> ALL ((consumer_domains)::text[])) OR ((supported_levels <@ ARRAY[(3)::smallint, (4)::smallint, (5)::smallint]) AND ((((preference_key)::text = 'general.explanation_detail'::text) AND ((category)::text = 'general'::text) AND ((value_kind)::text = 'option'::text) AND (allowed_values <@ ARRAY['concise'::text, 'standard'::text, 'detailed'::text]) AND ((supported_scopes)::text[] <@ ARRAY['global'::text, 'context'::text])) OR (((preference_key)::text = 'txse.signal_families'::text) AND ((category)::text = 'markets'::text) AND ((value_kind)::text = 'options'::text) AND (allowed_values <@ ARRAY['depth_imbalance'::text, 'liquidity_withdrawal'::text, 'execution_velocity'::text, 'hidden_liquidity_ratio'::text, 'auction_pressure'::text])) OR (((preference_key)::text = 'txse.default_window'::text) AND ((category)::text = 'markets'::text) AND ((value_kind)::text = 'option'::text) AND (allowed_values <@ ARRAY['1m'::text, '5m'::text, '15m'::text, '1h'::text, '1d'::text])) OR (((preference_key)::text = 'txse.alert_severity'::text) AND ((category)::text = 'markets'::text) AND ((value_kind)::text = 'option'::text) AND (allowed_values <@ ARRAY['low'::text, 'medium'::text, 'high'::text, 'critical'::text])) OR (((preference_key)::text = 'txse.presentation_units'::text) AND ((category)::text = 'markets'::text) AND ((value_kind)::text = 'option'::text) AND (allowed_values <@ ARRAY['shares'::text, 'notional'::text, 'basis_points'::text])))))))`
- `preference_definitions_version_check`: `CHECK ((version >= 1))`

Indexes:

- `CREATE UNIQUE INDEX preference_definitions_pkey ON public.preference_definitions USING btree (id)`
- `CREATE UNIQUE INDEX preference_definitions_preference_key_key ON public.preference_definitions USING btree (preference_key)`

## preference_operations

Model: `OperationRow`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `operation_kind` | `character varying(16)` | no | `—` |
| `idempotency_key` | `character varying(128)` | no | `—` |
| `request_digest` | `character(64)` | no | `—` |
| `state` | `character varying(24)` | no | `—` |
| `result_preference_id` | `text` | yes | `—` |
| `result_version` | `bigint` | yes | `—` |
| `error_code` | `character varying(64)` | no | `''::character varying` |
| `expires_at` | `timestamp with time zone` | no | `—` |
| `retain_until` | `timestamp with time zone` | no | `—` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |
| `result_profile_version` | `bigint` | yes | `—` |

Constraints:

- `preference_operations_customer_id_fkey`: `FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE`
- `preference_operations_customer_identity_unique`: `UNIQUE (customer_id, id)`
- `preference_operations_kind_check`: `CHECK (((operation_kind)::text = ANY ((ARRAY['upsert'::character varying, 'delete'::character varying])::text[])))`
- `preference_operations_pkey`: `PRIMARY KEY (id)`
- `preference_operations_shape_check`: `CHECK ((preference_opaque_valid(id) AND preference_opaque_valid(customer_id) AND preference_opaque_valid((idempotency_key)::text) AND (request_digest ~ '^[a-f0-9]{64}$'::text) AND (((error_code)::text = ''::text) OR preference_opaque_valid((error_code)::text, 64)) AND isfinite(expires_at) AND isfinite(retain_until) AND (retain_until >= expires_at) AND ((((state)::text = 'completed'::text) AND (result_profile_version IS NOT NULL) AND (result_profile_version >= 1) AND (result_preference_id IS NOT NULL) AND preference_opaque_valid(result_preference_id) AND (result_version IS NOT NULL) AND (result_version >= 1) AND ((error_code)::text = ''::text)) OR (((state)::text <> 'completed'::text) AND (result_profile_version IS NULL) AND (result_preference_id IS NULL) AND (result_version IS NULL)))))`
- `preference_operations_state_check`: `CHECK (((state)::text = ANY ((ARRAY['pending'::character varying, 'completed'::character varying, 'failed'::character varying, 'outcome_unknown'::character varying])::text[])))`
- `preference_operations_unique`: `UNIQUE (customer_id, idempotency_key)`
- `preference_operations_version_check`: `CHECK (((result_version IS NULL) OR (result_version >= 1)))`

Indexes:

- `CREATE INDEX idx_preference_operations_customer ON public.preference_operations USING btree (customer_id, created_at DESC, id DESC)`
- `CREATE INDEX idx_preference_operations_expiry ON public.preference_operations USING btree (retain_until) WHERE ((state)::text = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::text[]))`
- `CREATE INDEX idx_preference_operations_reconciliation ON public.preference_operations USING btree (updated_at) WHERE ((state)::text = ANY ((ARRAY['pending'::character varying, 'outcome_unknown'::character varying])::text[]))`
- `CREATE INDEX idx_preference_operations_terminal_retention ON public.preference_operations USING btree (retain_until, id) WHERE ((state)::text = ANY ((ARRAY['completed'::character varying, 'failed'::character varying])::text[]))`
- `CREATE UNIQUE INDEX preference_operations_customer_identity_unique ON public.preference_operations USING btree (customer_id, id)`
- `CREATE UNIQUE INDEX preference_operations_pkey ON public.preference_operations USING btree (id)`
- `CREATE UNIQUE INDEX preference_operations_unique ON public.preference_operations USING btree (customer_id, idempotency_key)`

## product_categories

Model: `ProductCategoryEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `slug` | `text` | no | `—` |
| `parent_id` | `text` | yes | `—` |
| `path` | `text` | no | `—` |
| `ancestor_ids` | `text` | yes | `—` |
| `level` | `integer` | no | `0` |
| `active` | `boolean` | no | `true` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_product_categories_parent`: `FOREIGN KEY (parent_id) REFERENCES product_categories(id)`
- `product_categories_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_product_categories_active ON public.product_categories USING btree (active)`
- `CREATE INDEX idx_product_categories_parent_id ON public.product_categories USING btree (parent_id)`
- `CREATE UNIQUE INDEX idx_product_categories_path ON public.product_categories USING btree (path)`
- `CREATE INDEX idx_product_categories_slug ON public.product_categories USING btree (slug)`
- `CREATE UNIQUE INDEX product_categories_pkey ON public.product_categories USING btree (id)`

## product_category_assignments

Model: `ProductCategoryAssignmentEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `product_id` | `text` | no | `—` |
| `category_id` | `text` | no | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `product_category_assignments_pkey`: `PRIMARY KEY (product_id, category_id)`

Indexes:

- `CREATE INDEX idx_product_category_assignments_category_id ON public.product_category_assignments USING btree (category_id)`
- `CREATE UNIQUE INDEX product_category_assignments_pkey ON public.product_category_assignments USING btree (product_id, category_id)`

## product_variants

Model: `ProductVariantEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `product_id` | `text` | no | `—` |
| `name` | `text` | yes | `—` |
| `model` | `text` | yes | `—` |
| `size` | `text` | yes | `—` |
| `color` | `text` | yes | `—` |
| `sku` | `text` | yes | `—` |
| `price_minor_units` | `bigint` | no | `0` |
| `active` | `boolean` | no | `true` |
| `inventory_count` | `integer` | no | `0` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |
| `currency` | `character(3)` | no | `'USD'::bpchar` |

Constraints:

- `fk_services_variants`: `FOREIGN KEY (product_id) REFERENCES services(id)`
- `product_variants_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_product_variants_active ON public.product_variants USING btree (active)`
- `CREATE INDEX idx_product_variants_color ON public.product_variants USING btree (color)`
- `CREATE INDEX idx_product_variants_model ON public.product_variants USING btree (model)`
- `CREATE INDEX idx_product_variants_product_id ON public.product_variants USING btree (product_id)`
- `CREATE INDEX idx_product_variants_size ON public.product_variants USING btree (size)`
- `CREATE UNIQUE INDEX idx_product_variants_sku_unique ON public.product_variants USING btree (sku) WHERE (sku <> ''::text)`
- `CREATE UNIQUE INDEX product_variants_pkey ON public.product_variants USING btree (id)`

## resume_employment_records

Model: `ResumeEmploymentRecordEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `resume_id` | `text` | no | `—` |
| `employment_record_id` | `text` | no | `—` |
| `sort_order` | `integer` | yes | `—` |
| `include` | `boolean` | no | `true` |
| `tailored_title` | `text` | yes | `—` |
| `tailored_summary` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_resume_employment_records_employment_record`: `FOREIGN KEY (employment_record_id) REFERENCES employment_records(id)`
- `fk_resume_employment_records_resume`: `FOREIGN KEY (resume_id) REFERENCES resumes(id)`
- `resume_employment_records_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_resume_employment_record ON public.resume_employment_records USING btree (resume_id, employment_record_id)`
- `CREATE INDEX idx_resume_employment_records_employment_record_id ON public.resume_employment_records USING btree (employment_record_id)`
- `CREATE INDEX idx_resume_employment_records_resume_id ON public.resume_employment_records USING btree (resume_id)`
- `CREATE INDEX idx_resume_employment_records_sort_order ON public.resume_employment_records USING btree (sort_order)`
- `CREATE UNIQUE INDEX resume_employment_records_pkey ON public.resume_employment_records USING btree (id)`

## resumes

Model: `ResumeEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `skill_profile_id` | `text` | no | `—` |
| `title` | `text` | no | `—` |
| `content` | `text` | yes | `—` |
| `file_url` | `text` | yes | `—` |
| `name` | `text` | yes | `—` |
| `content_text` | `text` | yes | `—` |
| `version` | `integer` | yes | `—` |
| `is_active` | `boolean` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |
| `deleted_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_resumes_skill_profile`: `FOREIGN KEY (skill_profile_id) REFERENCES skill_profiles(id)`
- `resumes_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_resumes_customer_id ON public.resumes USING btree (customer_id)`
- `CREATE INDEX idx_resumes_deleted_at ON public.resumes USING btree (deleted_at)`
- `CREATE INDEX idx_resumes_is_active ON public.resumes USING btree (is_active)`
- `CREATE INDEX idx_resumes_skill_profile_id ON public.resumes USING btree (skill_profile_id)`
- `CREATE UNIQUE INDEX resumes_pkey ON public.resumes USING btree (id)`

## role_permissions

Model: `RolePermissionEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `role_id` | `text` | no | `—` |
| `grpc_method` | `text` | no | `—` |
| `description` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `fk_role_permissions_role`: `FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE`
- `role_permissions_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_role_permission ON public.role_permissions USING btree (role_id, grpc_method)`
- `CREATE INDEX idx_role_permissions_g_rpc_method ON public.role_permissions USING btree (grpc_method)`
- `CREATE UNIQUE INDEX role_permissions_pkey ON public.role_permissions USING btree (id)`

## roles

Model: `RoleEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `description` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | no | `now()` |
| `updated_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `roles_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_roles_name ON public.roles USING btree (name)`
- `CREATE UNIQUE INDEX roles_pkey ON public.roles USING btree (id)`

## schema_migration_lock

Model: `Migration lease`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `smallint` | no | `—` |
| `owner` | `character varying(128)` | no | `—` |
| `locked_until` | `timestamp with time zone` | no | `—` |

Constraints:

- `schema_migration_lock_id_check`: `CHECK ((id = 1))`
- `schema_migration_lock_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX schema_migration_lock_pkey ON public.schema_migration_lock USING btree (id)`

## schema_migrations

Model: `Migration ledger`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `version` | `character varying(32)` | no | `—` |
| `filename` | `text` | no | `—` |
| `checksum` | `character(64)` | no | `—` |
| `applied_at` | `timestamp with time zone` | no | `now()` |

Constraints:

- `schema_migrations_filename_key`: `UNIQUE (filename)`
- `schema_migrations_pkey`: `PRIMARY KEY (version)`

Indexes:

- `CREATE UNIQUE INDEX schema_migrations_filename_key ON public.schema_migrations USING btree (filename)`
- `CREATE UNIQUE INDEX schema_migrations_pkey ON public.schema_migrations USING btree (version)`

## services

Model: `ServiceEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | yes | `—` |
| `category` | `text` | yes | `—` |
| `price_minor_units` | `bigint` | no | `0` |
| `type` | `text` | yes | `—` |
| `schedule_date` | `text` | yes | `—` |
| `start_date` | `text` | yes | `—` |
| `agent_name` | `text` | yes | `—` |
| `description` | `text` | yes | `—` |
| `sku` | `text` | yes | `—` |
| `active` | `boolean` | no | `true` |
| `product_model` | `text` | yes | `—` |
| `currency` | `text` | no | `'USD'::text` |
| `inventory_count` | `integer` | no | `0` |
| `closeout` | `boolean` | no | `false` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |
| `version` | `bigint` | no | `1` |

Constraints:

- `services_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_services_active ON public.services USING btree (active)`
- `CREATE INDEX idx_services_closeout ON public.services USING btree (closeout)`
- `CREATE INDEX idx_services_product_model ON public.services USING btree (product_model)`
- `CREATE UNIQUE INDEX idx_services_sku_unique ON public.services USING btree (sku) WHERE (sku <> ''::text)`
- `CREATE UNIQUE INDEX services_pkey ON public.services USING btree (id)`

## skill_profile_skills

Model: `SkillProfileSkillEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `skill_profile_id` | `text` | no | `—` |
| `skill_id` | `text` | no | `—` |
| `level` | `text` | yes | `—` |
| `years_experience` | `integer` | yes | `—` |
| `description` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_skill_profile_skills_skill`: `FOREIGN KEY (skill_id) REFERENCES skills(id)`
- `fk_skill_profiles_skills`: `FOREIGN KEY (skill_profile_id) REFERENCES skill_profiles(id)`
- `skill_profile_skills_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_skill_profile_skills_skill_id ON public.skill_profile_skills USING btree (skill_id)`
- `CREATE INDEX idx_skill_profile_skills_skill_profile_id ON public.skill_profile_skills USING btree (skill_profile_id)`
- `CREATE UNIQUE INDEX skill_profile_skills_pkey ON public.skill_profile_skills USING btree (id)`

## skill_profiles

Model: `SkillProfileEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `customer_id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `summary` | `text` | yes | `—` |
| `years_of_experience` | `integer` | yes | `—` |
| `target_role` | `text` | yes | `—` |
| `is_default` | `boolean` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `fk_skill_profiles_customer`: `FOREIGN KEY (customer_id) REFERENCES customers(id)`
- `skill_profiles_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE INDEX idx_skill_profiles_customer_id ON public.skill_profiles USING btree (customer_id)`
- `CREATE INDEX idx_skill_profiles_is_default ON public.skill_profiles USING btree (is_default)`
- `CREATE INDEX idx_skill_profiles_target_role ON public.skill_profiles USING btree (target_role)`
- `CREATE UNIQUE INDEX skill_profiles_pkey ON public.skill_profiles USING btree (id)`

## skills

Model: `SkillEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | no | `—` |
| `category` | `text` | yes | `—` |
| `description` | `text` | yes | `—` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |

Constraints:

- `skills_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_skills_name_category ON public.skills USING btree (name, category)`
- `CREATE UNIQUE INDEX skills_pkey ON public.skills USING btree (id)`

## users

Model: `UserEntity`.

| Column | PostgreSQL type | Nullable | Default |
|---|---|---|---|
| `id` | `text` | no | `—` |
| `name` | `text` | yes | `—` |
| `company` | `text` | yes | `—` |
| `email` | `text` | no | `—` |
| `password` | `text` | yes | `—` |
| `token` | `text` | yes | `—` |
| `role` | `text` | no | `—` |
| `status` | `text` | no | `'active'::text` |
| `created_at` | `timestamp with time zone` | yes | `—` |
| `updated_at` | `timestamp with time zone` | yes | `—` |
| `version` | `bigint` | no | `1` |

Constraints:

- `users_pkey`: `PRIMARY KEY (id)`

Indexes:

- `CREATE UNIQUE INDEX idx_users_email ON public.users USING btree (email)`
- `CREATE UNIQUE INDEX idx_users_email_lower_unique ON public.users USING btree (lower(email))`
- `CREATE INDEX idx_users_status ON public.users USING btree (status)`
- `CREATE UNIQUE INDEX users_pkey ON public.users USING btree (id)`
