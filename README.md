# openshift-fluentd-loginsight
Example configuration for log forwarding to log insight for OpenShift 4.x


## Usage

1) First, install the ClusterLogging operator as per instructions at:
https://access.redhat.com/documentation/en-us/openshift_container_platform/4.2/html/logging/cluster-logging-deploying#cluster-logging-deploy-eo-cli_cluster-logging-deploying

2) Set the ClusterLogging instance to "Unmanaged"

```
$ oc edit ClusterLogging/instance
```

3) Create the fluent-plugin configmap:

```
$ oc create configmap fluent-plugin --from-file=openshift/configmaps/fluent-plugin
```

5) Edit the daemonset configuration for fluentd to include the fluent-plugin configmap

```
$ oc edit daemonset/fluentd
```

Should look like this:

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
  revisionHistoryLimit: 10
  selector:
    matchLabels:
      component: fluentd
      logging-infra: fluentd
      provider: openshift
  template:
    metadata:
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ""
      creationTimestamp: null
      labels:
        component: fluentd
        logging-infra: fluentd
        provider: openshift
      name: fluentd
    spec:
      containers:
      - env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        - name: MERGE_JSON_LOG
          value: "false"
        - name: PRESERVE_JSON_LOG
          value: "true"
        - name: K8S_HOST_URL
          value: https://kubernetes.default.svc
        - name: ES_HOST
          value: elasticsearch
        - name: ES_PORT
          value: "9200"
        - name: ES_CLIENT_CERT
          value: /etc/fluent/keys/app-cert
        - name: ES_CLIENT_KEY
          value: /etc/fluent/keys/app-key
        - name: ES_CA
          value: /etc/fluent/keys/app-ca
        - name: METRICS_CERT
          value: /etc/fluent/metrics/tls.crt
        - name: METRICS_KEY
          value: /etc/fluent/metrics/tls.key
        - name: OPS_HOST
          value: elasticsearch
        - name: OPS_PORT
          value: "9200"
        - name: OPS_CLIENT_CERT
          value: /etc/fluent/keys/infra-cert
        - name: OPS_CLIENT_KEY
          value: /etc/fluent/keys/infra-key
        - name: OPS_CA
          value: /etc/fluent/keys/infra-ca
        - name: BUFFER_QUEUE_LIMIT
          value: "32"
        - name: BUFFER_SIZE_LIMIT
          value: 8m
        - name: FILE_BUFFER_LIMIT
          value: 256Mi
        - name: FLUENTD_CPU_LIMIT
          valueFrom:
            resourceFieldRef:
              containerName: fluentd
              divisor: "0"
              resource: limits.cpu
        - name: FLUENTD_MEMORY_LIMIT
          valueFrom:
            resourceFieldRef:
              containerName: fluentd
              divisor: "0"
              resource: limits.memory
        - name: NODE_IPV4
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: status.hostIP
        - name: CDM_KEEP_EMPTY_FIELDS
          value: message
        image: registry.redhat.io/openshift4/ose-logging-fluentd
        imagePullPolicy: IfNotPresent
        name: fluentd
        ports:
        - containerPort: 24231
          name: metrics
          protocol: TCP
        resources:
          limits:
            memory: 1Gi
          requests:
            cpu: 200m
            memory: 1Gi
        securityContext:
          privileged: true
        terminationMessagePath: /dev/termination-log
        terminationMessagePolicy: File
        volumeMounts:
        - mountPath: /run/log/journal
          name: runlogjournal
        - mountPath: /var/log
          name: varlog
        - mountPath: /var/lib/docker
          name: varlibdockercontainers
          readOnly: true
        - mountPath: /etc/fluent/configs.d/user
          name: config
          readOnly: true
        - mountPath: /etc/fluent/keys
          name: certs
          readOnly: true
        - mountPath: /etc/fluent/plugin
          name: fluent-plugin
          readOnly: true
        - mountPath: /etc/localtime
          name: localtime
          readOnly: true
        - mountPath: /etc/sysconfig/docker
          name: dockercfg
          readOnly: true
        - mountPath: /etc/docker
          name: dockerdaemoncfg
          readOnly: true
        - mountPath: /var/lib/fluentd
          name: filebufferstorage
        - mountPath: /etc/fluent/metrics
          name: collector-metrics
      dnsPolicy: ClusterFirst
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: cluster-logging
      restartPolicy: Always
      schedulerName: default-scheduler
      securityContext: {}
      serviceAccount: logcollector
      serviceAccountName: logcollector
      terminationGracePeriodSeconds: 10
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/master
        operator: Exists
      - effect: NoSchedule
        key: node.kubernetes.io/disk-pressure
        operator: Exists
      volumes:
      - hostPath:
          path: /run/log/journal
          type: ""
        name: runlogjournal
      - hostPath:
          path: /var/log
          type: ""
        name: varlog
      - hostPath:
          path: /var/lib/docker
          type: ""
        name: varlibdockercontainers
      - configMap:
          defaultMode: 420
          name: fluentd
        name: config
      - configMap:
          defaultMode: 420
          name: fluent-plugin
        name: fluent-plugin
      - name: certs
        secret:
          defaultMode: 420
          secretName: fluentd
      - hostPath:
          path: /etc/localtime
          type: ""
        name: localtime
      - hostPath:
          path: /etc/sysconfig/docker
          type: ""
        name: dockercfg
      - hostPath:
          path: /etc/docker
          type: ""
        name: dockerdaemoncfg
      - hostPath:
          path: /var/lib/fluentd
          type: ""
        name: filebufferstorage
      - name: collector-metrics
        secret:
          defaultMode: 420
          secretName: fluentd-metrics
  updateStrategy:
    rollingUpdate:
      maxUnavailable: 1
    type: RollingUpdate
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
