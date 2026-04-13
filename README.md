apiVersion: apps/v1
kind: Deployment
metadata:
  name: titan-backend
  namespace: tanishq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: titan-backend
  template:
    metadata:
      labels:
        app: titan-backend
    spec:
      containers:
      - image: difinative/tanishq-be:latest
        imagePullPolicy: Always
        name: tanishq-test-container
        ports:
        - containerPort: 8000
          protocol: TCP
        envFrom:
          - configMapRef:
              name: titan-configmap
          - secretRef:
              name: rds-secret
          - secretRef:
              name: titan-secrets
