# frozen_string_literal: true

#
# Cookbook Name:: resource_documents_storage
# Recipe:: elasticsearch_service
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
# SERVICE
#

# Update the elasticsearch start script to enable it to calculate its required
# memory
elasticsearch_pid_file = "#{node['elasticsearch']['path']['pid']}/elasticsearch.pid"
elasticsearch_start_script = '/usr/share/elasticsearch/bin/elasticsearch'
file elasticsearch_start_script do
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

    echo "$!" >"#{elasticsearch_pid_file}"
  TXT
  group node['elasticsearch']['service_group']
  mode '0550'
  owner node['elasticsearch']['service_user']
end

elasticsearch_user = node['elasticsearch']['service_user']
elasticsearch_group = node['elasticsearch']['service_group']
service_name = node['elasticsearch']['service_name']
systemd_service service_name do
  action :create
  install do
    wanted_by %w[multi-user.target]
  end
  service do
    # Load env vars from /etc/default/ and /etc/sysconfig/ if they exist.
    # Prefixing the path with '-' makes it try to load, but if the file doesn't
    # exist, it continues onward.
    environment_file '-/etc/default/elasticsearch'
    environment %W[
      ES_HOME=#{node['elasticsearch']['path']['home']}
      ES_PATH_CONF=#{node['elasticsearch']['path']['config']}
      PID_DIR=#{node['elasticsearch']['path']['pid']}
    ]
    exec_start "#{elasticsearch_start_script} -p #{elasticsearch_pid_file} --quiet"
    group elasticsearch_group
    kill_mode 'process'
    kill_signal 'SIGTERM'
    limit_as 'infinity'
    limit_fsize 'infinity'
    limit_nofile 65_536
    limit_nproc 4_096
    pid_file elasticsearch_pid_file
    restart 'always'
    restart_sec 5
    send_sigkill false
    success_exit_status 143
    timeout_stop_sec '0'
    type 'forking'
    user elasticsearch_user
  end
  unit do
    after %w[network-online.target]
    description 'Elasticsearch'
    documentation 'https://elastic.co'
    requires %w[network-online.target]
    start_limit_interval_sec 0
  end
end

service service_name do
  action :enable
end
