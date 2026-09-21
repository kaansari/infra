#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

server = ENV.fetch("CEERAT_KEYCLOAK_SERVER", "http://localhost:8080").sub(%r{/+$}, "")
uri = URI(server)
abort("admin client reconciliation accepts loopback Keycloak only") unless
  %w[http https].include?(uri.scheme) && %w[localhost 127.0.0.1].include?(uri.host)

realm = ENV.fetch("CEERAT_KEYCLOAK_REALM", "ceerat")
abort("invalid realm") unless realm.match?(/\A[a-zA-Z0-9_-]+\z/)
root = File.expand_path("../..", __dir__)
password_file = ENV.fetch("CEERAT_LOCAL_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(File.expand_path("..", root), ".run", "keycloak-admin-password"))
password = ENV["CEERAT_KEYCLOAK_ADMIN_PASSWORD"] || File.read(password_file).strip
definition = JSON.parse(File.read(File.join(__dir__, "ceerat-realm.json")))
admin_client = definition.fetch("clients").find { |client| client["clientId"] == "ceerat-admin-ui" }
abort("admin client missing from local realm definition") unless admin_client
scope_names = admin_client.fetch("optionalClientScopes")
scope_definitions = definition.fetch("clientScopes").select { |scope| scope_names.include?(scope["name"]) }
abort("admin scope definitions are incomplete") unless scope_definitions.length == scope_names.length

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
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 10) { |http| http.request(req) }
end

def success!(response, label)
  abort("#{label} failed with HTTP #{response.code}") unless [200, 201, 204].include?(response.code.to_i)
end

token_response = request(:post, "#{server}/realms/master/protocol/openid-connect/token", form: {
  grant_type: "password", client_id: "admin-cli", username: ENV.fetch("CEERAT_KEYCLOAK_ADMIN", "admin"), password: password
})
success!(token_response, "local Keycloak admin authentication")
headers = { "Authorization" => "Bearer #{JSON.parse(token_response.body).fetch("access_token")}" }
base = "#{server}/admin/realms/#{realm}"

scope_response = request(:get, "#{base}/client-scopes", headers: headers)
success!(scope_response, "list client scopes")
existing_scopes = JSON.parse(scope_response.body).to_h { |scope| [scope.fetch("name"), scope.fetch("id")] }
scope_definitions.each do |scope|
  name = scope.fetch("name")
  id = existing_scopes[name]
  response = if id
    request(:put, "#{base}/client-scopes/#{id}", headers: headers, json: scope)
  else
    request(:post, "#{base}/client-scopes", headers: headers, json: scope)
  end
  success!(response, "reconcile #{name}")
end

clients_response = request(:get, "#{base}/clients?clientId=ceerat-admin-ui", headers: headers)
success!(clients_response, "find admin client")
existing_client = JSON.parse(clients_response.body).find { |client| client["clientId"] == "ceerat-admin-ui" }
response = if existing_client
  request(:put, "#{base}/clients/#{existing_client.fetch('id')}", headers: headers, json: admin_client)
else
  request(:post, "#{base}/clients", headers: headers, json: admin_client)
end
success!(response, "reconcile admin client")

clients_response = request(:get, "#{base}/clients?clientId=ceerat-admin-ui", headers: headers)
success!(clients_response, "verify admin client")
client_id = JSON.parse(clients_response.body).find { |client| client["clientId"] == "ceerat-admin-ui" }&.fetch("id")
abort("admin client was not found after reconciliation") unless client_id

scope_response = request(:get, "#{base}/client-scopes", headers: headers)
success!(scope_response, "verify client scopes")
scope_ids = JSON.parse(scope_response.body).to_h { |scope| [scope.fetch("name"), scope.fetch("id")] }
scope_names.each do |name|
  id = scope_ids.fetch(name)
  success!(request(:put, "#{base}/clients/#{client_id}/optional-client-scopes/#{id}", headers: headers), "assign #{name}")
end

puts("Reconciled loopback ceerat-admin-ui client and #{scope_names.length} admin scopes")
