# Webinar

В данном документе будет описан тестовый сценарий миграции данного контура.


![alt text](../../docs/images/webinar-stage-0.png)

## Поднимаем стенд

Для поднятия тестового стенда с инфраструктурой на sprut необходимо установить terraform и скачать .rc файл с данными для доступа к проекту.

Быстрый старт по terraform можно рассмотреть в [документации](https://cloud.vk.com/docs/ru/tools-for-using-services/terraform/quick-start).

Как получить .rc файл для управления облаком через api можно посмотреть в [документации](https://cloud.vk.com/docs/tools-for-using-services/cli/openstack-cli#3_proydite_autentifikaciyu) (в том числе необходимо для openstack cli). 

```bash
source openstack_creds.rc
```

переходим в директорию с кодом terraform:

```bash
cd terraform
```

инициализируем terraform:

```bash
terraform init
```

применяем terraform код:

```bash
terraform apply --auto-approve
```

## Работа со скриптами

```bash
cd ../script-inputs
```

## Копирование групп безопасности

![alt text](../../docs/images/webinar-stage-1.png)

Копирование групп безопасности осуществляется при помощи [скрипта](../../docs/scripts/copy-security-group.md):
```bash
./../../../copy-security-group.sh --groups=webinar-secgroup-http
```

Они будут созданы с аналогичными исходным названиями с постфиксом -sprut.

Проверить что группы скопировались можно при помощи [скрипта](../../check-if-all-sprut-sg-present.sh):
```bash
./../../../check-if-all-sprut-sg-present.sh
```

## Копирование роутеров сетей, подсетей
![alt text](../../docs/images/webinar-stage-2.png)

Для копирования всей сетевой инфраструктуры используется [скрипт](../../docs/scripts/copy-router-and-networks.md).
Для скрипта достаточно указать id исходного роутера и в каком виде он должен быть создан на sprut:
- продвинутый (необходим для построения vpn на sprut, не поддерживает floating ip, только DNAT)
или 
- стандартный (не поддерживает vpn на sprut, поддерживает floating ip)

Конфиг файл для скрипта:
```shell
neutron router id,adv
```

ID роутеров на нейтроне можно получить через личный кабинет или при помощи openstack cli:
```bash
openstack router list
```

Запускаем скрипт:
```bash
./../../../copy-router-and-networks.sh copy-router-networks-input.csv
```

В итоге получим аналогичные роутер и все подключенные сети с подсетями.

## Копирование балансировщика нагрузки

Для теста данного кейса необходимо на созданные в стенде вм webinar-nginx-server-vm-0
и webinar-nginx-server-vm-1 установить какое-то веб приложение, например nginx.

```bash
sudo apt update
```

```bash
sudo apt install nginx
```

Миграция осуществляется при помощи [скрипта](../../docs/scripts/copy-loadbalancer.md)

На создание балансировщика уходит ~5 минут, это можно сделать вне технического окна.

Конфиг:
```bash
имя балансировщика neutron,имя сети sprut,имя сети подсети sprut
```

Запускаем скрипт:
```bash
./../../../copy-loadbalancer.sh copy-loadbalancer-input.csv
```

В результате выполнения будет создан балансировщик нагрузки в сети sprut с таким же серым ip.
![alt text](../../docs/images/webinar-stage-3.png)

Создание аналогичного балансировщика никак не влияет на исходную инфраструктуру

**ВАЖНО!** На данном этапе не нужно удалять стандартный балансировщик, он ещё понадобится для копирования правил балансировки.

## Миграция виртуальных машин

На данном этапе требуется техническое окно, так как переключение интерфейсов подразумевает потерю сетевой связности.
Миграция будет выполнятся  при помощи [скрипта](../../docs/scripts/migrator-multiple.md).

Для данного скрипта понадобится техокно, у каждой вм будут последовательно переключаться порты и это займёт 30-45 секунд.

конфиг:
```bash
имя вм,имя сети sprut,имя сети подсети sprut 
```

Запускаем скрипт:

```bash
./../../../migrator-multiple.sh migrator-multiple-input.csv
```

![alt text](../../docs/images/webinar-stage-4.png)

В результате получим вм в новой сети, с теми же серыми ip и мак адресами.

## Копирование правил балансировки

Копирование правил балансировки необходимо выполнить после того, как вм будут подключены в sprut.
Копирование осуществляется при помощи [скритпа](../../docs/scripts/copy-loadbalancer.md).

Запускаем перенос правил.
```bash
./../../../copy-loadbalancer-rules.sh copy-loadbalancer-script-output-config.csv
```

После переноса правил приложение должно быть доступно и все правила перенесены.

![alt text](../../docs/images/webinar-stage-5.png)

## Копирование ipsec

Копирование будет выполнятся при помощи [скрипта](../../docs/scripts/copy-ipsec.md).

Скрипт принимает на вход id стандартного роутера на neutron с которого будут скопированны все туннели, и id продвинутого роутера куда будут перенесены туннели.

Конфиг:
```bash
id стандартного роутера, id продвинутого 
```

Запускаем скрипт:
```bash
./../../../copy-ipsec-v2.sh copy-ipsec-input.csv
```

![alt text](../../docs/images/webinar-stage-6.png)

**Важно!** После копирования ipsec, так как будет использоваться новый роутер с новым ip, необходимо на другой стороне туннеля поменять адрес пира (указать внешний ip продвинутого роутера).

## Итоговая инфраструктура

![alt text](../../docs/images/webinar-stage-7.png)