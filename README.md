apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: rds-secret
  namespace: titan
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: ""
        objectType: "secretsmanager"
        jmesPath:
          - path: "password"
            objectAlias: "password"
