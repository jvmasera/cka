# Step one
# We want to edit the config map to only support TLSv1.2 and make it immutable
# Note: In Kubernetes, you can set `immutable: true` on the ConfigMap.
# If modifying an existing ConfigMap, you can update `ssl_protocols TLSv1.2;` and add `immutable: true`.
# ConfigMaps don't support "kubectl patch"/"kubectl edit" for the `immutable`
# field together with data changes in every version, and "kubectl edit" is
# interactive (hangs when this script runs unattended, e.g. via "cka
# gabaritar"). Since the ConfigMap is not yet immutable, it can still be
# replaced in-place with "kubectl apply" using the full desired manifest:
cat <<'EOF' | k apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-config
  namespace: nginx-static
immutable: true
data:
  nginx.conf: |
    events {}
    http {
      server {
        listen 443 ssl;
        ssl_certificate /etc/nginx/tls/tls.crt;
        ssl_certificate_key /etc/nginx/tls/tls.key;
        ssl_protocols TLSv1.2;
        location / {
          return 200 "Hello TLS\n";
        }
      }
    }
EOF
# Under metadata/data:
# 1. Update ssl_protocols to only TLSv1.2:
#        ssl_protocols TLSv1.2;
# 2. Add immutable field at root level:
#    immutable: true

# Step 2
# We need to get the IP of the service
k get svc -n nginx-static
# We need to add this IP with the host name to /etc/hosts
IP=$(k get svc -n nginx-static nginx-static -o jsonpath='{.spec.clusterIP}')
echo "$IP ckaquestion.k8s.local" | sudo tee -a /etc/hosts
# Check the hosts file has been updated the IP and host should be added to the bottom of the file
sudo cat /etc/hosts

# Step 3
# If we run the check commands now we see v1.3 might still work or config not reloaded,
# restart the deployment to use the new CM config:
k rollout restart -n nginx-static deployment nginx-static
# Test the commands:
# curl -vk --tlsv1.2 --tls-max 1.2 https://ckaquestion.k8s.local # should work
# curl -vk --tlsv1.3 https://ckaquestion.k8s.local # should fail
