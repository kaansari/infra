#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

server = ENV.fetch("CEERAT_KEYCLOAK_SERVER", "http://localhost:8080").sub(%r{/+$}, "")
abort("local gRPC client reconciliation refuses non-loopback Keycloak") unless URI(server).host.match?(%r{\A(?:localhost|127\.0\.0\.1)\z})
realm = ENV.fetch("CEERAT_KEYCLOAK_REALM", "ceerat")
root = File.expand_path("../../..", __dir__)
password_file = ENV.fetch("CEERAT_LOCAL_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(File.expand_path("..", root), ".run", "keycloak-admin-password"))
password = File.read(password_file).strip

def request(method, url, headers: {}, form: nil, json: nil)
  uri = URI(url); klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put }.fetch(method); req = klass.new(uri)
  headers.each { |key, value| req[key] = value }
  if form then req.set_form_data(form) elsif json then req["Content-Type"] = "application/json"; req.body = JSON.generate(json) end
  Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 10) { |http| http.request(req) }
end

token_response = request(:post, "#{server}/realms/master/protocol/openid-connect/token", form: {
  grant_type: "password", client_id: "admin-cli", username: "admin", password: password
})
abort("local Keycloak admin authentication failed") unless token_response.code.to_i == 200
headers = { "Authorization" => "Bearer #{JSON.parse(token_response.body).fetch("access_token")}" }
definition = JSON.parse(File.read(File.join(root, "deploy/render/keycloak/clients/ceerat-grpc-dev.json")))
clients = request(:get, "#{server}/admin/realms/#{realm}/clients?clientId=ceerat-grpc-dev", headers: headers)
existing = JSON.parse(clients.body).find { |client| client["clientId"] == "ceerat-grpc-dev" }
response = existing ? request(:put, "#{server}/admin/realms/#{realm}/clients/#{existing.fetch("id")}", headers: headers, json: definition) : request(:post, "#{server}/admin/realms/#{realm}/clients", headers: headers, json: definition)
abort("local gRPC client reconciliation failed with HTTP #{response.code}") unless [201, 204].include?(response.code.to_i)
puts("Reconciled loopback-only ceerat-grpc-dev client")
