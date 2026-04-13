kubectl delete -f https://github.com/aws/secrets-store-csi-driver-provider-aws/releases/latest/download/provider-aws-installer.yaml
kubectl delete -f https://raw.githubusercontent.com/kubernetes-sigs/secrets-store-csi-driver/main/deploy/secrets-store-csi-driver.yaml
kubectl delete csidriver secrets-store.csi.k8s.io
kubectl delete crd secretproviderclasses.secrets-store.csi.x-k8s.io
kubectl delete crd secretproviderclasspodstatuses.secrets-store.csi.x-k8s.io
