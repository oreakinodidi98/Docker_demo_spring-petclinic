# Quick Reference - Passwordless Authentication

## 🎯 What Was Done
✅ Upgraded Kubernetes YAML files to use **passwordless authentication** with Azure PostgreSQL
✅ Configured **Workload Identity** for secure pod-to-Azure authentication
✅ Removed all passwords from configuration files
✅ Enhanced deployment with resource limits and health checks

## 📂 Files Modified

### Core Changes
- **k8s/db.yml** - Removed local PostgreSQL (now using Azure)
- **k8s/petclinic.yml** - Configured passwordless authentication

### Documentation Created
- **PASSWORDLESS_AUTH_GUIDE.md** - Complete passwordless auth guide
- **PASSWORDLESS_UPGRADE_SUMMARY.md** - Upgrade summary and deployment steps
- **YAML_CHANGES_COMPARISON.md** - Before/after comparison
- **deploy-to-aks.ps1** - Automated deployment script
- **QUICK_REFERENCE.md** - This file

## 🔑 Key Configuration Values

From your setup (stored in `../.envrc` and `../sc.log`):

```
Service Account:  sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df
Secret Name:      sc-pg-secret
Managed Identity: acda3ed9-e3d0-4f77-8887-37e2db05f5df
Database Host:    db-petclinic189769.postgres.database.azure.com
Database Name:    petclinic
Database User:    aad_pg (Entra ID user)
ACR Name:         acrpetclinic189769
AKS Cluster:      aks-petclinic-1897692303
```

## 🚀 Deploy in 3 Steps

### Option 1: Automated (Recommended)
```powershell
cd c:\Demo_AKS_Mod\AKS_APPMod\spring-petclinic
.\deploy-to-aks.ps1
```

### Option 2: Manual
```powershell
# 1. Build & Push
docker build -t spring-petclinic:v1 .
az acr login --name acrpetclinic189769
docker tag spring-petclinic:v1 acrpetclinic189769.azurecr.io/spring-petclinic:v1
docker push acrpetclinic189769.azurecr.io/spring-petclinic:v1

# 2. Update k8s/petclinic.yml image line to:
#    image: acrpetclinic189769.azurecr.io/spring-petclinic:v1

# 3. Deploy
$env:KUBECONFIG = "..\aks-petclinic-1897692303.config"
kubectl apply -f k8s/petclinic.yml
kubectl get service petclinic -w
```

## 🔍 Essential Commands

### Check Deployment Status
```powershell
kubectl get pods -l app=petclinic
kubectl get service petclinic
```

### View Logs
```powershell
kubectl logs -l app=petclinic -f
```

### Verify Authentication
```powershell
# Check for successful database connection
kubectl logs -l app=petclinic | Select-String "Started PetClinicApplication"
```

### Get Application URL
```powershell
$IP = kubectl get service petclinic -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
Start-Process "http://$IP"
```

## 🐛 Quick Troubleshooting

### Pod Not Starting
```powershell
kubectl describe pod -l app=petclinic
kubectl logs -l app=petclinic --tail=100
```

### Image Pull Errors
```powershell
# Verify ACR is attached to AKS
az aks show --resource-group rg-petclinic1897692303 \
  --name aks-petclinic-1897692303 \
  --query "servicePrincipalProfile.clientId"
```

### Authentication Errors
```powershell
# Verify Service Connector resources
kubectl get serviceaccount sc-account-acda3ed9-e3d0-4f77-8887-37e2db05f5df
kubectl get secret sc-pg-secret
```

### Database Connection Issues
```powershell
# Check if database is accessible
kubectl logs -l app=petclinic | Select-String "postgres"
kubectl logs -l app=petclinic | Select-String "authentication"
```

## 📊 Health Check Endpoints

Once deployed, these endpoints are available:

- **Application:** `http://<EXTERNAL-IP>/`
- **Actuator Health:** `http://<EXTERNAL-IP>/actuator/health`
- **Liveness:** `http://<EXTERNAL-IP>/livez`
- **Readiness:** `http://<EXTERNAL-IP>/readyz`

## 🔐 Security Features

✅ **Zero Passwords** - No credentials stored anywhere
✅ **Token-Based Auth** - Azure AD tokens used for authentication
✅ **Auto-Rotation** - Tokens automatically refresh every hour
✅ **Audit Trail** - All access logged with managed identity
✅ **Least Privilege** - Dedicated identity per application

## 📚 Documentation Quick Links

- **Full Guide:** [PASSWORDLESS_AUTH_GUIDE.md](PASSWORDLESS_AUTH_GUIDE.md)
- **Deployment Steps:** [PASSWORDLESS_UPGRADE_SUMMARY.md](PASSWORDLESS_UPGRADE_SUMMARY.md)
- **YAML Changes:** [YAML_CHANGES_COMPARISON.md](YAML_CHANGES_COMPARISON.md)
- **Containerization:** [CONTAINERIZATION_SUMMARY.md](CONTAINERIZATION_SUMMARY.md)

## 💡 Key Concepts

### Workload Identity
Kubernetes pods authenticate as Azure Managed Identities using OIDC token exchange. No secrets required!

### Service Connector
Azure service that automates connections between AKS and other Azure services, managing configuration and secrets.

### Passwordless Authentication
Uses Azure AD tokens instead of passwords. Tokens are short-lived and automatically rotated.

## ✅ Success Indicators

Your deployment is successful when you see:

1. ✅ Pod status: `Running`
2. ✅ Service has `EXTERNAL-IP` assigned
3. ✅ Logs show: "Started PetClinicApplication"
4. ✅ Application accessible in browser
5. ✅ No authentication errors in logs

## 🆘 Need Help?

1. **Check pod logs first:**
   ```powershell
   kubectl logs -l app=petclinic --tail=50
   ```

2. **Review detailed guide:**
   Open [PASSWORDLESS_AUTH_GUIDE.md](PASSWORDLESS_AUTH_GUIDE.md)

3. **Verify infrastructure:**
   ```powershell
   # Check Service Connector status
   az aks connection list `
     --source-id /subscriptions/cb5b077c-3ef5-4b2e-83e5-490cc5ca0e19/resourceGroups/rg-petclinic1897692303/providers/Microsoft.ContainerService/managedClusters/aks-petclinic-1897692303
   ```

---

**Ready to Deploy?** Run `.\deploy-to-aks.ps1` and watch the magic happen! 🚀
