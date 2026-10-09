package preferencesintegration

import (
	"bytes"
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	pb "github.com/kaansari/ceerat-contracts/proto/preference"
	"github.com/kaansari/ceerat-contracts/security"
	"github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway/internal/auth"
	"github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway/internal/gateway"
	"github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway/internal/platform"
	"github.com/kaansari/ceerat-platform/services/ceerat-user-service/preferences"
	"github.com/kaansari/ceerat-platform/services/ceerat-user-service/user"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
	"gorm.io/gorm/logger"
)

const integrationClient = "ceerat-mcp-codex-dev"
const readWriteScopes = "ceerat.preferences.read ceerat.preferences.write"

// Log capture is synchronized because actual HTTP and gRPC handlers run in
// independent goroutines. Only assertions access the resulting private buffer.
type logCapture struct {
	mu sync.Mutex
	bytes.Buffer
}

func (b *logCapture) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.Buffer.Write(p)
}
func (b *logCapture) snapshot() string { b.mu.Lock(); defer b.mu.Unlock(); return b.Buffer.String() }

type integrationFixture struct {
	audits                     *logCapture
	db                         *gorm.DB
	private                    pb.PreferenceServiceClient
	gateway                    *gateway.Server
	issuer, databaseURL, nonce string
	key                        *rsa.PrivateKey
	logger                     *slog.Logger
	logs                       *logCapture
	validator                  *auth.JWTValidator
	client                     *platform.Client
	grpcServer                 *grpc.Server
	dropNextReply              atomic.Bool
	malformedRead              atomic.Bool
	writes                     atomic.Int64
}

// RBAC's production interceptor consumes the actual bootstrapped permission
// rows. The service's concrete cache belongs to package main and is not exported;
// this boundary adapter queries that same durable canonical permission table.
type databasePermissions struct{ db *gorm.DB }

func (p databasePermissions) Refresh(context.Context) error { return nil }
func (p databasePermissions) IsAllowed(ctx context.Context, role, method string) (bool, error) {
	var allowed bool
	err := p.db.WithContext(ctx).Raw(`SELECT EXISTS(SELECT 1 FROM role_permissions p JOIN roles r ON r.id=p.role_id WHERE r.name=? AND p.grpc_method IN (?, '*'))`, role, method).Scan(&allowed).Error
	return allowed, err
}

