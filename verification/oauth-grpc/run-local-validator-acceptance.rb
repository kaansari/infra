#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "cgi"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "uri"

ISSUER = ENV.fetch("CEERAT_LOCAL_OAUTH_ISSUER", "http://localhost:8080/realms/ceerat")
abort("local validator acceptance refuses non-loopback issuer") unless ISSUER.match?(%r{\Ahttp://(localhost|127\.0\.0\.1):\d+/})

ROOT = File.expand_path("../..", __dir__)
STACK_ROOT = File.expand_path("..", ROOT)
CONTRACT_ROOT = File.join(STACK_ROOT, "contracts-repo", "packages", "ceerat-contracts")
ADMIN_PASSWORD_FILE = ENV.fetch("CEERAT_LOCAL_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(STACK_ROOT, ".run", "keycloak-admin-password"))
ADMIN_USER = ENV.fetch("CEERAT_LOCAL_KEYCLOAK_ADMIN_USER", "admin")
CLIENT_ID = "ceerat-grpc-validator-#{SecureRandom.hex(5)}"
USERNAME = "oauth-validator-#{SecureRandom.hex(5)}@local.invalid"
USER_PASSWORD = Base64.urlsafe_encode64(SecureRandom.random_bytes(24), padding: false)
REDIRECT_URI = "http://127.0.0.1:8765/callback"

def request(method, url, headers: {}, form: nil, json: nil)
  uri = URI(url)
  request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete, put: Net::HTTP::Put }.fetch(method)
  req = request_class.new(uri)
  headers.each { |key, value| req[key] = value }
  if form
    req.set_form_data(form)
  elsif json
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(json)
  end
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 5) { |http| http.request(req) }
end

def require_status!(response, *expected)
  return response if expected.include?(response.code.to_i)

  abort("local Keycloak acceptance failed with HTTP #{response.code}")
end

admin_password = File.read(ADMIN_PASSWORD_FILE).strip
abort("local Keycloak admin credential is empty") if admin_password.empty?

master_token_response = require_status!(request(:post, "http://localhost:8080/realms/master/protocol/openid-connect/token", form: {
  "grant_type" => "password", "client_id" => "admin-cli", "username" => ADMIN_USER, "password" => admin_password
}), 200)
admin_token = JSON.parse(master_token_response.body).fetch("access_token")
admin_headers = { "Authorization" => "Bearer #{admin_token}" }
admin_base = "http://localhost:8080/admin/realms/ceerat"
client_internal_id = nil
user_internal_id = nil

begin
  client_response = require_status!(request(:post, "#{admin_base}/clients", headers: admin_headers, json: {
    "clientId" => CLIENT_ID,
    "name" => "Temporary local OAuth validator acceptance",
    "enabled" => true,
    "publicClient" => true,
    "standardFlowEnabled" => true,
    "implicitFlowEnabled" => false,
    "directAccessGrantsEnabled" => false,
    "serviceAccountsEnabled" => false,
    "consentRequired" => false,
    "redirectUris" => [REDIRECT_URI],
    "webOrigins" => [],
    "attributes" => { "pkce.code.challenge.method" => "S256" },
    "protocolMappers" => [
      {
        "name" => "subject",
        "protocol" => "openid-connect",
        "protocolMapper" => "oidc-sub-mapper",
        "consentRequired" => false,
        "config" => { "access.token.claim" => "true", "id.token.claim" => "true" }
      },
      {
        "name" => "CEERAT API audience",
        "protocol" => "openid-connect",
        "protocolMapper" => "oidc-audience-mapper",
        "consentRequired" => false,
        "config" => { "included.custom.audience" => "ceerat-api", "access.token.claim" => "true", "id.token.claim" => "false" }
      },
      {
        "name" => "email",
        "protocol" => "openid-connect",
        "protocolMapper" => "oidc-usermodel-property-mapper",
        "consentRequired" => false,
        "config" => { "user.attribute" => "email", "claim.name" => "email", "jsonType.label" => "String", "access.token.claim" => "true" }
      },
      {
        "name" => "email verified",
        "protocol" => "openid-connect",
        "protocolMapper" => "oidc-usermodel-property-mapper",
        "consentRequired" => false,
        "config" => { "user.attribute" => "emailVerified", "claim.name" => "email_verified", "jsonType.label" => "boolean", "access.token.claim" => "true" }
      },
      {
        "name" => "given name",
        "protocol" => "openid-connect",
        "protocolMapper" => "oidc-usermodel-property-mapper",
        "consentRequired" => false,
        "config" => { "user.attribute" => "firstName", "claim.name" => "given_name", "jsonType.label" => "String", "access.token.claim" => "true" }
      },
      {
        "name" => "family name",
        "protocol" => "openid-connect",
        "protocolMapper" => "oidc-usermodel-property-mapper",
        "consentRequired" => false,
        "config" => { "user.attribute" => "lastName", "claim.name" => "family_name", "jsonType.label" => "String", "access.token.claim" => "true" }
      }
    ]
  }), 201)
  client_internal_id = client_response["Location"].to_s.split("/").last

  user_response = require_status!(request(:post, "#{admin_base}/users", headers: admin_headers, json: {
    "username" => USERNAME, "email" => USERNAME, "emailVerified" => true,
    "firstName" => "OAuth", "lastName" => "Validator", "enabled" => true,
    "requiredActions" => [],
    "credentials" => [{ "type" => "password", "value" => USER_PASSWORD, "temporary" => false }]
  }), 201)
  user_internal_id = user_response["Location"].to_s.split("/").last

  verifier = Base64.urlsafe_encode64(SecureRandom.random_bytes(48), padding: false)
  challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  state = SecureRandom.hex(16)
  authorize_uri = URI("#{ISSUER}/protocol/openid-connect/auth")
  authorize_uri.query = URI.encode_www_form(
    "response_type" => "code", "client_id" => CLIENT_ID, "redirect_uri" => REDIRECT_URI,
    "scope" => "openid", "state" => state,
    "code_challenge" => challenge, "code_challenge_method" => "S256"
  )

  cookies = {}
  login_url = authorize_uri.to_s
  login_response = nil
  5.times do
    login_response = request(:get, login_url, headers: { "Cookie" => cookies.map { |key, value| "#{key}=#{value}" }.join("; ") })
    Array(login_response.get_fields("Set-Cookie")).each { |cookie| key, value = cookie.split(";", 2).first.split("=", 2); cookies[key] = value }
    break unless [302, 303, 307, 308].include?(login_response.code.to_i)

    next_uri = URI.join(login_url, login_response["Location"].to_s)
    unless next_uri.host == authorize_uri.host && next_uri.port == authorize_uri.port
      params = URI.decode_www_form(next_uri.query.to_s).to_h
      abort("local Keycloak redirected outside the loopback origin (#{next_uri.host}:#{next_uri.port}#{next_uri.path}, oauth_error=#{params["error"] || "none"})")
    end
    login_url = next_uri.to_s
  end
  require_status!(login_response, 200)
  action = CGI.unescapeHTML(login_response.body[/<form[^>]+(?:id="kc-form-login"[^>]+action|action)="([^"]+)"/, 1].to_s)
  abort("local Keycloak login form was not found") if action.empty?

  login_submit = request(:post, action, headers: { "Cookie" => cookies.map { |key, value| "#{key}=#{value}" }.join("; ") }, form: {
    "username" => USERNAME, "password" => USER_PASSWORD, "credentialId" => ""
  })
  require_status!(login_submit, 302, 303)
  callback = URI(login_submit["Location"].to_s)
  callback_params = URI.decode_www_form(callback.query.to_s).to_h
  abort("OAuth state mismatch") unless callback_params["state"] == state
  code = callback_params["code"]
  abort("authorization code was not returned") if code.to_s.empty?

  token_response = require_status!(request(:post, "#{ISSUER}/protocol/openid-connect/token", form: {
    "grant_type" => "authorization_code", "client_id" => CLIENT_ID,
    "redirect_uri" => REDIRECT_URI, "code" => code, "code_verifier" => verifier
  }), 200)
  access_token = JSON.parse(token_response.body).fetch("access_token")

  test_env = {
    "CEERAT_LOCAL_OAUTH_ACCESS_TOKEN" => access_token,
    "CEERAT_LOCAL_OAUTH_ISSUER" => ISSUER,
    "CEERAT_LOCAL_OAUTH_CLIENT_ID" => CLIENT_ID
  }
  ok = system(test_env, "go", "test", "./security", "-run", "TestOAuthValidatorAgainstLocalKeycloak", "-count=1", chdir: CONTRACT_ROOT)
  unless ok
    payload = access_token.split(".")[1]
    padding = "=" * ((4 - payload.length % 4) % 4)
    claim_names = JSON.parse(Base64.urlsafe_decode64(payload + padding)).keys.sort
    warn("local token claim names: #{claim_names.join(",")}")
    abort("local OAuth validator Go acceptance failed")
  end
  service_env = test_env.merge("CEERAT_TEST_DATABASE_URL" => ENV.fetch("CEERAT_TEST_DATABASE_URL", "postgres://postgres:postgres@localhost:55434/postgres?sslmode=disable"))
  service_root = File.join(STACK_ROOT, "services-repo", "services", "ceerat-user-service")
  ok = system(service_env, "go", "test", "./user", "-run", "TestOAuthIdentityResolverAgainstLocalKeycloak", "-count=1", chdir: service_root)
  abort("local OAuth identity resolver acceptance failed") unless ok
  puts("Local Keycloak PKCE validator and CEERAT identity-resolution acceptance passed")
ensure
  request(:delete, "#{admin_base}/users/#{user_internal_id}", headers: admin_headers) if user_internal_id && !user_internal_id.empty?
  request(:delete, "#{admin_base}/clients/#{client_internal_id}", headers: admin_headers) if client_internal_id && !client_internal_id.empty?
end
