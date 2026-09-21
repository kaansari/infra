#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

infra = File.expand_path("../..", __dir__)
workspace = File.expand_path("..", infra)
server = ENV.fetch("CEERAT_KEYCLOAK_SERVER", "http://localhost:8080").sub(%r{/+$}, "")
realm = ENV.fetch("CEERAT_KEYCLOAK_REALM", "ceerat")
abort("browser-client reconciliation is local only") unless URI(server).host.match?(%r{\A(?:localhost|127\.0\.0\.1)\z})

admin_user = ENV.fetch("CEERAT_KEYCLOAK_ADMIN_USERNAME", ENV.fetch("CEERAT_KEYCLOAK_ADMIN", "admin"))
password_file = ENV.fetch("CEERAT_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(workspace, ".run", "keycloak-admin-password"))
admin_password = ENV["CEERAT_KEYCLOAK_ADMIN_PASSWORD"]
admin_password = File.read(password_file).strip if admin_password.to_s.empty? && File.file?(password_file)
abort("Keycloak admin password is required") if admin_password.to_s.empty?

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

token_response = nil
30.times do
  begin
    token_response = request(:post, "#{server}/realms/master/protocol/openid-connect/token", form: {
      "grant_type" => "password", "client_id" => "admin-cli", "username" => admin_user, "password" => admin_password
    })
    break if token_response.code.to_i == 200
  rescue EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET, Net::OpenTimeout, Net::ReadTimeout
    # Keycloak is still starting.
  end
  sleep 1
end
abort("Keycloak admin authentication failed") unless token_response&.code.to_i == 200
headers = { "Authorization" => "Bearer #{JSON.parse(token_response.body).fetch("access_token")}" }
admin_base = "#{server}/admin/realms/#{realm}"

scope_dir = File.join(infra, "deploy/render/keycloak/client-scopes")
Dir[File.join(scope_dir, "*.json")].sort.each do |path|
  definition = JSON.parse(File.read(path))
  scopes = JSON.parse(request(:get, "#{admin_base}/client-scopes", headers: headers).body)
  existing = scopes.find { |scope| scope["name"] == definition.fetch("name") }
  response = if existing
    request(:put, "#{admin_base}/client-scopes/#{existing.fetch("id")}", headers: headers, json: definition)
  else
    request(:post, "#{admin_base}/client-scopes", headers: headers, json: definition)
  end
  abort("Could not reconcile scope #{definition.fetch("name")}: HTTP #{response.code}") unless [201, 204].include?(response.code.to_i)
end

scope_ids = JSON.parse(request(:get, "#{admin_base}/client-scopes", headers: headers).body).to_h { |scope| [scope.fetch("name"), scope.fetch("id")] }
%w[ceerat-web-ui ceerat-customer-ui].each do |client_id|
  definition = JSON.parse(File.read(File.join(infra, "deploy/render/keycloak/clients/#{client_id}.json")))
  candidates = JSON.parse(request(:get, "#{admin_base}/clients?clientId=#{URI.encode_www_form_component(client_id)}", headers: headers).body)
  existing = candidates.find { |client| client["clientId"] == client_id }
  response = if existing
    request(:put, "#{admin_base}/clients/#{existing.fetch("id")}", headers: headers, json: definition)
  else
    request(:post, "#{admin_base}/clients", headers: headers, json: definition)
  end
  abort("Could not reconcile #{client_id}: HTTP #{response.code}") unless [201, 204].include?(response.code.to_i)

  candidates = JSON.parse(request(:get, "#{admin_base}/clients?clientId=#{URI.encode_www_form_component(client_id)}", headers: headers).body)
  internal_id = candidates.find { |client| client["clientId"] == client_id }.fetch("id")
  definition.fetch("optionalClientScopes").reject { |name| name == "offline_access" }.each do |name|
    response = request(:put, "#{admin_base}/clients/#{internal_id}/optional-client-scopes/#{scope_ids.fetch(name)}", headers: headers)
    abort("Could not assign #{name} to #{client_id}") unless response.code.to_i == 204
  end
end

all_clients = JSON.parse(request(:get, "#{admin_base}/clients", headers: headers).body)
%w[ceerat-web-ui ceerat-customer-ui].each do |client_id|
  count = all_clients.count { |client| client["clientId"] == client_id }
  abort("Expected one #{client_id} client, found #{count}") unless count == 1
end
scope_names = JSON.parse(request(:get, "#{admin_base}/client-scopes", headers: headers).body).map { |scope| scope.fetch("name") }
scope_counts = scope_names.each_with_object(Hash.new(0)) { |name, counts| counts[name] += 1 }
duplicates = scope_counts.select { |_name, count| count > 1 }.keys
abort("Duplicate client scopes found: #{duplicates.join(", ")}") unless duplicates.empty?

puts("Reconciled ceerat-web-ui and ceerat-customer-ui for #{server}/realms/#{realm}")
