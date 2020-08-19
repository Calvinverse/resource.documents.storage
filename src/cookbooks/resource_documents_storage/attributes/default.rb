# frozen_string_literal: true

#
# CONSULTEMPLATE
#

default['consul_template']['config_path'] = '/etc/consul-template.d/conf'
default['consul_template']['template_path'] = '/etc/consul-template.d/templates'

#
# ELASTICSEARCH
#

default['elasticsearch']['version'] = '6.6.1'
default['elasticsearch']['service_name'] = 'elasticsearch'
default['elasticsearch']['service_user'] = 'elasticsearch'
default['elasticsearch']['service_group'] = 'elasticsearch'

default['elasticsearch']['path']['data_base'] = '/srv/elasticsearch'
default['elasticsearch']['path']['data'] = '/srv/elasticsearch/data'

default['elasticsearch']['path']['home'] = '/usr/share/elasticsearch'
default['elasticsearch']['path']['config'] = '/etc/elasticsearch'
default['elasticsearch']['path']['logs'] = '/var/log/elasticsearch'
default['elasticsearch']['path']['pid'] = '/var/run/elasticsearch'
default['elasticsearch']['path']['plugins'] = '/usr/share/elasticsearch/plugins'
default['elasticsearch']['path']['bin'] = '/usr/share/elasticsearch/bin'

default['elasticsearch']['port']['discovery'] = 9300
default['elasticsearch']['port']['http'] = 9200

default['elasticsearch']['telegraf']['consul_template_inputs_file'] = 'telegraf_elasticsearch_inputs.ctmpl'

#
# FIREWALL
#

# Allow communication on the loopback address (127.0.0.1 and ::1)
default['firewall']['allow_loopback'] = true

# Do not allow MOSH connections
default['firewall']['allow_mosh'] = false

# Do not allow WinRM (which wouldn't work on Linux anyway, but close the ports just to be sure)
default['firewall']['allow_winrm'] = false

# No communication via IPv6 at all
default['firewall']['ipv6_enabled'] = false

#
# JAVA
#

default['java']['jdk_version'] = '8'
default['java']['install_flavor'] = 'openjdk'
default['java']['install_type'] = 'jdk'

#
# TELEGRAF
#

default['telegraf']['service_user'] = 'telegraf'
default['telegraf']['service_group'] = 'telegraf'
default['telegraf']['config_directory'] = '/etc/telegraf/telegraf.d'
