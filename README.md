apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: test-secret
spec:
  refreshInterval: 1m
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  target:
    name: test-secret
  data:
  - secretKey: password
    remoteRef:
      key: 
      property: password
