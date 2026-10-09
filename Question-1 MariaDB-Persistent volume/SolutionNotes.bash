# Step 1: create PVC with no storageClass (PV is pre-reset by LabSetUp.bash)
cat <<'EOF' > ~/cka/sandbox/pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mariadb
  namespace: mariadb
spec:
  storageClassName: standard
  volumeName: mariadb-pv
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 250Mi
EOF
kubectl apply -f ~/cka/sandbox/pvc.yaml
# Give the binding controller a moment to actually bind the PVC to the PV
# before checking status (right after "apply" the PVC can still briefly show
# as Pending even though volumeName/storageClassName already match the PV).
kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/mariadb -n mariadb --timeout=60s || true
kubectl get pvc mariadb -n mariadb
kubectl get pv mariadb-pv     # should show Bound to mariadb

# Step 2: ensure deployment uses the PVC
# mariadb-deploy.yaml should mount claimName: mariadb
sed -i 's/claimName: ""/claimName: mariadb/' ~/cka/sandbox/mariadb-deploy.yaml
# (LabSetUp.bash leaves claimName blank for practice)
kubectl apply -f ~/cka/sandbox/mariadb-deploy.yaml
# Wait for the deployment to actually become available before finishing, so
# that an immediate verification (e.g. "cka gabaritar 1") doesn't catch the
# pod mid-startup and report a false failure.
kubectl wait --for=condition=Available deployment/mariadb -n mariadb --timeout=60s || true
kubectl get pods -n mariadb
