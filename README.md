# EKS reference cluster - Unit A / Black and Unit B / Red

Builds the same EKS cluster in two separate AWS accounts with Terraform.
No Terraform knowledge needed to follow it. Do the steps in order.

**What Terraform is:** you describe the cluster in text files, and Terraform creates it in AWS.
`plan` shows what it WOULD do. `apply` actually does it.

## How the project is organised

    eks-platform/
    ├── modules/                     reusable building blocks (the "how"). You rarely edit these
    │   ├── eks-cluster/             control plane, KMS key, logs, Access Entries
    │   ├── eks-node-group/          one managed node group (reusable: General, Data/AI, ...)
    │   ├── eks-core-addons/         VPC CNI, kube-proxy, Pod Identity Agent (before nodes)
    │   ├── eks-node-addons/         CoreDNS, EBS CSI driver, StorageClass (after nodes)
    │   ├── eks-lb-controller/       AWS Load Balancer Controller (+ its IAM policy JSON)
    │   └── eks-governance/          namespaces, Pod Security, quotas, NetworkPolicy, RBAC
    ├── environments/                one folder per AWS account (the "what and where")
    │   ├── unit-a-black/            Unit A -> AWS Account A -> ex-a-eks
    │   │   ├── terraform.tfvars     <- THE FILE YOU EDIT (account-specific values)
    │   │   ├── main.tf              wires the modules together
    │   │   ├── variables.tf, providers.tf, versions.tf, backend.tf, outputs.tf
    │   └── unit-b-red/              Unit B -> AWS Account B -> ex-b-eks (same files)
    ├── scripts/tf.sh                helper that runs Terraform safely for one unit
    └── docs/                        your two diagrams and the scope text

