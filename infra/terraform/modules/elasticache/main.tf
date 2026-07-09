# Random password for Redis auth
# ElastiCache only allows: alphanumeric and symbols (excluding @, ", /)
resource "random_password" "redis" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

# Store Redis auth token in Secrets Manager
resource "aws_secretsmanager_secret" "redis_auth" {
  name_prefix = "${var.name_prefix}-redis-auth-"
  description = "Redis authentication token"

  tags = {
    Name = "${var.name_prefix}-redis-auth"
  }
}

resource "aws_secretsmanager_secret_version" "redis_auth" {
  secret_id     = aws_secretsmanager_secret.redis_auth.id
  secret_string = jsonencode({
    auth_token = random_password.redis.result
  })
}

# Security Group for Redis
resource "aws_security_group" "redis" {
  name        = "${var.name_prefix}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-redis-sg"
  }
}

# Allow Lambda to access Redis
resource "aws_security_group_rule" "redis_from_lambda" {
  type                     = "ingress"
  description              = "Allow Redis access from Lambda"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  security_group_id        = aws_security_group.redis.id
  source_security_group_id = var.lambda_security_group_ids[0]
}

# ElastiCache Subnet Group
resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-redis-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name_prefix}-redis-subnet-group"
  }
}

# ElastiCache Replication Group (Redis Cluster)
resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.name_prefix}-redis"
  description                 = "Redis cluster for ${var.name_prefix}"

  engine               = "redis"
  engine_version       = var.engine_version
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name
  node_type            = var.node_type

  # High Availability
  num_cache_clusters         = var.num_cache_nodes
  automatic_failover_enabled = var.num_cache_nodes > 1
  multi_az_enabled          = var.num_cache_nodes > 1

  # Network
  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.redis.id]

  # Backup
  snapshot_retention_limit = var.snapshot_retention_limit
  snapshot_window         = "03:00-05:00"

  # Maintenance
  maintenance_window      = "sun:05:00-sun:07:00"
  auto_minor_version_upgrade = true

  # Security
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  auth_token                = random_password.redis.result

  # Notifications
  notification_topic_arn = aws_sns_topic.redis_events.arn

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}

# Parameter Group for optimized settings
resource "aws_elasticache_parameter_group" "main" {
  name   = "${var.name_prefix}-redis-params"
  family = "redis7"

  # Optimize for Lambda usage patterns
  parameter {
    name  = "timeout"
    value = "300"  # 5 minutes
  }

  parameter {
    name  = "tcp-keepalive"
    value = "60"
  }

  parameter {
    name  = "maxmemory-policy"
    value = "allkeys-lru"  # Evict least recently used keys
  }

  tags = {
    Name = "${var.name_prefix}-redis-params"
  }
}

# SNS Topic for Redis events
resource "aws_sns_topic" "redis_events" {
  name = "${var.name_prefix}-redis-events"

  tags = {
    Name = "${var.name_prefix}-redis-events"
  }
}

# CloudWatch Alarms
resource "aws_cloudwatch_metric_alarm" "redis_cpu_high" {
  alarm_name          = "${var.name_prefix}-redis-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "75"
  alarm_description   = "Redis CPU exceeds 75%"
  alarm_actions       = [aws_sns_topic.redis_events.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }
}

resource "aws_cloudwatch_metric_alarm" "redis_memory_high" {
  alarm_name          = "${var.name_prefix}-redis-memory-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseMemoryUsagePercentage"
  namespace           = "AWS/ElastiCache"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Redis memory usage exceeds 80%"
  alarm_actions       = [aws_sns_topic.redis_events.arn]

  dimensions = {
    ReplicationGroupId = aws_elasticache_replication_group.main.id
  }
}
