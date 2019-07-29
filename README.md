# Sums Bot

[@the_very_sums_bot](https://t.me/the_very_sums_bot)

Телеграмный бот-записная книжка с элементами калькулятора: умеет складывать числа и хранить суммы по ним. Создавался в том числе для знакомства с Nim'ом, так что образцом качественного кода точно не является.

Имеет собственную реализацию телеграмного ботового АПИ (`tg.nim`), умеет работать в лонгпольном и вебхуковом режимах. В качестве HTTP-сервера использует [httpbeast](https://github.com/dom96/httpbeast) в многопоточном режиме. Данные пишет в Sqlite3.

## Установка

`nimble install https://github.com/3bl3gamer/sums-bot`

## Запуск

```bash
# Long Polling
TG_BOT_TOKEN=<token> sumsbot

# Long Polling + HTTP proxy
TG_BOT_TOKEN=<token> sumsbot --http-proxy-addr="http://127.0.0.1:8118"

# Webhook
TG_BOT_TOKEN=<token> sumsbot --webhook-url="example.com/path/to/webhook"

# Webhook + self-signed cert
TG_BOT_TOKEN=<token> sumsbot --webhook-url="example.com/webhook" --webhook-cert-path="path/to/cert.pem"
```

Из локальной копии репозитория `./run.sh` запускает бота в отладчном режиме (`nimble run` не хочет передавать аргументы внутрь команды). `nimble install` собирает в релизном режиме бинарник `sumsbot`.

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

## Всякое

### /etc/nginx/nginx.conf
```
server {
    listen 8443 ssl http2;

    ssl_certificate /etc/nginx/ssl/sums_bot_cert.pem;
    ssl_certificate_key /etc/nginx/ssl/sums_bot_key.pem;

    location /sums_bot_secret_webhook {
        proxy_pass http://127.0.0.1:9003/webhook;
    }
}
```

### /etc/systemd/system/sumsbot.service
```
[Unit]
Description=SumsBot
After=network.target

[Service]
User=sums
WorkingDirectory=/home/sums
Environment="TG_BOT_TOKEN=<key>"
ExecStart=subsbot --webhook-cert-path=/etc/nginx/ssl/sums_bot_cert.pem --webhook-url=https://example.com/webhook'
Restart=on-failure

[Install]
WantedBy=multi-user.target
```