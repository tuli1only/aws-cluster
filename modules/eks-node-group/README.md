# eks-node-group
One managed node group with its own IAM role and launch template (encrypted disk, IMDSv2 only).
Reusable: call it again for the Data / AI group with min 0, max 4, and a label + taint.
Key inputs: cluster_name, node_group_name, subnet_ids, instance_types, desired/min/max_size, labels, taints.
