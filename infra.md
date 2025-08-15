oc get nodes --show-labels

oc label node worker-0.example.com node-role.kubernetes.io/infra=true
oc label node worker-1.example.com node-role.kubernetes.io/infra=true

oc get nodes -o custom-columns=NODE:.metadata.name,TAINTS:.spec.taints

oc describe node <node-name> | grep -i taints

spec:
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: "true"
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/infra
      operator: Exists


spec:
  # ... other existing fields
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: "true"
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/infra
      operator: Exists
  # ... other existing fields


  oc get pods -n openshift-ingress -o wide --watch
