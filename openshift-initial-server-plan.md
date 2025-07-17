# Initial OpenShift Server Setup Plan

## Important Note: OpenShift Version Clarification

**There is no OpenShift 8.** Red Hat OpenShift currently follows the 4.x versioning scheme. The latest versions as of 2025 are:
- **OpenShift 4.19** (Generally Available)
- **OpenShift 4.18** (Supported)
- **OpenShift 4.20** (Preview/Development)

This plan will focus on setting up **OpenShift 4.19** or **OpenShift 4.18** for your initial server deployment.

## Phase 1: Pre-Installation Planning and Requirements

### 1.1 Infrastructure Assessment

#### Minimum System Requirements for OpenShift 4.19/4.18

**Control Plane Nodes (3 nodes minimum):**
- **CPU**: 4 vCPUs minimum (8+ recommended)
- **Memory**: 16 GB RAM minimum (32 GB recommended)
- **Storage**: 120 GB minimum (SSD recommended)
- **Network**: 1 Gbps minimum

**Worker Nodes (2 nodes minimum):**
- **CPU**: 2 vCPUs minimum (4+ recommended)
- **Memory**: 8 GB RAM minimum (16 GB recommended)
- **Storage**: 120 GB minimum (SSD recommended)
- **Network**: 1 Gbps minimum

**Total Minimum Cluster:**
- 5 nodes (3 control plane + 2 worker)
- 20 vCPUs
- 64 GB RAM
- 600 GB storage

#### Supported Platforms
- **Bare Metal**
- **VMware vSphere**
- **AWS** (EC2)
- **Microsoft Azure**
- **Google Cloud Platform (GCP)**
- **IBM Cloud**
- **Red Hat OpenStack Platform (RHOSP)**
- **Red Hat Virtualization (RHV)**

### 1.2 Network Requirements

#### IP Address Planning
- **Machine Network**: CIDR for cluster nodes (e.g., 10.0.0.0/16)
- **Service Network**: Internal services (default: 172.30.0.0/16)
- **Pod Network**: Pod communication (default: 10.128.0.0/14)

#### Required Ports
**Control Plane:**
- 6443/tcp (Kubernetes API)
- 22623/tcp (Machine Config Server)
- 2379-2380/tcp (etcd)

**Worker Nodes:**
- 10250/tcp (Kubelet)
- 10256/tcp (openshift-sdn)
- 4789/udp (VXLAN)

#### DNS Requirements
- Forward DNS records for all nodes
- Reverse DNS records for all nodes
- API endpoint: `api.<cluster_name>.<domain>`
- Wildcard for applications: `*.apps.<cluster_name>.<domain>`

### 1.3 Storage Planning

#### Storage Classes Needed
- **Default storage** for general workloads
- **Fast storage** (SSD) for databases
- **Backup storage** for persistent volume backups

#### Persistent Storage Options
- **Local Storage** (for development)
- **Network File System (NFS)**
- **Container Storage Interface (CSI)** drivers
- **Red Hat OpenShift Data Foundation** (recommended for production)

## Phase 2: Installation Method Selection

### 2.1 Choose Installation Approach

#### Option A: Installer-Provisioned Infrastructure (IPI)
**Best for:**
- Cloud deployments (AWS, Azure, GCP)
- VMware vSphere with automation
- Teams wanting automated infrastructure provisioning

**Advantages:**
- Automated infrastructure setup
- Built-in load balancers
- Automatic DNS configuration
- Easier upgrades

#### Option B: User-Provisioned Infrastructure (UPI)
**Best for:**
- Bare metal deployments
- Existing infrastructure
- Custom network configurations
- Air-gapped environments

**Advantages:**
- Complete control over infrastructure
- Custom network topologies
- Integration with existing systems

#### Option C: Assisted Installer
**Best for:**
- Simplified bare metal installations
- Teams new to OpenShift
- Standard configurations

**Advantages:**
- GUI-based installation
- Pre-flight validation
- Minimal networking requirements

### 2.2 Recommended Approach for Initial Setup

For a first-time deployment, we recommend:

1. **Development/Testing**: Single-node OpenShift or CodeReady Containers
2. **Production**: Assisted Installer for bare metal or IPI for cloud

## Phase 3: Pre-Installation Preparation

### 3.1 Prerequisites Checklist

#### Red Hat Subscription
- [ ] Red Hat customer account
- [ ] OpenShift subscription entitlements
- [ ] Pull secret from Red Hat Hybrid Cloud Console

#### Infrastructure Preparation
- [ ] Hardware/VM provisioning
- [ ] Network configuration and firewall rules
- [ ] DNS records configuration
- [ ] Load balancer setup (for UPI)
- [ ] Storage configuration

#### Tools Installation
- [ ] OpenShift installer (`openshift-install`)
- [ ] OpenShift CLI (`oc`)
- [ ] kubectl
- [ ] Git (for GitOps)

### 3.2 Download Required Components

```bash
# Download OpenShift installer and CLI
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz
wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz

# Extract tools
tar -xzf openshift-install-linux.tar.gz
tar -xzf openshift-client-linux.tar.gz

# Move to PATH
sudo mv openshift-install oc kubectl /usr/local/bin/
```

## Phase 4: Installation Execution

### 4.1 Basic Installation Steps (IPI Example)

#### Step 1: Create Installation Configuration
```bash
# Create installation directory
mkdir openshift-install
cd openshift-install

# Generate install configuration
openshift-install create install-config
```

#### Step 2: Customize Configuration
Edit `install-config.yaml` with your specific requirements:
- Cluster name and domain
- Platform-specific settings
- Node counts and instance types
- Network configuration
- Pull secret

#### Step 3: Launch Installation
```bash
# Create cluster
openshift-install create cluster --dir=./ --log-level=info
```

