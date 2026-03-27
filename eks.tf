module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0" # Using latest v21 module

  # Updated to v21 syntax
  name               = var.cluster_name
  kubernetes_version = "1.31"

  vpc_id                 = module.vpc.vpc_id
  subnet_ids             = module.vpc.private_subnets
  endpoint_public_access = true

  # Crucial for newer EKS module versions: 
  # Grants the IAM user running Terraform 'cluster-admin' permissions
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    capstone_nodes = {
      min_size     = 1
      max_size     = 3
      desired_size = 2

      instance_types = ["c7i-flex.large"] # Maintained customized instance requirement
      capacity_type  = "ON_DEMAND"
    }
  }

  tags = {
    Environment = "dev"
    Project     = "devops-capstone"
  }
}
