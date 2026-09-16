require "json"
require "minitest/autorun"

ROOT = File.expand_path("../../..", __dir__)
REALM = JSON.parse(File.read(File.join(ROOT, "dev/keycloak/ceerat-realm.json")))
CLIENTS = REALM.fetch("clients").to_h { |client| [client.fetch("clientId"), client] }
IDENTITY_PROVIDERS = REALM.fetch("identityProviders").to_h { |provider| [provider.fetch("alias"), provider] }

class RealmConfigTest < Minitest::Test
  HOSTED_CALLBACK = "https://chatgpt.com/connector_platform_oauth_redirect"
  LOOPBACK_CALLBACKS = ["http://127.0.0.1:*", "http://localhost:*"].freeze
  REQUIRED_SCOPES = %w[
    profile
    email
    ceerat.profile.read
    ceerat.profile.write
    ceerat.connections.read
    ceerat.connections.revoke
  ].freeze
  PRODUCT_SCOPES = %w[
    ceerat.products.read
    ceerat.products.cart.read
    ceerat.products.cart.write
  ].freeze
  PRODUCT_CONSENT = {
    "ceerat.products.read" => "View products available from CEERAT",
    "ceerat.products.cart.read" => "View your CEERAT shopping cart",
    "ceerat.products.cart.write" => "Add, update, or remove items in your CEERAT shopping cart"
  }.freeze
  ORDER_SCOPES = %w[
    ceerat.orders.read
    ceerat.orders.checkout
    ceerat.orders.write
  ].freeze
  ORDER_CONSENT = {
    "ceerat.orders.read" => "View your CEERAT orders and checkout pricing",
    "ceerat.orders.checkout" => "Create CEERAT orders from your cart after confirmation",
    "ceerat.orders.write" => "Update or cancel eligible CEERAT orders after confirmation"
  }.freeze
  PREFERENCE_SCOPES = %w[
    ceerat.preferences.read
    ceerat.preferences.write
  ].freeze
  PREFERENCE_CONSENT = {
    "ceerat.preferences.read" => "View your saved CEERAT preferences",
    "ceerat.preferences.write" => "Save, update, or remove your CEERAT preferences after confirmation"
  }.freeze

  def test_realm_uses_short_tokens_rotation_and_verified_email
    assert_equal true, REALM["verifyEmail"]
    assert_equal 600, REALM["accessTokenLifespan"]
    assert_equal true, REALM["revokeRefreshToken"]
    assert_equal 0, REALM["refreshTokenMaxReuse"]
    assert_operator REALM["offlineSessionIdleTimeout"], :<=, 2_592_000
    assert_operator REALM["offlineSessionMaxLifespan"], :<=, 5_184_000
  end

  def test_chatgpt_client_has_only_exact_hosted_callback
    client = CLIENTS.fetch("ceerat-mcp-chatgpt")
    assert_equal [HOSTED_CALLBACK], client["redirectUris"]
    refute client["redirectUris"].any? { |uri| uri.include?("*") }
    assert_confidential_pkce_client(client)
  end

  def test_codex_client_has_only_loopback_callbacks
    client = CLIENTS.fetch("ceerat-mcp-codex-dev")
    assert_equal LOOPBACK_CALLBACKS, client["redirectUris"]
    refute_includes client["redirectUris"], HOSTED_CALLBACK
    assert_public_pkce_client(client)
  end

  def test_direct_grpc_client_is_public_pkce_with_canonical_audience
    client = CLIENTS.fetch("ceerat-grpc-dev")
    assert_equal LOOPBACK_CALLBACKS, client["redirectUris"]
    assert_public_pkce_client(client)
    audience = client.fetch("protocolMappers").find { |mapper| mapper["protocolMapper"] == "oidc-audience-mapper" }
    assert_equal "ceerat-api", audience.dig("config", "included.custom.audience")
    assert_equal %w[profile email], client["defaultClientScopes"]
    assert_equal client, JSON.parse(File.read(File.join(ROOT, "deploy/render/keycloak/clients/ceerat-grpc-dev.json")))
  end

  def test_mcp_clients_have_explicit_scopes_and_audience
    %w[ceerat-mcp-chatgpt ceerat-mcp-codex-dev].each do |client_id|
      client = CLIENTS.fetch(client_id)
      assert_equal REQUIRED_SCOPES, client["defaultClientScopes"]
      assert_equal ["offline_access", *PRODUCT_SCOPES, *ORDER_SCOPES, *PREFERENCE_SCOPES], client["optionalClientScopes"]
      audiences = client.fetch("protocolMappers")
        .select { |mapper| mapper["protocolMapper"] == "oidc-audience-mapper" }
        .map { |mapper| mapper.dig("config", "included.custom.audience") }
      assert_equal ["ceerat-api", "https://ceerat-agent-gateway.onrender.com/mcp"], audiences.sort
    end
  end

  def test_domain_scopes_are_optional_with_explicit_consent
    scopes = REALM.fetch("clientScopes").to_h { |scope| [scope.fetch("name"), scope] }
    PRODUCT_CONSENT.merge(ORDER_CONSENT).merge(PREFERENCE_CONSENT).each do |name, consent|
      scope = scopes.fetch(name)
      assert_equal "openid-connect", scope["protocol"]
      assert_equal "true", scope.dig("attributes", "include.in.token.scope")
      assert_equal "true", scope.dig("attributes", "display.on.consent.screen")
      assert_equal consent, scope.dig("attributes", "consent.screen.text")
      assert_empty scope["protocolMappers"]

      template = JSON.parse(File.read(File.join(ROOT, "deploy/render/keycloak/client-scopes/#{name}.json")))
      assert_equal scope, template
    end

    refute CLIENTS.key?("ceerat-mcp-dev")
    domain_scopes = PRODUCT_SCOPES + ORDER_SCOPES + PREFERENCE_SCOPES
    assert_empty domain_scopes & Array(REALM["defaultDefaultClientScopes"])
    assert_empty domain_scopes & Array(REALM["defaultOptionalClientScopes"])
    refute scopes.key?("ceerat.orders.admin")
    refute scopes.key?("ceerat.preferences.admin")
  end

  def test_authentication_and_consent_events_are_audited
    assert_equal true, REALM["eventsEnabled"]
    assert_includes REALM["eventsListeners"], "jboss-logging"
    %w[LOGIN_ERROR CODE_TO_TOKEN_ERROR GRANT_CONSENT DENY_CONSENT UPDATE_CONSENT].each do |event|
      assert_includes REALM["enabledEventTypes"], event
    end
    %w[IDENTITY_PROVIDER_LOGIN IDENTITY_PROVIDER_FIRST_LOGIN IDENTITY_PROVIDER_LINK_ACCOUNT IDENTITY_PROVIDER_LOGIN_ERROR].each do |event|
      assert_includes REALM["enabledEventTypes"], event
    end
  end

  def test_revoker_is_confidential_service_only_and_has_no_redirect
    client = CLIENTS.fetch("ceerat-gateway-revoker")
    assert_equal true, client["enabled"]
    assert_equal false, client["publicClient"]
    assert_equal false, client["standardFlowEnabled"]
    assert_equal false, client["implicitFlowEnabled"]
    assert_equal false, client["directAccessGrantsEnabled"]
    assert_equal true, client["serviceAccountsEnabled"]
    assert_empty client["redirectUris"]
    assert_empty client["defaultClientScopes"]
    refute client.key?("secret")
  end

  def test_smtp_uses_starttls_without_committed_secret
    smtp = REALM.fetch("smtpServer")
    assert_equal "true", smtp["auth"]
    assert_equal "true", smtp["starttls"]
    assert_equal "false", smtp["ssl"]
    assert_equal "${CEERAT_SMTP_PASSWORD}", smtp["password"]
  end

  def test_reconciliation_templates_match_realm_clients
    %w[ceerat-mcp-chatgpt ceerat-mcp-codex-dev ceerat-gateway-revoker].each do |client_id|
      path = File.join(ROOT, "deploy/render/keycloak/clients/#{client_id}.json")
      assert_equal CLIENTS.fetch(client_id), JSON.parse(File.read(path))
    end
  end

  def test_reconciliation_grants_only_required_revoker_role
    script = File.read(File.join(ROOT, "deploy/render/keycloak/reconcile-live-realm.sh"))
    assert_includes script, "--cclientid realm-management --rolename manage-users"
    refute_includes script, "--rolename realm-admin"
    refute_includes script, "--rolename manage-realm"
  end

  def test_reconciliation_preserves_chatgpt_client_secret
    script = File.read(File.join(ROOT, "deploy/render/keycloak/reconcile-live-realm.sh"))
    assert_includes script, 'get "clients/$internal_id/client-secret"'
    assert_includes script, '-s "secret=$existing_secret"'
    refute_includes script, "echo $existing_secret"
  end

  def test_google_broker_is_minimal_and_secret_indirected
    provider = IDENTITY_PROVIDERS.fetch("google")
    assert_equal "google", provider["providerId"]
    assert_equal true, provider["enabled"]
    assert_equal true, provider["trustEmail"]
    assert_equal false, provider["storeToken"]
    assert_equal false, provider["addReadTokenRoleOnCreate"]
    assert_equal false, provider["authenticateByDefault"]
    assert_equal false, provider["linkOnly"]
    assert_equal "first broker login", provider["firstBrokerLoginFlowAlias"]
    assert_equal "openid profile email", provider.dig("config", "defaultScope")
    assert_equal "IMPORT", provider.dig("config", "syncMode")
    assert_equal "${CEERAT_GOOGLE_CLIENT_ID}", provider.dig("config", "clientId")
    assert_equal "${CEERAT_GOOGLE_CLIENT_SECRET}", provider.dig("config", "clientSecret")
    template = JSON.parse(File.read(File.join(ROOT, "deploy/render/keycloak/identity-providers/google.json")))
    assert_equal provider, template
  end

  def test_google_reconciliation_is_local_by_default_and_never_logs_secrets
    script = File.read(File.join(ROOT, "deploy/render/keycloak/reconcile-google-provider.rb"))
    assert_includes script, "CEERAT_ALLOW_LIVE_GOOGLE_RECONCILE"
    assert_includes script, "localhost|127\\.0\\.0\\.1"
    assert_includes script, "/broker/google/endpoint"
    refute_includes script, 'puts(google_secret)'
    refute_includes script, 'puts(admin_password)'
    assert_includes script, "ACCOUNT_DEFAULT_SCOPES"
    assert_includes script, "default-client-scopes"
    assert_includes script, "%w[account account-console]"
  end


  def test_reconciliation_creates_scopes_before_updating_clients
    script = File.read(File.join(ROOT, "deploy/render/keycloak/reconcile-live-realm.sh"))
    scope_position = script.index('for definition in "$script_dir"/client-scopes/*.json')
    client_position = script.index('"$script_dir/clients/ceerat-mcp-chatgpt.json"')
    refute_nil scope_position
    refute_nil client_position
    assert_operator scope_position, :<, client_position
    refute_match(/\b(?:awk|jq)\b/, script)
    assert_includes script, 'optional-client-scopes/$scope_internal_id'
    assert_includes script, 'assign_mcp_optional_scopes "$internal_id"'
    assert_includes script, 'delete_superseded_client "ceerat-mcp-dev"'
  end

  private

  def assert_confidential_pkce_client(client)
    assert_equal true, client["enabled"]
    assert_equal false, client["publicClient"]
    assert_equal "client-secret", client["clientAuthenticatorType"]
    assert_equal true, client["standardFlowEnabled"]
    assert_equal false, client["implicitFlowEnabled"]
    assert_equal false, client["directAccessGrantsEnabled"]
    assert_equal false, client["serviceAccountsEnabled"]
    assert_equal "S256", client.dig("attributes", "pkce.code.challenge.method")
    assert_empty client["webOrigins"]
    refute client.key?("secret")
  end

  def assert_public_pkce_client(client)
    assert_equal true, client["enabled"]
    assert_equal true, client["publicClient"]
    assert_equal true, client["standardFlowEnabled"]
    assert_equal false, client["implicitFlowEnabled"]
    assert_equal false, client["directAccessGrantsEnabled"]
    assert_equal false, client["serviceAccountsEnabled"]
    assert_equal "S256", client.dig("attributes", "pkce.code.challenge.method")
    assert_empty client["webOrigins"]
    refute client.key?("secret")
  end
end
