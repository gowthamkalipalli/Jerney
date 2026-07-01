# ============================================================================
# DNS Configuration & Weighted Routing Guide for GCP ALB Migration
# ============================================================================
# This guide shows how to configure DNS for zero-downtime migration
# from Kubernetes LoadBalancer to GCP Application Load Balancer

---

## Overview

You will gradually shift traffic from your current Kubernetes LoadBalancer to 
the new GCP ALB using weighted DNS routing. This approach allows you to:

✅ Test ALB with real traffic (1-10% of users)
✅ Monitor performance before full cutover
✅ Instant rollback (change DNS weight back to 100% LoadBalancer)
✅ Zero downtime guarantee

---

## Current Setup

```
DNS: jerney.example.com
     ↓
K8s LoadBalancer External IP: 34.123.45.67 (100% traffic)
     ↓
Frontend Pods → Backend → Database
```

---

## Target Setup After Migration

```
DNS: jerney.example.com
     ↓
GCP ALB External IP: 34.98.76.54 (100% traffic)
     ↓
NEG → Frontend Pods → Backend → Database
```

---

## Step 1: Capture Your Current IPs

### Get Current LoadBalancer IP

```bash
# Current Kubernetes LoadBalancer IP
kubectl get svc jerney-frontend -n jerney -o wide

# Output example:
# NAME               TYPE          CLUSTER-IP    EXTERNAL-IP    PORT(S)
# jerney-frontend    LoadBalancer  10.0.1.50     34.123.45.67   80:31234/TCP
```

**Save this IP:** `34.123.45.67`

### Get New ALB IP (After Terraform Apply)

```bash
# After terraform apply completes
cd production/
terraform output alb_ip_address

# Output example:
# alb_ip_address = "34.98.76.54"
```

**Save this IP:** `34.98.76.54`

---

## Step 2: Check Current DNS TTL

### Current TTL Setting

```bash
# Check your current DNS configuration
dig jerney.example.com

# Look for this line:
# jerney.example.com. 3600 IN A 34.123.45.67
#                    ^^^^
#                    TTL = 3600 seconds (1 hour)
```

### If TTL is High (> 300 seconds)

**BEFORE starting migration:**
1. Reduce TTL to 60 seconds
2. Wait 2 hours (so all DNS caches expire)
3. Then proceed with migration

This ensures DNS changes propagate quickly during cutover.

**Why important:** If TTL is 3600 seconds and you update DNS, some users might 
still see the old IP for up to 1 hour, causing mixed traffic.

---

## Step 3: DNS Configuration Methods

Choose one method based on your DNS provider:

### Option A: Google Cloud DNS (Recommended if using GCP)

#### A. Create Cloud DNS Zone (if not exists)

```bash
# List existing zones
gcloud dns managed-zones list

# Create new zone (if needed)
gcloud dns managed-zones create jerney-zone \
  --dns-name="jerney.example.com." \
  --description="DNS for Jerney application"
```

#### B. Get Nameservers

```bash
# Get nameservers for your domain
gcloud dns managed-zones describe jerney-zone \
  --format="value(nameServers)"

# Output:
# ns-123.googledomains.com.
# ns-456.googledomains.com.
# ns-789.googledomains.com.
# ns-012.googledomains.com.

# Update your domain registrar to use these nameservers
```

#### C. Create Weighted DNS Records

```bash
# First, delete any existing A records
gcloud dns record-sets delete jerney.example.com. \
  --rrdatas="34.123.45.67" \
  --ttl=3600 \
  --type=A \
  --zone=jerney-zone

# Create weighted record for LoadBalancer (50% traffic)
gcloud dns record-sets create jerney.example.com. \
  --rrdatas="34.123.45.67" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-type=weighted \
  --routing-policy-data='weight=50'

# Create weighted record for ALB (50% traffic)
gcloud dns record-sets create jerney.example.com. \
  --rrdatas="34.98.76.54" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-type=weighted \
  --routing-policy-data='weight=50'

# Verify
gcloud dns record-sets list --zone=jerney-zone
```

#### D. Update Weights During Migration

```bash
# Increase ALB traffic to 70%
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.98.76.54" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-type=weighted \
  --routing-policy-data='weight=70'

# Decrease LoadBalancer to 30%
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.123.45.67" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-type=weighted \
  --routing-policy-data='weight=30'

# Final: 100% ALB
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.98.76.54" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-type=weighted \
  --routing-policy-data='weight=100'
```

---

### Option B: AWS Route 53 (If using AWS)

#### A. Update Hosted Zone

```bash
# Get hosted zone ID
aws route53 list-hosted-zones-by-name \
  --dns-name jerney.example.com

# Create weighted routing policy
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123XYZ \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "jerney.example.com",
          "Type": "A",
          "SetIdentifier": "LoadBalancer-50",
          "Weight": 50,
          "TTL": 60,
          "ResourceRecords": [{"Value": "34.123.45.67"}]
        }
      },
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "jerney.example.com",
          "Type": "A",
          "SetIdentifier": "ALB-50",
          "Weight": 50,
          "TTL": 60,
          "ResourceRecords": [{"Value": "34.98.76.54"}]
        }
      }
    ]
  }'
```

