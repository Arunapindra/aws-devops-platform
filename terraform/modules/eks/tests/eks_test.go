package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestEksModule(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../",
		Vars: map[string]interface{}{
			"project_name":      "test-platform",
			"environment":       "test",
			"cluster_version":   "1.29",
			"vpc_id":            "vpc-test123",
			"subnet_ids":        []string{"subnet-a", "subnet-b", "subnet-c"},
			"node_instance_types": []string{"t3.medium"},
			"node_min_size":     1,
			"node_max_size":     3,
			"node_desired_size": 2,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndPlan(t, terraformOptions)

	clusterName := terraform.Output(t, terraformOptions, "cluster_name")
	assert.Contains(t, clusterName, "test-platform")

	oidcIssuer := terraform.Output(t, terraformOptions, "oidc_issuer_url")
	assert.Contains(t, oidcIssuer, "https://oidc.eks")

	clusterEndpoint := terraform.Output(t, terraformOptions, "cluster_endpoint")
	assert.Contains(t, clusterEndpoint, "https://")
}

func TestEksModuleIRSA(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../",
		Vars: map[string]interface{}{
			"project_name":    "test-platform",
			"environment":     "test",
			"cluster_version": "1.29",
			"vpc_id":          "vpc-test456",
			"subnet_ids":      []string{"subnet-d", "subnet-e", "subnet-f"},
			"enable_irsa":     true,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndPlan(t, terraformOptions)

	oidcProviderArn := terraform.Output(t, terraformOptions, "oidc_provider_arn")
	assert.Contains(t, oidcProviderArn, "arn:aws:iam::")
}
