module github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway/integration/preferences

go 1.26.2

require (
	github.com/google/uuid v1.6.0
	github.com/kaansari/ceerat-contracts v0.0.0
	github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway v0.0.0
	github.com/kaansari/ceerat-platform/services/ceerat-user-service v0.0.0
	google.golang.org/grpc v1.72.1
	gorm.io/driver/postgres v1.5.11
	gorm.io/gorm v1.25.12
)

require (
	github.com/golang/protobuf v1.5.4 // indirect
	github.com/jackc/pgpassfile v1.0.0 // indirect
	github.com/jackc/pgservicefile v0.0.0-20240606120523-5a60cdf6a761 // indirect
	github.com/jackc/pgx/v5 v5.7.4 // indirect
	github.com/jackc/puddle/v2 v2.2.2 // indirect
	github.com/jinzhu/inflection v1.0.0 // indirect
	github.com/jinzhu/now v1.1.5 // indirect
	golang.org/x/crypto v0.38.0 // indirect
	golang.org/x/net v0.40.0 // indirect
	golang.org/x/sync v0.14.0 // indirect
	golang.org/x/sys v0.33.0 // indirect
	golang.org/x/text v0.25.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20250528174236-200df99c418a // indirect
	google.golang.org/protobuf v1.36.6 // indirect
)

replace github.com/kaansari/ceerat-contracts => ../../../../contracts-repo/packages/ceerat-contracts

replace github.com/kaansari/ceerat-platform/ai/ceerat-agent-gateway => ../../../../apps-repo/ai/ceerat-agent-gateway

replace github.com/kaansari/ceerat-platform/services/ceerat-user-service => ../../../../services-repo/services/ceerat-user-service
