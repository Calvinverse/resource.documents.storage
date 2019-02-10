# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: elasticsearch
#
# Copyright 2017, P. van der Velde
#

#
# INSTALL THE CALCULATOR
#

apt_package 'bc' do
  action :install
end

#
# ELASTICSEARCH USER
#

es_user = node['elasticsearch']['service_user']
es_group = node['elasticsearch']['service_group']
elasticsearch_user 'elasticsearch' do
  action :create
  groupname es_group
  username es_user
end

#
# CREATE DATA PATH
#

service_path = node['elasticsearch']['path']['data_base']
directory service_path do
  action :create
  recursive true
end

elasticsearch_data_path = node['elasticsearch']['path']['data']
directory elasticsearch_data_path do
  action :create
  group node['elasticsearch']['service_group']
  mode '770'
  owner node['elasticsearch']['service_user']
  recursive true
end

#
# INSTALL ELASTICSEARCH
#

elasticsearch_install 'elasticsearch' do
  action :install
  type 'repository'
  version node['elasticsearch']['version']
end

#
# CONFIGURATION
#

elasticsearch_config_path = node['elasticsearch']['path']['config']
elasticsearch_data_path = node['elasticsearch']['path']['data']
elasticsearch_log_path = node['elasticsearch']['path']['logs']

elasticsearch_configure 'elasticsearch' do
  action :manage
  logging(action: 'INFO')
  path_bin node['elasticsearch']['path']['bin']
  path_conf elasticsearch_config_path
  path_data elasticsearch_data_path
  path_home node['elasticsearch']['path']['home']
  path_logs elasticsearch_log_path
  path_pid node['elasticsearch']['path']['pid']
  path_plugins node['elasticsearch']['path']['plugins']
end

# Disable DNS caching in the JVM. We have unbound for this. See:
# - https://docs.oracle.com/javase/8/docs/technotes/guides/net/properties.html
# - https://github.com/elastic/elasticsearch/issues/16412
elasticsearch_jvm_security_override = "#{elasticsearch_config_path}/java.security"
file elasticsearch_jvm_security_override do
  action :create
  content <<~PROPERTIES
    networkaddress.cache.ttl=0
    networkaddress.cache.negative.ttl=0
  PROPERTIES
  group node['elasticsearch']['service_group']
  mode '0550'
  owner node['elasticsearch']['service_user']
end

file "#{elasticsearch_config_path}/jvm.options" do
  action :create
  content <<~CONF
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
    -Djava.security.properties=#{elasticsearch_jvm_security_override}
  CONF
  group node['elasticsearch']['service_group']
  mode '0550'
  owner node['elasticsearch']['service_user']
end

# Update the elasticsearch start script to enable it to calculate its required
# memory
file '/usr/share/elasticsearch/bin/elasticsearch' do
  action :create
  content <<~TXT
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
  group node['elasticsearch']['service_group']
  mode '0550'
  owner node['elasticsearch']['service_user']
end

#
# SERVICE
#

service_name = 'elasticsearch'
elasticsearch_service service_name do
end

service service_name do
  action :enable
end

#
# ALLOW ELASTICSEARCH THROUGH THE FIREWALL
#

http_port = node['elasticsearch']['port']['http']
firewall_rule 'elasticsearch-http' do
  command :allow
  description 'Allow ElasticSearch HTTP traffic'
  dest_port http_port
  direction :in
end

discovery_port = node['elasticsearch']['port']['discovery']
firewall_rule 'elasticsearch-discovery' do
  command :allow
  description 'Allow ElasticSearch discovery traffic'
  dest_port discovery_port
  direction :in
end

#
# CONSUL FILES
#

consul_service_name = 'documents'
consul_service_tag = 'http'
file '/etc/consul/conf.d/elasticsearch-http.json' do
  action :create
  content <<~JSON
    {
      "services": [
        {
          "checks": [
            {
              "http": "http://localhost:#{http_port}/_cluster/health",
              "id": "elasticsearch_http_health_check",
              "interval": "30s",
              "method": "GET",
              "name": "ElasticSearch HTTP health check",
              "timeout": "5s"
            }
          ],
          "enable_tag_override": false,
          "id": "elasticsearch_http",
          "name": "#{consul_service_name}",
          "port": #{http_port},
          "tags": [
            "#{consul_service_tag}"
          ]
        }
      ]
    }
  JSON
end

#
# FLAG FILES
#

flag_config = '/var/log/elasticsearch_config.log'
file flag_config do
  action :create
  content <<~TXT
    NotInitialized
  TXT
end

flag_jvm_options = '/var/log/jvm_options.log'
file flag_jvm_options do
  action :create
  content <<~TXT
    NotInitialized
  TXT
end

#
# CONSUL-TEMPLATE FILES
#

