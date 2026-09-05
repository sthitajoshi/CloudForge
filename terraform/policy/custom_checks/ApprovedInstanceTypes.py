from checkov.common.models.enums import CheckCategories, CheckResult
from checkov.terraform.checks.resource.base_resource_check import BaseResourceCheck

# Deliberately narrow. Widening this list is a conscious, reviewable change
# to the policy rather than something that slips through inside a plan.
APPROVED_INSTANCE_TYPES = {"t3.small", "t3.medium", "t3.large", "t3a.medium"}


class ApprovedInstanceTypes(BaseResourceCheck):
    """Blocks the oversized-instance mistake that shows up on the bill weeks
    later. Pairs with the Infracost comment: this stops the change, the
    comment explains what it would have cost."""

    def __init__(self):
        super().__init__(
            name="Node groups must use an approved instance type",
            id="CKV_CLOUDFORGE_2",
            categories=[CheckCategories.GENERAL_SECURITY],
            supported_resources=["aws_eks_node_group"],
        )

    def scan_resource_conf(self, conf):
        declared = conf.get("instance_types")
        if not declared:
            return CheckResult.PASSED

        values = declared[0] if isinstance(declared[0], list) else declared
        for instance_type in values:
            if isinstance(instance_type, str) and instance_type not in APPROVED_INSTANCE_TYPES:
                return CheckResult.FAILED
        return CheckResult.PASSED


check = ApprovedInstanceTypes()
