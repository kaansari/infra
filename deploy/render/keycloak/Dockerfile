FROM quay.io/keycloak/keycloak:26.4.0 AS builder

ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true

RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.4.0

COPY --from=builder /opt/keycloak/ /opt/keycloak/
COPY --chown=keycloak:keycloak dev/keycloak/ceerat-realm.json /opt/keycloak/data/import/ceerat-realm.json
COPY --chmod=0755 deploy/render/keycloak/reconcile-live-realm.sh /opt/keycloak/reconcile-live-realm.sh
COPY --chmod=0755 deploy/render/keycloak/entrypoint.sh /opt/keycloak/ceerat-entrypoint.sh

ENTRYPOINT ["/opt/keycloak/ceerat-entrypoint.sh"]
CMD ["start", "--optimized", "--import-realm"]
