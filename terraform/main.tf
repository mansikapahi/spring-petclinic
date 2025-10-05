# Data sources for AZs
data "aws_availability_zones" "available" {
  state = "available"
}

# Route53 for Multi-Region Failover (Update "example.com." to your hosted zone or comment out if no DNS needed)
# data "aws_route53_zone" "main" {
#   name         = "example.com."  # UPDATE: Change to your actual zone (e.g., "gorillaclinc.com."). If no zone, comment this block and aws_route53_record below.
#   private_zone = false
# }

# VPC (multi-AZ public subnets, env-prefixed)
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "petclinic-vpc-${var.env}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "petclinic-igw-${var.env}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = {
    Name = "petclinic-public-rt-${var.env}"
  }
}

resource "aws_subnet" "public1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags = {
    Name = "petclinic-public-1-${var.env}"
  }
}

resource "aws_subnet" "public2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true
  tags = {
    Name = "petclinic-public-2-${var.env}"
  }
}

resource "aws_route_table_association" "public1" {
  subnet_id      = aws_subnet.public1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public2" {
  subnet_id      = aws_subnet.public2.id
  route_table_id = aws_route_table.public.id
}

# Security Groups (ALB ingress 80, tasks egress all + ingress from ALB on 8080, env-prefixed)
resource "aws_security_group" "alb" {
  name_prefix = "petclinic-alb-${var.env}-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "petclinic-alb-sg-${var.env}"
  }
}

resource "aws_security_group" "ecs_tasks" {
  name_prefix = "petclinic-ecs-${var.env}-"
  vpc_id      = aws_vpc.main.id
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "petclinic-ecs-sg-${var.env}"
  }
}

# IAM Roles (ECS execution/service, env-prefixed)
resource "aws_iam_role" "ecs_task_execution" {
  name = "petclinic-ecs-task-execution-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# Inline Policy for ECS Task Execution Role (ECR/logs)
resource "aws_iam_role_policy" "ecs_task_execution_inline" {
  name = "petclinic-ecs-task-execution-inline-${var.env}"
  role = aws_iam_role.ecs_task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role" "ecs_service" {
  name = "petclinic-ecs-service-${var.env}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs.amazonaws.com"
        }
      }
    ]
  })
}

# Inline Policy for ECS Service Role (ECS/ELB + PassRole)
resource "aws_iam_role_policy" "ecs_service_inline" {
  name = "petclinic-ecs-service-inline-${var.env}"
  role = aws_iam_role.ecs_service.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*",
          "elasticloadbalancing:Describe*",
          "ecs:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = [
          aws_iam_role.ecs_task_execution.arn
        ]
      }
    ]
  })
}

# ALB (internet-facing, stickiness for sessions, env-prefixed)
resource "aws_lb" "main" {
  name               = "petclinic-alb-${var.env}"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public1.id, aws_subnet.public2.id]
  tags = {
    Name = "petclinic-alb-${var.env}"
  }

  # Optional: Stickiness scale-in behavior (moved from TG; disables termination stickiness on scale-in)
  # enable_deletion_protection = true  # Uncomment for prod HA
}

resource "aws_lb_target_group" "app" {
  name        = "petclinic-tg-${var.env}"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"  # For Fargate awsvpc

  # Stickiness for reduced latency in sessions
  stickiness {
    enabled         = true
    type            = "lb_cookie"
    cookie_duration = 3600
  }

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/actuator/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }
  tags = {
    Name = "petclinic-tg-${var.env}"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ECS Cluster (env-prefixed)
resource "aws_ecs_cluster" "main" {
  name = "petclinic-cluster-${var.env}"
}

# CloudWatch Log Group (7 days, env-prefixed)
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/petclinic-${var.env}"
  retention_in_days = 7
}

