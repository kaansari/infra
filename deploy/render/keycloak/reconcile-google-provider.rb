#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

root = File.expand_path("../../..", __dir__)
server = ENV.fetch("CEERAT_KEYCLOAK_SERVER", "http://localhost:8080").sub(%r{/+$}, "")
realm = ENV.fetch("CEERAT_KEYCLOAK_REALM", "ceerat")
local = URI(server).host.match?(%r{\A(?:localhost|127\.0\.0\.1)\z})
abort("live Google reconciliation requires CEERAT_ALLOW_LIVE_GOOGLE_RECONCILE=true") unless local || ENV["CEERAT_ALLOW_LIVE_GOOGLE_RECONCILE"] == "true"

admin_user = ENV.fetch("CEERAT_KEYCLOAK_ADMIN_USERNAME", "admin")
password_file = ENV.fetch("CEERAT_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(File.expand_path("..", root), ".run", "keycloak-admin-password"))
admin_password = ENV["CEERAT_KEYCLOAK_ADMIN_PASSWORD"]
admin_password = File.read(password_file).strip if admin_password.to_s.empty? && File.file?(password_file)
abort("Keycloak admin password is required") if admin_password.to_s.empty?
google_id = ENV["CEERAT_GOOGLE_CLIENT_ID"].to_s.strip
google_secret = ENV["CEERAT_GOOGLE_CLIENT_SECRET"].to_s.strip
abort("Google client ID and secret are required") if google_id.empty? || google_secret.empty?

ACCOUNT_DEFAULT_SCOPES = %w[web-origins acr roles profile basic email].freeze

def request(method, url, headers: {}, form: nil, json: nil)
  uri = URI(url)
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method)
  req = klass.new(uri)
  headers.each { |key, value| req[key] = value }
  if form
    req.set_form_data(form)
  elsif json
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(json)
  end
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
end

def without_keycloak_ids(value)
  case value
  when Hash
    value.each_with_object({}) do |(key, child), clean|
      clean[key] = without_keycloak_ids(child) unless key == "id"
    end
  when Array
    value.map { |child| without_keycloak_ids(child) }
  else
    value
  end
end

token_response = request(:post, "#{server}/realms/master/protocol/openid-connect/token", form: {
  "grant_type" => "password", "client_id" => "admin-cli", "username" => admin_user, "password" => admin_password
})
abort("Keycloak admin authentication failed") unless token_response.code.to_i == 200
admin_token = JSON.parse(token_response.body).fetch("access_token")
headers = { "Authorization" => "Bearer #{admin_token}" }

template = JSON.parse(File.read(File.join(root, "deploy/render/keycloak/identity-providers/google.json")))
template.fetch("config")["clientId"] = google_id
template.fetch("config")["clientSecret"] = google_secret
base = "#{server}/admin/realms/#{realm}/identity-provider/instances"
existing = request(:get, "#{base}/google", headers: headers)
response = if existing.code.to_i == 200
  request(:put, "#{base}/google", headers: headers, json: template)
else
  request(:post, base, headers: headers, json: template)
end
abort("Google broker reconciliation failed with HTTP #{response.code}") unless [201, 204].include?(response.code.to_i)

# Realm imports that declare their own clientScopes do not receive all of
# Keycloak's built-in account-console scopes. Copy only the standard definitions
# from the installation's master realm, then attach them only to Keycloak's
# account clients. CEERAT API clients retain their explicit least-privilege
# scope assignments.
master_scopes_response = request(:get, "#{server}/admin/realms/master/client-scopes", headers: headers)
target_scopes_response = request(:get, "#{server}/admin/realms/#{realm}/client-scopes", headers: headers)
abort("Could not inspect Keycloak client scopes") unless master_scopes_response.code.to_i == 200 && target_scopes_response.code.to_i == 200
master_scopes = JSON.parse(master_scopes_response.body).to_h { |scope| [scope.fetch("name"), scope] }
target_scopes = JSON.parse(target_scopes_response.body).to_h { |scope| [scope.fetch("name"), scope] }

ACCOUNT_DEFAULT_SCOPES.each do |name|
  next if target_scopes.key?(name)

  definition = without_keycloak_ids(master_scopes.fetch(name))
  created = request(:post, "#{server}/admin/realms/#{realm}/client-scopes", headers: headers, json: definition)
  unless created.code.to_i == 201
    detail = JSON.parse(created.body).fetch("errorMessage", "HTTP #{created.code}") rescue "HTTP #{created.code}"
    abort("Could not create standard Keycloak scope #{name}: #{detail}")
  end
end

target_scopes_response = request(:get, "#{server}/admin/realms/#{realm}/client-scopes", headers: headers)
target_scopes = JSON.parse(target_scopes_response.body).to_h { |scope| [scope.fetch("name"), scope] }
%w[account account-console].each do |client_id|
  clients_response = request(:get, "#{server}/admin/realms/#{realm}/clients?clientId=#{URI.encode_www_form_component(client_id)}", headers: headers)
  client = JSON.parse(clients_response.body).find { |candidate| candidate["clientId"] == client_id }
  abort("Keycloak built-in client #{client_id} is missing") unless client

  ACCOUNT_DEFAULT_SCOPES.each do |name|
    assigned = request(:put, "#{server}/admin/realms/#{realm}/clients/#{client.fetch("id")}/default-client-scopes/#{target_scopes.fetch(name).fetch("id")}", headers: headers)
    abort("Could not assign #{name} to #{client_id}") unless assigned.code.to_i == 204
  end
end

puts("Reconciled Google broker for #{server}/realms/#{realm}")
puts("Reconciled standard Keycloak Account Console scopes")
puts("Register exact callback: #{server}/realms/#{realm}/broker/google/endpoint")
