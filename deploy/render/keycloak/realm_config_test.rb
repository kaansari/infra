require "json"
require "minitest/autorun"

ROOT = File.expand_path("../../..", __dir__)
REALM = JSON.parse(File.read(File.join(ROOT, "dev/keycloak/ceerat-realm.json")))
CLIENTS = REALM.fetch("clients").to_h { |client| [client.fetch("clientId"), client] }

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
    assert_public_pkce_client(client)
  end

  def test_codex_client_has_only_loopback_callbacks
    client = CLIENTS.fetch("ceerat-mcp-codex-dev")
    assert_equal LOOPBACK_CALLBACKS, client["redirectUris"]
    refute_includes client["redirectUris"], HOSTED_CALLBACK
    assert_public_pkce_client(client)
  end

  def test_public_clients_have_explicit_scopes_and_audience
    %w[ceerat-mcp-chatgpt ceerat-mcp-codex-dev].each do |client_id|
      client = CLIENTS.fetch(client_id)
      assert_equal REQUIRED_SCOPES, client["defaultClientScopes"]
      assert_equal ["offline_access"], client["optionalClientScopes"]
      audience = client.fetch("protocolMappers").find { |mapper| mapper["protocolMapper"] == "oidc-audience-mapper" }
      refute_nil audience
      assert_equal "https://ceerat-agent-gateway.onrender.com/mcp", audience.dig("config", "included.custom.audience")
    end
  end

  def test_revoker_is_confidential_disabled_roleless_and_has_no_redirect
    client = CLIENTS.fetch("ceerat-gateway-revoker")
    assert_equal false, client["enabled"]
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

  private

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
