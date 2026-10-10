# Step 1: pause workload
kubectl scale deployment wordpress --replicas 0

# Step 2: edit deployment (set same resources on all init + main containers)
# kubectl edit deployment wordpress
# In spec.template.spec.containers[] and spec.template.spec.initContainers[] set:
# resources:
#   requests:
#     cpu: "200m"
#     memory: "256Mi"
#   limits:
#     cpu: "200m"
#     memory: "256Mi"
# (Requests == limits so every Pod gets a fixed, predictable share of the
# node - low enough that 3 replicas actually fit on a small lab node/VM and
# the rollout doesn't freeze waiting forever for a Pod stuck Pending due to
# insufficient CPU/memory.)
# Applied here non-interactively via a strategic-merge patch instead of
# "kubectl edit", so this solution can run unattended (e.g. via "cka
# gabaritar") without opening an interactive editor:
RESOURCES='{"requests":{"cpu":"200m","memory":"256Mi"},"limits":{"cpu":"200m","memory":"256Mi"}}'
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
# Use a bounded timeout instead of letting this hang forever: if the chosen
# resources don't fit on the node, "kubectl rollout status" with no timeout
# will wait indefinitely for the stuck Pending Pod. A --timeout lets the
# script move on and the "kubectl get pods" below shows what actually
# happened, instead of freezing the whole SolutionNotes.bash run.
kubectl rollout status deployment wordpress --timeout=120s || true
kubectl get pods -l app=wordpress
