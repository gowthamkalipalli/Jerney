#!/bin/bash
# ============================================================================
# ROLLBACK SCRIPTS FOR GCP ALB MIGRATION
# ============================================================================
# Use these scripts if you need to rollback from ALB to K8s LoadBalancer
# All scripts are designed to be non-destructive and reversible
#
# WARNING: These are emergency procedures - use only if ALB is failing
# ============================================================================

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# ============================================================================
# SCRIPT 1: QUICK DNS ROLLBACK (< 1 minute)
# ============================================================================
# Use this if ALB is down and you need to restore traffic immediately

rollback_dns_only() {
  echo -e "${RED}🚨 INITIATING DNS-ONLY ROLLBACK${NC}"
  echo "Time: $(date)"
  echo ""
  
  # Confirm action
  read -p "⚠️  This will route 100% traffic back to K8s LoadBalancer. Continue? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Rollback cancelled."
    exit 0
  fi
  
  echo ""
  echo -e "${BLUE}Step 1: Current DNS Configuration${NC}"
  gcloud dns record-sets list --zone=jerney-zone --format="table(name,type,rrdatas,ttl)"
  
  echo ""
  echo -e "${BLUE}Step 2: Updating DNS to 100% LoadBalancer${NC}"
  
  # Get LoadBalancer IP
  LB_IP=$(kubectl get svc jerney-frontend -n jerney -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  
  if [ -z "$LB_IP" ]; then
    echo -e "${RED}❌ ERROR: LoadBalancer IP not found${NC}"
    echo "Make sure K8s LoadBalancer service is still active:"
    echo "  kubectl get svc jerney-frontend -n jerney"
    exit 1
  fi
  
  echo "LoadBalancer IP: $LB_IP"
  
  # Update DNS record
  gcloud dns record-sets update jerney.example.com. \
    --rrdatas="$LB_IP" \
    --ttl=60 \
    --type=A \
    --zone=jerney-zone \
    --clear-routing-policy
  
  echo -e "${GREEN}✅ DNS updated to LoadBalancer${NC}"
  
  echo ""
  echo -e "${BLUE}Step 3: Verifying DNS Propagation${NC}"
  
  for i in {1..5}; do
    echo "Check $i (waiting 15 seconds)..."
    sleep 15
    RESOLVED_IP=$(dig jerney.example.com +short | head -1)
    echo "  Resolved IP: $RESOLVED_IP"
    
    if [ "$RESOLVED_IP" == "$LB_IP" ]; then
      echo -e "${GREEN}✅ DNS Propagated!${NC}"
      break
    fi
  done
  
  echo ""
  echo -e "${BLUE}Step 4: Testing LoadBalancer Connectivity${NC}"
  
  RESPONSE=$(curl -m 10 -s -o /dev/null -w "%{http_code}" https://jerney.example.com/)
  echo "HTTP Response: $RESPONSE"
  
  if [ "$RESPONSE" == "200" ] || [ "$RESPONSE" == "301" ] || [ "$RESPONSE" == "302" ]; then
    echo -e "${GREEN}✅ LoadBalancer Responding Correctly${NC}"
  else
    echo -e "${RED}⚠️  Unexpected response code: $RESPONSE${NC}"
  fi
  
  echo ""
  echo -e "${GREEN}✅ ROLLBACK COMPLETE${NC}"
  echo ""
  echo "Traffic is now 100% on K8s LoadBalancer"
  echo ""
  echo "Next Steps:"
  echo "1. Monitor application for errors: kubectl logs -f deployment/jerney-frontend -n jerney"
  echo "2. Investigate ALB issues"
  echo "3. Fix issues in staging environment"
  echo "4. Retry ALB migration after verification"
}

# ============================================================================
# SCRIPT 2: PARTIAL ROLLBACK (Reduce ALB Traffic)
# ============================================================================
# Use this if ALB is having issues but still somewhat functional

rollback_reduce_alb_traffic() {
  echo -e "${YELLOW}⚠️  REDUCING ALB TRAFFIC (Gradual Rollback)${NC}"
  echo "Time: $(date)"
  echo ""
  
  read -p "Current ALB weight (default 70): " alb_weight
  alb_weight=${alb_weight:-70}
  
  new_alb_weight=$((alb_weight - 25))
  new_lb_weight=$((100 - new_alb_weight))
  
  echo "Current: $alb_weight% ALB, $((100 - alb_weight))% LoadBalancer"
  echo "New:     $new_alb_weight% ALB, $new_lb_weight% LoadBalancer"
  echo ""
  
  read -p "Continue? (yes/no): " confirm
  if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
  fi
  
  # Get IPs
  LB_IP=$(kubectl get svc jerney-frontend -n jerney -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  ALB_IP=$(terraform -chdir=production output -raw alb_ip_address 2>/dev/null || echo "")
  
  if [ -z "$ALB_IP" ]; then
    ALB_IP="34.98.76.54"
    read -p "ALB IP not found. Enter ALB IP ($ALB_IP): " user_alb_ip
    ALB_IP=${user_alb_ip:-$ALB_IP}
  fi
  
  echo ""
  echo "Updating DNS weights..."
  echo "  LoadBalancer ($LB_IP): $new_lb_weight%"
  echo "  ALB ($ALB_IP): $new_alb_weight%"
  
  # Update weights
  gcloud dns record-sets update jerney.example.com. \
    --rrdatas="$LB_IP" \
    --ttl=60 \
    --type=A \
    --zone=jerney-zone \
    --routing-policy-type=weighted \
    --routing-policy-data="weight=$new_lb_weight"
  
  gcloud dns record-sets update jerney.example.com. \
    --rrdatas="$ALB_IP" \
    --ttl=60 \
    --type=A \
    --zone=jerney-zone \
    --routing-policy-type=weighted \
    --routing-policy-data="weight=$new_alb_weight"
  
  echo -e "${GREEN}✅ DNS weights updated${NC}"
  echo ""
  echo "Monitoring after weight change..."
  
  for i in {1..10}; do
    echo "Check $i:"
    ERROR_RATE=$(gcloud logging read \
      "resource.type=http_load_balancer AND httpRequest.status>=500" \
      --limit 100 --format=json | jq 'length' 2>/dev/null || echo "0")
    echo "  Recent 5xx errors: $ERROR_RATE"
    sleep 10
  done
}

# ============================================================================
# SCRIPT 3: FULL INFRASTRUCTURE ROLLBACK
# ============================================================================
# Use this to completely destroy ALB and restore original state

rollback_full_infrastructure() {
  echo -e "${RED}🚨 FULL INFRASTRUCTURE ROLLBACK${NC}"
  echo "Time: $(date)"
  echo ""
  echo "WARNING: This will:"
  echo "  ❌ Destroy GCP ALB infrastructure"
  echo "  ❌ Delete ALB forwarding rules"
  echo "  ❌ Delete backend services"
  echo "  ❌ Keep K8s LoadBalancer active"
  echo ""
  
  read -p "Are you SURE you want to proceed? Type 'ROLLBACK' to confirm: " confirm
  if [ "$confirm" != "ROLLBACK" ]; then
    echo "Cancelled."
    exit 0
  fi
  
  # Step 1: Restore DNS
  echo ""
  echo -e "${BLUE}Step 1: Restoring DNS to LoadBalancer${NC}"
  bash <(cat << 'EOF'
LB_IP=$(kubectl get svc jerney-frontend -n jerney -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
gcloud dns record-sets update jerney.example.com. \
  --rrdatas="$LB_IP" \
  --ttl=300 \
  --type=A \
  --zone=jerney-zone \
  --clear-routing-policy
echo "✅ DNS restored"
EOF
  )
  
  # Step 2: Verify traffic restored
  echo ""
  echo -e "${BLUE}Step 2: Verifying traffic restoration${NC}"
  for i in {1..3}; do
    echo "Verification attempt $i..."
    sleep 10
    RESPONSE=$(curl -m 5 -s -o /dev/null -w "%{http_code}" https://jerney.example.com/)
    if [ "$RESPONSE" == "200" ] || [ "$RESPONSE" == "301" ]; then
      echo -e "${GREEN}✅ Traffic restored${NC}"
      break
    fi
  done
  
  # Step 3: Destroy ALB resources
  echo ""
  echo -e "${BLUE}Step 3: Destroying ALB Infrastructure${NC}"
  echo "Running: terraform destroy -auto-approve"
  
  cd production/
  
  # Back up state first
  cp terraform.tfstate terraform.tfstate.backup.$(date +%s)
  echo "✅ State backed up: terraform.tfstate.backup.*"
  
  # Destroy specific ALB resources (not everything)
  terraform destroy \
    -target=google_compute_backend_service.jerney_backend \
    -target=google_compute_global_forwarding_rule.jerney_https_rule \
    -target=google_compute_global_forwarding_rule.jerney_http_rule \
    -target=google_compute_target_https_proxy.jerney_https_proxy \
    -target=google_compute_target_http_proxy.jerney_http_proxy \
    -target=google_compute_url_map.jerney_url_map \
    -target=google_compute_url_map.jerney_https_redirect \
    -target=google_compute_managed_ssl_certificate.jerney_cert \
    -target=google_compute_network_endpoint_group.jerney_neg \
    -target=google_compute_health_check.jerney_health_check \
    -target=google_compute_firewall.jerney_alb_health_check \
    -target=google_compute_firewall.jerney_alb_to_pods \
    -target=google_compute_security_policy.jerney_security_policy \
    -auto-approve
  
  echo -e "${GREEN}✅ ALB infrastructure destroyed${NC}"
  
  cd ..
  
  # Step 4: Verify ALB resources gone
  echo ""
  echo -e "${BLUE}Step 4: Verifying Cleanup${NC}"
  echo "Remaining GCP resources:"
  gcloud compute backend-services list --format="table(name)"
  
  echo ""
  echo -e "${GREEN}✅ FULL ROLLBACK COMPLETE${NC}"
  echo ""
  echo "Your application is back to original state:"
  echo "  - K8s LoadBalancer active"
  echo "  - DNS pointing to LoadBalancer"
  echo "  - ALB infrastructure destroyed"
  echo ""
  echo "To retry ALB migration:"
  echo "  1. Investigate what failed"
  echo "  2. Fix issues"
  echo "  3. Test in staging"
  echo "  4. Re-run: terraform apply"
}

# ============================================================================
# SCRIPT 4: EMERGENCY SERVICE RESTORATION
# ============================================================================
# Use this if LoadBalancer service is also having issues

emergency_restore_service() {
  echo -e "${RED}🚨 EMERGENCY SERVICE RESTORATION${NC}"
  echo ""
  
  echo -e "${BLUE}Current K8s LoadBalancer Status:${NC}"
  kubectl get svc jerney-frontend -n jerney
  
  LB_IP=$(kubectl get svc jerney-frontend -n jerney -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  
  if [ -z "$LB_IP" ]; then
    echo -e "${RED}LoadBalancer IP is unassigned (service might be recreating)${NC}"
    echo ""
    echo -e "${BLUE}Option 1: Wait for LB to get new IP${NC}"
    echo "  kubectl get svc jerney-frontend -n jerney --watch"
    echo ""
    echo -e "${BLUE}Option 2: Delete and recreate service${NC}"
    read -p "Delete and recreate LoadBalancer service? (yes/no): " recreate
    if [ "$recreate" == "yes" ]; then
      kubectl delete svc jerney-frontend -n jerney
      sleep 5
      kubectl apply -f k8s/jerney.yaml
      echo "Waiting for new LoadBalancer IP..."
      kubectl get svc jerney-frontend -n jerney --watch
    fi
  else
    echo -e "${GREEN}✅ LoadBalancer IP is active: $LB_IP${NC}"
    
    echo ""
    echo -e "${BLUE}Testing LoadBalancer:${NC}"
    curl -v https://jerney.example.com/ 2>&1 | head -20
  fi
}

# ============================================================================
# SCRIPT 5: STATE RECOVERY (Restore from backup)
# ============================================================================
# Use this if Terraform state is corrupted

recover_terraform_state() {
  echo -e "${RED}🚨 TERRAFORM STATE RECOVERY${NC}"
  echo ""
  
  cd production/
  
  echo -e "${BLUE}Available state backups:${NC}"
  ls -lah terraform.tfstate.backup.*
  
  echo ""
  read -p "Enter backup file to restore (e.g., terraform.tfstate.backup.1234567890): " backup_file
  
  if [ ! -f "$backup_file" ]; then
    echo -e "${RED}Backup file not found: $backup_file${NC}"
    exit 1
  fi
  
  echo -e "${BLUE}Step 1: Backing up current state${NC}"
  cp terraform.tfstate terraform.tfstate.corrupted.$(date +%s)
  echo "✅ Current state backed up"
  
  echo ""
  echo -e "${BLUE}Step 2: Restoring from backup${NC}"
  cp "$backup_file" terraform.tfstate
  echo "✅ State restored"
  
  echo ""
  echo -e "${BLUE}Step 3: Refreshing state${NC}"
  terraform refresh
  echo "✅ State refreshed"
  
  echo ""
  echo -e "${BLUE}Step 4: Verifying state${NC}"
  terraform state list | head -10
  
  echo ""
  echo -e "${GREEN}✅ TERRAFORM STATE RECOVERED${NC}"
  
  cd ..
}

# ============================================================================
# SCRIPT 6: CLEAN LOGS BEFORE RETRY
# ============================================================================
# Clear old logs before attempting migration again

clean_logs_for_retry() {
  echo -e "${BLUE}Cleaning logs for migration retry${NC}"
  echo ""
  
  echo -e "${BLUE}Clearing old pod logs:${NC}"
  
  # Delete and recreate pods to clear logs
  kubectl rollout restart deployment/jerney-frontend -n jerney
  kubectl rollout restart deployment/jerney-backend -n jerney
  
  echo "Waiting for pods to restart..."
  kubectl rollout status deployment/jerney-frontend -n jerney
  kubectl rollout status deployment/jerney-backend -n jerney
  
  echo -e "${GREEN}✅ Pods restarted with clean logs${NC}"
  
  echo ""
  echo "Current pod logs:"
  kubectl logs deployment/jerney-frontend -n jerney --tail=5
}

# ============================================================================
# MAIN MENU
# ============================================================================

show_menu() {
  echo ""
  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║           ALB MIGRATION ROLLBACK SCRIPT MENU                   ║"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Choose rollback option:"
  echo ""
  echo "  1) Quick DNS Rollback (< 1 minute)"
  echo "     └─ Route 100% traffic back to K8s LoadBalancer immediately"
  echo ""
  echo "  2) Reduce ALB Traffic Gradually"
  echo "     └─ Reduce ALB traffic, increase LoadBalancer traffic"
  echo ""
  echo "  3) Full Infrastructure Rollback"
  echo "     └─ Destroy ALB completely, restore original state"
  echo ""
  echo "  4) Emergency Service Restoration"
  echo "     └─ Restore K8s LoadBalancer if also having issues"
  echo ""
  echo "  5) Recover Terraform State from Backup"
  echo "     └─ Restore corrupted Terraform state"
  echo ""
  echo "  6) Clean Logs for Retry"
  echo "     └─ Clear old logs and restart pods"
  echo ""
  echo "  0) Exit"
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo ""
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

if [ $# -eq 0 ]; then
  # Interactive mode
  while true; do
    show_menu
    read -p "Enter option (0-6): " option
    echo ""
    
    case $option in
      1) rollback_dns_only ;;
      2) rollback_reduce_alb_traffic ;;
      3) rollback_full_infrastructure ;;
      4) emergency_restore_service ;;
      5) recover_terraform_state ;;
      6) clean_logs_for_retry ;;
      0) 
        echo "Exiting rollback script."
        exit 0
        ;;
      *)
        echo -e "${RED}Invalid option. Please try again.${NC}"
        ;;
    esac
    
    echo ""
    read -p "Press Enter to continue..."
  done
else
  # Command line mode
  case $1 in
    dns) rollback_dns_only ;;
    reduce) rollback_reduce_alb_traffic ;;
    full) rollback_full_infrastructure ;;
    emergency) emergency_restore_service ;;
    state) recover_terraform_state ;;
    clean) clean_logs_for_retry ;;
    *)
      echo "Usage: $0 [dns|reduce|full|emergency|state|clean]"
      echo ""
      echo "Options:"
      echo "  dns        - Quick DNS rollback"
      echo "  reduce     - Gradually reduce ALB traffic"
      echo "  full       - Complete infrastructure rollback"
      echo "  emergency  - Restore LoadBalancer service"
      echo "  state      - Recover Terraform state"
      echo "  clean      - Clean logs before retry"
      echo ""
      echo "Run without arguments for interactive menu:"
      echo "  $0"
      exit 1
      ;;
  esac
fi
