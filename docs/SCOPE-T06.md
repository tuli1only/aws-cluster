# T06 - EKS cluster management and configuration (scope)

Source: the request text and the two architecture diagrams in this folder.
(English reconstruction of the Hebrew scope text.)

## Tasks
1. Write a Terraform file to provision the EKS cluster.
2. Select the Kubernetes version and make sure it is compatible with the AWS-managed control plane.
3. Define all relevant parameters for the EKS setup.
4. Provision three nodes of type m7i.2xlarge (8 vCPU, 32 GiB RAM each).

## T06 scope
- General Node Group management.
- Cluster add-on installation: AWS VPC CNI, CoreDNS, Amazon EBS CSI Driver,
  AWS Load Balancer Controller, Pod Identity Agent, kube-proxy.
- Enforcement of hierarchical cluster governance: RBAC, ResourceQuotas, NetworkPolicy.
- GitLab Runners: stateless job pods for build and test workloads, in the
  `ex-platform-ci` namespace on EKS.

## Architecture (see the PNG files in this folder)
- Two AWS accounts, one cluster each: Unit A / Black (ex-a-eks), Unit B / Red (ex-b-eks).
- Isolated by default, no connector between the units. Identical reference cluster in each.
- Namespace naming: ex-platform-*, ex-app-<team>.

## Open questions
- The second diagram labels the cluster "OpenShift A", the rest says EKS. Which is right?
- Data / AI node group (0-4 nodes, label + taint): not in this scope, not included.
- GitLab Runner Helm release: not included yet (only its namespace, quota and network rules).
- Which AWS region? Is m7i.2xlarge offered there?
