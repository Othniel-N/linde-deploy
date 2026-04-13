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
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/csidriver.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/rbac-secretproviderclass.yaml

kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store-csi-driver.yaml

 kubectl apply -f https://github.com/kubernetes-sigs/secrets-store-csi-driver/releases/latest/download/secrets-store.csi.x-k8s.io_secretproviderclasses.yaml
 kubectl apply -f https://github.com/kubernetes-sigs/secrets-store-csi-driver/releases/latest/download/secrets-store-csi-driver.yaml


apiVersion: v1
kind: Pod
metadata:
  name: secret-test
  namespace: titan
spec:
  containers:
    - name: test
      image: busybox
      command: ["sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: secrets-store
          mountPath: "/mnt/secrets"
          readOnly: true

  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        volumeAttributes:
          secretProviderClass: "rds-secret"
