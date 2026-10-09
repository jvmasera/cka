# Step 1: pause workload
kubectl scale deployment wordpress --replicas 0

# Step 2: edit deployment (set same resources on all init + main containers)
# kubectl edit deployment wordpress
# In spec.template.spec.containers[] and spec.template.spec.initContainers[] set:
# resources:
#   requests:
#     cpu: "300m"
#     memory: "600Mi"
#   limits:
#     cpu: "400m"
#     memory: "700Mi"
# (Values are just an example of dividing the node evenly and keeping some headroom;
# ensure every container—init and main—uses the exact same requests/limits.)
# Applied here non-interactively via a strategic-merge patch instead of
# "kubectl edit", so this solution can run unattended (e.g. via "cka
# gabaritar") without opening an interactive editor:
RESOURCES='{"requests":{"cpu":"300m","memory":"600Mi"},"limits":{"cpu":"400m","memory":"700Mi"}}'
INIT_CONTAINERS=$(kubectl get deployment wordpress -o jsonpath='{.spec.template.spec.initContainers[*].name}')
MAIN_CONTAINERS=$(kubectl get deployment wordpress -o jsonpath='{.spec.template.spec.containers[*].name}')
PATCH_CONTAINERS=$(for n in $MAIN_CONTAINERS; do echo "{\"name\":\"$n\",\"resources\":$RESOURCES}"; done | jq -s '.')
if [ -n "$INIT_CONTAINERS" ]; then
  PATCH_INIT_CONTAINERS=$(for n in $INIT_CONTAINERS; do echo "{\"name\":\"$n\",\"resources\":$RESOURCES}"; done | jq -s '.')
  kubectl patch deployment wordpress --type strategic -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":$PATCH_CONTAINERS,\"initContainers\":$PATCH_INIT_CONTAINERS}}}}"
else
  kubectl patch deployment wordpress --type strategic -p "{\"spec\":{\"template\":{\"spec\":{\"containers\":$PATCH_CONTAINERS}}}}"
fi

# Step 3: resume replicas
kubectl scale deployment wordpress --replicas 3
kubectl rollout status deployment wordpress
kubectl get pods -l app=wordpress
