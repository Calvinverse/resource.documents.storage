# frozen_string_literal: true

#
# CONSULTEMPLATE
#

default['consul_template']['config_path'] = '/etc/consul-template.d/conf'
default['consul_template']['template_path'] = '/etc/consul-template.d/templates'

#
# ELASTICSEARCH
#

default['elasticsearch']['version'] = '6.3.1'
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

# default['elasticsearch']['configure'] = {
#   'path_home' => node['elasticsearch']['path']['home'],
#   'path_conf' => node['elasticsearch']['path']['config'],
#   'path_data' => node['elasticsearch']['path']['data'],
#   'path_logs' => node['elasticsearch']['path']['logs'],
#   'path_pid' => node['elasticsearch']['path']['pid'],
#   'path_plugins' => node['elasticsearch']['path']['plugins'],
#   'path_bin' => node['elasticsearch']['path']['bin'],
#   'http.port' => node['elasticsearch']['port']['http']
# }

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
# TELEGRAF
#

default['telegraf']['config_directory'] = '/etc/telegraf/telegraf.d'
