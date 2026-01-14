package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

func TestVpcModule(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../",
		Vars: map[string]interface{}{
			"project_name": "test-platform",
			"environment":  "test",
			"vpc_cidr":     "10.99.0.0/16",
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndPlan(t, terraformOptions)

	vpcCidr := terraform.Output(t, terraformOptions, "vpc_cidr")
	assert.Equal(t, "10.99.0.0/16", vpcCidr)

	privateSubnets := terraform.OutputList(t, terraformOptions, "private_subnet_ids")
	assert.Equal(t, 3, len(privateSubnets), "Expected 3 private subnets across AZs")

	publicSubnets := terraform.OutputList(t, terraformOptions, "public_subnet_ids")
	assert.Equal(t, 3, len(publicSubnets), "Expected 3 public subnets across AZs")

	natGatewayIP := terraform.Output(t, terraformOptions, "nat_gateway_public_ip")
	assert.NotEmpty(t, natGatewayIP, "NAT Gateway should have a public IP")
}

func TestVpcModuleFlowLogs(t *testing.T) {
	t.Parallel()

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../",
		Vars: map[string]interface{}{
			"project_name":     "test-platform",
			"environment":      "test",
			"vpc_cidr":         "10.98.0.0/16",
			"enable_flow_logs": true,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndPlan(t, terraformOptions)

	flowLogId := terraform.Output(t, terraformOptions, "vpc_flow_log_id")
	assert.NotEmpty(t, flowLogId, "VPC flow log should be enabled")
}
