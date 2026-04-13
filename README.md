apiVersion: apps/v1
kind: Deployment
metadata:
  name: tanishq-fe-test-deployment
  namespace: tanishq
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tanishq-fe-test
  template:
    metadata:
      labels:
        app: tanishq-fe-test
    spec:
      containers:
        image: difinative/tanishq-fe:latest
        imagePullPolicy: Always
        name: tanishq-fe-test-container
        ports:
        - containerPort: 80
          protocol: TCP
        envFrom:
          - configMapRef:
              name: titan-configmap
          - secretRef:
              name: rds-secret
          - secretRef:
              name: titan-secrets
