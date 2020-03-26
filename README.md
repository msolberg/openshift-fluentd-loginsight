# openshift-fluentd-loginsight
Example configuration for log forwarding to log insight for OpenShift 4.x


## Usage

1) First, install the ClusterLogging operator as per instructions at:
https://access.redhat.com/documentation/en-us/openshift_container_platform/4.2/html/logging/cluster-logging-deploying#cluster-logging-deploy-eo-cli_cluster-logging-deploying

2) Set the ClusterLogging instance to "Unmanaged"

```
$ oc edit ClusterLogging/instance
```

3) Create the fluent-plugin configmap from the directory in this git repository:

```
$ oc create configmap fluent-plugin --from-file=openshift/configmaps/fluent-plugin
```

5) Edit the daemonset configuration for fluentd to include the fluent-plugin configmap

```
$ oc edit daemonset/fluentd
```

Relevant sections are highlighted below:

```
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  labels:
    component: fluentd
    logging-infra: fluentd
    provider: openshift
  name: fluentd
  namespace: openshift-logging
spec:
  ...
    spec:
      containers:
      ...
      volumeMounts:
      ...
        - mountPath: /etc/fluent/plugin
          name: fluent-plugin
          readOnly: true
      ...
      volumes:
      ...
      - configMap:
          defaultMode: 420
          name: fluent-plugin
        name: fluent-plugin
      ...
```

4) Edit the fluentd configmap with an updated fluent.conf and secure-forward.conf. Substitute your hostname, port, and agent_id for the defaults below:

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

6) Restart pods and check /var/log/fluentd/fluentd.log to make sure that the fluentd daemon isn't erroring out.
