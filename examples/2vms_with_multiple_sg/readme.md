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
./../../migrator-multiple.sh --all-secgroup-sprut-id=<id секьюрити группы all на спруте> migration-input.csv
```

После переключения управляемость терраформом потеряется, необходимо обновить стейтфайлы удалив и добавив вм.