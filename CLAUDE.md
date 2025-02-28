# CLAUDE.md - Agent Guidelines

## Project Overview
Terraform configuration for AWS Warm Standby Disaster Recovery POC with Aurora PostgreSQL Global Database

## Commands
- `terraform init` - Initialize Terraform working directory
- `terraform validate` - Validate Terraform configuration
- `terraform plan` - Preview changes before applying
- `terraform apply` - Apply Terraform configuration changes
- `bash iac/disaster-recovery-script.sh` - Test DR scenarios

## Code Style
- **Naming**: Use descriptive snake_case for resources prefixed with application name
- **Formatting**: 2-space indentation and consistent spacing
- **Variables**: Always define type, description, and defaults
- **Comments**: Add descriptive file headers and section dividers
- **Organization**: Group related resources in logical files
- **Tagging**: Maintain standard tags across all resources (Name, Environment, Owner)

## Error Handling
- Use conditionals for error prevention when appropriate
- Implement proper timeout and retry mechanisms
- Validate inputs before processing