Each environment has its **own state** (Terraform's memory of what it built), so Unit A and
Unit B can never affect each other, matching "isolated by default, no connector between Units".

Order of creation: cluster, core add-ons, node group, node add-ons, then the load balancer
controller and governance.

## What gets built (per unit)

- EKS cluster: private API endpoint, encrypted secrets (KMS), selected control plane logs in CloudWatch
- General / Platform node group: 3 x m7i.2xlarge
- Add-ons: VPC CNI, CoreDNS, kube-proxy, EBS CSI driver, Pod Identity Agent, AWS Load Balancer Controller
- Governance: namespace `ex-platform-ci` (add more), Pod Security labels, ResourceQuotas,
  default-deny NetworkPolicy (DNS allowed), RBAC per team

## Step 1 - Install the tools (once, on the machine that will run this)

- Terraform 1.5 or newer: https://developer.hashicorp.com/terraform/install
- AWS CLI v2: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
- kubectl: https://kubernetes.io/docs/tasks/tools/

Check them:

    ./scripts/tf.sh a check

## Step 2 - Log in to the right AWS account

Unit A and Unit B are different accounts. You must be logged in to the matching one.
The script shows which account you are in and makes you confirm before plan, apply or destroy.

    aws configure --profile unit-a      # or your SSO login
    export AWS_PROFILE=unit-a           # unit-b for Unit B

The identity needs rights to create EKS, IAM, KMS, EC2 and CloudWatch resources.

## Step 3 - Fill in the settings

Open `environments/unit-a-black/terraform.tfvars` and replace every `CHANGE-ME`:
region, VPC ID, and at least two private subnet IDs in different Availability Zones.
Optionally add admin role ARNs. Do the same in `unit-b-red/terraform.tfvars` for Unit B.

Subnets need plenty of free IPs because every pod gets a VPC address (your T09 note).

## Step 4 - Where to run this (important)

The cluster API is **private**. Terraform can create the cluster from anywhere, but the parts
that configure inside it (StorageClass, load balancer controller, namespaces, quotas, network
policies) must reach that private API. Run Terraform from a machine **inside the VPC or
connected to it** (your jump host, a VM, or a CI runner).

From a laptop outside the VPC the apply fails at the Kubernetes/Helm parts. Either move to an
in-VPC machine or, temporarily, set in `terraform.tfvars`:

    endpoint_public_access = true
    public_access_cidrs    = ["YOUR.PUBLIC.IP/32"]

and set it back to `false` afterwards. Get security approval first. The cluster module refuses
to open the API without a CIDR list, so it can't be made world-open by accident.

## Step 5 - Pick a Kubernetes version

    aws eks describe-cluster-versions --region <your-region> \
      --query 'clusterVersions[].[clusterVersion,status,endOfStandardSupportDate]' --output table

Choose one in standard support and set `kubernetes_version`. The default 1.35 is unconfirmed for
your region. 1.34 leaves EKS standard support on 2 December 2026, so don't start on it.

## Step 6 - Build it

    ./scripts/tf.sh a init        # downloads providers and modules, first time only
    ./scripts/tf.sh a validate    # checks for mistakes
    ./scripts/tf.sh a plan        # shows what will be created. Read it first
    ./scripts/tf.sh a apply       # creates it. Type 'yes' when asked. About 15-25 minutes

Use `b` instead of `a` for Unit B. Always `plan` first.
If `validate` or `plan` prints an error, copy it into a chat with Claude.

## Step 7 - Check that it works

    aws eks update-kubeconfig --name ex-a-eks --region <your-region> --profile unit-a
    kubectl get nodes                          # 3 nodes, all Ready
    kubectl get pods -n kube-system            # aws-node, coredns, kube-proxy, ebs-csi, pod-identity, LBC: Running
    kubectl get ns                             # includes ex-platform-ci
    kubectl describe quota -n ex-platform-ci
    kubectl get networkpolicy -n ex-platform-ci
    kubectl get storageclass                   # ebs-gp3 (default)

NetworkPolicy check (T06 "verify enforcement"): start a pod in `ex-platform-ci` and try to reach
another service. It should be blocked until you add an allow rule.

## Everyday changes

| I want to... | Edit |
|---|---|
| Change region, subnets, version, admins | `environments/<unit>/terraform.tfvars` |
| Change node count or size | `general_node_group` in `terraform.tfvars` |
| Add a namespace or change quotas | `namespaces` in `terraform.tfvars` (repeat `ex-platform-ci` too, it replaces the default list) |
| Give a team access | `team_access` in `terraform.tfvars` (its namespaces must exist in `namespaces`) |
| Add the Data / AI node group | add a module block to `main.tf` (below) |

Then run `plan` and `apply`. Terraform changes only the difference. Run `./scripts/tf.sh a fmt` to tidy formatting.

### Example: add the Data / AI node group (0-4 nodes, label + taint)

Paste into `environments/<unit>/main.tf`, in both units:

    module "data_ai_node_group" {
      source          = "../../modules/eks-node-group"
      cluster_name    = module.cluster.cluster_name
      node_group_name = "data-ai"
      subnet_ids      = var.private_subnet_ids
      instance_types  = ["m7i.2xlarge"]
      desired_size    = 0
      min_size        = 0
      max_size        = 4
      labels          = { "node-group" = "data-ai", "workload" = "data-ai" }
      taints          = [{ key = "workload", value = "data-ai", effect = "NO_SCHEDULE" }]
      depends_on      = [module.core_addons]
    }

Nodes only start once something needs them (needs an autoscaler such as Karpenter or Cluster Autoscaler).

## State: keep it safe

Terraform's state lives in `environments/<unit>/terraform.tfstate` by default (local file).
- Don't delete it and don't commit it to Git (the `.gitignore` blocks it, it can contain secrets).
- For real use, move it to an S3 bucket in that unit's own account: see `backend.tf`, then run `init` again.
- Do commit `.terraform.lock.hcl` (created by `init`). It pins provider versions.

## Tearing it down

    ./scripts/tf.sh a destroy

Deletes the cluster and everything in it. The StorageClass uses `Retain`, so volumes created by pods
survive and keep costing money until you delete them by hand.

## Cost warning

3 x m7i.2xlarge plus the EKS control plane run 24/7 in each account. Check prices at
https://aws.amazon.com/eks/pricing/ and https://aws.amazon.com/ec2/pricing/on-demand/ and destroy test clusters.

## Safety rules

- Always `plan` before `apply`, and check the account the script prints.
- Unit A and Unit B stay separate: different account, different folder, different state.
- Never open the API endpoint publicly without a reason and an approved CIDR.

## Not included yet

- Data / AI node group (example above)
- GitLab Runner install (only the `ex-platform-ci` namespace, quota and network rules exist)
- Pod Identity for the runners, ex-app-<team> namespaces, EFS
- Splunk / SIEM log forwarding

## Open questions

See `docs/SCOPE-T06.md`. Main one: the second diagram says "OpenShift A" while everything else says EKS.
