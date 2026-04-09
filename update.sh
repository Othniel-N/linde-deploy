#!/bin/bash

NAMESPACE=linde
DEPLOYMENT=linde-app
HELPER_POD=pvc-helper

# Unzip files (assumes ZIPs are in current directory)
echo "Step 0: Unzip public.zip"
unzip -o public.zip -x "__MACOSX/*"  # This creates ./public folder

echo "Step 1: Unzip prisma.zip"
unzip -o prisma.zip -x "__MACOSX/*"  # This creates ./prisma folder


echo "Step 2: Ensure helper pod exists"
kubectl apply -f helper.yaml -n $NAMESPACE


# Wait for helper pod to be in Running state
echo "Step 2a: Waiting for helper pod to be Running..."
while true; do
  STATUS=$(kubectl get pod $HELPER_POD -n $NAMESPACE -o jsonpath='{.status.phase}')
  if [ "$STATUS" == "Running" ]; then
    echo "Helper pod is Running ✅"
    break
  else
    echo "Helper pod status: $STATUS. Waiting 3s..."
    sleep 3
  fi
done

echo "Step 3: Empty public PVC"
kubectl exec -it -n $NAMESPACE $HELPER_POD -- sh -c "rm -rf /app/public/* /app/public/.??*"

echo "Step 4: Copy public files"
kubectl cp ./public/. $NAMESPACE/$HELPER_POD:/app/public

echo "Step 5: Scale down main pod (for Prisma update)"
kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=0

echo "Step 6: Empty Prisma PVC"
kubectl exec -it -n $NAMESPACE $HELPER_POD -- sh -c "rm -rf /app/prisma/* /app/prisma/.??*"

echo "Step 7: Copy Prisma files"
kubectl cp ./prisma/. $NAMESPACE/$HELPER_POD:/app/prisma

echo "Step 7a: Fix permissions for Prisma"
kubectl exec -n $NAMESPACE $HELPER_POD -- sh -c "chown -R 10001:10001 /app/prisma && chmod -R 775 /app/prisma"

echo "Step 8: Scale up main pod"
kubectl scale deployment $DEPLOYMENT -n $NAMESPACE --replicas=1

echo "Update complete!"
