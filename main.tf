provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "capstone_devops_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "capstone-devops-vpc"
  }
}

resource "aws_subnet" "capstone_devops_subnet" {
  count                   = 2
  vpc_id                  = aws_vpc.capstone_devops_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.capstone_devops_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["us-east-1a", "us-east-1b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "capstone-devops-subnet-${count.index}"
    # FIX: These tags are MANDATORY for AWS Load Balancers to discover the subnets!
    "kubernetes.io/cluster/capstone-devops-cluster" = "shared"
    "kubernetes.io/role/elb"                        = 1
  }
}

resource "aws_internet_gateway" "capstone_devops_igw" {
  vpc_id = aws_vpc.capstone_devops_vpc.id

  tags = {
    Name = "capstone-devops-igw"
  }
}

resource "aws_route_table" "capstone_devops_route_table" {
  vpc_id = aws_vpc.capstone_devops_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.capstone_devops_igw.id
  }

  tags = {
    Name = "capstone-devops-route-table"
  }
}

resource "aws_route_table_association" "capstone_devops_association" {
  count          = 2
  subnet_id      = aws_subnet.capstone_devops_subnet[count.index].id
  route_table_id = aws_route_table.capstone_devops_route_table.id
}

resource "aws_security_group" "capstone_devops_cluster_sg" {
  vpc_id = aws_vpc.capstone_devops_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "capstone-devops-cluster-sg"
  }
}

resource "aws_security_group" "capstone_devops_node_sg" {
  vpc_id = aws_vpc.capstone_devops_vpc.id

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "capstone-devops-node-sg"
  }
}

resource "aws_eks_cluster" "capstone_devops" {
  name     = "capstone-devops-cluster"
  role_arn = aws_iam_role.capstone_devops_cluster_role.arn

  vpc_config {
    subnet_ids         = aws_subnet.capstone_devops_subnet[*].id
    security_group_ids = [aws_security_group.capstone_devops_cluster_sg.id]
  }

  # Ensure IAM permissions are attached BEFORE creating the cluster
  depends_on = [
    aws_iam_role_policy_attachment.capstone_devops_cluster_role_policy
  ]
}

resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name = aws_eks_cluster.capstone_devops.name
  addon_name   = "aws-ebs-csi-driver"

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.capstone_devops]
}

resource "aws_eks_node_group" "capstone_devops" {
  cluster_name    = aws_eks_cluster.capstone_devops.name
  node_group_name = "capstone-devops-node-group"
  node_role_arn   = aws_iam_role.capstone_devops_node_group_role.arn
  subnet_ids      = aws_subnet.capstone_devops_subnet[*].id

  scaling_config {
    desired_size = 3
    max_size     = 3
    min_size     = 3
  }

  instance_types = ["c7i-flex.large"]

  remote_access {
    ec2_ssh_key               = var.ssh_key_name
    source_security_group_ids = [aws_security_group.capstone_devops_node_sg.id]
  }

  # Ensure IAM permissions are attached BEFORE creating the worker nodes
  depends_on = [
    aws_iam_role_policy_attachment.capstone_devops_node_group_role_policy,
    aws_iam_role_policy_attachment.capstone_devops_node_group_cni_policy,
    aws_iam_role_policy_attachment.capstone_devops_node_group_registry_policy,
    aws_iam_role_policy_attachment.capstone_devops_node_group_ebs_policy
  ]
}

resource "aws_iam_role" "capstone_devops_cluster_role" {
  name = "capstone-devops-cluster-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "eks.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "capstone_devops_cluster_role_policy" {
  role       = aws_iam_role.capstone_devops_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "capstone_devops_node_group_role" {
  name = "capstone-devops-node-group-role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "capstone_devops_node_group_role_policy" {
  role       = aws_iam_role.capstone_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "capstone_devops_node_group_cni_policy" {
  role       = aws_iam_role.capstone_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "capstone_devops_node_group_registry_policy" {
  role       = aws_iam_role.capstone_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "capstone_devops_node_group_ebs_policy" {
  role       = aws_iam_role.capstone_devops_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
