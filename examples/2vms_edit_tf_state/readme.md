Поднять стенд:

```bash
cd terraform
```

```bash
terraform init
```

```bash
terraform apply --auto-approve
```

```bash
cd ../
```

Выполнить переключение:

```bash
./../../migrator-multiple.sh migration-input.csv
```

После переключения управляемость терраформом потеряется, необходимо обновить стейтфайлы удалив и добавив вм.

Заменяем в файле terraform/main.tf в описании вм с

```c
  network {
    uuid = vkcs_networking_network.app.id
  }
```

на
```
  network {
    uuid = vkcs_networking_network.app_sprut.id
  }
```

Запускаем скрипт для изменения state файла terraform

```bash
./../../../modify_terraform_state.sh
```

В выводе получим список вм в терраформе имя и айди.

Получим на выходе файл-скрипт **terraform_modify_to_sprut_state**, который при запуске выполнит для каждой вм

```bash
terraform state rm
terraform state import
```

выполним скрипт

```bash
./terraform_modify_to_sprut_state.sh
```

После этого можно выполнить проверку при помощи

```bash
terraform plan
```

Должно быть 0 изменений.

```shell
No changes. Your infrastructure matches the configuration.
```