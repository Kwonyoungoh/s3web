// s3 생성
resource "aws_s3_bucket" "webs3" {
    bucket = "s3-yo-web-test"

    tags = {
        Name        = "s3test"
        Environment = "Dev"
    }
}

resource "aws_s3_bucket_ownership_controls" "webs3" {
  bucket = aws_s3_bucket.webs3.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_public_access_block" "webs3" {
  bucket = aws_s3_bucket.webs3.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_acl" "webs3" {
  depends_on = [
    aws_s3_bucket_ownership_controls.webs3,
    aws_s3_bucket_public_access_block.webs3,
  ]

  bucket = aws_s3_bucket.webs3.id
  acl    = "public-read"
}

// 버킷 정책 설정
resource "aws_s3_bucket_policy" "webs3_policy" {
  bucket = aws_s3_bucket.webs3.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid       = "PublicReadGetObject",
        Effect    = "Allow",
        Principal = "*",
        Action    = ["s3:GetObject"],
        Resource  = ["arn:aws:s3:::${aws_s3_bucket.webs3.bucket}/*"]
      },
    ]
  })
}


// s3 버킷 웹사이트 구성 설정
resource "aws_s3_bucket_website_configuration" "example" {
  bucket = aws_s3_bucket.webs3.bucket

  index_document {
    suffix = "index.html"
  }
}

############################################################
// CloudFront 배포 설정

data "aws_acm_certificate" "yotest" {
    provider    = aws.us-east-1
    domain   = var.domain
    statuses = ["ISSUED"]
    most_recent = true
}

resource "aws_cloudfront_origin_access_control" "yotest" {
  name = aws_s3_bucket.webs3.bucket_domain_name
  description = "test for s3 hosting"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.webs3.bucket_domain_name
    origin_id   = "S3-${aws_s3_bucket.webs3.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.yotest.id
  }

  enabled             = true
  default_root_object = "index.html"

  aliases = ["${var.domain}"]

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.webs3.id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  viewer_certificate {
    acm_certificate_arn = "${data.aws_acm_certificate.yotest.arn}"
    ssl_support_method  = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

############################################################
// Route53 도메인 연결
data "aws_route53_zone" "selected" {
  name         = "${var.domain}"
  private_zone = false
}

resource "aws_route53_record" "cdn" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.s3_distribution.domain_name
    zone_id                = aws_cloudfront_distribution.s3_distribution.hosted_zone_id
    evaluate_target_health = false
  }
}


############################################################
// GithubAction s3 접근 role 생성
resource "aws_iam_role" "github_actions_s3_access" {
    name = "GitHubActionsS3Access"

    assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${aws_iam_openid_connect_provider.github.url}:aud" = "sts.amazonaws.com"
          },
          StringLike ={
            "${aws_iam_openid_connect_provider.github.url}:sub" = "repo:${var.github_repository}:*"
          }
        }
      }
    ]
  })
}

// 정책 생성
resource "aws_iam_role_policy" "s3_policy" {
  name   = "GitHubActionsS3Policy"
  role   = aws_iam_role.github_actions_s3_access.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = "${aws_s3_bucket.webs3.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.webs3.arn
      }
    ]
  })
}

// https://github.blog/changelog/label/openid-connect/
resource "aws_iam_openid_connect_provider" "github" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["1c58a3a8518e8759bf075b76b750d4f2df264fcd"]  # GitHub의 OIDC 지문
  url             = "https://token.actions.githubusercontent.com"
}
