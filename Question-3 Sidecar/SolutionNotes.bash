# Add shared volume + sidecar to deployment
# kubectl edit deployment wordpress   # add emptyDir volume and mounts below (shown here non-interactively via kubectl apply)
# spec.template.spec.volumes:
# - name: log
#   emptyDir: {}
# main container volumeMounts:
# - mountPath: /var/log
#   name: log
# add sidecar:
# - name: sidecar
#   image: busybox:stable
#   command: ["/bin/sh","-c","tail -f /var/log/wordpress.log"]
#   volumeMounts:
#   - mountPath: /var/log
#     name: log
# Patch wordpress deployment to add shared volume + sidecar.
# NOTE: "kubectl apply" does a three-way merge against the last-applied
# config. Submitting a *partial* Deployment here (omitting selector,
# labels, replicas, the original container's image/command/ports, etc.)
# would make kubectl apply try to DELETE those fields (since they were
# present in the original lastApplied config but missing from this new
# manifest) - and since spec.selector is immutable, the whole apply gets
# rejected, silently leaving the deployment with only the original 1
# container. So we always re-apply the FULL desired Deployment spec,
# matching everything LabSetUp.bash originally created plus the new
# volume/sidecar additions.
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress
  labels:
    app: wordpress
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wordpress
  template:
    metadata:
      labels:
        app: wordpress
    spec:
      volumes:
      - name: log
        emptyDir: {}
      containers:
      - name: wordpress
        image: wordpress:php8.2-apache
        command: ["/bin/sh", "-c", "while true; do echo 'WordPress is running...' >> /var/log/wordpress.log; sleep 5; done"]
        ports:
        - containerPort: 80
        volumeMounts:
        - name: log
          mountPath: /var/log
      - name: sidecar
        image: busybox:stable
        command: ["/bin/sh","-c","tail -f /var/log/wordpress.log"]
        volumeMounts:
        - name: log
          mountPath: /var/log
EOF

kubectl rollout status deployment wordpress
kubectl get pods -l app=wordpress