# ECS Task Definition (Enhanced: 2048 CPU/4096 MB for low latency, fixed environment JSON)
resource "aws_ecs_task_definition" "app" {
  family                   = "petclinic-task-${var.env}"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "2048"  # Increased for 30k scale
  memory                   = "4096"  # Increased for Java/GC
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "petclinic-app"
      image     = var.ecr_image
      essential = true
      portMappings = [
        {
          containerPort = 8080
          # hostPort not needed for Fargate awsvpc
        }
      ]
      environment = [
        {
          name  = "JAVA_OPTS"
          value = "-Xmx3072m -XX:+UseG1GC -XX:MaxGCPauseMillis=100"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = "eu-central-1"  # Hardcoded to fix undeclared var.region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])
}

# ECS Service (Zero-downtime rolling with ECS controller; Spot for cost)
resource "aws_ecs_service" "main" {
  name            = "petclinic-service-${var.env}"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 0  # Min 0 for pay-per-use; scaling manages

  # Native rolling for zero-downtime (2-5 min deploys)
  deployment_controller {
    type = "ECS"
  }
  deployment_maximum_percent         = 200  # 200% for rolling/blue-green
  deployment_minimum_healthy_percent = 100  # No disruption (1 task at a time)

  network_configuration {
    subnets          = [aws_subnet.public1.id, aws_subnet.public2.id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.id
    container_name   = "petclinic-app"
    container_port   = 8080
  }

  # Spot for pay-per-use savings
  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 1
  }

  depends_on = [
    aws_iam_role_policy.ecs_task_execution_inline,
    aws_iam_role_policy.ecs_service_inline,
    aws_lb_listener.front_end
  ]
}

# ECS Auto-Scaling (For 30k users: CPU-based, min 2/max 100)
resource "aws_appautoscaling_target" "ecs_service" {
  max_capacity       = var.desired_count_max
  min_capacity       = var.desired_count_min
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.main.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Target Tracking Policy (50% CPU, 30s cooldowns)
resource "aws_appautoscaling_policy" "ecs_service_cpu" {
  name               = "cpu-autoscaling-${var.env}"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_service.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_service.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = 50.0  # Scale at 50% CPU for <200 ms P98
    scale_in_cooldown  = 30
    scale_out_cooldown = 30
  }
}

# Step Scaling Policy (+5 tasks on alarm; placed before alarm to avoid circular ref)
resource "aws_appautoscaling_policy" "ecs_service_step" {
  name                = "step-autoscaling-${var.env}"
  service_namespace   = "ecs"
  resource_id         = aws_appautoscaling_target.ecs_service.resource_id
  scalable_dimension  = aws_appautoscaling_target.ecs_service.scalable_dimension

  step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 30
    metric_aggregation_type = "Average"

    step_adjustment {
      metric_interval_lower_bound = 0
      scaling_adjustment          = 5  # +5 tasks on >50% CPU alarm
    }
  }
}

# CloudWatch Alarm for Step Scaling (references step policy ARN)
resource "aws_cloudwatch_metric_alarm" "ecs_cpu_high" {
  alarm_name          = "ecs-cpu-high-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = "60"
  statistic           = "Average"
  threshold           = "50"
  alarm_description   = "Alarm when ECS service CPU exceeds 50%"

  dimensions = {
    ClusterName = aws_ecs_cluster.main.name
    ServiceName = aws_ecs_service.main.name
  }

  alarm_actions = [aws_appautoscaling_policy.ecs_service_step.arn]
}

# Route53 for Multi-Region Failover (Primary; duplicate stack for secondary)
# resource "aws_route53_record" "alb_primary" {
#   zone_id = data.aws_route53_zone.main.zone_id
#   name    = "petclinic-${var.env}"
#   type    = "A"
#
#   set_identifier = "eu-central-1-primary"
#
#   failover_routing_policy {
#     type = "PRIMARY"
#   }
#
#   alias {
#     name                   = aws_lb.main.dns_name
#     zone_id                = aws_lb.main.zone_id
#     evaluate_target_health = true
#   }
# }
