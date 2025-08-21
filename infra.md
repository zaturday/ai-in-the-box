```
# taint node infra no schedule / lable node to infra

oc get nodes --show-labels

oc label node worker-0.example.com node-role.kubernetes.io/infra=true
oc label node worker-1.example.com node-role.kubernetes.io/infra=true

oc get nodes -o custom-columns=NODE:.metadata.name,TAINTS:.spec.taints

oc describe node <node-name> | grep -i taints
```
```
spec:
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/infra: "true"
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/infra
      operator: Exists
```

```
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
```
```
  oc get pods -n openshift-ingress -o wide --watch
```

setup mcp with infra node
```
cat infra.mcp.yaml
```

```
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfigPool
metadata:
  name: infra
spec:
  machineConfigSelector:
    matchExpressions:
      - {key: machineconfiguration.openshift.io/role, operator: In, values: [worker,infra]}
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/infra: ""
```

maybe spec for MCP
```
  machineConfigSelector:
    matchExpressions:
    - key: machineconfiguration.openshift.io/role
      operator: In
      values:
      - worker
      - infra
  nodeSelector:
    matchLabels:
      node-role.kubernetes.io/infra: ""

```

