HELMFILE_ENV=unified-demo-staging \
COMMON_TAG=v2.9.2-4a60f20 \
\
helmfile -f ./deploy-as-code/helm/digit-helmfile.yaml \
--set digit-ui.image.tag=$COMMON_TAG \
--set egov-hrms.image.tag=hrms-boundary-individual-61e6097 \
--set health-individual.image.tag=Individual-master-register-studio-d307985 \
--set health-service-request.image.tag=multiarch-changes-digit-studio-3fd88be \
template > build.yaml
