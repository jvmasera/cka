# Patch wordpress deployment to add shared volume + native sidecar (initContainer with restartPolicy: Always)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
spec:
  template:
    spec:
      volumes:
      - name: log
        emptyDir: {}
      initContainers:
      - name: sidecar
        image: busybox:stable
        restartPolicy: Always
        command: ["/bin/sh","-c","touch /var/log/wordpress.log; tail -f /var/log/wordpress.log"]
        volumeMounts:
        - name: log
          mountPath: /var/log
      containers:
      - name: wordpress
        volumeMounts:
        - name: log
          mountPath: /var/log
EOF

kubectl rollout status deployment wordpress
kubectl get pods -l app=wordpress
