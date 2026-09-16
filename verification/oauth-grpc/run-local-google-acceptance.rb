#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "json"
require "net/http"
require "securerandom"
require "socket"
require "timeout"
require "uri"

ISSUER = ENV.fetch("CEERAT_LOCAL_OAUTH_ISSUER", "http://localhost:8080/realms/ceerat")
abort("Google acceptance refuses non-loopback issuer") unless ISSUER.match?(%r{\Ahttp://(?:localhost|127\.0\.0\.1):\d+/})

ROOT = File.expand_path("../..", __dir__)
STACK_ROOT = File.expand_path("..", ROOT)
CONTRACT_ROOT = File.join(STACK_ROOT, "contracts-repo", "packages", "ceerat-contracts")
SERVICE_ROOT = File.join(STACK_ROOT, "services-repo", "services", "ceerat-user-service")
PASSWORD_FILE = ENV.fetch("CEERAT_LOCAL_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(STACK_ROOT, ".run", "keycloak-admin-password"))
CLIENT_ID = "ceerat-google-acceptance-#{SecureRandom.hex(5)}"
CALLBACK_PORT = Integer(ENV.fetch("CEERAT_GOOGLE_CALLBACK_PORT", "8766"), 10)
REDIRECT_URI = "http://127.0.0.1:#{CALLBACK_PORT}/callback"

def request(method, url, headers: {}, form: nil, json: nil)
  uri = URI(url)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, delete: Net::HTTP::Delete }.fetch(method)
  req = klass.new(uri)
  headers.each { |key, value| req[key] = value }
  if form
    req.set_form_data(form)
  elsif json
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(json)
  end
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 10) { |http| http.request(req) }
end

def require_status!(response, *expected)
  return response if expected.include?(response.code.to_i)
  abort("local Google acceptance failed with HTTP #{response.code}")
end

password = File.read(PASSWORD_FILE).strip
token_response = require_status!(request(:post, "http://localhost:8080/realms/master/protocol/openid-connect/token", form: {
  "grant_type" => "password", "client_id" => "admin-cli", "username" => "admin", "password" => password
}), 200)
headers = { "Authorization" => "Bearer #{JSON.parse(token_response.body).fetch("access_token")}" }
admin_base = "http://localhost:8080/admin/realms/ceerat"
client_internal_id = nil

begin
  created = require_status!(request(:post, "#{admin_base}/clients", headers: headers, json: {
    "clientId" => CLIENT_ID, "name" => "Temporary local Google acceptance",
    "enabled" => true, "publicClient" => true, "standardFlowEnabled" => true,
    "implicitFlowEnabled" => false, "directAccessGrantsEnabled" => false,
    "serviceAccountsEnabled" => false, "consentRequired" => false,
    "redirectUris" => [REDIRECT_URI], "webOrigins" => [],
    "attributes" => { "pkce.code.challenge.method" => "S256" },
    "protocolMappers" => [
      { "name" => "subject", "protocol" => "openid-connect", "protocolMapper" => "oidc-sub-mapper", "consentRequired" => false,
        "config" => { "access.token.claim" => "true", "id.token.claim" => "true" } },
      { "name" => "CEERAT API audience", "protocol" => "openid-connect", "protocolMapper" => "oidc-audience-mapper", "consentRequired" => false,
        "config" => { "included.custom.audience" => "ceerat-api", "access.token.claim" => "true", "id.token.claim" => "false" } },
      { "name" => "email", "protocol" => "openid-connect", "protocolMapper" => "oidc-usermodel-property-mapper", "consentRequired" => false,
        "config" => { "user.attribute" => "email", "claim.name" => "email", "jsonType.label" => "String", "access.token.claim" => "true" } },
      { "name" => "email verified", "protocol" => "openid-connect", "protocolMapper" => "oidc-usermodel-property-mapper", "consentRequired" => false,
        "config" => { "user.attribute" => "emailVerified", "claim.name" => "email_verified", "jsonType.label" => "boolean", "access.token.claim" => "true" } },
      { "name" => "given name", "protocol" => "openid-connect", "protocolMapper" => "oidc-usermodel-property-mapper", "consentRequired" => false,
        "config" => { "user.attribute" => "firstName", "claim.name" => "given_name", "jsonType.label" => "String", "access.token.claim" => "true" } },
      { "name" => "family name", "protocol" => "openid-connect", "protocolMapper" => "oidc-usermodel-property-mapper", "consentRequired" => false,
        "config" => { "user.attribute" => "lastName", "claim.name" => "family_name", "jsonType.label" => "String", "access.token.claim" => "true" } }
    ]
  }), 201)
  client_internal_id = created["Location"].to_s.split("/").last

  verifier = Base64.urlsafe_encode64(SecureRandom.random_bytes(48), padding: false)
  challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
  state = SecureRandom.hex(24)
  authorize = URI("#{ISSUER}/protocol/openid-connect/auth")
  authorize.query = URI.encode_www_form(
    response_type: "code", client_id: CLIENT_ID, redirect_uri: REDIRECT_URI,
    scope: "openid", state: state, code_challenge: challenge,
    code_challenge_method: "S256", kc_idp_hint: "google", prompt: "login"
  )

  listener = TCPServer.new("127.0.0.1", CALLBACK_PORT)
  puts("Browser login required; complete Google authentication in the opened window.")
  system("open", authorize.to_s) or abort("could not open browser")
  socket = Timeout.timeout(300) { listener.accept }
  request_line = socket.gets.to_s
  callback_path = request_line.split(" ")[1].to_s
  while (line = socket.gets)
    break if line == "\r\n"
  end
  params = URI.decode_www_form(URI(callback_path).query.to_s).to_h
  success = params["state"] == state && !params["code"].to_s.empty?
  body = success ? "CEERAT local Google authentication completed. You may close this window." : "CEERAT local Google authentication failed."
  socket.write("HTTP/1.1 #{success ? "200 OK" : "400 Bad Request"}\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
  socket.close
  listener.close
  abort("Google authorization failed: #{params["error"] || "invalid callback"}") unless success

  exchanged = require_status!(request(:post, "#{ISSUER}/protocol/openid-connect/token", form: {
    grant_type: "authorization_code", client_id: CLIENT_ID, redirect_uri: REDIRECT_URI,
    code: params.fetch("code"), code_verifier: verifier
  }), 200)
  access_token = JSON.parse(exchanged.body).fetch("access_token")

  env = { "CEERAT_LOCAL_OAUTH_ACCESS_TOKEN" => access_token, "CEERAT_LOCAL_OAUTH_ISSUER" => ISSUER, "CEERAT_LOCAL_OAUTH_CLIENT_ID" => CLIENT_ID }
  abort("shared OAuth validator rejected Google-brokered token") unless system(env, "go", "test", "./security", "-run", "TestOAuthValidatorAgainstLocalKeycloak", "-count=1", chdir: CONTRACT_ROOT)
  service_env = env.merge("CEERAT_TEST_DATABASE_URL" => ENV.fetch("CEERAT_TEST_DATABASE_URL", "postgres://postgres:postgres@localhost:55434/postgres?sslmode=disable"))
  abort("CEERAT identity resolver rejected Google-brokered token") unless system(service_env, "go", "test", "./user", "-run", "TestOAuthIdentityResolverAgainstLocalKeycloak", "-count=1", chdir: SERVICE_ROOT)
  puts("Google -> Keycloak -> CEERAT API token validation and idempotent identity resolution passed")
ensure
  request(:delete, "#{admin_base}/clients/#{client_internal_id}", headers: headers) if client_internal_id && !client_internal_id.empty?
end
