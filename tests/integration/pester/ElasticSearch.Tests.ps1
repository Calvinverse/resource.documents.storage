Describe 'The elasticsearch application' {
    Context 'is installed' {
        It 'with files in /usr/share/elasticsearch' {
            '/usr/share/elasticsearch' | Should Exist
            '/usr/share/elasticsearch/bin' | Should Exist
            '/usr/share/elasticsearch/bin/elasticsearch' | Should Exist
        }

        It 'with default configuration in /etc/elasticsearch/influxdb.conf' {
            '/etc/elasticsearch/influxdb.conf' | Should Exist
        }
    }

    Context 'has been daemonized' {
        $serviceConfigurationPath = '/etc/systemd/system/elasticsearch.service'
        if (-not (Test-Path $serviceConfigurationPath))
        {
            It 'has a systemd configuration' {
               $false | Should Be $true
            }
        }

        $expectedContent = @'
[Unit]
Description=Elasticsearch
Requires=multi-user.target
Wants=network-online.target
After=network-online.target
Documentation=http://www.elastic.co

[Install]
WantedBy=network-online.target

[Service]
ExecStart=/usr/share/elasticsearch/bin/elasticsearch -p /var/run/elasticsearch/elasticsearch.pid
User=elasticsearch
Group=elasticsearch
WorkingDirectory=/usr/share/elasticsearch
Environment="ES_HOME=/usr/share/elasticsearch" "ES_PATH_CONF=/etc/elasticsearch" "PID_DIR=/var/run/elasticsearch"
RuntimeDirectory=elasticsearch
LimitNOFILE=65536
LimitAS=infinity
LimitNPROC=4096
KillMode=process
KillSignal=SIGTERM
SendSIGKILL=no
TimeoutStopSec=0
Restart=on-failure
SuccessExitStatus=143

'@
        $serviceFileContent = Get-Content $serviceConfigurationPath | Out-String
        $systemctlOutput = & systemctl status elasticsearch
        It 'with a systemd service' {
            $serviceFileContent | Should Be ($expectedContent -replace "`r", "")

            $systemctlOutput | Should Not Be $null
            $systemctlOutput.GetType().FullName | Should Be 'System.Object[]'
            $systemctlOutput.Length | Should BeGreaterThan 3
            $systemctlOutput[0] | Should Match 'elasticsearch.service - Elasticsearch'
        }

        It 'that is enabled' {
            $systemctlOutput[1] | Should Match 'Loaded:\sloaded\s\(.*;\senabled;.*\)'

        }

        It 'and is running' {
            $systemctlOutput[2] | Should Match 'Active:\sactive\s\(running\).*'
        }
    }

    Context 'can be contacted' {
        try
        {
            $response = Invoke-WebRequest -Uri "http://localhost:9200/_cluster/health" -Headers $headers -UseBasicParsing
        }
        catch
        {
            # Because powershell sucks it throws if the response code isn't a 200 one ...
            $response = $_.Exception.Response
        }

        It 'responds to HTTP calls' {
            $response.StatusCode | Should Be 200
        }
    }
}
