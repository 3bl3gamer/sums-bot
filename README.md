# Sums Bot

[@the_very_sums_bot](https://t.me/the_very_sums_bot)

Телеграмный бот-записная книжка с элементами калькулятора: умеет складывать числа и хранить суммы по ним. Создавался в том числе для знакомства с Nim'ом, так что образцом качественного кода точно не является.

Имеет собственную реализацию телеграмного ботового АПИ (`tg.nim`), умеет работать в лонгпольном и вебхуковом режимах. В качестве HTTP-сервера использует [httpbeast](https://github.com/dom96/httpbeast) в многопоточном режиме.

## Запуск

`./run.sh` запускает бота в отладчном режиме (`nimble run` не хочет передавать аргументы внутрь команды).

`nimble install` собирает в релизном режиме бинарник `sumsbot`, который можно использовать вместо `./run.sh`.

```bash
# Long Polling
TG_BOT_TOKEN=<token> ./run.sh

# Long Polling + HTTP proxy
TG_BOT_TOKEN=<token> ./run.sh --http-proxy-addr="http://127.0.0.1:8118"

# Webhook
TG_BOT_TOKEN=<token> ./run.sh --webhook-url="example.com/path/to/webhook"

# Webhook + self-signed cert
TG_BOT_TOKEN=<token> ./run.sh --webhook-url="example.com/webhook" --webhook-cert-path="path/to/cert.pem"
```

## Пример работы
```
Me:  +1
Bot: default: 1

Me:  100
Bot: default: 101

Me:  the Answer 42
Bot: the Answer: 42

Me:  /info
Bot: Все суммы:
default: 101
the Answer: 42

Последнее изменение
the Answer: 42
могу отменить (/cancel)
```