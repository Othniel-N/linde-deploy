apiVersion: apps/v1
kind: Deployment
metadata:
  name: titan-uploader
  namespace: titan
spec:
  replicas: 1
  selector:
    matchLabels:
      app: titan-uploader
  template:
    metadata:
      labels:
        app: titan-uploader
    spec:
      containers:
      - image: difinative/titan-fastapi:v20
        imagePullPolicy: Always
        livenessProbe:
          failureThreshold: 5
          httpGet:
            path: /health
            port: 5000
            scheme: HTTP
          initialDelaySeconds: 120
          periodSeconds: 30
          successThreshold: 1
          timeoutSeconds: 10
        name: titan-fastapi
        ports:
        - containerPort: 5000
          name: http
          protocol: TCP
        readinessProbe:
          failureThreshold: 5
          httpGet:
            path: /health
            port: 5000
            scheme: HTTP
          initialDelaySeconds: 90
          periodSeconds: 10
          successThreshold: 1
          timeoutSeconds: 10
        resources:
          limits:
            cpu: "2"
            memory: 4Gi
          requests:
            cpu: 500m
            memory: 2Gi
        volumeMounts:
        - mountPath: /app/inbox
          name: titan-data
          subPath: inbox
        - mountPath: /app/uploaded
          name: titan-data
          subPath: uploaded
        - mountPath: /app/failed
          name: titan-data
          subPath: failed
        - mountPath: /app/logs
          name: titan-data
          subPath: logs
      - env:
        - name: API_URL
          value: http://localhost:5000/api/upload-to-archive
        image: difinative/titan-watcher:v20
        imagePullPolicy: Always
        name: titan-watcher
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 256Mi
        volumeMounts:
        - mountPath: /app/inbox
          name: titan-data
          subPath: inbox
        - mountPath: /app/uploaded
          name: titan-data
          subPath: uploaded
        - mountPath: /app/failed
          name: titan-data
          subPath: failed
        - mountPath: /app/logs
          name: titan-data
          subPath: logs
      initContainers:
      - command:
        - sh
        - -c
        - mkdir -p /data/inbox /data/uploaded /data/failed /data/logs
        image: busybox:1.36
        imagePullPolicy: IfNotPresent
        name: init-dirs
        volumeMounts:
        - mountPath: /data
          name: titan-data
      restartPolicy: Always
      volumes:
      - name: titan-data
        persistentVolumeClaim:
          claimName: titan-uploader-pvc
