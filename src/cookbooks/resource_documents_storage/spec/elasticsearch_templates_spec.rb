# frozen_string_literal: true

require 'spec_helper'

describe 'resource_documents_storage::elasticsearch_templates' do
  context 'adds the flag files' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    flag_config_content = <<~TXT
      NotInitialized
    TXT
    it 'creates the /etc/elasticsearch/java.security' do
      expect(chef_run).to create_file('/var/log/elasticsearch_config.log')
        .with_content(flag_config_content)
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

      discovery.zen.ping.unicast.hosts: '127.0.0.1'
      discovery.zen.hosts_provider: file
      discovery.zen.minimum_master_nodes: {{ key "config/services/documents/masters" }}

      xpack.monitoring.enabled: true
      xpack.monitoring.elasticsearch.collection.enabled: true
      xpack.monitoring.collection.enabled: true
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
