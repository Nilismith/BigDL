#!/bin/bash

usage() {
    echo "Usage: $0 [-m --mode <controller|worker>] [-w --worker <model_worker|vllm_worker>] [--help]"
    echo "--help: Print help message."
    echo "The following environment variables can be set."
    echo "MODEL_PATH (default: empty)."
    echo "CONTROLLER_HOST (default: localhost)."
    echo "CONTROLLER_PORT (default: 21001)."
    echo "WORKER_HOST (default: localhost)."
    echo "WORKER_PORT (default: 21002)."
    echo "API_HOST (default: localhost)."
    echo "API_PORT (default: 8000)."
    exit 1
}

# Default values
controller_host="localhost"
controller_port="21001"
worker_host="localhost"
worker_port="21002"
api_host="localhost"
api_port="8000"
model_path=""
mode=""
dispatch_method="shortest_queue" # shortest_queue or lottery
stream_interval=1
worker_type="model_worker"

# We do not have any arguments, just run bash
if [ "$#" == 0 ]; then
    echo "[INFO] no command is passed in"
    echo "[INFO] enter pass-through mode"
    exec /usr/bin/bash -s -- "bash"
else
    # Parse command-line options
    options=$(getopt -o "m:hw:" --long "mode:,help,worker:" -n "$0" -- "$@")
    if [ $? != 0 ]; then
        usage
    fi
    eval set -- "$options"
    
    while true; do
        case "$1" in
            -m|--mode)
                mode="$2"
                [[ $mode == "controller" || $mode == "worker" ]] || usage
                shift 2
            ;;
            -w|--worker)
                worker_type="$2"
                [[ $worker_type == "model_worker" || $worker_type == "vllm_worker" ]] || usage
                shift 2
            ;;
            -h|--help)
                usage
            ;;
            --)
                shift
                break
            ;;
            *)
                usage
            ;;
        esac
    done
    
    if [ "$worker_type" == "model_worker" ]; then
        worker_type="bigdl.llm.serving.model_worker"
    elif [ "$worker_type" == "vllm_worker" ]; then
        worker_type="bigdl.llm.serving.vllm_worker"
    fi
    
    if [[ -n $CONTROLLER_HOST ]]; then
        controller_host=$CONTROLLER_HOST
    fi
    
    if [[ -n $CONTROLLER_PORT ]]; then
        controller_port=$CONTROLLER_PORT
    fi
    
    if [[ -n $WORKER_HOST ]]; then
        worker_host=$WORKER_HOST
    fi
    
    if [[ -n $WORKER_PORT ]]; then
        worker_port=$WORKER_PORT
    fi
    
    if [[ -n $MODEL_PATH ]]; then
        model_path=$MODEL_PATH
    fi
    
    if [[ -n $API_HOST ]]; then
        api_host=$API_HOST
    fi
    
    if [[ -n $API_PORT ]]; then
        api_port=$API_PORT
    fi
    
    if [[ -n $DISPATCH_METHOD ]]; then
        dispatch_method=$DISPATCH_METHOD
    fi
    
    if [[ -n $STREAM_INTERVAL ]]; then
        stream_interval=$STREAM_INTERVAL
    fi
    
    controller_address="http://$controller_host:$controller_port"
    
    unset http_proxy
    unset https_proxy
    
    if [[ $mode == "controller" ]]; then
        
        api_address="http://$api_host:$api_port"
        echo "Controller address: $controller_address"
        echo "OpenAI API address: $api_address"
        python3 -m fastchat.serve.controller --host $controller_host --port $controller_port --dispatch-method $dispatch_method &
        python3 -m fastchat.serve.openai_api_server --host $api_host --port $api_port --controller-address $controller_address
        
    else
        
        worker_address="http://$worker_host:$worker_port"
        echo "Worker type: $worker_type"
        echo "Worker address: $worker_address"
        echo "Controller address: $controller_address"
        
        if [ "$worker_type" == "bigdl.llm.serving.model_worker" ]; then
            python3 -m "$worker_type" --model-path $model_path --device xpu --host $worker_host --port $worker_port --worker-address $worker_address --controller-address $controller_address --stream-interval $stream_interval
        elif [ "$worker_type" == "bigdl.llm.serving.vllm_worker" ]; then
            python3 -m "$worker_type" --model-path $model_path --device xpu --host $worker_host --port $worker_port --worker-address $worker_address --controller-address $controller_address
        fi
    fi
    
fi

exec /usr/bin/bash -s -- "bash"
