#!/bin/bash

# Set your monitoring tool URLs (replace with actual URLs)
PROMETHEUS_PUSH_GATEWAY="http://10.0.34.195:9091/metrics"
LOKI_URL="http://10.0.34.195:3100/loki/api/v1/push"
TEMPO_URL="http://10.0.34.195:3200/api/traces"

# Function to collect metrics for a given process (memory, CPU)
collect_metrics_for_process() {
    local pid=$1
    local app_name=$2

    # Get memory and CPU usage for the application
    MEMORY_USAGE=$(ps -p $pid -o %mem=)
    CPU_USAGE=$(ps -p $pid -o %cpu=)
    TIMESTAMP=$(date +%s)

    # Prepare Prometheus metrics in the correct format
    METRICS="app_memory_usage{app=\"$app_name\"} $MEMORY_USAGE ${TIMESTAMP}
app_cpu_usage{app=\"$app_name\"} $CPU_USAGE ${TIMESTAMP}"

    echo "$METRICS"
}

# Function to push collected metrics to Prometheus Push Gateway
push_to_prometheus() {
    local metrics=$1
    echo "$metrics" | curl --data-binary @- "$PROMETHEUS_PUSH_GATEWAY"
    if [ $? -eq 0 ]; then
        echo "Metrics successfully pushed to Prometheus"
    else
        echo "Failed to push metrics to Prometheus"
    fi
}

# Function to send logs to Loki
send_logs_to_loki() {
    local app_name=$1
    local pid=$2
    LOG_MESSAGE="Application $app_name (PID $pid) is running."
    TIMESTAMP=$(date +%s)

    JSON_PAYLOAD=$(cat <<EOF
{
    "streams": [
        {
            "stream": {
                "app": "$app_name",
                "pid": "$pid"
            },
            "values": [
                ["$TIMESTAMP", "$LOG_MESSAGE"]
            ]
        }
    ]
}
EOF
)

    curl -X POST -H "Content-Type: application/json" -d "$JSON_PAYLOAD" "$LOKI_URL"
    if [ $? -eq 0 ]; then
        echo "Logs successfully sent to Loki"
    else
        echo "Failed to send logs to Loki"
    fi
}

# Function to send traces to Tempo
send_traces_to_tempo() {
    local app_name=$1
    local pid=$2

    TRACE_DATA=$(cat <<EOF
{
  "resourceSpans": [{
    "instrumentationLibrarySpans": [{
      "spans": [{
        "traceId": "1234abcd5678efgh",
        "spanId": "abcd1234efgh5678",
        "name": "example_span",
        "startTimeUnixNano": $(($(date +%s) * 1000000000)),
        "endTimeUnixNano": $(($(date +%s) * 1000000000 + 1000000000)),
        "attributes": [{
          "key": "app",
          "value": {"stringValue": "$app_name"}
        },{
          "key": "pid",
          "value": {"stringValue": "$pid"}
        }]
      }]
    }]
  }]
}
EOF
)

    curl -X POST -H "Content-Type: application/json" -d "$TRACE_DATA" "$TEMPO_URL"
    if [ $? -eq 0 ]; then
        echo "Traces successfully sent to Tempo"
    else
        echo "Failed to send traces to Tempo"
    fi
}

# Function to filter application-related processes
is_application_process() {
    local app_name=$1
    # Define a list of known system process names (you can expand this list)
    local system_processes=("init" "systemd" "kthreadd" "kworker" "sshd" "cron" "dmesg" "bash")

    for process in "${system_processes[@]}"; do
        if [[ "$app_name" == "$process" ]]; then
            return 1 # Return 1 for system processes
        fi
    done
    return 0 # Return 0 for application processes
}

# Main logic to monitor application-related processes
monitor_all_apps() {
    # List all running processes and their names
    ps -eo pid,comm --no-headers | while read pid app_name; do
        # Only monitor application-related processes
        if is_application_process "$app_name"; then
            echo "Monitoring application: $app_name (PID: $pid)"
            
            # Collect metrics for the current application
            metrics=$(collect_metrics_for_process "$pid" "$app_name")
            
            # Push metrics to Prometheus
            push_to_prometheus "$metrics"

            # Send logs to Loki
            send_logs_to_loki "$app_name" "$pid"

            # Send traces to Tempo
            send_traces_to_tempo "$app_name" "$pid"
        fi
    done
}

# Run the monitoring function
monitor_all_apps
