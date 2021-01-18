FROM wata727/tflint:0.22.0

ARG TERRAFORM_VERSION=0.14.3

RUN apk add --no-cache curl git \
  && curl -L https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip > terraform.zip \
  && unzip terraform.zip \
  && rm -fr terraform.zip \
  && mv terraform /usr/local/bin \
  && mkdir -p /root/.terraform.d/plugin-cache \
  && mkdir -p /root/.terraform.d/plugins

ENV TF_PLUGIN_CACHE_DIR "/root/.terraform.d/plugin-cache"
ENV TF_IN_AUTOMATION "true"

COPY tests/lint /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/lint"]

WORKDIR /data
COPY . /data
