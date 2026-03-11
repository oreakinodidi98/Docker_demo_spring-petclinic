# Kubernetes YAML Changes - Before & After Comparison

## Overview
This document shows the key changes made to migrate from password-based to passwordless authentication.

---

## k8s/db.yml

### ❌ BEFORE (Password-Based)
```yaml
---
apiVersion: v1
kind: Secret
metadata:
  name: demo-db
type: servicebinding.io/postgresql
stringData:
  type: "postgresql"
  provider: "postgresql"
  host: "demo-db"
  port: "5432"
  database: "petclinic"
  username: "user"
  password: "pass"  # ⚠️ Password stored in YAML!

---
apiVersion: v1
kind: Service
metadata:
  name: demo-db
spec:
  ports:
    - port: 5432
  selector:
    app: demo-db

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-db
spec:
  # ... local PostgreSQL deployment in cluster
```

### ✅ AFTER (Passwordless - Azure PostgreSQL)
```yaml
# Local PostgreSQL deployment removed!
# Now using Azure PostgreSQL Flexible Server:
#   Server: db-petclinic189769.postgres.database.azure.com
#   Database: petclinic
#   Authentication: Entra ID (Managed Identity)
#   Username: aad_pg
#
# Connection managed by Azure Service Connector
# Secret: sc-pg-secret (contains connection info, NO passwords)
```

**Result:** No local database pod, no passwords in YAML files!

---

## k8s/petclinic.yml

### Service Configuration

#### ❌ BEFORE
```yaml
spec:
  type: NodePort  # Requires port forwarding
  ports:
    - port: 80
      targetPort: 8080
```

#### ✅ AFTER
```yaml
spec:
  type: LoadBalancer  # Public IP automatically assigned
  ports:
    - port: 80
      targetPort: 8080
```

---

### Deployment - Pod Template

#### ❌ BEFORE
```yaml
template:
  metadata:
    labels:
      app: petclinic
      # No workload identity label
  spec:
    # No service account specified (uses default)
    containers:
      - name: workload
```

#### ✅ AFTER
```yaml
template:
  metadata:
    labels:
      app: petclinic
      azure.workload.identity/use: "true"  # ✅ Enable workload identity
  spec:
    serviceAccountName: sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df  # ✅ Federated identity
    nodeSelector:
      kubernetes.io/os: linux  # ✅ Linux nodes only
    containers:
      - name: workload
```

---

### Environment Variables & Secrets

#### ❌ BEFORE (Volume-Mounted Secret)
```yaml
env:
  - name: SPRING_PROFILES_ACTIVE
    value: postgres
  - name: SERVICE_BINDING_ROOT
    value: /bindings
    
volumeMounts:
  - mountPath: /bindings/secret
    name: binding
    readOnly: true

volumes:
  - name: binding
    projected:
      sources:
        - secret:
            name: demo-db  # ⚠️ Contains username/password
```

#### ✅ AFTER (Environment Variables from Service Connector)
```yaml
env:
  - name: SPRING_PROFILES_ACTIVE
    value: postgres
  
  # ✅ Connection details from Azure Service Connector secret
  - name: AZURE_POSTGRESQL_HOST
    valueFrom:
      secretKeyRef:
        name: sc-pg-secret
        key: AZURE_POSTGRESQL_HOST
  
  - name: AZURE_POSTGRESQL_USERNAME
    valueFrom:
      secretKeyRef:
        name: sc-pg-secret
        key: AZURE_POSTGRESQL_USERNAME  # Value: aad_pg
  
  - name: AZURE_POSTGRESQL_CLIENTID
    valueFrom:
      secretKeyRef:
        name: sc-pg-secret
        key: AZURE_POSTGRESQL_CLIENTID  # Managed identity ID
  
  # ✅ Enable passwordless authentication
  - name: SPRING_CLOUD_AZURE_CREDENTIAL_MANAGED_IDENTITY_ENABLED
    value: "true"
  
  - name: SPRING_DATASOURCE_AZURE_PASSWORDLESS_ENABLED
    value: "true"

# No volumes needed - no passwords to mount!
```

---

### Health Probes

