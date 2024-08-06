#!/bin/bash

# Проверка наличия аргумента
if [ -z "$1" ]; then
    echo "Использование: $0 <файл с именами роутеров>"
    exit 1
fi

ROUTER_FILE=$1

# Функция для выполнения команды OpenStack и возврата результата
run_cli_command() {
    echo "Выполнение команды: $1"
    eval "$1"
}

# Функция для выполнения запросов к API
send_api_request() {
    METHOD=$1
    URL=$2
    DATA=$3
    TOKEN=$(openstack token issue -f value -c id)

    if [ "$METHOD" == "GET" ]; then
        RESPONSE=$(curl -s -H "X-SDN: SPRUT" -H "X-Auth-Token: $TOKEN" "$URL")
    elif [ "$METHOD" == "POST" ]; then
        RESPONSE=$(curl -s -X POST -H "X-SDN: SPRUT" -H "X-Auth-Token: $TOKEN" -H "Content-Type: application/json" -d "$DATA" "$URL")
    fi
    echo "Ответ API: $RESPONSE"
    echo "$RESPONSE"
}

# Считать CSV файл и выполнить миграцию туннелей
while IFS= read -r line || [ -n "$line" ]; do
    # Проверяем, что строка не пустая
    if [ -z "$line" ]; then
        continue
    fi

    IFS=',' read -r src_router tgt_router <<< "$line"
    echo "#########################################"
    echo "1. Миграция туннелей с $src_router на $tgt_router"
    echo "#########################################"

    # Получить список туннелей
    echo "-----------------------------------------"
    echo "2. Получить список туннелей"
    tunnels=$(run_cli_command "openstack vpn ipsec site connection list -f json")
    echo "Список туннелей: $tunnels"

    # Используем jq для фильтрации туннелей, относящихся к src_router
    filtered_tunnels=()
    for tunnel in $(echo "$tunnels" | jq -c '.[]'); do
        vpn_service_id=$(echo "$tunnel" | jq -r '.VPN Service')
        router_id=$(run_cli_command "openstack vpn service show $vpn_service_id -f json" | jq -r '.Router')
        if [ "$router_id" == "$src_router" ]; then
            filtered_tunnels+=("$tunnel")
        fi
    done

    echo "Фильтрованные туннели: ${filtered_tunnels[@]}"
    echo "-----------------------------------------"

    for tunnel in "${filtered_tunnels[@]}"; do
        tunnel_id=$(echo "$tunnel" | jq -r '.ID')
        echo "3. Миграция туннеля $tunnel_id"
        echo "-----------------------------------------"
        tunnel_info=$(run_cli_command "openstack vpn ipsec site connection show $tunnel_id -f json")
        echo "Информация о туннеле: $tunnel_info"

        ike_policy_id=$(echo "$tunnel_info" | jq -r '.IKE Policy')
        ipsec_policy_id=$(echo "$tunnel_info" | jq -r '.IPSec Policy')
        local_endpoint_group_id=$(echo "$tunnel_info" | jq -r '.Local Endpoint Group ID')
        peer_endpoint_group_id=$(echo "$tunnel_info" | jq -r '.Peer Endpoint Group ID')
        peer_id=$(echo "$tunnel_info" | jq -r '.Peer ID')
        preshared_key=$(echo "$tunnel_info" | jq -r '.Pre-shared Key')

        # Создать копию IKE Policy
        echo "-----------------------------------------"
        echo "4. Создать копию IKE Policy $ike_policy_id"
        ike_policy_info=$(run_cli_command "openstack vpn ike policy show $ike_policy_id -f json")
        echo "Информация о IKE Policy: $ike_policy_info"
        new_ike_policy_info=$(echo "$ike_policy_info" | jq 'del(.ID) | .Name = (.Name + "-sprut")')
        new_ike_policy_id=$(send_api_request "POST" "https://infra.mail.ru:9696/infra/network/v2.0/vpn/ikepolicies" "$new_ike_policy_info" | jq -r '.ikepolicy.id')
        echo "Новый IKE Policy ID: $new_ike_policy_id"
        echo "-----------------------------------------"

        # Создать копию IPSec Policy
        echo "-----------------------------------------"
        echo "5. Создать копию IPSec Policy $ipsec_policy_id"
        ipsec_policy_info=$(run_cli_command "openstack vpn ipsec policy show $ipsec_policy_id -f json")
        echo "Информация о IPSec Policy: $ipsec_policy_info"
        new_ipsec_policy_info=$(echo "$ipsec_policy_info" | jq 'del(.ID) | .Name = (.Name + "-sprut")')
        new_ipsec_policy_id=$(send_api_request "POST" "https://infra.mail.ru:9696/infra/network/v2.0/vpn/ipsecpolicies" "$new_ipsec_policy_info" | jq -r '.ipsecpolicy.id')
        echo "Новый IPSec Policy ID: $new_ipsec_policy_id"
        echo "-----------------------------------------"

        # Создать копию Local Endpoint Group
        echo "-----------------------------------------"
        echo "6. Создать копию Local Endpoint Group $local_endpoint_group_id"
        local_endpoint_info=$(run_cli_command "openstack vpn endpoint group show $local_endpoint_group_id -f json")
        echo "Информация о Local Endpoint Group: $local_endpoint_info"
        new_local_endpoint_info=$(echo "$local_endpoint_info" | jq 'del(.ID) | .Name = (.Name + "-sprut")')
        new_local_endpoint_id=$(send_api_request "POST" "https://infra.mail.ru:9696/infra/network/v2.0/vpn/endpointgroups" "$new_local_endpoint_info" | jq -r '.endpointgroup.id')
        echo "Новый Local Endpoint Group ID: $new_local_endpoint_id"
        echo "-----------------------------------------"

        # Создать копию Peer Endpoint Group
        echo "-----------------------------------------"
        echo "7. Создать копию Peer Endpoint Group $peer_endpoint_group_id"
        peer_endpoint_info=$(run_cli_command "openstack vpn endpoint group show $peer_endpoint_group_id -f json")
        echo "Информация о Peer Endpoint Group: $peer_endpoint_info"
        new_peer_endpoint_info=$(echo "$peer_endpoint_info" | jq 'del(.ID) | .Name = (.Name + "-sprut")')
        new_peer_endpoint_id=$(send_api_request "POST" "https://infra.mail.ru:9696/infra/network/v2.0/vpn/endpointgroups" "$new_peer_endpoint_info" | jq -r '.endpointgroup.id')
        echo "Новый Peer Endpoint Group ID: $new_peer_endpoint_id"
        echo "-----------------------------------------"

        # Создать новый туннель на целевом роутере
        echo "-----------------------------------------"
        echo "8. Создать новый туннель на целевом роутере $tgt_router"
        new_tunnel_info=$(echo "$tunnel_info" | jq 'del(.ID) | .Name = (.Name + "-sprut")')
        new_tunnel_info=$(echo "$new_tunnel_info" | jq --arg ike "$new_ike_policy_id" --arg ipsec "$new_ipsec_policy_id" --arg local "$new_local_endpoint_id" --arg peer "$new_peer_endpoint_id" --arg tgt_router "$tgt_router" '.IKE Policy = $ike | .IPSec Policy = $ipsec | .Local Endpoint Group ID = $local | .Peer Endpoint Group ID = $peer | .Router = $tgt_router')
        send_api_request "POST" "https://infra.mail.ru:9696/infra/network/v2.0/vpn/ipsec-site-connections" "$new_tunnel_info"
        echo "Новый туннель создан"
        echo "-----------------------------------------"
    done
    echo "#########################################"
    echo "Миграция туннелей с $src_router на $tgt_router завершена"
    echo "#########################################"
done < "$ROUTER_FILE"
