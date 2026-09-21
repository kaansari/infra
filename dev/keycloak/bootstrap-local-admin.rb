#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "openssl"
require "uri"

server = ENV.fetch("CEERAT_KEYCLOAK_SERVER", "http://localhost:8080").sub(%r{/+$}, "")
uri = URI(server)
abort("local admin bootstrap accepts loopback Keycloak only") unless
  %w[http https].include?(uri.scheme) && %w[localhost 127.0.0.1].include?(uri.host)

realm = ENV.fetch("CEERAT_KEYCLOAK_REALM", "ceerat")
abort("invalid realm") unless realm.match?(/\A[a-zA-Z0-9_-]+\z/)
email = ENV.fetch("CEERAT_LOCAL_ADMIN_EMAIL", "admin@ceerat.local")
root = File.expand_path("../..", __dir__)
run_dir = File.join(File.expand_path("..", root), ".run")
keycloak_password_file = ENV.fetch("CEERAT_LOCAL_KEYCLOAK_ADMIN_PASSWORD_FILE", File.join(run_dir, "keycloak-admin-password"))
login_password_file = ENV.fetch("CEERAT_LOCAL_ADMIN_PASSWORD_FILE", File.join(run_dir, "admin-login-password"))
keycloak_password = ENV["CEERAT_KEYCLOAK_ADMIN_PASSWORD"] || File.read(keycloak_password_file).strip

Dir.mkdir(run_dir) unless Dir.exist?(run_dir)
unless File.exist?(login_password_file)
  File.open(login_password_file, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(OpenSSL::Random.random_bytes(24).unpack1("H*")) }
end
File.chmod(0o600, login_password_file)
login_password = File.read(login_password_file).strip
File.write(login_password_file, login_password)

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

def success!(response, label, allowed = [200, 201, 204])
  abort("#{label} failed with HTTP #{response.code}") unless allowed.include?(response.code.to_i)
end

token_response = request(:post, "#{server}/realms/master/protocol/openid-connect/token", form: {
  grant_type: "password", client_id: "admin-cli", username: ENV.fetch("CEERAT_KEYCLOAK_ADMIN", "admin"), password: keycloak_password
})
success!(token_response, "local Keycloak admin authentication", [200])
headers = { "Authorization" => "Bearer #{JSON.parse(token_response.body).fetch("access_token")}" }
base = "#{server}/admin/realms/#{realm}"

users_response = request(:get, "#{base}/users?exact=true&email=#{URI.encode_www_form_component(email)}", headers: headers)
success!(users_response, "find local admin", [200])
user = JSON.parse(users_response.body).find { |candidate| candidate["email"]&.casecmp?(email) }
unless user
  create_response = request(:post, "#{base}/users", headers: headers, json: {
    username: email, email: email, emailVerified: true, enabled: true,
    firstName: "Ceerat", lastName: "Admin"
  })
  success!(create_response, "create local admin", [201])
  users_response = request(:get, "#{base}/users?exact=true&email=#{URI.encode_www_form_component(email)}", headers: headers)
  success!(users_response, "reload local admin", [200])
  user = JSON.parse(users_response.body).find { |candidate| candidate["email"]&.casecmp?(email) }
end
abort("local admin not found after creation") unless user
user_id = user.fetch("id")

update_response = request(:put, "#{base}/users/#{user_id}", headers: headers, json: user.merge("enabled" => true, "emailVerified" => true))
success!(update_response, "activate local admin", [204])
password_response = request(:put, "#{base}/users/#{user_id}/reset-password", headers: headers, json: {
  type: "password", temporary: false, value: login_password
})
success!(password_response, "set local admin password", [204])

puts("INITIAL_ADMIN_EMAIL=#{email}")
puts("INITIAL_ADMIN_ISSUER=#{server}/realms/#{realm}")
puts("INITIAL_ADMIN_SUBJECT=#{user_id}")
puts("INITIAL_ADMIN_CLIENT_ID=ceerat-admin-ui")
puts("Admin login password stored in #{login_password_file} with mode 0600")