### 4.2 Installation Monitoring

The installer will:
1. Create bootstrap node
2. Create control plane nodes
3. Create worker nodes
4. Configure cluster operators
5. Complete cluster initialization

**Expected Duration**: 45-60 minutes

## Phase 5: Post-Installation Configuration

### 5.1 Initial Cluster Verification

```bash
# Check cluster status
oc get nodes
oc get clusteroperators
oc get clusterversion

# Verify cluster health
oc adm node-logs --role=master -u kubelet
```

### 5.2 Essential Day-2 Operations

#### Authentication Configuration
- Configure identity providers (LDAP, OAuth, etc.)
- Set up RBAC policies
- Remove default kubeadmin user

#### Monitoring and Logging
- Configure cluster monitoring
- Set up log forwarding
- Install OpenShift Logging operator

#### Security Configuration
- Configure security context constraints
- Set up network policies
- Enable pod security standards

#### Storage Configuration
- Configure default storage class
- Set up backup policies
- Configure persistent volume reclaim policies

### 5.3 Application Platform Setup

#### Developer Tools
- Install OpenShift Dev Spaces (based on Eclipse Che)
- Configure internal image registry
- Set up CI/CD pipelines

#### Operators Installation
- Install Operator Lifecycle Manager operators
- Configure Red Hat OpenShift GitOps
- Install Red Hat OpenShift Pipelines

## Phase 6: Operational Readiness

### 6.1 Backup and Disaster Recovery

#### etcd Backup
```bash
# Schedule regular etcd backups
oc create -f etcd-backup-cronjob.yaml
```

#### Application Backup
- Install OADP (OpenShift API for Data Protection)
- Configure Velero for application backups
- Test restore procedures

### 6.2 Monitoring and Alerting

#### Cluster Monitoring
- Configure Prometheus retention
- Set up Grafana dashboards
- Configure AlertManager

#### Application Monitoring
- Enable user workload monitoring
- Configure custom metrics
- Set up application-specific alerts

### 6.3 Capacity Planning

#### Resource Monitoring
- Track CPU and memory utilization
- Monitor storage consumption
- Plan for cluster growth

#### Scaling Strategy
- Configure cluster autoscaling
- Plan node addition procedures
- Set up horizontal pod autoscaling

## Phase 7: Advanced Configuration (Optional)

### 7.1 Multi-Cluster Management

#### Red Hat Advanced Cluster Management
- Install ACM operator
- Configure cluster fleet management
- Set up policy-based governance

### 7.2 Service Mesh

#### Red Hat OpenShift Service Mesh
- Install Service Mesh operators
- Configure Istio components
- Set up traffic management

### 7.3 Serverless

#### Red Hat OpenShift Serverless
- Install Knative operators
- Configure serverless workloads
- Set up event-driven architecture

## Phase 8: Maintenance and Upgrades

### 8.1 Regular Maintenance Tasks

#### Weekly Tasks
- [ ] Review cluster health
- [ ] Check certificate expiration
- [ ] Monitor storage utilization
- [ ] Review security advisories

#### Monthly Tasks
- [ ] Update cluster operators
- [ ] Review and apply patches
- [ ] Test backup and restore procedures
- [ ] Capacity planning review

### 8.2 Upgrade Strategy

#### Upgrade Planning
- Review release notes
- Test upgrades in development
- Plan maintenance windows
- Backup before upgrades

#### Upgrade Execution
```bash
# Check available updates
oc adm upgrade

# Perform upgrade
oc adm upgrade --to-latest=true
```

## Troubleshooting Guide

### Common Issues and Solutions

#### Installation Failures
- **DNS resolution issues**: Verify DNS records and resolvers
- **Network connectivity**: Check firewall rules and routing
- **Resource constraints**: Verify hardware requirements
- **Authentication**: Validate pull secret and subscriptions

#### Post-Installation Issues
- **Pod scheduling failures**: Check node resources and taints
- **Storage issues**: Verify storage class configuration
- **Network problems**: Check CNI configuration and security groups

### Useful Commands

```bash
# Check cluster operators
oc get co

# Debug node issues
oc debug node/<node-name>

# Check cluster events
oc get events --sort-by='.lastTimestamp'

# View cluster logs
oc logs -n openshift-cluster-version deployments/cluster-version-operator
```

## Resource Requirements Summary

### Minimum Production Environment
- **Nodes**: 3 control plane + 3 worker nodes
- **CPU**: 24 vCPUs total
- **Memory**: 96 GB RAM total
- **Storage**: 720 GB total
- **Network**: Dedicated VLAN with load balancer

### Recommended Production Environment
- **Nodes**: 3 control plane + 6 worker nodes
- **CPU**: 48 vCPUs total
- **Memory**: 192 GB RAM total
- **Storage**: 1.5 TB total with SSD
- **Network**: Redundant network with multiple load balancers

## Next Steps

1. **Assess your infrastructure** and choose the appropriate installation method
2. **Gather prerequisites** including Red Hat subscriptions and pull secrets
3. **Plan your network** architecture and DNS configuration
4. **Start with a development** cluster to familiarize yourself with OpenShift
5. **Follow this plan** systematically for your production deployment

## Additional Resources

- [OpenShift 4.19 Documentation](https://docs.openshift.com/container-platform/4.19/)
- [Red Hat OpenShift Learning Hub](https://learn.openshift.com/)
- [OpenShift Interactive Learning Portal](https://learn.openshift.com/introduction/)
- [Red Hat Customer Portal](https://access.redhat.com/)
- [OpenShift Commons Community](https://commons.openshift.org/)

---

**Note**: This plan is based on OpenShift 4.19 (the latest GA version). Always refer to the official Red Hat documentation for the most current information and version-specific requirements.