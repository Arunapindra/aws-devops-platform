#!/bin/bash
set -euo pipefail

# Integration test script for deployed services
# Validates that all components are running and responding correctly

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

NAMESPACE=${1:-devops-platform}
FAILURES=0

echo "============================================"
echo "  AWS DevOps Platform - Integration Tests"
echo "  Namespace: $NAMESPACE"
echo "============================================"
echo ""

# Test 1: ArgoCD health
echo "1. Checking ArgoCD application health..."
if kubectl get application -n argocd 2>/dev/null | grep -q "Healthy"; then
    echo -e "   ${GREEN}PASS${NC} ArgoCD applications are healthy"
else
    echo -e "   ${RED}FAIL${NC} ArgoCD applications not healthy"
    FAILURES=$((FAILURES + 1))
fi

# Test 2: Helm releases
echo "2. Checking Helm releases..."
if helm list -n "$NAMESPACE" 2>/dev/null | grep -q "deployed"; then
    echo -e "   ${GREEN}PASS${NC} Helm releases are deployed"
else
    echo -e "   ${RED}FAIL${NC} No Helm releases found"
    FAILURES=$((FAILURES + 1))
fi

# Test 3: Deployments are ready
echo "3. Checking deployment readiness..."
NOT_READY=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.readyReplicas}/{.status.replicas}{"\n"}{end}' 2>/dev/null | grep -v "^$" || echo "")
if [ -n "$NOT_READY" ]; then
    echo "$NOT_READY" | while read -r line; do
        NAME=$(echo "$line" | cut -f1)
        RATIO=$(echo "$line" | cut -f2)
        READY=$(echo "$RATIO" | cut -d'/' -f1)
        TOTAL=$(echo "$RATIO" | cut -d'/' -f2)
        if [ "$READY" = "$TOTAL" ] && [ "$TOTAL" != "" ]; then
            echo -e "   ${GREEN}PASS${NC} $NAME ($RATIO)"
        else
            echo -e "   ${RED}FAIL${NC} $NAME ($RATIO)"
            FAILURES=$((FAILURES + 1))
        fi
    done
else
    echo -e "   ${RED}FAIL${NC} No deployments found"
    FAILURES=$((FAILURES + 1))
fi

# Test 4: Services have endpoints
echo "4. Checking service endpoints..."
kubectl get endpoints -n "$NAMESPACE" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.subsets[0].addresses[0].ip}{"\n"}{end}' 2>/dev/null | while read -r line; do
    SVC=$(echo "$line" | cut -f1)
    IP=$(echo "$line" | cut -f2)
    if [ -n "$IP" ]; then
        echo -e "   ${GREEN}PASS${NC} $SVC has endpoints"
    else
        echo -e "   ${RED}FAIL${NC} $SVC has no endpoints"
    fi
done

# Test 5: No pods in CrashLoopBackOff
echo "5. Checking for crash-looping pods..."
CRASH_PODS=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l | tr -d ' ')
if [ "$CRASH_PODS" = "0" ]; then
    echo -e "   ${GREEN}PASS${NC} No crash-looping pods"
else
    echo -e "   ${RED}FAIL${NC} $CRASH_PODS pods in bad state"
    FAILURES=$((FAILURES + 1))
fi

# Test 6: Network policies exist
echo "6. Checking network policies..."
NP_COUNT=$(kubectl get networkpolicies -n "$NAMESPACE" -o name 2>/dev/null | wc -l | tr -d ' ')
if [ "$NP_COUNT" -gt 0 ]; then
    echo -e "   ${GREEN}PASS${NC} $NP_COUNT network policies configured"
else
    echo -e "   ${RED}FAIL${NC} No network policies found"
    FAILURES=$((FAILURES + 1))
fi

echo ""
echo "============================================"
if [ "$FAILURES" -eq 0 ]; then
    echo -e "  Result: ${GREEN}ALL TESTS PASSED${NC}"
else
    echo -e "  Result: ${RED}$FAILURES TESTS FAILED${NC}"
fi
echo "============================================"

exit "$FAILURES"
