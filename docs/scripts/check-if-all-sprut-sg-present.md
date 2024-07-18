# Проверка наличия секьюрити групп на спруте, аналогичных нейтроновским

**check-if-all-sprut-sg-present.sh**

Скрипт проверяет группы на каждой вм и далее проверяет наличие групп с таким же названием и постфиксом -sprut.
Группы default, all, ssh+www игнорируются, так как являются базовыми для нейторна и спрута.

```bash
./check-if-all-sprut-sg-present.sh
```

```shell
------------------------------------
Security Group Check Summary
------------------------------------
The following security groups do not have corresponding '-sprut' groups:
- cluster_ml_sec_group
- custom-sprut-postgre
- icmp
------------------------------------
```