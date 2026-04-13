#!/bin/bash

SECRET_ID="arn:aws:secrebF"
NAMESPACE="titan"
SECRET_NAME="rds-secret"

echo "Fetching secret from AWS..."

SECRET=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_ID \
  --query SecretString \
  --output text)

PASSWORD=$(echo $SECRET | jq -r '.password')

echo "Updating Kubernetes secret..."

kubectl create secret generic $SECRET_NAME \
  --from-literal=DB_PASSWORD="$PASSWORD" \
  -n $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Done!"
