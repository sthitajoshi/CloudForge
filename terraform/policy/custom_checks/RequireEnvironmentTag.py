from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck


class RequireEnvironmentTag(BaseResourceCheck):
    """Untagged resources are the reason cost reports and incident triage
    stall: nobody can tell which environment an orphaned resource belongs
    to. A reviewer will miss a missing tag in a 300-line plan; this will
    not."""

    def __init__(self):
        super().__init__(
            name="Taggable resources must carry an Environment tag",
            id="CKV_CLOUDFORGE_1",
            categories=[CheckCategories.CONVENTION],
            supported_resources=[
                "aws_s3_bucket",
                "aws_vpc",
                "aws_subnet",
                "aws_security_group",
                "aws_iam_role",
                "aws_eks_cluster",
                "aws_eks_node_group",
            ],
        )

    def scan_resource_conf(self, conf):
        tags = conf.get("tags")
        if not tags or not isinstance(tags[0], dict):
            return CheckResult.FAILED
        return CheckResult.PASSED if "Environment" in tags[0] else CheckResult.FAILED


check = RequireEnvironmentTag()
