#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

server = ENV.fetch("CEERAT_KEYCLOAK_SERVER", "http://localhost:8080").sub(%r{/+$}, "")
abort("local Google broker verification refuses non-loopback Keycloak") unless URI(server).host.match?(%r{\A(?:localhost|127\.0\.0\.1)\z})
realm = ENV.fetch("CEERAT_KEYCLOAK_REALM", "ceerat")
root = File.expand_path("../..", __dir__)
stack_root = File.expand_path("..", root)
password_file = ENV.fetch("CEERAT_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(stack_root, ".run", "keycloak-admin-password"))
password = File.read(password_file).strip

def request(method, url, headers: {}, form: nil)
  uri = URI(url)
  req = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
  headers.each { |key, value| req[key] = value }
  req.set_form_data(form) if form
  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 3, read_timeout: 5) { |http| http.request(req) }
end

token_response = request(:post, "#{server}/realms/master/protocol/openid-connect/token", form: {
  "grant_type" => "password", "client_id" => "admin-cli", "username" => "admin", "password" => password
})
abort("local Keycloak admin authentication failed") unless token_response.code.to_i == 200
headers = { "Authorization" => "Bearer #{JSON.parse(token_response.body).fetch("access_token")}" }
provider_response = request(:get, "#{server}/admin/realms/#{realm}/identity-provider/instances/google", headers: headers)
provider = provider_response.code.to_i == 200 ? JSON.parse(provider_response.body) : nil
if provider
  abort("local Google provider stores upstream tokens") unless provider["storeToken"] == false
  abort("local Google provider scope is not minimal") unless provider.dig("config", "defaultScope") == "openid profile email"
end

expected_account_scopes = %w[web-origins acr roles profile basic email]
%w[account account-console].each do |client_id|
  clients_response = request(:get, "#{server}/admin/realms/#{realm}/clients?clientId=#{client_id}", headers: headers)
  client = JSON.parse(clients_response.body).find { |candidate| candidate["clientId"] == client_id }
  abort("local Keycloak #{client_id} client is missing") unless client
  scopes_response = request(:get, "#{server}/admin/realms/#{realm}/clients/#{client.fetch("id")}/default-client-scopes", headers: headers)
  abort("could not inspect #{client_id} default scopes") unless scopes_response.code.to_i == 200
  scope_names = JSON.parse(scopes_response.body).map { |scope| scope.fetch("name") }
  missing = expected_account_scopes - scope_names
  abort("#{client_id} is missing standard scopes: #{missing.join(", ")}") unless missing.empty?
end

flows_response = request(:get, "#{server}/admin/realms/#{realm}/authentication/flows", headers: headers)
abort("could not inspect local authentication flows") unless flows_response.code.to_i == 200
flow_alias = provider ? provider["firstBrokerLoginFlowAlias"] : "first broker login"
flow = JSON.parse(flows_response.body).find { |candidate| candidate["alias"] == flow_alias }
abort("first broker login flow is missing") unless flow
flow_path = URI.encode_www_form_component(flow.fetch("alias")).gsub("+", "%20")
executions_response = request(:get, "#{server}/admin/realms/#{realm}/authentication/flows/#{flow_path}/executions", headers: headers)
abort("could not inspect first broker login executions") unless executions_response.code.to_i == 200
providers = JSON.parse(executions_response.body).map { |execution| execution["providerId"] }.compact
abort("unsafe automatic existing-user linking is enabled") if providers.include?("idp-auto-link")
abort("explicit existing-account confirmation is missing") unless providers.include?("idp-confirm-link")
if provider
  puts("Local Google broker and explicit account-link flow verification passed")
else
  puts("Local explicit account-link flow passed; Google provider awaits development credentials")
end
