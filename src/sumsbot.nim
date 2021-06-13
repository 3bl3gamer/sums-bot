import db_sqlite, httpClient, options, asyncdispatch, parseopt, os, strutils,
    sequtils, json, tables
import httpbeast
import tg, core

var httpProxyAddr = ""
var webhookCertPath = ""
var webhookUrl = ""
let token = getEnv("TG_BOT_TOKEN")
# openssl req -newkey rsa:2048 -sha256 -nodes -keyout sums_bot_key.pem -x509 -days 3650 -out sums_bot_cert.pem -subj "/CN=127.0.0.1"


var p = initOptParser(commandLineParams())
while true:
  p.next()
  case p.kind
  of cmdEnd: break
  of cmdShortOption, cmdLongOption:
    if p.key == "http-proxy-addr":
      httpProxyAddr = p.val
    elif p.key == "webhook-cert-path":
      webhookCertPath = p.val
    elif p.key == "webhook-url":
      webhookUrl = p.val
  of cmdArgument:
    echo "unexpected argument: ", p.key


if token == "":
  raise newException(Exception, "TG_BOT_TOKEN env variable is missing")


let db = open("main.db", "", "", "")

let proxy = if httpProxyAddr == "": nil else: newProxy(url = httpProxyAddr)
let bot = newTGBot(token, proxy)


setupTables(db)
echo "DB: users: ", countUsers(db), ", sums: ", countSums(db)

let me = bot.getMe()
echo "TG: starting as @", me.username.get(), " aka ", me.first_name, " #", me.id


proc answer(bot: TGBot, user: core.User, text: string, parse: bool = false) =
  discard bot.sendMessage(user.id, text,
      parseMode = if parse: PMMarkdown else: PMNone)

proc onUpdate(bot: TGBot, update: Update) =
  let msg = update.message
  if msg.text.isSome:
    let f = msg.`from`.get()
    let user = findOrAddUser(db, f.id, f.first_name, f.last_name, f.username)
    let text = msg.text.get()

    if text.startsWith("/start") or text.startsWith("/help"):
      var msg = "Присланное число (целое) добавлю к текущей сумме, например:\n" &
        "`  100`\n\n" &
        "Я смотрю только на первую строку, так что под ней можно оставить комментарий, например:\n" &
        "`  42\n  с этим числом любая сумма будет лучше`\n\n" &
        "Перед числом можно дописать название другой суммы, чтоб изменить её, не переключаясь. Например:\n" &
        "`  звёзд на небе +1`\n\n" &
        "Ещё понмиаю несколько команд:\n" &
        "/cancel — отменю последнее изменение (только одно)\n" &
        "/info — покажу спиок всех сумм \n" &
        "/use <название> — переключусь на другую сумму и по умолчанию буду использовать её\n" &
        "/del <название> — забуду сумму\n" &
        "/help — напомню это всё ещё раз"
      if text.startsWith("/start"):
        msg = "Привет! Я — записная книжка с элементами калькулятора: " &
          "умею складывать числа и хранить суммы по ним. " &
          "А Телеграм заботливо сохранит изменения с комментариями.\n\n" & msg
      answer(bot, user, msg, true)

    elif text.startsWith("/info"):
      let sumRows = findUserSums(db, user.id)
        .mapIt(it.name & ": " & $it.value &
               (if it.name == user.curSumName: " (текущая)" else: ""))
      var msg = if sumRows.len == 0: "*Сумм нет.*"
        else: "*Все суммы:*\n" & sumRows.join("\n")

      if user.lastSum.isSome:
        let s = user.lastSum.get()
        msg &= "\n\n*Последнее изменение*\n" &
          s.name & ": " & $s.delta &
          "\nмогу отменить (/cancel)"
      else:
        msg &= "\n\n*Отменять нечего.*"

      answer(bot, user, msg, true)

    elif text.startsWith("/cancel"):
      if user.lastSum.isSome:
        let sum = user.lastSum.get()
        let newValue = updateUserSum(db, user.id, sum.name, -sum.delta)
        answer(bot, user, "Отменил, теперь\n" & sum.name & ": " & $newValue)
      else:
        answer(bot, user, "Отменять пока нечего.")

    elif text.startsWith("/use"):
      var sumName = text[4 .. ^1].strip()
      if sumName == "": sumName = "default"
      changeUserCurSum(db, user.id, sumName)
      let sumValue = findSumValue(db, user.id, sumName)
      let strValue = if sumValue.isSome: $sumValue.get() else: "<пусто>"
      answer(bot, user, "Переключился на\n" & sumName & ": " & strValue)

    elif text.startsWith("/del"):
      let sumName = text[4 .. ^1].strip()
      if sumName == "":
        answer(bot, user, "Назвние суммы обязательно. Например `/del default`.", true)
      else:
        let removed = removeUserSum(db, user.id, sumName)
        answer(bot, user, if removed: "Удалил." else: "Такой суммы нет.")

    elif text.startsWith("/"):
      answer(bot, user, "Не знаю такой команды.")

    else:
      let lines = text.split('\n', maxSplit = 1) # lines after first are ignored and may be used as comment
      let parts = lines[0].rsplit(" ", maxSplit = 1)
      let delta = try: some(int64(parseInt(parts[^1]))) except ValueError: none(int64)
      let sumName = if parts.len == 1: user.curSumName else: parts[0]
      if delta.isSome:
        let newValue = updateUserSum(db, user.id, sumName, delta.get())
        answer(bot, user, sumName & ": " & $newValue)
      else:
        answer(bot, user, "Не понял.")


if webhookUrl == "":
  discard bot.deleteWebhook()
  # bot.startPollingThread(60, onUpdate, allowedUpdates = {UTMessage})
  bot.startPoling(60, onUpdate, allowedUpdates = {UTMessage})
else:
  let cert = if webhookCertPath == "": none(string) else: some(readFile(webhookCertPath))
  discard bot.setWebhook(webhookUrl, cert, allowedUpdates = {UTMessage})
  var bots = initTable[int, TGBot]()

  proc onRequest(req: Request): Future[void] =
    if req.httpMethod == some(HttpPost) and req.path.get() == "/webhook":
      let body = req.body()
      if body.isSome:
        let tid = getThreadId()
        {.gcsafe.}:
          let localBot = if bots.hasKey(tid): bots[tid]
            else: bots.getOrDefault(tid, bot.copy())
        onUpdate(localBot, parseJson(body.get()).to(Update))
      req.send("OK")
    else:
      req.send(Http404)

  run(onRequest, Settings(port: Port(9003)))
