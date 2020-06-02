# openshift-fluentd-loginsight
Example configuration for log forwarding to log insight for OpenShift 4.x

## Usage

1) First, create a namespace and a service account for fluentd.

```
oc create namespace openshift-logging
oc create sa logcollector
```
Allow the service account to use the privileged SCC so that fluentd can mount the log directory from the host.
```
oc create role log-collector-privileged \
  --verb use \
  --resource securitycontextconstraints \
  --resource-name privileged \
  -n openshift-logging                
oc create rolebinding log-collector-privileged-binding \
  --role=log-collector-privileged \
  --serviceaccount=openshift-logging:logcollector
```
Allow the service account to query metadata from kubernetes. This is used to tag the log entries with pod and namespace information.
```
oc create clusterrole metadata-reader \
  --verb=get,list,watch \
  --resource=pods,namespaces
oc create clusterrolebinding cluster-logging-metadata-reader \
  --clusterrole=metadata-reader \
  --serviceaccount=openshift-logging:logcollector
```

2) Create the fluent-plugin configmap from the example directory [here](openshift/configmaps/fluent-plugin):

```
$ oc create configmap fluent-plugin --from-file=openshift/configmaps/fluent-plugin -n openshift-logging
```

You can get the latest fluentd plugin for log insight from https://github.com/vmware/fluent-plugin-vmware-loginsight

3) Create a fluentd configmap with an updated fluent.conf and secure-forward.conf. Substitute your hostname, port, and agent_id for the defaults below:

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluentd
  namespace: openshift-logging
data:
  fluent.conf: |2

    @include configs.d/openshift/system.conf


    @include configs.d/openshift/input-pre-*.conf
    @include configs.d/dynamic/input-docker-*.conf
    @include configs.d/dynamic/input-syslog-*.conf
    @include configs.d/openshift/input-post-*.conf

    <label @INGRESS>
      @include configs.d/openshift/filter-pre-*.conf
      @include configs.d/openshift/filter-retag-journal.conf
      @include configs.d/openshift/filter-k8s-meta.conf
      @include configs.d/openshift/filter-kibana-transform.conf
      @include configs.d/openshift/filter-k8s-flatten-hash.conf
      @include configs.d/openshift/filter-k8s-record-transform.conf
      @include configs.d/openshift/filter-syslog-record-transform.conf
      @include configs.d/openshift/filter-viaq-data-model.conf
      @include configs.d/openshift/filter-post-*.conf
    </label>

    <label @OUTPUT>
      # REMOVED ALL ELASTIC OUTPUT CONFIGURATION
      @include configs.d/user/secure-forward.conf
    </label>
  secure-forward.conf: |
    <match **>
    @type vmware_loginsight
    scheme https
    ssl_verify true
    host loginsight.example.com
    port 443
    path api/v1/events/ingest
    agent_id XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
    http_method post
    serializer json
    rate_limit_msec 0
    raise_on_error false
    log_text_keys ["log","msg","message"]
    include_tag_key true
    tag_key tag
    </match>
  throttle-config.yaml: ""
```


4) Create a daemonset for fluentd based on the one provided at [openshift/daemonset-fluentd.yaml](openshift/daemonset-fluentd.yaml)

```
$ oc create -f openshfit/daemonset-fluentd.yaml
```

5) Restart pods and check /var/log/fluentd/fluentd.log to make sure that the fluentd daemon isn't erroring out.