func newIntegrationFixture(t *testing.T) *integrationFixture {
	t.Helper()
	dsn := os.Getenv("CEERAT_PR08_DATABASE_URL")
	if dsn == "" {
		t.Fatal("integration requires the disposable bootstrapped database")
	}
	db, err := gorm.Open(postgres.Open(dsn), &gorm.Config{Logger: logger.Discard})
	if err != nil {
		t.Fatal("open integration database failed")
	}
	sqlDB, err := db.DB()
	if err != nil {
		t.Fatal("open database handle failed")
	}
	t.Cleanup(func() { _ = sqlDB.Close() })
	// Apply canonical permission inventory to fixture setup exactly as the
	// production startup reconciliation does; checks still run through SQL RBAC.
	for role, methods := range security.DefaultRolePermissions {
		if err := db.Exec(`INSERT INTO roles(id,name,description,created_at,updated_at) VALUES (?,?,?,now(),now()) ON CONFLICT(name) DO UPDATE SET updated_at=now()`, uuid.NewString(), role, "Canonical integration fixture role").Error; err != nil {
			t.Fatal("canonical role fixture setup failed")
		}
		if err := db.Exec(`DELETE FROM role_permissions WHERE role_id=(SELECT id FROM roles WHERE name=?) AND grpc_method NOT IN ?`, role, methods).Error; err != nil {
			t.Fatal("canonical permission reconciliation failed")
		}

		for _, method := range methods {
			if err := db.Exec(`INSERT INTO role_permissions(id,role_id,grpc_method,created_at,updated_at) SELECT ?,r.id,?,now(),now() FROM roles r WHERE r.name=? AND NOT EXISTS (SELECT 1 FROM role_permissions p WHERE p.role_id=r.id AND p.grpc_method=?)`, uuid.NewString(), method, role, method).Error; err != nil {
				t.Fatal("canonical permission fixture setup failed")
			}
		}
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal("generate fixture signing key failed")
	}
	jwks := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = json.NewEncoder(w).Encode(map[string]any{"keys": []any{map[string]any{"kty": "RSA", "kid": "integration-key", "alg": "RS256", "use": "sig", "n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()), "e": "AQAB"}}})
	}))
	t.Cleanup(jwks.Close)
	logs := &logCapture{}
	f := &integrationFixture{db: db, key: key, issuer: jwks.URL, databaseURL: dsn, nonce: uuid.NewString(), logs: logs, audits: &logCapture{}, logger: slog.New(slog.NewJSONHandler(logs, nil))}
	repo, err := preferences.NewRepository(db)
	if err != nil {
		t.Fatal("create preference repository failed")
	}
	svc, err := preferences.NewReadService(repo, f.logger, bytes.Repeat([]byte{7}, 32))
	if err != nil {
		t.Fatal("create preference service failed")
	}
	validator, err := security.NewOAuthAccessTokenValidator(security.OAuthValidatorConfig{Issuer: jwks.URL, Audience: security.CanonicalAPIAudience, JWKSURL: jwks.URL, AllowedClients: []string{integrationClient}})
	if err != nil {
		t.Fatal("create private OAuth validator failed")
	}
	resolver, err := user.NewOAuthIdentityResolver(user.NewRepository(db), []string{integrationClient}, map[string]user.ProvisioningPolicy{integrationClient: {Role: "customer", Status: "active", CreateCustomer: true}})
	if err != nil {
		t.Fatal("create canonical identity resolver failed")
	}
	oauth := security.NewOAuthInterceptor(validator, nil).WithLogger(f.logger)
	identity := security.NewOAuthIdentityInterceptor(resolver, nil)
	scopes := security.NewOAuthScopeInterceptor(security.MethodScopePolicies, nil)
	rbac := security.NewRBACInterceptor(databasePermissions{db}, nil)
	f.grpcServer = grpc.NewServer(grpc.ChainUnaryInterceptor(f.failureHook, oauth.Unary(), identity.Unary(), scopes.Unary(), rbac.Unary()))
	pb.RegisterPreferenceServiceServer(f.grpcServer, svc)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal("start private fixture listener failed")
	}
	go func() { _ = f.grpcServer.Serve(listener) }()
	t.Cleanup(func() { f.grpcServer.Stop(); _ = listener.Close() })
	conn, err := grpc.NewClient(listener.Addr().String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatal("create private fixture client failed")
	}
	t.Cleanup(func() { _ = conn.Close() })
	f.private = pb.NewPreferenceServiceClient(conn)
	f.client, err = platform.New(listener.Addr().String(), platform.TransportConfig{Mode: "insecure"})
	if err != nil {
		t.Fatal("create actual gateway platform client failed")
	}
	t.Cleanup(func() { _ = f.client.Close() })
	f.validator = &auth.JWTValidator{Issuer: f.issuer, Audience: security.CanonicalAPIAudience, JWKSURL: f.issuer, SubjectClaim: "ceerat_user_id", ClientIDClaim: "azp", AllowedClientIDs: map[string]bool{integrationClient: true}}
	f.gateway = f.newGateway(t)
	t.Cleanup(func() { f.assertAuditPrivacy(t) })
	return f
}
func (f *integrationFixture) newGateway(t *testing.T) *gateway.Server {
	t.Helper()
	state, err := gateway.NewState(f.databaseURL)
	if err != nil {
		t.Fatal("open durable gateway state failed")
	}
	t.Cleanup(func() { _ = state.Close() })
	return &gateway.Server{Validator: f.validator, Platform: f.client, State: state, Limiter: gateway.NewRateLimiter(state), ResourceURL: "http://127.0.0.1:8090/mcp", AuthorizationServer: f.issuer, Logger: f.logger, Timeout: 3 * time.Second}
}
func (f *integrationFixture) sign(subject, scope string, changes map[string]any) string {
	header := map[string]any{"alg": "RS256", "typ": "JWT", "kid": "integration-key"}
	claims := map[string]any{"iss": f.issuer, "sub": subject, "azp": integrationClient, "aud": security.CanonicalAPIAudience, "scope": scope, "iat": time.Now().Add(-time.Minute).Unix(), "exp": time.Now().Add(time.Hour).Unix(), "jti": "token-" + f.nonce + "-" + subject, "sid": "session-" + f.nonce + "-" + subject, "email": subject + "-" + f.nonce + "@fixture.invalid", "email_verified": true, "given_name": "Private fixture", "family_name": "Customer"}
	for k, v := range changes {
		if k == "alg" || k == "kid" {
			header[k] = v
		} else {
			claims[k] = v
		}
	}
	a, _ := json.Marshal(header)
	b, _ := json.Marshal(claims)
	input := base64.RawURLEncoding.EncodeToString(a) + "." + base64.RawURLEncoding.EncodeToString(b)
	digest := sha256.Sum256([]byte(input))
	sig, err := rsa.SignPKCS1v15(rand.Reader, f.key, crypto.SHA256, digest[:])
	if err != nil {
		panic("fixture signing failure")
	}
	return input + "." + base64.RawURLEncoding.EncodeToString(sig)
}
func (f *integrationFixture) ctx(token string) context.Context {
	return metadata.NewOutgoingContext(context.Background(), metadata.Pairs("authorization", "Bearer "+token))
}
func call(t *testing.T, s *gateway.Server, token, tool string, args any) map[string]any {
	t.Helper()
	body, err := json.Marshal(map[string]any{"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": map[string]any{"name": tool, "arguments": args}})
	if err != nil {
		t.Fatal("encode integration tool arguments failed")
	}
	req := httptest.NewRequest(http.MethodPost, "/mcp", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	s.Routes().ServeHTTP(w, req)
	var response map[string]any
	if json.Unmarshal(w.Body.Bytes(), &response) != nil {
		t.Fatal("invalid gateway JSON response")
	}
	result, ok := response["result"].(map[string]any)
	if !ok {
		t.Fatal("gateway returned JSON-RPC error")
	}
	env, ok := result["structuredContent"].(map[string]any)
	if !ok {
		t.Fatal("gateway returned no typed envelope")
	}
	return env
}
func readyCode(s *gateway.Server, token string) int {
	req := httptest.NewRequest(http.MethodGet, "/readyz", nil)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	w := httptest.NewRecorder()
	s.Routes().ServeHTTP(w, req)
	return w.Code
}
func requireOK(t *testing.T, env map[string]any) map[string]any {
	t.Helper()
	if env["ok"] != true {
		code := "unknown"
		if e, ok := env["error"].(map[string]any); ok {
			code, _ = e["code"].(string)
		}
		t.Fatalf("integration operation rejected: %s", code)
	}
	data, ok := env["data"].(map[string]any)
	if !ok {
		t.Fatal("missing integration response data")
	}
	return data
}
func errorCode(t *testing.T, env map[string]any) string {
	t.Helper()
	if env["ok"] != false {
		t.Fatal("denied operation unexpectedly succeeded")
	}
	e, ok := env["error"].(map[string]any)
	if !ok {
		t.Fatal("missing denied operation error")
	}
	code, _ := e["code"].(string)
	return code
}
func privateStringsAbsent(t *testing.T, value any, needles ...string) {
	t.Helper()
	b, _ := json.Marshal(value)
	for _, needle := range needles {
		if needle != "" && strings.Contains(string(b), needle) {
			t.Fatal("private fixture content leaked into diagnostics")
		}
	}
}

// Inject transport failures only at the external server boundary after the
// actual production handler commits. Status and retry assertions retain real DB.
func (f *integrationFixture) failureHook(ctx context.Context, req any, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (any, error) {
	ctx, audit := security.WithAudit(ctx)
	requestID, traceparent := security.CorrelationFromIncoming(ctx)
	defer func() {
		_ = json.NewEncoder(f.audits).Encode(auditRecord{Method: info.FullMethod, RequestID: requestID, Traceparent: traceparent, Snapshot: audit.Snapshot()})
	}()

	if info.FullMethod == "/preference.PreferenceService/UpsertMyPreference" {
		f.writes.Add(1)
	}
	result, err := handler(ctx, req)
	if err == nil && info.FullMethod == "/preference.PreferenceService/UpsertMyPreference" && f.dropNextReply.Swap(false) {
		return nil, status.Error(codes.Unavailable, "response unavailable")
	}
	if err == nil && info.FullMethod == "/preference.PreferenceService/ListMyPreferences" && f.malformedRead.Load() {
		result.(*pb.ListMyPreferencesResponse).ProtoReflect().SetUnknown([]byte{0xf8, 0x07, 1})
	}
	return result, err
}

type auditRecord struct {
	Method, RequestID, Traceparent string
	Snapshot                       security.AuditSnapshot
}

func (f *integrationFixture) assertAuditPrivacy(t *testing.T) {
	t.Helper()
	dec := json.NewDecoder(strings.NewReader(f.audits.snapshot()))
	count := 0
	for dec.More() {
		var record auditRecord
		if dec.Decode(&record) != nil {
			t.Error("invalid captured audit record")
			return
		}
		count++
		if !strings.HasPrefix(record.Method, "/preference.PreferenceService/") || !security.ValidRequestID(record.RequestID) || !security.ValidTraceparent(record.Traceparent) {
			t.Error("audit correlation or method was not bounded")
		}
		for _, digest := range []string{record.Snapshot.IssuerID, record.Snapshot.SubjectID, record.Snapshot.SessionID, record.Snapshot.TokenID, record.Snapshot.UserID} {
			if digest != "" {
				if decoded, err := hex.DecodeString(digest); err != nil || len(decoded) != 12 {
					t.Error("audit authority was not safely digested")
				}
			}
		}
		if record.Snapshot.ClientID != "" && record.Snapshot.ClientID != integrationClient {
			t.Error("audit contains undeclared OAuth client")
		}
		switch record.Snapshot.Category {
		case "authentication", "identity", "scope", "rbac", "dependency", "handler":
		default:
			t.Error("audit reason category is not closed")
		}
		switch record.Snapshot.Decision {
		case "denied", "allowed", "not_evaluated":
		default:
			t.Error("audit decision is not closed")
		}
	}
	if count == 0 {
		t.Error("no production authorization audit captured")
	}
	privateStringsAbsent(t, f.audits.snapshot(), f.nonce, f.databaseURL, "Private fixture", "Customer", "Bearer ", "SELECT ", "INSERT ")
}
