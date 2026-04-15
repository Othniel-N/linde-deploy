apiVersion: v1
kind: Service
metadata:
  name: titan-backend-service
  namespace: titan
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 8000
  selector:
    app: titan-backend
  type: ClusterIP



piVersion: v1
kind: Service
metadata:
  name: titan-frontend
  namespace: titan
spec:
  ports:
  - port: 80
    protocol: TCP
    targetPort: 80
  selector:
    app: titan-frontend
  type: ClusterIP



apiVersion: v1
kind: Service
metadata:
  name: titan-uploader
  namespace: titan
spec:
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 5000
  selector:
    app: titan-uploader
  type: ClusterIP