#### B. Update Weights

```bash
# Increase ALB to 70%, decrease LoadBalancer to 30%
aws route53 change-resource-record-sets \
  --hosted-zone-id Z123XYZ \
  --change-batch '{
    "Changes": [
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "jerney.example.com",
          "Type": "A",
          "SetIdentifier": "ALB-70",
          "Weight": 70,
          "TTL": 60,
          "ResourceRecords": [{"Value": "34.98.76.54"}]
        }
      },
      {
        "Action": "UPSERT",
        "ResourceRecordSet": {
          "Name": "jerney.example.com",
          "Type": "A",
          "SetIdentifier": "LoadBalancer-30",
          "Weight": 30,
          "TTL": 60,
          "ResourceRecords": [{"Value": "34.123.45.67"}]
        }
      }
    ]
  }'
```

---

### Option C: Cloudflare (If using Cloudflare)

#### A. Update DNS Record

```bash
# Via Cloudflare UI:
# 1. Go to DNS settings
# 2. Update existing A record for jerney.example.com
# 3. Set TTL to 60 seconds (Auto/1 minute)
# 4. Keep IP as 34.123.45.67 initially
```

#### B. Create Geolocation-Based Routing (Advanced)

```bash
# Cloudflare API approach (requires API token)

# Update A record to LoadBalancer
curl -X PUT "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record_id}" \
  -H "X-Auth-Email: your-email@example.com" \
  -H "X-Auth-Key: your-api-key" \
  -d '{
    "type": "A",
    "name": "jerney.example.com",
    "content": "34.123.45.67",
    "ttl": 60,
    "priority": 10
  }'

# Then switch to ALB
curl -X PUT "https://api.cloudflare.com/client/v4/zones/{zone_id}/dns_records/{record_id}" \
  -H "X-Auth-Email: your-email@example.com" \
  -H "X-Auth-Key: your-api-key" \
  -d '{
    "type": "A",
    "name": "jerney.example.com",
    "content": "34.98.76.54",
    "ttl": 60
  }'
```

---

### Option D: Manual/Other DNS Provider

#### A. Your DNS Provider UI Steps

1. **Log into your DNS provider** (GoDaddy, Namecheap, etc.)
2. **Find the A record** for `jerney.example.com`
3. **Set TTL to 60 seconds**
4. **Create two A records:**
   - Record 1: jerney.example.com → 34.123.45.67 (Weight: 50)
   - Record 2: jerney.example.com → 34.98.76.54 (Weight: 50)

#### B. Verify Changes

```bash
# Test from multiple locations
dig jerney.example.com @8.8.8.8
dig jerney.example.com @1.1.1.1

# Should show both IPs
# If provider doesn't support weighted routing, manually update
# and wait TTL expiration between updates
```

---

## Step 4: Verify DNS is Pointing to Both

```bash
# Check from public resolver
dig jerney.example.com +short

# Should show both IPs (order may vary):
# 34.123.45.67
# 34.98.76.54

# If only one IP shows, DNS hasn't propagated yet
# Wait and retry (can take 5-30 minutes)
```

---

## Step 5: Migration Timeline

### T=0:00 - Start Migration
```bash
# Verify both services are responding
curl http://34.123.45.67   # K8s LoadBalancer (should work)
curl http://34.98.76.54    # GCP ALB (should work)

# DNS set to 50/50
curl https://jerney.example.com/api/health
# ~50% requests go to LoadBalancer, ~50% to ALB
```

### T=0:05 - Monitor First 5 Minutes
```bash
# Check ALB backend health
gcloud compute backend-services get-health jerney-backend-service --global

# Expected output:
# - status: HEALTHY
# - instances with status HEALTHY

# Check error rates
kubectl logs -f deployment/jerney-backend -n jerney
```

### T=0:15 - If No Errors, Increase ALB Traffic
```bash
# Update DNS: 70% ALB, 30% LoadBalancer

# Cloud DNS example:
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.98.76.54" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-data='weight=70'
```

### T=0:20 - Monitor Again
```bash
# Check metrics
gcloud monitoring timeseries list \
  --filter='metric.type="loadbalancing.googleapis.com/https/request_count"'

# Check pod status
kubectl get pods -n jerney
```

### T=0:30 - Final Cutover to 100% ALB
```bash
# Switch all traffic to ALB
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.98.76.54" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-data='weight=100'

# Verify all traffic on ALB
# Check logs don't show LoadBalancer IPs
```

### T=24:00 - Verification Complete
```bash
# If all metrics good for 24 hours:
# - Error rate < 1%
# - Latency similar to before
# - No customer complaints
# Then proceed to cleanup
```

---

## Step 6: Instant Rollback (If Issues)

### Quick Rollback (< 1 minute)

