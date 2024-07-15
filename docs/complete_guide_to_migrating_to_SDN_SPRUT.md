Полное руководство по миграции на SDN SPRUT

В данном руководстве описаны причины и премущества миграции с SDN Neutron, на SDN Sprut. Приведены лучшие практики, типовые кейсы и способы миграции сервисов VK CLOUD.

- [Для чего нужна миграция](#_page0_x0.00_y451.12)
  - [Что такое sdn](#_page0_x0.00_y486.60)
  - [Чем sprut отличается от neutron](#_page0_x0.00_y575.74)
  - [Преимущества миграции](#_page1_x0.00_y408.15)
- [Сбор предварительных данных перед миграцией](#_page1_x0.00_y471.41)
- [Ограничения, к которым нужно быть готовым](#_page1_x0.00_y721.20)
  - [Смена плавающих ip](#_page2_x0.00_y81.64)
    - [Описание](#_page2_x0.00_y110.03)
    - [Решение](#_page2_x0.00_y175.46)
- [Как мигрировать](#_page2_x0.00_y236.66)
  - [IaaS](#_page2_x0.00_y348.52)
    - [Сети](#_page2_x0.00_y376.91)
      - [общая схема](#_page2_x0.00_y401.74)
      - [terraform](#_page6_x0.00_y226.61)
    - [Ipseс](#_page6_x0.00_y302.33)
    - [Балансировщики](#_page8_x0.00_y131.66)
    - [Виртуальные машины](#_page8_x0.00_y254.85)
      - [общая схема](#_page8_x0.00_y279.68)
    - [Подготовительные шаги.](#_page9_x0.00_y175.50)
      - [terraform](#_page14_x0.00_y459.86)
    - [NFS/CIFS](#_page16_x0.00_y129.53)
      - [общая схема](#_page16_x0.00_y154.35)
  - [PaaS](#_page16_x0.00_y249.64)
    - [Kubernetes](#_page17_x0.00_y232.09)
      - [общая схема](#_page17_x0.00_y256.91)
    - [DbaaS](#_page17_x0.00_y381.75)

# Для чего нужна миграция
## Что такое sdn
Software Defined Network — концепция выведения сетевых функций из специализированного железа на программный уровень и дальнейшего разделения ответственности на разные слои.

За счёт SDN в облаке реализуется маршрутизация, firewall и сетевая связность между сервисами в целом.

![sdn](https://dfzljdn9uc3pi.cloudfront.net/2022/cs-809/1/fig-1-2x.jpg)

<a name="_page0_x0.00_y575.74"></a>Чем sprut отличается от neutron

Долгое время в vk cloud использовался neutron, sdn входящий в openstack, но параллельно разрабатывалось собственное решение sdn - sprut, которое решает проблемы в архитектуре neutron, связанные с масштабируемостью и надёжностью.

На данной схеме предоставлена архитектура и схема работы обоих SDN. Подробнее в отдельной [статье](https://habr.com/ru/companies/vk/articles/763760/).

![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.001.jpeg)

1. Для sprut агентов предусмотрена возможность постоянного сбора информации о настройках Data plane при помощи HTTP API.

   В neutron конфигурация доставляется при помощи очереди, без проверки что она действительно пришла. В случае ошибок в конфигурации необходима пересборка портов, то есть full sync, который занимает время. 

2. В sprut больше нет событийной модели общения между компонентами. Теперь агенты всегда получают от сервера целевое состояние, в котором должны быть, и непрерывно перезапрашивают его. Получился аналог постоянного Full Sync, при котором агенты сравнивают текущее состояние Data plane с целевым состоянием от сервера, накладывают необходимый diff на Data plane и приводят его к актуальному состоянию. В теории автоматического управления такой подход называют замкнутым контуром управления. 
2. RabbitMQ заменён обычным HTTP REST API. Он лучше справляется с большими массивами данных о таргетном состоянии агентов, его проще разрабатывать и мониторить. Пропала ещё одна потенциальная точка отказа.

<a name="_page1_x0.00_y408.15"></a>Преимущества миграции

1. Повышение отказоустойчивости инфраструктуры, быстрое восстановление портов в случае выхода из строя сетевой инфраструктуры.
1. Переход на новый поддерживаемый sdn.

<a name="_page1_x0.00_y471.41"></a>Сбор предварительных данных перед миграцией

В начале необходимо собрать информацию по сетевой инфраструктуре всех проектов при помощи опросника.

1. Используется ли в облачном проекте Shared Network?
1. Используется ли в облачном проекте Shadow Port?
1. Используется ли в облачном проекте Floating IP?
1. Используется ли в облачном проекте публичный DNS?
1. Используется ли прямое подключение к сети ext-net?
1. Использует ли клиент сервис GSLB (Global Server Load Balancer)? ВАЖНО! Сервис является внешним по отношении к инфраструктуре VK Cloud.
1. Используется ли в облачном проекте IPsec VPNaaS?
1. Наличие статических маршрутов на базе Subnet / Router.
1. Наличие виртуальных машин пропускающих трафик (маршрутизаторы / балансировщики / прокси / межсетевые экраны).
1. Используются ли платформенные балансировщики нагрузки?
1. Используются ли правила L7 для платформенных балансировщиков? Если да, то какие именно правила (список)?
1. Есть ли сертификаты на платформенных балансировщиках?
1. Количество кастомных групп безопасности (Security Groups) и их привязка к портам ВМ.
1. Имеется ли в облачном проекте сетевой стык (приложить ссылку в Confluence)?
1. Уровень взаимосвязей между рассматриваемым в облачным проектом и другими облачными проектами заказчика.
1. Какие платформенные сервисы используются в облачном проекте?
1. Используется ли файловое хранилище nfs/cifs?

<a name="_page1_x0.00_y721.20"></a>Ограничения, к которым нужно быть готовым

Миграция с neutron на sprut процесс, требующий дополнительные действия с точки зрения сетевой инфраструктуры. 

<a name="_page2_x0.00_y81.64"></a>Смена плавающих ip

<a name="_page2_x0.00_y110.03"></a>Описание

Для предоставления белых ip адресов (плавающих, либо получаемых при прямом подключении) в SDN NEUTRON используется сеть ext-net, в которой имеются подсети с диапазоном белых ip адресов. 

Для SDN SPRUT используется такая же сеть, но с названием internet и с другим диапазоном адресов подстей.

<a name="_page2_x0.00_y175.46"></a>Решение

В ходе миграции нужно учитывать замену белых ip. Белые плавающие ip можно создать заранее и передать сторонним организациям (если такие есть), чтобы они заранее ввели новые ip в белые списки

<a name="_page2_x0.00_y236.66"></a>Как мигрировать

Процесс миграции может быть выполнен различными инструментами, в зависимости от сервиса и времени техокна (время когда сервис не будет работать).

Самый простой способ - пересоздание инфраструктуры в терраформе. В таком случае необходимо выполнить бэкапы/снапшоты тех вм и баз данных, где хранится состояние, так как терраформ при пересоздании удалит исходные жёсткие диски.

Другие способы, требующие меньшего техокна, будут описаны ниже.

<a name="_page2_x0.00_y348.52"></a>IaaS

<a name="_page2_x0.00_y376.91"></a>Сети

<a name="_page2_x0.00_y401.74"></a>общая схема

В начале необходимо создать на sprut аналогичные базовые сетевые сущности, которые были на netron:

1. Маршрутизаторы со всеми статическими маршрутами
1. Сети и подсети с такими же адресами сети, шлюзами, маршрутами. 

   Случай, когда в подсети подключен одновременно PaaS и IaaS рассмотрен ниже во вкладке DbaaS.

3. Секьюрити группы. Можно создать и скопировать правила при помощи скрипта

`      `#!/bin/bash![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.002.png)

- Function to display help message

display\_help() {

`    `echo "Usage: $0 --group-mapping=neutron\_id1=sprut\_id1,neutron\_id2=sprut\_id2,... --groups=group\_name1, group\_name2,..."

`    `echo

`    `echo "Options:"

`    `echo "  --group-mapping    Specifies the mapping of Neutron security group IDs to Sprut security group IDs."

`    `echo "  --groups           Specifies the names of security groups to be copied from Neutron to Sprut."

`    `echo

`    `echo "Example:"

`    `echo "  $0 --group-mapping=e70baf6b=5a60883e-c165-4f2d-9477-4c417acd5d6f,4b345b50-df8b-4e21-8fd5- 29c90c6d4918=8492ee54-a0a6-4dd1-a8af-0c73d4b5edf5 --groups=test-neutron-sg"

`    `echo

`    `echo "This script copies security group rules from the source Neutron environment to the target Sprut environment."

}

if ! command -v jq &> /dev/null; then

`    `echo "Error: jq is not installed."

`    `echo "jq is a lightweight and flexible command-line JSON processor."

`    `echo "You can install jq using the following commands:"     echo "For Ubuntu/Debian:"![ref1]

`    `echo "  sudo apt-get update"

`    `echo "  sudo apt-get install -y jq"

`    `echo "For CentOS/RHEL:"

`    `echo "  sudo yum install -y epel-release"

`    `echo "  sudo yum install -y jq"

`    `echo "For macOS using Homebrew:"

`    `echo "  brew install jq"

`    `exit 1

fi

- Function to get the authentication token get\_auth\_token() {

  `    `local token=$(openstack token issue -c id -f value)     echo "$token"

  }

- Function to check if a security group exists and get its ID

get\_sg\_id() {

`    `local sg\_name="$1"

`    `local sg\_id=$(openstack security group show "$sg\_name" -f value -c id 2>/dev/null)     echo "$sg\_id"

}

- Function to create security group with '-sprut' postfix create\_sg() {

  `    `local sg\_name="$1"

  `    `local new\_sg\_name="${sg\_name}-sprut"

  `    `local token="$2"

  `    `local url="https://infra.mail.ru:9696/infra/network/v2.0/security-groups"

  `    `local data=$(cat <<EOF

  {

  `    `"backend" : "sprut",

  `    `"security\_group": {

  `        `"name": "$new\_sg\_name",

  `        `"description": "Copy of $sg\_name"     }

  }

  EOF

  `    `)

  `    `curl -s -X POST $url \

  `        `-H "Content-Type: application/json" \         -H "X-Auth-Token: $token" \

  `        `-H "X-SDN: SPRUT" \

  `        `-d "$data"

  }

- Function to remove the default egress rule remove\_default\_egress\_rule() {

  `    `local sg\_id="$1"

- Get the rule ID of the default egress rule

`    `local rule\_ids=$(openstack security group rule list "$sg\_id" -f json | jq -r '.[] | select(. Direction == "egress" and ."IP Range" == "0.0.0.0/0" and ."Port Range" == "") | .ID')

- Remove the default egress rule

`    `for id in $rule\_ids; do

`        `openstack security group rule delete "$id"     done

}

- Function to copy security group rules from one group to another copy\_sg\_rules() {

  `    `local src\_sg="$1"

  `    `local dest\_sg="$2"

  `    `local -n mapping=$3

- Get the rule IDs of the source security group![ref1]

`    `local rules\_json=$(openstack security group show "$src\_sg" -f json | jq '.rules')

- Iterate over each rule to fetch full details

`    `for rule in $(echo "${rules\_json}" | jq -r '.[] | @base64'); do         \_jq() {

`            `echo "${rule}" | base64 --decode | jq -r "${1}"

`        `}

`        `local direction=$(\_jq '.direction')

`        `local protocol=$(\_jq '.protocol')

`        `local port\_range\_min=$(\_jq '.port\_range\_min')         local port\_range\_max=$(\_jq '.port\_range\_max')         local ip\_range=$(\_jq '.remote\_ip\_prefix')

`        `local ethertype=$(\_jq '.ethertype')

`        `local description=$(\_jq '.description')

`        `local remote\_sg=$(\_jq '.remote\_group\_id')

- Check for specific group names and get corresponding IDs

`        `if [[ "$remote\_sg" != "null" ]]; then

`            `local old\_remote\_sg="$remote\_sg"

`            `remote\_sg=$(echo ${mapping[$remote\_sg]})

`            `echo "Replacing Neutron SecurityGroup ID '$old\_remote\_sg' with Sprut SecurityGroup ID '$remote\_sg'"

`        `fi

- Construct command for creating rule

`        `local cmd="openstack security group rule create $dest\_sg"

`        `[ "$protocol" != "null" ] && cmd+=" --protocol $protocol"

`        `[ "$port\_range\_min" != "null" ] && cmd+=" --dst-port $port\_range\_min:$port\_range\_max"

`        `[ "$ip\_range" != "null" ] && [ "$remote\_sg" == "null" ] && cmd+=" --remote-ip $ip\_range"         [ "$direction" == "egress" ] && cmd+=" --egress"

`        `[ "$direction" == "ingress" ] && cmd+=" --ingress"

`        `[ "$ethertype" != "null" ] && cmd+=" --ethertype $ethertype"

`        `[ "$description" != "null" ] && cmd+=" --description \"$description\""

`        `[ "$remote\_sg" != "null" ] && cmd+=" --remote-group $remote\_sg"

- Execute the command

`        `echo "Executing: $cmd"

`        `if $cmd; then

`            `echo "Rule created successfully for $dest\_sg"         else

`            `echo "Failed to create rule for $dest\_sg"

`        `fi

`    `done

}

- Get the authentication token echo "Getting auth token" token=$(get\_auth\_token)
- Initialize statistics declare -A stats stats[success]=0 stats[fail]=0
- Read command-line arguments

  while [ $# -gt 0 ]; do

  `    `case "$1" in

  `        `--group-mapping=\*)

  `            `group\_mapping="${1#\*=}"

  `            `;;

  `        `--groups=\*)

  `            `groups="${1#\*=}"

  `            `;;

  `        `--help)

  `            `display\_help

  `            `exit 0

  `            `;;

  `        `\*)

  `            `echo "Unknown parameter: $1"

  `            `display\_help             exit 1![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.004.png)

  `            `;;

  `    `esac

  `    `shift

  done

- Check if group mapping is provided if [ -z "$group\_mapping" ]; then

  `    `echo "No group-mapping provided." fi

- Parse group mapping

declare -A sg\_mapping

if [ -n "$group\_mapping" ]; then

`    `IFS=',' read -r -a mappings <<< "$group\_mapping"

`    `for mapping in "${mappings[@]}"; do

`        `IFS='=' read -r neutron\_id sprut\_id <<< "$mapping"         sg\_mapping["$neutron\_id"]="$sprut\_id"

`    `done

fi

- Read each security group name from the command line arguments IFS=',' read -r -a sg\_names <<< "$groups"

  for sg\_name in "${sg\_names[@]}"; do

- Trim whitespace

`    `sg\_name=$(echo "$sg\_name" | xargs)

`    `echo "------------------------------------"     echo "Checking if group '$sg\_name' exists..."

- Check if the security group exists

`    `sg\_id=$(get\_sg\_id "$sg\_name")

`    `if [ -z "$sg\_id" ]; then

`        `echo "No SecurityGroup found for '$sg\_name'"         stats[fail]=$((stats[fail]+1))

`        `continue

`    `fi

`    `new\_sg\_name="${sg\_name}-sprut"

`    `echo "Checking if group '$new\_sg\_name' already exists..."

- Check if the target security group with postfix exists

`    `new\_sg\_id=$(get\_sg\_id "$new\_sg\_name")

`    `if [ ! -z "$new\_sg\_id" ]; then

`        `echo "SecurityGroup '$new\_sg\_name' already exists"         stats[fail]=$((stats[fail]+1))

`        `continue

`    `fi

`    `echo "Creating new security group '$new\_sg\_name'..."     create\_sg "$sg\_name" "$token"

`    `echo "Removing default egress rule from '$new\_sg\_name'..."     remove\_default\_egress\_rule "$new\_sg\_name"

`    `echo "Copying rules from '$sg\_name' to '$new\_sg\_name'..."     copy\_sg\_rules "$sg\_id" "$new\_sg\_name" sg\_mapping

`    `echo "Copying finished for '$sg\_name'"     stats[success]=$((stats[success]+1)) done

echo "------------------------------------" echo "Processing complete."

echo "Statistics:"

echo "Successfully copied: ${stats[success]}" echo "Failed to copy: ${stats[fail]}"

./copy-security-group.sh --group-mapping=<id    1>=<id    1>,<id    2>=<id    2>,... \ --groups=<      1>,<      2>,...![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.005.png)

--group-mapping - параметр нужен для правил, где в качестве источников указан не cidr, а другая секьюрити группа. Так как исходные id групп отличаются от целевых, например группы нейтрон all и спрут all, при этом названия у них одинаковые, необходимо через личный кабинет достать id и передать их в скрипт.

--groups - список групп на нейтроне, которые будут скопированы

В проекте по умолчанию доступна только группа default-sprut (в веб интерфейсы называется default) на sprut. Остальные группы будут доступны после ![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.006.png)![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.007.png)[создания ВМ](https://cloud.vk.com/docs/ru/computing/iaas/service-management/vm/vm-create) с такими группами в сети sprut. Вм можно будет потом сразу удалить.

<a name="_page6_x0.00_y226.61"></a>terraform

Можно скопировать описание всех сетевых объектов, которые уже имеются на neutron, добавить в названии и аттрибуте name постфикс -sprut и применить изменения, не забыв в зависимостях указать новые названия.

Сеть для интернета также будет изменена с ext-net на internet.

<a name="_page6_x0.00_y302.33"></a>Ipseс

- Туннели с одинаковыми селекторами (исходные и целевые диапазоны подсетей) не могут существовать одновременно, даже если они на разных sdn. Это означает, что создать аналогичный neutron туннель на sprut заранее нельзя, так как это приведёт к проблемам в работе с исходного.
- Для миграции можно заранее заготовить манифест terraform, который будет описывать туннель на sprut, также это можно сделать для туннеля на neutron для отката миграции при необходимости. Когда будет выполнятся миграция, исходный туннель на neutron необходимо удалить и применить манифест для туннеля на sprut, либо создать его через графический интерфейс, но это займёт больше времени.
- Необходимо помнить, что туннель создаётся с обоих сторон и клиент на другой стороне должен также быть готов удалить старый и принять новый туннель.
- Для построения ipsec туннелей на sprut необходимо использовать продвинутый маршрутизатор, а не стандартный как для neutron.

  ![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.008.jpeg)

  Данную схему можно преобразовать в такую, для сохранение описанного функционала

  ![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.009.jpeg)

  Данная схема необходима, так как сети подключенные к продвинутому роутеру не поддерживают плавающие ip адреса. Подключение продвинутого и стандартного роутера через транзитную сеть позволяет передать всю маршрутизацию роутерам. Никакие маршруты по dhcp передавать не нужно.

- В случае, если Ipsec используются для организации сетевой связности между разными проектами vk cloud переключение выполнить проще но

  ![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.010.jpeg)

  Рекомендуется заменить её на схему с шаренной сетью, shared network, так как это более производительно и надёжно. Стандартную сеть можно сделать доступной сразу в нескольких проектах, для этого нужно сделать запрос в техподдержку.

  ![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.011.jpeg)

- Для работы SNAT, то есть наличия доступа выхода в интернет, подсеть должна быть подключена к стандартному, а не продвинутому маршрутизатору.
- К одной сети нельзя подключить несколько стандартных роутеров без админских прав, которые есть у техподдержки.
- Мы используем продвинутые роутеры для подключения проектов к шаренной сети.
- Между стандартным и продвинутым маршрутизатором мы строим транзитную сеть. Для каждого стандартного маршрутизатора нужна отдельная транзитная сеть.
- Необходимо прописать соответствующие статические маршруты на стандартных и продвинутых маршрутизаторах.

<a name="_page8_x0.00_y131.66"></a>Балансировщики

- Сервис одинаков для neutron и sprut, но для миграции его необходимо пересоздать, так как у балансировщика нельзя заменить сеть.
- Можно пересоздать в terraform, указав сеть sprut в описании манифеста и подключить виртуальные машины уже после их миграции.
- Можно создать балансировщик вручную и указать вм в правилах.
- В разработке скрипт для создания копии балансировщика и с назначением всех виртуальных машин.

Публичный DNS

- В связи со сменой плавающих ip необходимо отредактировать текущие A-записи.
- Если используется внешний сервис dns, изменить записи в нём.

<a name="_page8_x0.00_y254.85"></a>Виртуальные машины

<a name="_page8_x0.00_y279.68"></a>общая схема

Для миграции виртуальных машин используется скрипт migrator-multiple.sh, который работает по следующему алгоритму:

![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.012.jpeg)

Сценарий предполагает выполнение последовательности действий, которая позволит переключить сетевой интерфейс ВМ в новый SDN. При этом важно помнить, что данная операция выполняется с разрывом сетевой связности.

Классификация виртуальных машин по сложности мигрирования.

Красный - несколько сетевых интерфейсов, вм выступает в роли роутера/прокси/пограничного файерволла.

Рекомендуется вручную мигрировать данную виртуальную машину без скрипта, так как скрипт предназначен для вм с одним портом.

Жёлтый - вм с плавающим ip либо с прямым подключением к сети ext-net.

Необходимо создать заранее плавающий ip в sprut и указать его id в конфиг файле скрипта.

В случае с прямым подключением ext-net рекомендуется перейти на плавающий ip, либо пересоздать вм.

Зелёный - один сетевой интерфейс в серой сети без плавающего ip.

<a name="_page9_x0.00_y175.50"></a>Подготовительные шаги.

1. В проекте VK Cloud создана ВМ с подключением к виртуальной сети, принадлежащей SDN Neutron.
1. В проекте VK Cloud создана новая сеть в SDN Sprut c подсетью, настройки которой повторяют настройки подсети, созданной в сети Neutron.
1. Подготовлено рабочее место администратора (ВМ с ОС Linux) с установленными компонентами OpenStack CLI, файл конфигурации отправлен в source и вызовы CLI проходят без ошибок.
1. На рабочее место администратора перенесен скрипт автоматизации.
1. Определен сервер, порт которого будет переключаться (логическое имя сервера).
1. Выполнена проверка о наличии аналогичных нейтроновским секьюрити групп на спруте. Их имя должно иметь постфикс -sprut (исключение базовые группы создаваемые по умолчанию вроде: default,all).

   Скрипт:

`      `#!/bin/bash![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.013.png)

echo " #######################################

- #
- Security Group Check Script    #
- # #######################################

This script checks all VMs in the tenant, collects the names of the assigned security groups, and verifies if there are corresponding security groups with the '-sprut' postfix.

It will skip checking for security groups named 'default', 'ssh+www', and 'all'. "

- Function to get a list of all VMs in the tenant function get\_all\_vms {

  `    `openstack server list -f value -c Name

  }

- Function to get the security groups assigned to a VM

function get\_vm\_security\_groups {

`    `local vm\_name=$1

`    `openstack server show "$vm\_name" -f json | jq -r '.security\_groups[] | .name' }

- Function to check if a security group with a given name and '-sprut' postfix exists function check\_sprut\_sg\_exists {

  `    `local sg\_name=$1

  `    `openstack security group list -f value -c Name | grep -qw "${sg\_name}-sprut"

  }

- Main script execution all\_vms=$(get\_all\_vms) sg\_names=()

  for vm in $all\_vms; do

  `    `echo "Checking VM: $vm"

  `    `vm\_sg\_names=$(get\_vm\_security\_groups "$vm")

  `    `echo "Security groups found on VM $vm: $vm\_sg\_names"     for sg\_name in $vm\_sg\_names; do

  `        `sg\_names+=("$sg\_name")

  `    `done done![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.014.png)

- Remove duplicates and sort the list

unique\_sg\_names=($(echo "${sg\_names[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))

- Filter out the security groups that should not be checked

filtered\_sg\_names=()

for sg\_name in "${unique\_sg\_names[@]}"; do

`    `if [[ "$sg\_name" != "default" && "$sg\_name" != "ssh+www" && "$sg\_name" != "all" ]]; then         filtered\_sg\_names+=("$sg\_name")

`    `fi

done

- Check for corresponding '-sprut' security groups and report missing ones missing\_sg=()

  for sg\_name in "${filtered\_sg\_names[@]}"; do

  `    `echo "Checking for corresponding '-sprut' security group for: $sg\_name"     if check\_sprut\_sg\_exists "$sg\_name"; then

  `        `echo "Found corresponding '-sprut' group for: $sg\_name"

  `    `else

  `        `echo "Missing corresponding '-sprut' group for: $sg\_name"

  `        `missing\_sg+=("$sg\_name")

  `    `fi

  done

  echo "------------------------------------"

  echo "Security Group Check Summary"

  echo "------------------------------------"

  if [ ${#missing\_sg[@]} -eq 0 ]; then

  `    `echo "All security groups have corresponding '-sprut' groups."

  else

  `    `echo "The following security groups do not have corresponding '-sprut' groups:"     for sg in "${missing\_sg[@]}"; do

  `        `echo "- $sg"

  `    `done

  fi

  echo "------------------------------------"

7. Запустить скрипт миграции:

Для запуска скрипта:

./migrator-multiple.sh --all-secgroup-sprut-id=<id  all  >  <csv     >![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.015.png)

--all-secgroup-sprut-id - так как в проекте будет 2 группы all для neutron и sprut, необходимо указать id в sprut, так как openstack cli неспособен различить принадлежность секьюрити группы к sdn.

csv файл с описанием мигрируемых вм имеет следующий формат:

имя вм1,имя сети sprut,имя подсети sprut,<опционально: id плавающего ip на спрут, который назначится> имя вм2,имя сети sprut,имя подсети sprut

Код скрипта:

`    `#!/bin/bash![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.016.png)

echo " #######################################

- #
- Port Migration Script        #
- #

####################################### Mandatory Input Data:![ref2]

Input file format: server\_name1,dest\_net1,dest\_subnet1,floating\_ip\_id1 server\_name2,dest\_net2,dest\_subnet2,floating\_ip\_id2

Note: If floating\_ip\_id is not provided, the script will not attach a Floating IP.

Optional: --all-secgroup-sprut-id=<id> --ssh-www-secgroup-sprut-id=<id>

"

- Parse arguments

for i in "$@"

do

case $i in

`    `--all-secgroup-sprut-id=\*)

`    `all\_sg\_sprut\_id="${i#\*=}"

`    `shift

`    `;;

`    `--ssh-www-secgroup-sprut-id=\*)     ssh\_www\_sg\_sprut\_id="${i#\*=}"     shift

`    `;;

`    `\*)

- unknown option

`    `;;

esac

done

- Function Definitions
- Capture port information with full details

function capture\_info\_full {

`    `echo "Executing step 1: Capturing port information"

- Define the migrated port name format

`    `migrated\_port\_name="${sname}\_migrated\_port"

- Check if the migrated port already exists and is attached to the server

`    `existing\_migrated\_port\_info=$(openstack port list -f value -c ID -c Name | grep "$migrated\_port\_name")     existing\_migrated\_port\_id=$(echo "$existing\_migrated\_port\_info" | awk '{print $1}' | head -n 1)

`    `if [ ! -z "$existing\_migrated\_port\_id" ]; then

- Check if this port is already attached to the server

`        `echo "Migrated port ${migrated\_port\_name} exists, checking for attachment..."

`        `attached\_port\_info=$(openstack server port list $sname -f value -c ID | grep "$existing\_migrated\_port\_id")

`        `if [ ! -z "$attached\_port\_info" ]; then

`            `echo "Migrated port $migrated\_port\_name already exists and is attached to server $sname. Skipping..."

`            `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*"

`            `return 1 # Use return code 1 to indicate skipping

`        `fi

`    `fi

- Proceed with capturing port information if no migrated port is attached

`    `port\_output=$(openstack port list --server $sname -c id -c "MAC Address" -c "Fixed IP Addresses")     srcpid=$(echo "$port\_output" | awk -F'|' 'NR==4{print $2}' | sed 's/ //g')

`    `mcs=$(echo "$port\_output" | awk -F'|' 'NR==4{print $3}' | sed 's/ //g')

`    `ips=$(echo "$port\_output" | awk -F'|' 'NR==4{print $4}' | grep -oP "ip\_address='\K[^']+")

`    `echo "Source Port ID is:        $srcpid"

`    `echo "Source Port IP Addr is:   $ips"

`    `echo "Source Port MAC Addr is:  $mcs"

`    `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*" }

- Capture server ID and security group names![ref2]

function capture\_id\_and\_sec\_group {

`    `echo "Executing step 2: Capturing server ID and security group names"

`    `server\_output=$(openstack server show $sname)

`    `servid=$(echo "$server\_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')     echo "Server ID is:             $servid"

- Fetch security group IDs

`    `sec\_group\_ids=$(openstack port show $srcpid -c security\_group\_ids -f value)

- Preprocess to remove brackets and split by comma

`    `sec\_group\_ids=$(echo $sec\_group\_ids | tr -d '[]' | tr -d '"' | tr -d "'")

- Convert to array and iterate

`    `IFS=',' read -ra ADDR <<< "$sec\_group\_ids"

`    `sec\_group\_names=()

`    `for sec\_group\_id in "${ADDR[@]}"; do

`        `sec\_group\_name=$(openstack security group show $sec\_group\_id -c name -f value)         sec\_group\_names+=("$sec\_group\_name")

`    `done

`    `echo "Security Groups captured: ${sec\_group\_names[@]}"

`    `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*"

}

- Create port in target network with source IP and MAC, with checks for existing port by name using grep function create\_port\_with\_mac\_ip {

  `    `echo "Executing step 3: Creating port with source IP and MAC"

- Define the port name format

`    `port\_name="${sname}\_migrated\_port"

- Attempt to find an existing port by name using grep

`    `existing\_port\_info=$(openstack port list -f value -c ID -c Name | grep "$port\_name")     existing\_port\_id=$(echo "$existing\_port\_info" | awk '{print $1}' | head -n 1)

`    `if [ ! -z "$existing\_port\_id" ]; then

`        `echo "Port named $port\_name already exists. Port ID: $existing\_port\_id"

`        `pmigid=$existing\_port\_id

`    `else

- If no existing port found, attempt to create a new port

`        `create\_port\_cmd="openstack port create --network $defnet --fixed-ip subnet=$defsubnet,ip-address=$ips -- mac-address=$mcs $port\_name"

`        `echo "Running command: $create\_port\_cmd"

`        `new\_port\_output=$($create\_port\_cmd)

`        `pmigid=$(echo "$new\_port\_output" | awk -F'|' '/\| id / {print $3}' | sed 's/ //g')

`        `echo "Step 3 complete (New Port Created)"

`    `fi

`    `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*"

}

- Disconnect existing port from server

function detach\_source\_port {

`    `echo "Executing step 4: Disconnecting existing port from server"

`    `detach\_port\_cmd="openstack server remove port $servid $srcpid"

`    `echo "Running command: $detach\_port\_cmd"

`    `$detach\_port\_cmd

`    `echo "Step 4 complete (Source port disconnected from server $sname)"     echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*"

}

- Connect new port to server

function attach\_new\_port {

`    `echo "Executing step 5: Connecting new port to server"

`    `attach\_port\_cmd="openstack server add port $servid $pmigid"     echo "Running command: $attach\_port\_cmd"

`    `$attach\_port\_cmd

`    `echo "Step 5 complete (New port attached to server)"

`    `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*" }![ref2]

- Set security groups on the new port

function set\_security\_groups {

`    `echo "Executing step 6: Setting security groups on new port"     echo "Setting captured groups: ${sec\_group\_names[@]}"

`    `for sec\_group\_name in "${sec\_group\_names[@]}"; do

`        `echo "Original Security Group: $sec\_group\_name"

`        `if [[ "$sec\_group\_name" == "all" ]]; then

`            `modified\_sec\_group\_id="$all\_sg\_sprut\_id"

`        `elif [[ "$sec\_group\_name" == "default" ]]; then

`            `modified\_sec\_group\_name="default-sprut"

`            `if openstack security group show "$modified\_sec\_group\_name" -c id -f value &> /dev/null; then

`                `modified\_sec\_group\_id=$(openstack security group show "$modified\_sec\_group\_name" -c id -f value)             else

`                `echo "Security Group $modified\_sec\_group\_name does not exist, skipping..."

`                `continue

`            `fi

`        `elif [[ "$sec\_group\_name" == "ssh+www" ]]; then

`            `modified\_sec\_group\_id="$ssh\_www\_sg\_sprut\_id"

`        `else

`            `modified\_sec\_group\_name="${sec\_group\_name}-sprut"

- Check if modified security group exists before setting it

`            `if openstack security group show "$modified\_sec\_group\_name" -c id -f value &> /dev/null; then

`                `modified\_sec\_group\_id=$(openstack security group show "$modified\_sec\_group\_name" -c id -f value)             else

`                `echo "Security Group $modified\_sec\_group\_name does not exist, skipping..."

`                `continue

`            `fi

`        `fi

`        `echo "Modified Security Group ID: $modified\_sec\_group\_id"

`        `set\_sg\_cmd="openstack port set --security-group $modified\_sec\_group\_id $pmigid"

`        `echo "Running command: $set\_sg\_cmd"

`        `$set\_sg\_cmd

`        `echo "Security Group $sec\_group\_name set on new port"

`    `done

`    `echo "Step 6 complete (Security groups assignment complete)"

`    `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*"

}

- Attach Floating IP to the new port if provided function attach\_floating\_ip {

  `    `if [ ! -z "$floating\_ip\_id" ]; then

  `        `echo "Executing step 7: Attaching Floating IP"

  `        `attach\_fip\_cmd="openstack floating ip set --port $pmigid $floating\_ip\_id"         echo "Running command: $attach\_fip\_cmd"

  `        `$attach\_fip\_cmd

  `        `echo "Floating IP $floating\_ip\_id attached to new port"

  `        `echo "\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*\*"

  `    `fi

  }

- Process migration for each server function process\_migration {

  `    `sname=$1

  `    `defnet=$2

  `    `defsubnet=$3

  `    `floating\_ip\_id=$4

  `    `echo "Processing migration for server: $sname"     capture\_info\_full

  `    `if [ $? -eq 1 ]; then

- Skipping logic, e.g., continue in a loop

`        `continue

`    `fi

`    `capture\_id\_and\_sec\_group

`    `create\_port\_with\_mac\_ip

`    `detach\_source\_port

`    `attach\_new\_port![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.018.png)

`    `set\_security\_groups

`    `attach\_floating\_ip

`    `echo "Migration completed for server: $sname"     echo "---------------------------------------" }

- Main script execution

if [ -z "$1" ]; then

`    `echo "Error: No input file provided."     exit 1

fi

start\_time=$(date +%s)

while IFS=, read -r server\_name dest\_net dest\_subnet floating\_ip\_id

do

`    `process\_migration "$server\_name" "$dest\_net" "$dest\_subnet" "$floating\_ip\_id" done < "$1"

end\_time=$(date +%s) elapsed\_time=$(($end\_time - $start\_time)) echo "Elapsed time: $elapsed\_time seconds"

После миграции может возникнуть необходимость перезагрузить dhclient на вм Для Windows:

\```

ipconfig /release ipconfig /renew ```

Для Lunix: ```bash dhclient ```

<a name="_page14_x0.00_y459.86"></a>terraform

Как было сказано ранее, можно мигрировать вм на другой sdn при помощи terraform, что требует пересоздания вм. Миграция через скрипт, описанный выше также приведёт к пересозданию вм, если выполнить terraform apply. 

Это возникает из-за того, что id портов вм меняются, так как скрипт создаёт новые порты. Чтобы избежать пересоздания, необходимо поправить state указав новую сеть, на которую ссылается terraform, а также исправить state файл. 

Вм может быть много и менять стейт вручную неудобно, следующий скрипт позволяет собрать информацию о вм, которые были мигрированы и подготовить новый скрипт, правящий состояние terraform:

`    `#!/bin/bash![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.019.png)

echo " #######################################

- #
- Terraform State Modification Script#
- # ####################################### "
- ,      

if [[ -n "$1" ]]; then

`    `state\_file="-state=$1"

`    `echo "Using specified state file: $1" else

`    `state\_file=""

`    `echo "Using default state file"

fi![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.020.png)

- Terraform

terraform\_state\_list=$(terraform state list $state\_file)

- ,    vkcs\_compute\_instance

compute\_instances=$(echo "$terraform\_state\_list" | grep "vkcs\_compute\_instance")

- compute\_instances

if [[ -z "$compute\_instances" ]]; then

`    `echo "No vkcs\_compute\_instance resources found in the current Terraform state."     exit 1

fi

 

output\_script="terraform\_modify\_to\_sprut\_state.sh"

echo "#!/bin/bash" > $output\_script

echo "echo '#######################################'" >> $output\_script echo "echo '#                                     #'" >> $output\_script echo "echo '#  Modifying Terraform State Script   #'" >> $output\_script echo "echo '#                                     #'" >> $output\_script echo "echo '#######################################'" >> $output\_script

 

table\_output="terraform resource name | openstack vm id | vm name\n"

- compute\_instance       

while IFS= read -r instance; do

- id   

`    `resource\_info=$(terraform state show $state\_file $instance)

`    `resource\_id=$(echo "$resource\_info" | grep -E '^\s\*id\s\*=' | awk -F' = ' '{print $2}' | tr -d '"' | head -n 1)

`    `resource\_name=$(echo "$resource\_info" | grep -E '^\s\*name\s\*=' | awk -F' = ' '{print $2}' | tr -d '"' | head -n 1)

- id   

`    `if [[ -z "$resource\_id" || -z "$resource\_name" ]]; then

`        `echo "No id or name found for $instance in the current Terraform state."         continue

`    `fi

 

`    `echo "echo 'Modifying $instance'" >> $output\_script

`    `echo "terraform state rm $instance $state\_file" >> $output\_script

`    `echo "terraform import $instance $resource\_id $state\_file" >> $output\_script

 

`    `table\_output+="$instance | $resource\_id | $resource\_name\n" done <<< "$compute\_instances"

 

chmod +x $output\_script

 

echo -e "Generated script: $output\_script\n" echo -e "$table\_output"

- ` `table\_output\_file="state\_modification\_table.txt" echo -e "$table\_output" > $table\_output\_file

  echo "Table of resources saved to $table\_output\_file"

Для запуска:

![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.021.png)

`    `modify\_terraform\_state.sh <  >![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.022.png)

Если не указать в параметрах стейт файл терраформа, будет использоваться текущий файл terraform.tfstate Необходимо в коде терраформе также указать новые сети у вм.

<a name="_page16_x0.00_y129.53"></a>NFS/CIFS

<a name="_page16_x0.00_y154.35"></a>общая схема

Файловое хранилище поддерживает бэкапы, однако их нельзя поднять в сети другого sdn. Необходимо:

1. Создать аналогичное хранилище в sprut сети.
1. Создать вм 1-2 и подключить её к сетям старого и нового хранилищь.
1. Выполнить подключение на вм к обоим хранилищам и запустить rsync и перелить данные в новое хранилище. 

<a name="_page16_x0.00_y249.64"></a>PaaS

Общая схема миграции подразумевает создание копии PaaS в сети neutron и переноса нагрузки при помощи встроенных средств бэкапирования. Для простоты решения рекомендуется остановить кластеры на запись, пока выполняется перенос.

![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.023.jpeg)

![](Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.024.jpeg)

В данной схеме можно использовать продвинутый роутер в качестве связности neutron и sprut.

<a name="_page17_x0.00_y232.09"></a>Kubernetes

<a name="_page17_x0.00_y256.91"></a>общая схема

1. Создаём аналогичный кластер в новой сети sprut. В случае если в сети помимо кластера kubernetes есть другие сервисы или виртуалки, адрес сети на sprut, где размещён kubernetes должен отличаться от исходного.
1. Переносим нагрузку при помощи средства бэкапирования velero, в том числе pv. Примеры использования velero находятся в инструкции: <https://github.com/IlyaNyrkov/k8s-velero-vkcloud-workshop>
1. Внешние ip балансировщиков будут другие на новом кластере.
1. Подключаем продвинутый роутер к транзитным сетям с исходным и новым роутером на спруте. Прописываем необходимую статику как на схеме выше.
1. Проверяем функционирование приложения.
1. Удаляем старый кластер.

<a name="_page17_x0.00_y381.75"></a>DbaaS

1. Останавливаем исходную базу данных на запись и делаем снапшот. Альтернативно можно использовать pgdump и другие встроенные средства бэкапирования баз данных.
1. Из бэкапа поднимаем базу данных в новой сети.
1. Строем перемычку с виртуальными машиными при помощи продвинутого роутера.
1. Правим конфиги вм, чтобы они ходили в бд с новым адресом.
1. Удаляем исходную бд.

[ref1]: Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.003.png
[ref2]: Aspose.Words.ab5b0b3d-65d0-4b47-9be1-07d1d46ec625.017.png