consul_template_config_path = node['consul_template']['config_path']
consul_template_template_path = node['consul_template']['template_path']

#
# ELASTICSEARCH CONFIG
#

elasticsearch_config_script_template_file = 'elasticsearch_config.ctmpl'
file "#{consul_template_template_path}/#{elasticsearch_config_script_template_file}" do
  action :create
  content <<~CONF
    #!/bin/sh

    {{ if keyExists "config/services/consul/datacenter" }}
    {{ if keyExists "config/services/documents/masters" }}
    FLAG=$(cat #{flag_config})
    if [ "$FLAG" = "NotInitialized" ]; then
        echo "Write the elasticsearch configuration script ..."

        cat <<'EOT' > #{elasticsearch_config_path}/elasticsearch.yml
    cluster.name: "{{ key "config/services/consul/datacenter" }}"
    node.name: ${HOSTNAME}
    path.data: "#{elasticsearch_data_path}"
    path.logs: "#{elasticsearch_log_path}"

    network.bind_host: [ "_eth0:ipv4_", "_local:ipv4_" ]
    network.publish_host: [ "_eth0:ipv4_" ]

    http.port: #{http_port}
    transport.tcp.port: #{discovery_port}

    discovery.zen.host_provider: file
    discovery.zen.minimum_master_nodes: {{ key "config/services/documents/masters" }}
    EOT

        chown #{node['elasticsearch']['service_user']}:#{node['elasticsearch']['service_group']} #{elasticsearch_config_path}/elasticsearch.yml
        chmod 550 #{elasticsearch_config_path}/elasticsearch.yml

        if ( ! $(systemctl is-enabled --quiet #{service_name}) ); then
          systemctl enable #{service_name}

          while true; do
            if ( (systemctl is-enabled --quiet #{service_name}) ); then
                break
            fi

            sleep 1
          done
        fi

        if ( ! (systemctl is-active --quiet #{service_name}) ); then
          systemctl start #{service_name}

          while true; do
            if ( (systemctl is-active --quiet #{service_name}) ); then
                break
            fi

            sleep 1
          done
        else
          systemctl restart #{service_name}
        fi

        echo "Initialized" > #{flag_config}
    fi
    {{ else }}
    echo "Not all Consul K-V values are available. Will not start Elasticsearch."
    {{ end }}
    {{ else }}
    echo "Not all Consul K-V values are available. Will not start Elasticsearch."
    {{ end }}
  CONF
  group 'root'
  mode '0550'
  owner 'root'
end

elasticsearch_config_script_file = '/tmp/elasticsearch_config.sh'
file "#{consul_template_config_path}/elasticsearch_config.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{elasticsearch_config_script_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{elasticsearch_config_script_file}"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "sh #{elasticsearch_config_script_file}"

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
  HCL
  group 'root'
  mode '0550'
  owner 'root'
end

elasticsearch_hosts_template_file = 'elasticsearch_hosts.ctmpl'
file "#{consul_template_template_path}/#{elasticsearch_hosts_template_file}" do
  action :create
  content <<~CONF
    {{ $services := service "#{consul_service_tag}.#{consul_service_name}" }}
    {{ range $services }}
      - {{ .Name }}:#{discovery_port}
    {{ end }}
  CONF
  group 'root'
  mode '0550'
  owner 'root'
end

elasticsearch_hosts_file = "#{node['elasticsearch']['path']['config']}/unicast_hosts.txt"
file "#{consul_template_config_path}/elasticsearch_hosts.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{elasticsearch_hosts_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{elasticsearch_hosts_file}"

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
  HCL
  group 'root'
  mode '0550'
  owner 'root'
end

#
# TELEGRAF
#

telegraf_service = 'telegraf'
telegraf_config_directory = node['telegraf']['config_directory']
telegraf_elasticsearch_inputs_template_file = node['elasticsearch']['telegraf']['consul_template_inputs_file']
file "#{consul_template_template_path}/#{telegraf_elasticsearch_inputs_template_file}" do
  action :create
  content <<~CONF
    # Telegraf Configuration

    ###############################################################################
    #                            INPUT PLUGINS                                    #
    ###############################################################################

    [[inputs.elasticsearch]]
    ## specify a list of one or more Elasticsearch servers
    servers = ["http://localhost:#{http_port}"]

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
  group 'root'
  mode '0550'
  owner 'root'
end

file "#{consul_template_config_path}/telegraf_elasticsearch_inputs.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{telegraf_elasticsearch_inputs_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{telegraf_config_directory}/inputs_elasticsearch.conf"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "/bin/bash -c 'chown #{node['telegraf']['service_user']}:#{node['telegraf']['service_group']} #{telegraf_config_directory}/inputs_elasticsearch.conf && systemctl restart #{telegraf_service}'"

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
  HCL
  group 'root'
  mode '0550'
  owner 'root'
end
