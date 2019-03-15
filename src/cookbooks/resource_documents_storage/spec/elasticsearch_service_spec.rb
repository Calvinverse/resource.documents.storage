# frozen_string_literal: true

require 'spec_helper'

describe 'resource_documents_storage::elasticsearch_service' do
  context 'configures Elasticsearch as service' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

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

      echo "$!" >"/var/run/elasticsearch/elasticsearch.pid"
    TXT
    it 'creates the /usr/share/elasticsearch/bin/elasticsearch' do
      expect(chef_run).to create_file('/usr/share/elasticsearch/bin/elasticsearch')
        .with_content(elasticsearch_start_script_content)
    end

    it 'disables the elasticsearch service' do
      expect(chef_run).to disable_service('elasticsearch')
    end
  end
end
