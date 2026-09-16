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

issuer = ENV.fetch("CEERAT_LOCAL_OAUTH_ISSUER", "http://localhost:8080/realms/ceerat")
abort("verify-grpc-oauth refuses non-loopback issuer") unless issuer.match?(%r{\Ahttp://(?:localhost|127\.0\.0\.1):\d+/})
grpc_address = ENV.fetch("CEERAT_LOCAL_GRPC_ADDRESS", "127.0.0.1:50051")
abort("verify-grpc-oauth refuses non-loopback gRPC") unless grpc_address.match?(%r{\A(?:localhost|127\.0\.0\.1):\d+\z})
client_id = "ceerat-grpc-dev"
port = Integer(ENV.fetch("CEERAT_GRPC_OAUTH_CALLBACK_PORT", "8767"), 10)
redirect_uri = "http://127.0.0.1:#{port}/callback"

verifier = Base64.urlsafe_encode64(SecureRandom.random_bytes(48), padding: false)
challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
state = SecureRandom.hex(24)
authorize = URI("#{issuer}/protocol/openid-connect/auth")
authorize.query = URI.encode_www_form(response_type: "code", client_id: client_id, redirect_uri: redirect_uri,
  scope: "openid profile email ceerat.profile.read offline_access", state: state,
  code_challenge: challenge, code_challenge_method: "S256", kc_idp_hint: "google", prompt: "login")

listener = TCPServer.new("127.0.0.1", port)
puts("Complete Google authentication in the opened browser window.")
system("open", authorize.to_s) or abort("could not open browser")
socket = Timeout.timeout(300) { listener.accept }
path = socket.gets.to_s.split(" ")[1].to_s
while (line = socket.gets)
  break if line == "\r\n"
end
params = URI.decode_www_form(URI(path).query.to_s).to_h
ok = params["state"] == state && !params["code"].to_s.empty?
body = ok ? "CEERAT direct gRPC OAuth authentication complete." : "CEERAT direct gRPC OAuth authentication failed."
socket.write("HTTP/1.1 #{ok ? "200 OK" : "400 Bad Request"}\r\nContent-Type: text/plain\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
socket.close; listener.close
abort("authorization callback failed") unless ok

uri = URI("#{issuer}/protocol/openid-connect/token"); request = Net::HTTP::Post.new(uri)
request.set_form_data(grant_type: "authorization_code", client_id: client_id, redirect_uri: redirect_uri, code: params.fetch("code"), code_verifier: verifier)
response = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 10) { |http| http.request(request) }
abort("authorization-code exchange failed") unless response.code.to_i == 200
token = JSON.parse(response.body).fetch("access_token")
service_root = File.expand_path("../../../services-repo/services/ceerat-user-service", __dir__)
env = { "CEERAT_LOCAL_OAUTH_ACCESS_TOKEN" => token, "CEERAT_LOCAL_GRPC_ADDRESS" => grpc_address }
abort("direct protected gRPC OAuth acceptance failed") unless system(env, "go", "test", ".", "-run", "TestDirectGRPCOAuthAgainstLocalService", "-count=1", chdir: service_root)
puts(JSON.generate(schema_version: "1.0", result: "PASS", issuer: "loopback", grpc_target: "loopback", flow: "authorization_code_pkce_s256", client_id: client_id, token_logged: false))
