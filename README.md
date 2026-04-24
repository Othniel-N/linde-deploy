apiVersion: v1
data:
  env-config.js: |
    window._env_ = {
      VITE_API_BASE_URL: "https://tanishq.test.squirrelvision.ai",
      VITE_UPLOADER_URL: "https://titan-uploader.test.squirrelvision.ai",
      VITE_AZURE_CLIENT_ID: "your-client-id",
      VITE_AZURE_TENANT_ID: "your-tenant-id",
      VITE_AZURE_REDIRECT_URI: "https://tanishq-fe.test.squirrelvision.ai/auth"
    };
kind: ConfigMap
metadata:
  name: titan-frontend-env-config
  namespace: titan

fwqgst7lwtz98ghbsrwh56ln59gkq4xvt62xx22l98bv7gvwwnhllh



      volumes:
      - configMap:
          defaultMode: 420
          name: titan-frontend-env-config
        name: env-config-volume

        volumeMounts:
        - mountPath: /usr/share/nginx/html/env-config.js
          name: env-config-volume
          subPath: env-config.js
