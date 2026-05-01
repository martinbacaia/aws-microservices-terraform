# aws-microservices-terraform

Production-grade AWS microservices infrastructure as Terraform code. Builds a
real catalog API: an ECS Fargate REST service backed by RDS Postgres behind an
ALB, plus a Lambda image-resizer fronted by API Gateway and triggered by S3.

> Detailed README (architecture diagram, decisions, costs, quickstart) is
> written incrementally as modules land. Until then, browse `modules/` for
> the building blocks and `bootstrap/` for the remote-state setup.
