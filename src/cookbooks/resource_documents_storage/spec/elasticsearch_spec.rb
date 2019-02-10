# frozen_string_literal: true

require 'spec_helper'

describe 'resource_documents_storage::elasticsearch' do
  context 'installs Elastic Search' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates and mounts the data file system at /srv/elasticsearch' do
      expect(chef_run).to create_directory('/srv/elasticsearch')
    end

    it 'creates and mounts the meta file system at /srv/elasticsearch/data' do
      expect(chef_run).to create_directory('/srv/elasticsearch/data').with(
        group: 'elasticsearch',
        mode: '770',
        owner: 'elasticsearch'
      )
    end

    it 'creates the elasticsearch user' do
      expect(chef_run).to create_elasticsearch_user('elasticsearch')
    end

    it 'installs elasticsearch' do
      expect(chef_run).to install_elasticsearch('elasticsearch')
    end

    it 'configures elasticsearch' do
      expect(chef_run).to manage_elasticsearch_configure('elasticsearch')
    end

    it 'installs the elasticsearch service' do
      expect(chef_run).to configure_elasticsearch_service('elasticsearch')
    end

    elasticsearch_security_override_content = <<~PROPERTIES
      networkaddress.cache.ttl=0
      networkaddress.cache.negative.ttl=0
    PROPERTIES
    it 'creates the /etc/elasticsearch/java.security' do
      expect(chef_run).to create_file('/etc/elasticsearch/java.security')
        .with_content(elasticsearch_security_override_content)
    end

    elasticsearch_jvm_options_content = <<~PROPERTIES
      -XX:+UseConcMarkSweepGC
      -XX:CMSInitiatingOccupancyFraction=75
      -XX:+UseCMSInitiatingOccupancyOnly
      -XX:+AlwaysPreTouch
      -server
      -Xss1m
      -Djava.awt.headless=true
      -Dfile.encoding=UTF-8
      -Djna.nosys=true
      -XX:-OmitStackTraceInFastThrow
      -Dio.netty.noUnsafe=true
      -Dio.netty.noKeySetOptimization=true
      -Dio.netty.recycler.maxCapacityPerThread=0
      -Dlog4j.shutdownHookEnabled=false
      -Dlog4j2.disable.jmx=true
      -XX:+HeapDumpOnOutOfMemoryError
      -Djava.security.properties=/etc/elasticsearch/java.security
    PROPERTIES
    it 'creates the /etc/elasticsearch/jvm.options' do
      expect(chef_run).to create_file('/etc/elasticsearch/jvm.options')
        .with_content(elasticsearch_jvm_options_content)
    end

    elasticsearch_start_script_content = <<~TXT
      #!/bin/bash

      # CONTROLLING STARTUP:
      #
      # This script relies on a few environment variables to determine startup
      # behavior, those variables are:
      #
      #   ES_PATH_CONF -- Path to config directory
      #   ES_JAVA_OPTS -- External Java Opts on top of the defaults set
      #
      # Optionally, exact memory values can be set using the `ES_JAVA_OPTS`. Note that
      # the Xms and Xmx lines in the JVM options file must be commented out. Example
      # values are "512m", and "10g".
      #
      #   ES_JAVA_OPTS="-Xms8g -Xmx8g" ./bin/elasticsearch

      max_memory() {
        max_mem=$(free -m | grep -oP '\\d+' | head -n 1)
        echo "${max_mem}"
      }

      # Check for the 'real memory size' and calculate mx from a ratio
      # given (default is 70%)
      max_mem="$(max_memory)"
      java_max_memory=""
      if [ "x${max_mem}" != "x0" ]; then
        ratio=70

        mx=$(echo "(${max_mem} * ${ratio} / 100 + 0.5)" | bc | awk '{printf("%d\\n",$1 + 0.5)}')
        java_max_memory="-Xmx${mx}m -Xms${mx}m"

        echo "Maximum memory for VM set to ${max_mem}. Setting max memory for java to ${mx} Mb"
      fi

      source "`dirname "$0"`"/elasticsearch-env

      ES_JVM_OPTIONS="$ES_PATH_CONF"/jvm.options
      JVM_OPTIONS=`"$JAVA" -cp "$ES_CLASSPATH" org.elasticsearch.tools.launchers.JvmOptionsParser "$ES_JVM_OPTIONS"`
      ES_JAVA_OPTS="${JVM_OPTIONS//\\$\\{ES_TMPDIR\\}/$ES_TMPDIR} $ES_JAVA_OPTS"

      cd "$ES_HOME"
      nohup \\
        "$JAVA" \\
        $ES_JAVA_OPTS \\
        $java_max_memory \\
        -Des.path.home="$ES_HOME" \\
        -Des.path.conf="$ES_PATH_CONF" \\
        -Des.distribution.flavor="$ES_DISTRIBUTION_FLAVOR" \\
        -Des.distribution.type="$ES_DISTRIBUTION_TYPE" \\
        -cp "$ES_CLASSPATH" \\
        org.elasticsearch.bootstrap.Elasticsearch \\
        "$@" \\
        <&- &

      retval=$?
      pid=$!

      [ $retval -eq 0 ] || exit $retval
      if [ ! -z "$ES_STARTUP_SLEEP_TIME" ]; then
        sleep $ES_STARTUP_SLEEP_TIME
      fi
      if ! ps -p $pid > /dev/null ; then
        exit 1
      fi
      exit 0

      exit $?
    TXT
    it 'creates the /usr/share/elasticsearch/bin/elasticsearch' do
      expect(chef_run).to create_file('/usr/share/elasticsearch/bin/elasticsearch')
        .with_content(elasticsearch_start_script_content)
    end
  end

  context 'configures the firewall for ElasticSearch' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'opens the ElasticSearch HTTP port' do
      expect(chef_run).to create_firewall_rule('elasticsearch-http').with(
        command: :allow,
        dest_port: 9200,
        direction: :in
      )
    end
  end

  context 'registers the service with consul' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    consul_elasticsearch_http_config_content = <<~JSON
      {
        "services": [
          {
            "checks": [
              {
                "http": "http://localhost:9200/_cluster/health",
                "id": "elasticsearch_http_health_check",
                "interval": "30s",
                "method": "GET",
                "name": "ElasticSearch HTTP health check",
                "timeout": "5s"
              }
            ],
            "enable_tag_override": false,
            "id": "elasticsearch_http",
            "name": "documents",
            "port": 9200,
            "tags": [
              "http"
            ]
          }
        ]
      }
    JSON
    it 'creates the /etc/consul/conf.d/elasticsearch-http.json' do
      expect(chef_run).to create_file('/etc/consul/conf.d/elasticsearch-http.json')
        .with_content(consul_elasticsearch_http_config_content)
    end
  end

  context 'adds the flag files' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    flag_config_content = <<~TXT
      NotInitialized
    TXT
    it 'creates the /etc/elasticsearch/java.security' do
      expect(chef_run).to create_file('/var/log/elasticsearch_config.log')
        .with_content(flag_config_content)
    end

    flag_jvm_options_content = <<~TXT
      NotInitialized
    TXT
    it 'creates the /etc/elasticsearch/java.security' do
      expect(chef_run).to create_file('/var/log/jvm_options.log')
        .with_content(flag_jvm_options_content)
    end
  end

  context 'adds the consul-template files for the elasticsearch configuration' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    elasticsearch_config_script_template_content = <<~CONF
      #!/bin/sh

      {{ if keyExists "config/services/consul/datacenter" }}
      {{ if keyExists "config/services/documents/masters" }}
      FLAG=$(cat /var/log/elasticsearch_config.log)
      if [ "$FLAG" = "NotInitialized" ]; then
          echo "Write the elasticsearch configuration script ..."

          cat <<'EOT' > /etc/elasticsearch/elasticsearch.yml
      cluster.name: "{{ key "config/services/consul/datacenter" }}"
      node.name: ${HOSTNAME}
      path.data: "/srv/elasticsearch/data"
      path.logs: "/var/log/elasticsearch"

      network.bind_host: [ "_eth0:ipv4_", "_local:ipv4_" ]
      network.publish_host: [ "_eth0:ipv4_" ]

      http.port: 9200
      transport.tcp.port: 9300

      discovery.zen.host_provider: file
      discovery.zen.minimum_master_nodes: {{ key "config/services/documents/masters" }}
      EOT

          chown elasticsearch:elasticsearch /etc/elasticsearch/elasticsearch.yml
          chmod 550 /etc/elasticsearch/elasticsearch.yml

          if ( ! $(systemctl is-enabled --quiet elasticsearch) ); then
            systemctl enable elasticsearch

            while true; do
              if ( (systemctl is-enabled --quiet elasticsearch) ); then
                  break
              fi

              sleep 1
            done
          fi

          if ( ! (systemctl is-active --quiet elasticsearch) ); then
            systemctl start elasticsearch

            while true; do
              if ( (systemctl is-active --quiet elasticsearch) ); then
                  break
              fi

              sleep 1
            done
          else
            systemctl restart elasticsearch
          fi

          echo "Initialized" > /var/log/elasticsearch_config.log
      fi
      {{ else }}
      echo "Not all Consul K-V values are available. Will not start Elasticsearch."
      {{ end }}
      {{ else }}
      echo "Not all Consul K-V values are available. Will not start Elasticsearch."
      {{ end }}
    CONF
    it 'creates ElasticSearch configuration template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/elasticsearch_config.ctmpl')
        .with_content(elasticsearch_config_script_template_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end

    consul_template_elasticsearch_config_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/elasticsearch_config.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/tmp/elasticsearch_config.sh"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "sh /tmp/elasticsearch_config.sh"

        # This is the maximum amount of time to wait for the optional command to
        # return. Default is 30s.
        command_timeout = "45s"

        # Exit with an error when accessing a struct or map field/key that does not
        # exist. The default behavior will print "<no value>" when accessing a field
        # that does not exist. It is highly recommended you set this to "true" when
        # retrieving secrets from Vault.
        error_on_missing_key = false

        # This is the permission to render the file. If this option is left
        # unspecified, Consul Template will attempt to match the permissions of the
        # file that already exists at the destination path. If no file exists at that
        # path, the permissions are 0644.
        perms = 0550

        # This option backs up the previously rendered template at the destination
        # path before writing a new one. It keeps exactly one backup. This option is
        # useful for preventing accidental changes to the data without having a
        # rollback strategy.
        backup = true

        # These are the delimiters to use in the template. The default is "{{" and
        # "}}", but for some templates, it may be easier to use a different delimiter
        # that does not conflict with the output file itself.
        left_delimiter  = "{{"
        right_delimiter = "}}"

        # This is the `minimum(:maximum)` to wait before rendering a new template to
        # disk and triggering a command, separated by a colon (`:`). If the optional
        # maximum value is omitted, it is assumed to be 4x the required minimum value.
        # This is a numeric time with a unit suffix ("5s"). There is no default value.
        # The wait value for a template takes precedence over any globally-configured
        # wait.
        wait {
          min = "2s"
          max = "10s"
        }
      }
    CONF
    it 'creates elasticsearch_config.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/elasticsearch_config.hcl')
        .with_content(consul_template_elasticsearch_config_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end

    elasticsearch_hosts_template_content = <<~CONF
      {{ $services := service "http.documents" }}
      {{ range $services }}
        - {{ .Name }}:9300
      {{ end }}
    CONF
    it 'creates ElasticSearch hosts template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/elasticsearch_hosts.ctmpl')
        .with_content(elasticsearch_hosts_template_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end

    consul_template_elasticsearch_hosts_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/elasticsearch_hosts.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/elasticsearch/unicast_hosts.txt"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = ""

        # This is the maximum amount of time to wait for the optional command to
        # return. Default is 30s.
        command_timeout = "45s"

        # Exit with an error when accessing a struct or map field/key that does not
        # exist. The default behavior will print "<no value>" when accessing a field
        # that does not exist. It is highly recommended you set this to "true" when
        # retrieving secrets from Vault.
        error_on_missing_key = false

        # This is the permission to render the file. If this option is left
        # unspecified, Consul Template will attempt to match the permissions of the
        # file that already exists at the destination path. If no file exists at that
        # path, the permissions are 0644.
        perms = 0550

        # This option backs up the previously rendered template at the destination
        # path before writing a new one. It keeps exactly one backup. This option is
        # useful for preventing accidental changes to the data without having a
        # rollback strategy.
        backup = true

        # These are the delimiters to use in the template. The default is "{{" and
        # "}}", but for some templates, it may be easier to use a different delimiter
        # that does not conflict with the output file itself.
        left_delimiter  = "{{"
        right_delimiter = "}}"

        # This is the `minimum(:maximum)` to wait before rendering a new template to
        # disk and triggering a command, separated by a colon (`:`). If the optional
        # maximum value is omitted, it is assumed to be 4x the required minimum value.
        # This is a numeric time with a unit suffix ("5s"). There is no default value.
        # The wait value for a template takes precedence over any globally-configured
        # wait.
        wait {
          min = "2s"
          max = "10s"
        }
      }
    CONF
    it 'creates elasticsearch_hosts.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/elasticsearch_hosts.hcl')
        .with_content(consul_template_elasticsearch_hosts_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end
  end

  context 'adds the consul-template files for telegraf monitoring of elasticsearch' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    telegraf_elasticsearch_inputs_template_content = <<~CONF
      # Telegraf Configuration

      ###############################################################################
      #                            INPUT PLUGINS                                    #
      ###############################################################################

      [[inputs.elasticsearch]]
      ## specify a list of one or more Elasticsearch servers
      servers = ["http://localhost:9200"]

      ## Timeout for HTTP requests to the elastic search server(s)
      http_timeout = "5s"

      ## When local is true (the default), the node will read only its own stats.
      ## Set local to false when you want to read the node stats from all nodes
      ## of the cluster.
      local = true

      ## Set cluster_health to true when you want to also obtain cluster health stats
      cluster_health = false

      ## Adjust cluster_health_level when you want to also obtain detailed health stats
      ## The options are
      ##  - indices (default)
      ##  - cluster
      # cluster_health_level = "indices"

      ## Set cluster_stats to true when you want to also obtain cluster stats from the
      ## Master node.
      cluster_stats = false

      ## node_stats is a list of sub-stats that you want to have gathered. Valid options
      ## are "indices", "os", "process", "jvm", "thread_pool", "fs", "transport", "http",
      ## "breaker". Per default, all stats are gathered.
      # node_stats = ["jvm", "http"]

      ## Optional SSL Config
      # ssl_ca = "/etc/telegraf/ca.pem"
      # ssl_cert = "/etc/telegraf/cert.pem"
      # ssl_key = "/etc/telegraf/key.pem"
      ## Use SSL but skip chain & host verification
      # insecure_skip_verify = false
      [inputs.elasticsearch.tags]
        influxdb_database = "{{ keyOrDefault "config/services/metrics/databases/services" "services" }}"
    CONF
    it 'creates telegraf ElasticSearch input template file in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/templates/telegraf_elasticsearch_inputs.ctmpl')
        .with_content(telegraf_elasticsearch_inputs_template_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end

    consul_template_telegraf_elasticsearch_inputs_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "/etc/consul-template.d/templates/telegraf_elasticsearch_inputs.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "/etc/telegraf/telegraf.d/inputs_elasticsearch.conf"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "/bin/bash -c 'chown telegraf:telegraf /etc/telegraf/telegraf.d/inputs_elasticsearch.conf && systemctl restart telegraf'"

        # This is the maximum amount of time to wait for the optional command to
        # return. Default is 30s.
        command_timeout = "15s"

        # Exit with an error when accessing a struct or map field/key that does not
        # exist. The default behavior will print "<no value>" when accessing a field
        # that does not exist. It is highly recommended you set this to "true" when
        # retrieving secrets from Vault.
        error_on_missing_key = false

        # This is the permission to render the file. If this option is left
        # unspecified, Consul Template will attempt to match the permissions of the
        # file that already exists at the destination path. If no file exists at that
        # path, the permissions are 0644.
        perms = 0550

        # This option backs up the previously rendered template at the destination
        # path before writing a new one. It keeps exactly one backup. This option is
        # useful for preventing accidental changes to the data without having a
        # rollback strategy.
        backup = true

        # These are the delimiters to use in the template. The default is "{{" and
        # "}}", but for some templates, it may be easier to use a different delimiter
        # that does not conflict with the output file itself.
        left_delimiter  = "{{"
        right_delimiter = "}}"

        # This is the `minimum(:maximum)` to wait before rendering a new template to
        # disk and triggering a command, separated by a colon (`:`). If the optional
        # maximum value is omitted, it is assumed to be 4x the required minimum value.
        # This is a numeric time with a unit suffix ("5s"). There is no default value.
        # The wait value for a template takes precedence over any globally-configured
        # wait.
        wait {
          min = "2s"
          max = "10s"
        }
      }
    CONF
    it 'creates telegraf_elasticsearch_inputs.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('/etc/consul-template.d/conf/telegraf_elasticsearch_inputs.hcl')
        .with_content(consul_template_telegraf_elasticsearch_inputs_content)
        .with(
          group: 'root',
          owner: 'root',
          mode: '0550'
        )
    end
  end
end
