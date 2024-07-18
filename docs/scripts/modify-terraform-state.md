# Скрипт обновления состояния терраформа после миграции

**modify_terraform_state.sh**

В случае, если используется terraform в качестве основного инструмента управления инфраструктурой, необходимо описать копии сетей, групп безопасности, роутеров и других компонентов на sdn sprut, для этого необходимо проставить соответствующие параметры. Например есть исходная сеть на нейтроне: 

```c
resource "vkcs_networking_network" "app" {
  name        = "app-tf-example"
  description = "Application network"
}
```

Мы создаём копию на спруте, при этом для чёткого разграничения указываем у исходной сети на нейтроне sdn=neutron.

```c
resource "vkcs_networking_network" "app" {
  name        = "app-tf-example"
  description = "Application network"
  sdn = "neutron"
}

resource "vkcs_networking_network" "app-sprut" {
  name        = "app-tf-example-sprut"
  description = "Application network"
  sdn = "sprut"
}
```

Мигрируем скриптом вм, после чего правим в манифесте вм сеть, к которой подключена вм (уже на спрут).

**ВАЖНО!** Перед правкой файлов терраформа рекомендуется сделать резервную копию.

Запускаем скрипт изменения состояния ./modify_terraform_state.sh

Получаем скрипт terraform_modify_to_sprut_state.sh и таблицу state_modification_table.txt с именами вм в терраформе и их id в openstack.

Скрипт **terraform_modify_to_sprut_state.sh** состоит из команд изменения состояний для каждой вм:

```bash
terraform state rm
terraform import
```

При каждом выполнении шага в скрипте создаётся новая версия-копия стейт файла терраформа для отката в случае проблем. 

**ВАЖНО!** Рекомендуется перед запуском скрипта изменения стейта сделать исходную копию исходной стейт файла терраформа.