```bash
# If ALB has issues, immediately switch back

# Option A: Set DNS to 100% LoadBalancer
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.123.45.67" \
  --ttl=60 \
  --type=A \
  --zone=jerney-zone \
  --routing-policy-data='weight=100'

# Verify
dig jerney.example.com +short
# Should show only: 34.123.45.67

# Option B: If DNS cached, directly update A record
gcloud dns record-sets delete jerney.example.com. \
  --rrdatas="34.98.76.54" \
  --zone=jerney-zone

# Test
curl https://jerney.example.com/
# Should now route to LoadBalancer
```

---

## Step 7: Monitoring During Migration

### Key Metrics to Watch

```bash
# 1. Error Rate
curl -s https://jerney.example.com/api/health | jq .

# 2. Latency
time curl -w '\nLatency: %{time_total}s\n' https://jerney.example.com/

# 3. Pod Restarts (should be 0)
kubectl get pods -n jerney

# 4. Database Connections
kubectl exec deployment/jerney-backend -n jerney -- \
  env | grep DB_

# 5. ALB Backend Status
gcloud compute backend-services get-health jerney-backend-service --global

# 6. Traffic Distribution (roughly 50/50 initially)
gcloud logging read "resource.type=http_load_balancer" \
  --limit 100 \
  --format="table(httpRequest.requestUrl,httpRequest.latency)"
```

### CloudWatch/Monitoring Dashboard

```bash
# If using Cloud Monitoring, check dashboard
gcloud monitoring dashboards list

# Create alerts for:
# - Error rate > 1%
# - Latency > 1000ms
# - Backend health != HEALTHY
```

---

## Step 8: Common Issues & Solutions

### Issue: DNS Still Points to Old IP

```bash
# Check DNS propagation
nslookup jerney.example.com 8.8.8.8
nslookup jerney.example.com 1.1.1.1

# Clear local DNS cache (varies by OS)
# macOS:
sudo dscacheutil -flushcache

# Linux:
sudo systemctl restart systemd-resolved

# Windows:
ipconfig /flushdns
```

### Issue: ALB Returns 502 Bad Gateway

```bash
# Check NEG status
gcloud compute network-endpoint-groups list \
  --format="table(name,networkEndpointType,status)"

# Check if pods are running
kubectl get pods -n jerney -l app.kubernetes.io/name=jerney-frontend

# Check health check endpoint
kubectl port-forward svc/jerney-frontend-alb 8080:80 -n jerney
curl localhost:8080/
```

### Issue: High Latency After Switch

```bash
# Check if connection draining is working
gcloud compute backend-services describe jerney-backend-service \
  --global \
  --format="value(connectionDrainingTimeoutSec)"

# Increase if needed
gcloud compute backend-services update jerney-backend-service \
  --global \
  --connection-draining-timeout-sec=60
```

---

## Step 9: Post-Migration Cleanup (After 24+ hours)

### Delete Kubernetes LoadBalancer Service

```bash
# Only after confirming ALB stable for 24 hours
kubectl delete svc jerney-frontend -n jerney

# Verify it's deleted
kubectl get svc -n jerney

# This will also trigger GCP to delete the auto-created LB
# (may take 5-10 minutes)
```

### Verify GCP Load Balancer Deletion

```bash
# Check forwarding rules (should decrease)
gcloud compute forwarding-rules list

# Check backend services
gcloud compute backend-services list
```

---

## Rollback to K8s LoadBalancer

### If You Need to Rollback Completely

```bash
# 1. Restore K8s LoadBalancer service
kubectl apply -f k8s/jerney.yaml

# 2. Update DNS back to LoadBalancer IP
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="34.123.45.67" \
  --ttl=300 \
  --type=A \
  --zone=jerney-zone

# 3. Destroy ALB (optional, if not needed)
cd production/
terraform destroy -target=google_compute_backend_service.jerney_backend \
                  -target=google_compute_global_forwarding_rule.jerney_https_rule \
                  -target=google_compute_global_forwarding_rule.jerney_http_rule
```

---

## DNS Cutover Checklist

```
□ Verified current LoadBalancer IP: _______________
□ Verified ALB IP from terraform output: _______________
□ Reduced DNS TTL to 60 seconds
□ Waited 2 hours for TTL expiration
□ Created weighted DNS records (50/50)
□ Verified DNS propagation (dig shows both IPs)
□ Tested ALB directly (curl both IPs)
□ Verified ALB backend status = HEALTHY
□ Monitored for 5 minutes (error rate < 1%)
□ Increased ALB weight to 70%
□ Monitored for 10 minutes
□ Switched to 100% ALB
□ Monitored for 24 hours
□ Verified no error spikes
□ Verified latency similar to before
□ Deleted K8s LoadBalancer service
□ Deleted unused K8s resources
□ Updated DNS TTL back to 300+ seconds
```

---

**Last Updated:** 2026-07-01  
**Status:** ✅ Ready for Production Migration  
**Zero Downtime:** ✅ Guaranteed with weighted DNS routing  
**Rollback Time:** ~1 minute (DNS change)