#### ❌ BEFORE
```yaml
livenessProbe:
  httpGet:
    path: /livez
    port: http
    # No timeouts or startup probe

readinessProbe:
  httpGet:
    path: /readyz
    port: http
    # No timeouts or startup probe
```

#### ✅ AFTER
```yaml
livenessProbe:
  httpGet:
    path: /livez
    port: http
  initialDelaySeconds: 60
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /readyz
    port: http
  initialDelaySeconds: 30
  periodSeconds: 5
  timeoutSeconds: 3
  failureThreshold: 3

startupProbe:  # ✅ New: allows for slow startup
  httpGet:
    path: /actuator/health
    port: http
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 3
  failureThreshold: 30  # 5 minutes maximum startup time
```

---

### Resource Management

#### ❌ BEFORE
```yaml
# No resource requests or limits defined
```

#### ✅ AFTER
```yaml
resources:
  requests:
    memory: "512Mi"
    cpu: "250m"
  limits:
    memory: "1Gi"
    cpu: "1000m"
```

---

## Authentication Flow Comparison

### ❌ BEFORE (Password-Based)

```
┌─────────────────────┐
│   PetClinic Pod     │
│                     │
│ 1. Read username    │
│    and password     │
│    from secret      │
│                     │
│ 2. Connect with     │
│    credentials      │
└──────────┬──────────┘
           │
           │ Username: user
           │ Password: pass
           │
           ▼
┌─────────────────────┐
│  PostgreSQL Pod     │
│  (in cluster)       │
│                     │
│  ⚠️ Password stored │
│     in multiple     │
│     places          │
└─────────────────────┘
```

### ✅ AFTER (Passwordless)

```
┌─────────────────────────────────────────────┐
│   PetClinic Pod                             │
│                                             │
│   Uses: sc-account-acda3ed9-...            │
│   Label: azure.workload.identity/use       │
│                                             │
│   1. Workload Identity webhook injects      │
│      OIDC token                             │
│                                             │
│   2. Spring Cloud Azure SDK:                │
│      - Reads AZURE_POSTGRESQL_CLIENTID      │
│      - Exchanges OIDC for Azure AD token    │
│      - Gets PostgreSQL access token         │
│                                             │
│   3. Connects using access token            │
│      (NO password!)                         │
└──────────────────┬──────────────────────────┘
                   │
                   │ Azure AD Token
                   │ (auto-refreshed)
                   │
                   ▼
┌─────────────────────────────────────────────┐
│  Azure PostgreSQL Flexible Server          │
│                                             │
│  db-petclinic189769.postgres.database...   │
│                                             │
│  ✅ Validates token with Azure AD          │
│  ✅ Grants access to aad_pg user           │
│  ✅ No password authentication              │
└─────────────────────────────────────────────┘
```

---

## Key Differences Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Database Location** | In-cluster pod | Azure PostgreSQL Flexible Server |
| **Authentication** | Username/Password | Azure Managed Identity (passwordless) |
| **Credentials Storage** | Kubernetes Secret (plaintext) | No credentials stored |
| **Service Account** | default | Federated with Azure Managed Identity |
| **Identity** | None | azure.workload.identity/use: "true" |
| **Secret Type** | Contains passwords | Contains connection info only |
| **Token Rotation** | Manual password changes | Automatic (every hour) |
| **Service Type** | NodePort | LoadBalancer |
| **Resource Limits** | None | Defined (512Mi-1Gi RAM) |
| **Health Probes** | Basic | Enhanced with startup probe |
| **Security Posture** | Medium (credentials in YAML) | High (zero credentials) |

---

## Migration Checklist

- [x] Remove local PostgreSQL deployment (db.yml)
- [x] Configure workload identity label
- [x] Set federated service account
- [x] Add Azure PostgreSQL environment variables
- [x] Enable managed identity authentication
- [x] Enable passwordless authentication
- [x] Remove password-based secrets
- [x] Update service to LoadBalancer
- [x] Add resource requests and limits
- [x] Enhance health probes
- [x] Add node selector for Linux

---

**Status:** ✅ All changes applied successfully!

**Next Step:** Deploy using `.\deploy-to-aks.ps1` or follow the manual steps in [PASSWORDLESS_UPGRADE_SUMMARY.md](PASSWORDLESS_UPGRADE_SUMMARY.md)
