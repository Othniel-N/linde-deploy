apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: titan-uploader-pvc
  namespace: titan
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
