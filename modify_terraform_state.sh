#!/bin/bash

echo "
#######################################
#                                     #
#  Terraform State Modification Script#
#                                     #
#######################################
"

# Проверяем, передан ли файл состояния как аргумент
if [[ -n "$1" ]]; then
    state_file="-state=$1"
    echo "Using specified state file: $1"
else
    state_file=""
    echo "Using default state file"
fi

# Получаем список всех ресурсов в состоянии Terraform
terraform_state_list=$(terraform state list $state_file)

# Фильтруем ресурсы, чтобы оставить только vkcs_compute_instance
compute_instances=$(echo "$terraform_state_list" | grep "vkcs_compute_instance")

# Проверка наличия compute_instances
if [[ -z "$compute_instances" ]]; then
    echo "No vkcs_compute_instance resources found in the current Terraform state."
    exit 1
fi

# Генерируем скрипт для изменения состояния
output_script="terraform_modify_to_sprut_state.sh"
echo "#!/bin/bash" > $output_script
echo "echo '#######################################'" >> $output_script
echo "echo '#                                     #'" >> $output_script
echo "echo '#  Modifying Terraform State Script   #'" >> $output_script
echo "echo '#                                     #'" >> $output_script
echo "echo '#######################################'" >> $output_script

# Инициализируем таблицу для вывода
table_output="terraform resource name | openstack vm id | vm name\n"

# Проходим по каждому compute_instance и генерируем команды для удаления и импорта
while IFS= read -r instance; do
    # Получаем id и имя ресурса
    resource_info=$(terraform state show $state_file $instance)
    resource_id=$(echo "$resource_info" | grep -E '^\s*id\s*=' | awk -F' = ' '{print $2}' | tr -d '"' | head -n 1)
    resource_name=$(echo "$resource_info" | grep -E '^\s*name\s*=' | awk -F' = ' '{print $2}' | tr -d '"' | head -n 1)
    
    # Проверка наличия id и имени ресурса
    if [[ -z "$resource_id" || -z "$resource_name" ]]; then
        echo "No id or name found for $instance in the current Terraform state."
        continue
    fi

    # Добавляем команды для удаления и импорта ресурса в скрипт
    echo "echo 'Modifying $instance'" >> $output_script
    echo "terraform state rm $instance $state_file" >> $output_script
    echo "terraform import $instance $resource_id $state_file" >> $output_script

    # Добавляем строку в таблицу
    table_output+="$instance | $resource_id | $resource_name\n"
done <<< "$compute_instances"

# Делаем сгенерированный скрипт исполняемым
chmod +x $output_script

# Выводим результаты
echo -e "Generated script: $output_script\n"
echo -e "$table_output"

# Записываем таблицу в файл для удобства
table_output_file="state_modification_table.txt"
echo -e "$table_output" > $table_output_file

echo "Table of resources saved to $table_output_file"
