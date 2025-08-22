oc get ingresscontroller default -n openshift-ingress-operator -o yaml

oc get pods -n openshift-ingress



oc label node <node-name> node-role.kubernetes.io/infra=true

oc label node worker-0.example.com node-role.kubernetes.io/infra=true
oc label node worker-1.example.com node-role.kubernetes.io/infra=true

oc edit ingresscontroller default -n openshift-ingress-operator

spec:
  # ... other existing fields
  nodePlacement:
    nodeSelector:
      matchLabels:
        node-role.kubernetes.io/master: ""
    tolerations:
    - effect: NoSchedule
      key: node-role.kubernetes.io/master
      operator: Exists
  # ... other existing fields

  


oc describe node <node-name> | grep -i taints