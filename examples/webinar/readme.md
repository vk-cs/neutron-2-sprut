# Webinar

В данном документе будет описан тестовый сценарий миграции данного контура.


![alt text](../../docs/images/webinar-stage-0.png)

## Поднимаем стенд

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
cd ../script-inputs
```

## Копирование групп безопасности

![alt text](../../docs/images/webinar-stage-1.png)

```bash
./../../../copy-security-group.sh --groups=webinar-secgroup-http
```

проверить что группы скопировались:

```bash
./../../../check-if-all-sprut-sg-present.sh
```

## Копирование роутеров сетей, подсетей
![alt text](../../docs/images/webinar-stage-2.png)

конфиг:

```shell
neutron router id,adv
```

```bash
./../../../copy-router-and-networks.sh copy-router-networks-input.csv
```

## Копирование балансировщика нагрузки

на балансировщик уходит ~5 минут

```bash
./../../../copy-loadbalancer.sh copy-loadbalancer-input.csv
```

![alt text](../../docs/images/webinar-stage-3.png)

## Миграция виртуальных машин

На данном этапе требуется техническое окно, так как переключение интерфейсов подразумевает потерю сетевой связности.

```bash
./../../../migrator-multiple.sh migrator-multiple-input.csv
```

![alt text](../../docs/images/webinar-stage-4.png)

## Копирование правил балансировки

```bash
./../../../copy-loadbalancer-rules.sh copy-loadbalancer-script-output-config.csv
```

![alt text](../../docs/images/webinar-stage-5.png)

## Копирование ipsec


конфиг
```bash
id стандартного роутера, id продвинутого 
```

```bash
./../../../copy-ipsec-v2.sh copy-ipsec-input.csv
```

![alt text](../../docs/images/webinar-stage-6.png)

## Итоговая инфраструктура

![alt text](../../docs/images/webinar-stage-7.png)