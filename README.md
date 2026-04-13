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


kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/rbac-secretproviderclass.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store-csi-driver.yaml

kubectl apply -f https://github.com/aws/secrets-store-csi-driver-provider-aws/releases/latest/download/provider-aws-installer.yaml
