# API Reference

## EKS Cluster Provisioning Platform API Reference

This document provides comprehensive API reference for the Enterprise EKS Cluster Automation Platform.

## REST API Endpoints

### Cluster Management

#### Create Cluster
```http
POST /api/v1/clusters
Content-Type: application/json

{
  "name": "example-cluster",
  "version": "1.29",
  "region": "us-west-2",
  "nodeGroups": [
    {
      "name": "system-nodes",
      "instanceType": "t3.medium",
      "minSize": 1,
      "maxSize": 3,
      "desiredSize": 2
    }
  ]
}
```

#### Get Cluster Status
```http
GET /api/v1/clusters/{clusterName}
```

#### Update Cluster
```http
PUT /api/v1/clusters/{clusterName}
Content-Type: application/json
```

#### Delete Cluster
```http
DELETE /api/v1/clusters/{clusterName}
```

### Upgrade Management

#### Check Available Upgrades
```http
GET /api/v1/clusters/{clusterName}/upgrades
```

#### Trigger Cluster Upgrade
```http
POST /api/v1/clusters/{clusterName}/upgrade
Content-Type: application/json

{
  "targetVersion": "1.29",
  "maintainWindow": "2024-01-15T02:00:00Z"
}
```

### Chaos Engineering

#### List Chaos Experiments
```http
GET /api/v1/chaos/experiments
```

#### Create Chaos Experiment
```http
POST /api/v1/chaos/experiments
Content-Type: application/json

{
  "name": "pod-failure-test",
  "type": "pod-chaos",
  "target": {
    "namespace": "default",
    "labelSelector": "app=test"
  },
  "duration": "5m"
}
```

## CLI Commands

### Cluster Operations
```bash
# Create cluster
eks-platform cluster create --name my-cluster --config cluster-config.yaml

# List clusters
eks-platform cluster list

# Get cluster info
eks-platform cluster describe my-cluster

# Delete cluster
eks-platform cluster delete my-cluster
```

### Upgrade Operations
```bash
# Check upgrade availability
eks-platform upgrade check my-cluster

# Perform upgrade
eks-platform upgrade start my-cluster --version 1.29

# Get upgrade status
eks-platform upgrade status my-cluster
```

### Chaos Engineering
```bash
# Run chaos experiment
eks-platform chaos run --experiment pod-failure.yaml

# List experiments
eks-platform chaos list

# Stop experiment
eks-platform chaos stop experiment-id
```

## Response Codes

| Code | Description |
|------|-------------|
| 200  | Success |
| 201  | Created |
| 400  | Bad Request |
| 401  | Unauthorized |
| 403  | Forbidden |
| 404  | Not Found |
| 500  | Internal Server Error |

## Authentication

All API endpoints require Bearer token authentication:

```http
Authorization: Bearer <your-api-token>
```

## Rate Limiting

API requests are limited to 100 requests per minute per API key.

## Error Handling

Errors are returned in JSON format:

```json
{
  "error": {
    "code": "INVALID_REQUEST",
    "message": "Cluster name is required",
    "details": {}
  }
}
```
