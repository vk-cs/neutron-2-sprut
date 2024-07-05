#!/bin/bash

# Проверка наличия входного параметра
if [ -z "$1" ]; then
    echo "Использование: $0 lb-to-sprut-net=<имя исходного балансера в нейтроне 1>=<имя спрут сети 1>,<имя исходного балансера в нейтроне 2>=<имя спрут сети 2>,..."
    exit 1
fi

# Разбор входного параметра
IFS=',' read -r -a LB_TO_NET <<< "${1#lb-to-sprut-net=}"

# Функция для получения ID балансировщика по имени
get_lb_id_by_name() {
    openstack loadbalancer list --name "$1" -f value -c id
}

# Функция для создания копии балансировщика
create_lb_copy() {
    local source_lb_name=$1
    local target_network_id=$2

    # Получение ID исходного балансировщика
    local source_lb_id=$(get_lb_id_by_name "$source_lb_name")

    if [ -z "$source_lb_id" ]; then
        echo "Балансировщик нагрузки с именем $source_lb_name не найден."
        return
    fi

    # Создание нового балансировщика нагрузки
    local new_lb_id=$(openstack loadbalancer create --vip-subnet-id $target_network_id --name "Copy_of_$source_lb_name" -f value -c id)

    echo "Создан новый балансировщик нагрузки с ID $new_lb_id"

    # Копирование слушателей (listeners)
    local listeners=$(openstack loadbalancer listener list --loadbalancer $source_lb_id -f json)
    for row in $(echo "${listeners}" | jq -r '.[] | @base64'); do
        _jq() {
            echo ${row} | base64 --decode | jq -r ${1}
        }

        local listener_id=$(_jq '.id')
        local listener_name=$(_jq '.name')
        local listener_protocol=$(_jq '.protocol')
        local listener_protocol_port=$(_jq '.protocol_port')
        local listener_connection_limit=$(_jq '.connection_limit')

        local new_listener_id=$(openstack loadbalancer listener create --name "Copy_of_$listener_name" --loadbalancer $new_lb_id --protocol $listener_protocol --protocol-port $listener_protocol_port --connection-limit $listener_connection_limit -f value -c id)

        echo "Создан новый слушатель с ID $new_listener_id"

        # Копирование пулов (pools)
        local pools=$(openstack loadbalancer pool list --listener $listener_id -f json)
        for row in $(echo "${pools}" | jq -r '.[] | @base64'); do
            _jq() {
                echo ${row} | base64 --decode | jq -r ${1}
            }

            local pool_id=$(_jq '.id')
            local pool_name=$(_jq '.name')
            local pool_protocol=$(_jq '.protocol')
            local pool_lb_algorithm=$(_jq '.lb_algorithm')

            local new_pool_id=$(openstack loadbalancer pool create --name "Copy_of_$pool_name" --listener $new_listener_id --protocol $pool_protocol --lb-algorithm $pool_lb_algorithm -f value -c id)

            echo "Создан новый пул с ID $new_pool_id"

            # Копирование членов (members)
            local members=$(openstack loadbalancer member list $pool_id -f json)
            for row in $(echo "${members}" | jq -r '.[] | @base64'); do
                _jq() {
                    echo ${row} | base64 --decode | jq -r ${1}
                }

                local member_address=$(_jq '.address')
                local member_protocol_port=$(_jq '.protocol_port')
                local member_weight=$(_jq '.weight')
                local member_subnet_id=$(_jq '.subnet_id')

                openstack loadbalancer member create --subnet-id $member_subnet_id --address $member_address --protocol-port $member_protocol_port --weight $member_weight $new_pool_id

                echo "Создан новый член пула с адресом $member_address"
            done

            # Копирование мониторов здоровья (health monitors)
            local health_monitor_id=$(openstack loadbalancer pool show $pool_id -f value -c healthmonitor_id)
            if [ "$health_monitor_id" != "None" ]; then
                local health_monitor=$(openstack loadbalancer healthmonitor show $health_monitor_id -f json)
                local health_monitor_type=$(echo $health_monitor | jq -r '.type')
                local health_monitor_delay=$(echo $health_monitor | jq -r '.delay')
                local health_monitor_timeout=$(echo $health_monitor | jq -r '.timeout')
                local health_monitor_max_retries=$(echo $health_monitor | jq -r '.max_retries')
                local health_monitor_http_method=$(echo $health_monitor | jq -r '.http_method')
                local health_monitor_url_path=$(echo $health_monitor | jq -r '.url_path')
                local health_monitor_expected_codes=$(echo $health_monitor | jq -r '.expected_codes')

                openstack loadbalancer healthmonitor create --type $health_monitor_type --delay $health_monitor_delay --timeout $health_monitor_timeout --max-retries $health_monitor_max_retries --http-method $health_monitor_http_method --url-path $health_monitor_url_path --expected-codes $health_monitor_expected_codes --pool $new_pool_id

                echo "Создан новый монитор здоровья для пула $new_pool_id"
            fi
        done
    done

    echo "Копирование балансировщика нагрузки $source_lb_name завершено."
}

# Основной цикл для копирования балансировщиков
for lb_to_net in "${LB_TO_NET[@]}"; do
    IFS='=' read -r -a parts <<< "$lb_to_net"
    SOURCE_LB_NAME="${parts[0]}"
    TARGET_NETWORK_ID="${parts[1]}"
    create_lb_copy "$SOURCE_LB_NAME" "$TARGET_NETWORK_ID"
done
